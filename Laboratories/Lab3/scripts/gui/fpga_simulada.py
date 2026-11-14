"""
fpga_simulada.py - Una FPGA "de mentira" que habla EXACTAMENTE el mismo
protocolo que la real, byte por byte (src/params.vh, seccion 6).

Sirve para:
  * el "modo demo" del depurador (usar toda la app sin la placa);
  * los tests del protocolo y de la vista del pipeline.

Por dentro imita a control_fsmd (la debug_unit) y, para el procesador, usa
pipeline_sim.py: un simulador ciclo a ciclo del cpu que reproduce los 480 bits
de los latches igual que el RTL (verificado con Icarus Verilog en
tests/test_pipeline_sim.py). Asi el volcado simulado trae registros, memoria,
PC, estado Y latches reales.

Limitacion: un programa sin fin "corre" a VELOCIDAD ciclos por segundo (la
placa hace 70 millones, a 70 MHz). 'R' primero simula hasta CICLOS_RAPIDOS
ciclos de golpe; si no se detuvo, queda corriendo y al llegar la 'I' se
simula hasta el ciclo que corresponde al tiempo transcurrido.

Mismos metodos que transporte.PuertoSerie:
    escribir(bytes), leer(n, timeout), vaciar_entrada(), cerrar()
"""
import threading
import time

import rutas  # noqa: F401  (agrega scripts/ al path)
from decodificador import armar_volcado, N_MEM_WORDS
from pipeline_sim import PipelineSim
from protocolo import ErrorConexion

VELOCIDAD = 2000            # ciclos por segundo de un 'R' sin fin (simulado)
CICLOS_RAPIDOS = 5000       # 'R' simula esto de golpe antes de quedar "corriendo"
MAX_CICLOS_SIN_FIN = 200_000
IMEM_WORDS = 256


class FpgaSimulada:

    def __init__(self, retardo_byte=0.0):
        """retardo_byte: segundos por byte de respuesta (0 = instantaneo).
        Con 10/115200 se imita la velocidad real de la UART."""
        self.retardo_byte = retardo_byte
        self._salida = bytearray()
        self._cv = threading.Condition()
        self._desconectada = False
        # Al configurar la FPGA: programa todo en HALT, memoria de datos en 0.
        self.cpu = PipelineSim([], [0] * N_MEM_WORDS)
        self.interrumpido = False
        self._fsm = "IDLE"                         # IDLE, LOAD_LEN, LOAD_WORD, RUN
        self._acum = bytearray()
        self._n_words = 0
        self._palabras = []
        self._t_run = 0.0
        self._c_run = 0

    # -------------------------------------------------- procesador
    @property
    def imem(self):
        return self.cpu.imem

    @property
    def dmem(self):
        return self.cpu.dmem

    @property
    def ciclos(self):
        return self.cpu.ciclos

    @property
    def detenido(self):
        return bool(self.cpu.halted)

    def _reset_cpu(self):
        """i_cpu_reset: PC, registros, latches y halted en 0; contador de ciclos
        y bit de interrumpido en 0. Las memorias (RAM) NO se borran."""
        self.cpu.reset()
        self.interrumpido = False

    def _volcado(self):
        c = self.cpu
        estado = (0x05 if c.fault else 0x01 if c.halted else 0) | (2 if self.interrumpido else 0)
        return armar_volcado(c.pc, c.ciclos, estado, [c.reg(i) for i in range(32)],
                             c.dmem, c.latches_bits())

    # -------------------------------------------------- debug_unit (control_fsmd)
    def _responder(self, datos):
        with self._cv:
            self._salida += datos
            self._cv.notify_all()

    def _byte(self, b):
        if self._fsm == "IDLE":
            c = bytes([b])
            if c == b"X":
                self._reset_cpu()
                self._responder(b"K")
            elif c == b"L":
                self._fsm, self._acum = "LOAD_LEN", bytearray()
            elif c == b"D":
                self._responder(self._volcado())
            elif c == b"S":
                self.interrumpido = False
                self.cpu.paso()                      # detenido: no hace nada
                self._responder(self._volcado())
            elif c == b"R":
                self.interrumpido = False
                if self.cpu.correr(self.cpu.ciclos + CICLOS_RAPIDOS):
                    self._responder(self._volcado())
                else:
                    self._fsm, self._t_run, self._c_run = "RUN", time.monotonic(), self.cpu.ciclos
            # cualquier otro byte (incluida 'I' fuera de RUN): se descarta
        elif self._fsm == "RUN":
            if b == ord("I"):                        # todo lo demas se ignora
                avance = int((time.monotonic() - self._t_run) * VELOCIDAD)
                objetivo = min(self._c_run + max(avance, 1), MAX_CICLOS_SIN_FIN)
                # Si se detiene antes, gana el HALT (como en la placa).
                self.interrumpido = not self.cpu.correr(objetivo)
                self._fsm = "IDLE"
                self._responder(self._volcado())
        elif self._fsm == "LOAD_LEN":
            self._acum.append(b)
            if len(self._acum) == 2:
                self._n_words = int.from_bytes(self._acum, "little")
                self._palabras, self._acum = [], bytearray()
                self._fsm = "LOAD_WORD" if self._n_words else "IDLE"
                if not self._n_words:
                    self._fin_carga()
        elif self._fsm == "LOAD_WORD":
            self._acum.append(b)
            if len(self._acum) == 4:
                self._palabras.append(int.from_bytes(self._acum, "little"))
                self._acum = bytearray()
                if len(self._palabras) == self._n_words:
                    self._fsm = "IDLE"
                    self._fin_carga()

    def _fin_carga(self):
        """WRITE + CLEAR: el programa, HALT en el resto, la 255 siempre HALT;
        las palabras 256+ se descartan. Despues RESET + 'K'."""
        p = self._palabras[:IMEM_WORDS]
        self.cpu.imem[:] = p + [0] * (IMEM_WORDS - len(p))
        self.cpu.imem[IMEM_WORDS - 1] = 0
        self._reset_cpu()
        self._responder(b"K")

    # -------------------------------------------------- interfaz de transporte
    def escribir(self, datos):
        if self._desconectada:
            raise ErrorConexion("FPGA simulada desconectada")
        for b in bytes(datos):
            self._byte(b)

    def leer(self, n, timeout):
        if self._desconectada:
            raise ErrorConexion("FPGA simulada desconectada")
        limite = time.monotonic() + timeout
        with self._cv:
            while not self._salida:
                resto = limite - time.monotonic()
                if resto <= 0:
                    return b""
                self._cv.wait(resto)
            n = min(n, len(self._salida))
            if self.retardo_byte:
                n = min(n, max(1, int(timeout / self.retardo_byte)))
            datos = bytes(self._salida[:n])
            del self._salida[:n]
        if self.retardo_byte:
            time.sleep(self.retardo_byte * len(datos))
        return datos

    def vaciar_entrada(self):
        with self._cv:
            self._salida.clear()

    def cerrar(self):
        pass

    def desconectar(self):
        """Para probar el aviso de "cable desconectado"."""
        self._desconectada = True
