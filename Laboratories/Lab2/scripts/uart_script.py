#!/usr/bin/env python3
"""
Interfaz grafica para operar la ALU de la FPGA por UART.

Protocolo:
    PC   -> FPGA : 3 bytes en orden [A, B, OPCODE]
    FPGA -> PC   : 1 byte con el resultado

Requiere:
    pip install pyserial
(tkinter viene incluido con Python)
"""

import time
import tkinter as tk
from tkinter import ttk, messagebox
from tkinter.scrolledtext import ScrolledText

import serial
import serial.tools.list_ports

# ----------------------------------------------------------------- Config
DEFAULT_BAUD     = 9600
RESPONSE_BYTES   = 1       # bytes que devuelve la FPGA por operacion
READ_TIMEOUT     = 1.0     # segundos esperando la respuesta
INTER_BYTE_DELAY = 0.002   # pausa entre bytes enviados, deja la linea en
                           # reposo por si el Rx espera mas de 2 stop bits

OPCODES = {
    "ADD": 0b100000,
    "SUB": 0b100010,
    "AND": 0b100100,
    "OR":  0b100101,
    "XOR": 0b100110,
    "NOR": 0b100111,
    "SRA": 0b000011,
    "SRL": 0b000010,
}

PARITIES = {
    "Ninguna (N)": serial.PARITY_NONE,
    "Par (E)":     serial.PARITY_EVEN,
    "Impar (O)":   serial.PARITY_ODD,
}

STOPBITS = {
    "1": serial.STOPBITS_ONE,
    "2": serial.STOPBITS_TWO,
}

PORT_SEP = " — "


# ----------------------------------------------------------------- Modelo
def to_signed(x):
    """Interpreta un byte como entero con signo (complemento a 2)."""
    return x - 256 if x & 0x80 else x


def alu_model(a, b, op):
    """Modelo en Python de la ALU de 8 bits, para comparar con la FPGA."""
    shamt = b & 0b111
    if   op == "ADD": r = a + b
    elif op == "SUB": r = a - b
    elif op == "AND": r = a & b
    elif op == "OR":  r = a | b
    elif op == "XOR": r = a ^ b
    elif op == "NOR": r = ~(a | b)
    elif op == "SRA": r = to_signed(a) >> shamt
    elif op == "SRL": r = a >> shamt
    else:             r = 0
    return r & 0xFF


def parse_byte(text):
    """Acepta decimal con signo (-128..255), hex (0x..) o binario (0b..)."""
    text = text.strip()
    try:
        value = int(text, 0)
    except ValueError:
        value = int(text, 10)          # permite ceros a la izquierda: "007"
    if not -128 <= value <= 255:
        raise ValueError(f"'{text}' no entra en 8 bits")
    return value & 0xFF


# ----------------------------------------------------------------- GUI
class AluGui(tk.Tk):
    def __init__(self):
        super().__init__()
        self.title("ALU por UART")
        self.resizable(False, False)
        self.ser = None
        self._build_ui()
        self.refresh_ports()
        self.protocol("WM_DELETE_WINDOW", self.on_close)

    # ------------------------------------------------------------- Layout
    def _build_ui(self):
        pad = {"padx": 6, "pady": 4}

        # --- Conexion
        conn = ttk.LabelFrame(self, text="Conexión")
        conn.grid(row=0, column=0, sticky="ew", **pad)

        ttk.Label(conn, text="Puerto").grid(row=0, column=0, sticky="e", **pad)
        self.port_var = tk.StringVar()
        self.port_combo = ttk.Combobox(conn, textvariable=self.port_var,
                                       width=32, state="readonly")
        self.port_combo.grid(row=0, column=1, columnspan=3, sticky="w", **pad)
        ttk.Button(conn, text="↻", width=3,
                   command=self.refresh_ports).grid(row=0, column=4, **pad)

        ttk.Label(conn, text="Baud").grid(row=1, column=0, sticky="e", **pad)
        self.baud_var = tk.StringVar(value=str(DEFAULT_BAUD))
        ttk.Entry(conn, textvariable=self.baud_var,
                  width=8).grid(row=1, column=1, sticky="w", **pad)

        ttk.Label(conn, text="Paridad").grid(row=1, column=2, sticky="e", **pad)
        self.parity_var = tk.StringVar(value="Ninguna (N)")
        ttk.Combobox(conn, textvariable=self.parity_var, values=list(PARITIES),
                     width=11, state="readonly").grid(row=1, column=3, sticky="w", **pad)

        ttk.Label(conn, text="Stop").grid(row=1, column=4, sticky="e", **pad)
        self.stop_var = tk.StringVar(value="1")
        ttk.Combobox(conn, textvariable=self.stop_var, values=list(STOPBITS),
                     width=3, state="readonly").grid(row=1, column=5, sticky="w", **pad)

        self.conn_btn = ttk.Button(conn, text="Conectar",
                                   command=self.toggle_connection)
        self.conn_btn.grid(row=0, column=5, **pad)

        # --- Operacion
        op = ttk.LabelFrame(self, text="Operación")
        op.grid(row=1, column=0, sticky="ew", **pad)

        ttk.Label(op, text="A").grid(row=0, column=0, **pad)
        self.a_var = tk.StringVar(value="5")
        ttk.Entry(op, textvariable=self.a_var, width=8).grid(row=0, column=1, **pad)

        ttk.Label(op, text="B").grid(row=0, column=2, **pad)
        self.b_var = tk.StringVar(value="3")
        ttk.Entry(op, textvariable=self.b_var, width=8).grid(row=0, column=3, **pad)

        ttk.Label(op, text="Operación").grid(row=0, column=4, **pad)
        self.op_var = tk.StringVar(value="ADD")
        ttk.Combobox(op, textvariable=self.op_var, values=list(OPCODES),
                     width=6, state="readonly").grid(row=0, column=5, **pad)

        self.calc_btn = ttk.Button(op, text="Calcular",
                                   command=self.calculate, state="disabled")
        self.calc_btn.grid(row=0, column=6, **pad)

        ttk.Label(op, text="Decimal (-128..255), hex (0x2A) o binario (0b101)",
                  foreground="gray").grid(row=1, column=0, columnspan=7,
                                          sticky="w", padx=6)

        # --- Resultado
        res = ttk.LabelFrame(self, text="Resultado")
        res.grid(row=2, column=0, sticky="ew", **pad)

        self.res_vars = {}
        fields = ["Hex", "Sin signo", "Con signo",
                  "Binario", "Esperado", "Estado"]
        for i, name in enumerate(fields):
            r, c = divmod(i, 3)
            ttk.Label(res, text=name + ":").grid(row=r, column=c * 2,
                                                 sticky="e", **pad)
            var = tk.StringVar(value="—")
            lbl = ttk.Label(res, textvariable=var, width=12, font="TkFixedFont")
            lbl.grid(row=r, column=c * 2 + 1, sticky="w", **pad)
            self.res_vars[name] = var
        self.status_label = lbl        # el ultimo campo es "Estado"

        # --- Bytes crudos (loopback)
        raw = ttk.LabelFrame(self, text="Bytes crudos (prueba de loopback)")
        raw.grid(row=3, column=0, sticky="ew", **pad)

        self.raw_var = tk.StringVar(value="41 42 43")
        ttk.Entry(raw, textvariable=self.raw_var,
                  width=36).grid(row=0, column=0, **pad)
        self.raw_btn = ttk.Button(raw, text="Enviar y leer",
                                  command=self.send_raw, state="disabled")
        self.raw_btn.grid(row=0, column=1, **pad)
        ttk.Label(raw, text="Bytes en hex separados por espacio",
                  foreground="gray").grid(row=1, column=0, columnspan=2,
                                          sticky="w", padx=6)

        # --- Log
        log_frame = ttk.LabelFrame(self, text="Log")
        log_frame.grid(row=4, column=0, sticky="nsew", **pad)
        self.log = ScrolledText(log_frame, width=72, height=10,
                                font="TkFixedFont", state="disabled")
        self.log.pack(fill="both", expand=True, padx=4, pady=4)

    # ------------------------------------------------------------ Helpers
    def log_msg(self, msg):
        self.log.configure(state="normal")
        self.log.insert("end", time.strftime("%H:%M:%S  ") + msg + "\n")
        self.log.see("end")
        self.log.configure(state="disabled")

    def _set_io_state(self, state):
        self.calc_btn.configure(state=state)
        self.raw_btn.configure(state=state)

    def _set_status(self, text, color):
        self.res_vars["Estado"].set(text)
        self.status_label.configure(foreground=color)

    def _send(self, data):
        """Manda los bytes de a uno, con una pequena pausa entre cada uno."""
        self.ser.reset_input_buffer()          # descarta basura previa
        for byte in data:
            self.ser.write(bytes([byte]))
            self.ser.flush()
            time.sleep(INTER_BYTE_DELAY)
        self.log_msg("TX → " + " ".join(f"{b:02X}" for b in data))

    def _receive(self, n):
        data = self.ser.read(n)
        if data:
            self.log_msg("RX ← " + " ".join(f"{b:02X}" for b in data))
        return data

    # ------------------------------------------------------------ Acciones
    def refresh_ports(self):
        ports = [f"{p.device}{PORT_SEP}{p.description}"
                 for p in serial.tools.list_ports.comports()]
        self.port_combo["values"] = ports
        if ports and self.port_var.get() not in ports:
            self.port_var.set(ports[0])
        elif not ports:
            self.port_var.set("")

    def toggle_connection(self):
        # Desconectar
        if self.ser and self.ser.is_open:
            self.ser.close()
            self.ser = None
            self.conn_btn.configure(text="Conectar")
            self._set_io_state("disabled")
            self.log_msg("Desconectado")
            return

        # Conectar
        port = self.port_var.get().split(PORT_SEP)[0]
        if not port:
            messagebox.showerror("Error", "No hay ningún puerto seleccionado")
            return
        try:
            self.ser = serial.Serial(
                port=port,
                baudrate=int(self.baud_var.get()),
                bytesize=serial.EIGHTBITS,
                parity=PARITIES[self.parity_var.get()],
                stopbits=STOPBITS[self.stop_var.get()],
                timeout=READ_TIMEOUT,
            )
        except (serial.SerialException, ValueError) as e:
            messagebox.showerror("No se pudo abrir el puerto", str(e))
            self.ser = None
            return

        self.conn_btn.configure(text="Desconectar")
        self._set_io_state("normal")
        self.log_msg(f"Conectado a {port}  "
                     f"({self.ser.baudrate} 8{self.ser.parity}{self.ser.stopbits:g})")

    def calculate(self):
        try:
            a = parse_byte(self.a_var.get())
            b = parse_byte(self.b_var.get())
        except ValueError as e:
            messagebox.showerror("Operando inválido", str(e))
            return

        op = self.op_var.get()
        try:
            self._send([a, b, OPCODES[op]])
            data = self._receive(RESPONSE_BYTES)
        except serial.SerialException as e:
            messagebox.showerror("Error de comunicación", str(e))
            return

        expected = alu_model(a, b, op)
        self.res_vars["Esperado"].set(f"0x{expected:02X}")

        if len(data) < RESPONSE_BYTES:
            for k in ("Hex", "Sin signo", "Con signo", "Binario"):
                self.res_vars[k].set("—")
            self._set_status("sin respuesta", "orange")
            self.log_msg("Timeout: la FPGA no respondió")
            return

        r = data[0]
        self.res_vars["Hex"].set(f"0x{r:02X}")
        self.res_vars["Sin signo"].set(str(r))
        self.res_vars["Con signo"].set(str(to_signed(r)))
        self.res_vars["Binario"].set(f"{r:08b}")

        if r == expected:
            self._set_status("✓ correcto", "green")
        else:
            self._set_status("✗ distinto", "red")

    def send_raw(self):
        try:
            data = [int(tok, 16) for tok in self.raw_var.get().split()]
            if not data or any(not 0 <= x <= 255 for x in data):
                raise ValueError
        except ValueError:
            messagebox.showerror("Entrada inválida",
                                 "Escribí bytes en hex separados por espacio, "
                                 "por ejemplo: 41 42 FF")
            return

        try:
            self._send(data)
            received = self._receive(len(data))
        except serial.SerialException as e:
            messagebox.showerror("Error de comunicación", str(e))
            return

        if len(received) < len(data):
            self.log_msg(f"Llegaron {len(received)} de {len(data)} bytes")
        elif list(received) == data:
            self.log_msg("Loopback OK")
        else:
            self.log_msg("Loopback: los bytes no coinciden")

    def on_close(self):
        if self.ser and self.ser.is_open:
            self.ser.close()
        self.destroy()


if __name__ == "__main__":
    AluGui().mainloop()