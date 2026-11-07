#!/usr/bin/env python3
"""
uart_test.py - Prueba de la comunicacion PC <-> FPGA (apartado B).

Requisito:  pip install pyserial

Uso:
  python uart_test.py --list                 lista los puertos serie disponibles
  python uart_test.py COM5 echo              paso 1: manda texto y espera el MISMO eco
  python uart_test.py COM5 echo "Hola!"      idem con otro texto
  python uart_test.py COM5 x                 paso 3: manda 'X' y espera 'K'
  python uart_test.py COM5 l prog.hex        carga el programa de prog.hex ('L') y espera 'K'
  python uart_test.py COM5 l prog.hex --verificar
                                             idem, y despues compara con un 'D' (SOLO con el
                                             cpu_stub: su volcado muestra la memoria de programa)
  python uart_test.py COM5 d                 manda 'D', recibe los 314 bytes del volcado
                                             y los muestra ordenados
  python uart_test.py COM5 d --raw           idem, y ademas los 314 bytes en hex
  python uart_test.py COM5 s                 manda 'S' (un ciclo de clock) y muestra el volcado
  python uart_test.py COM5 step              paso a paso interactivo: Enter = un 'S', muestra
                                             solo lo que cambio; 'd' = volcado completo,
                                             'x' = reset del procesador, 'q' = salir
  python uart_test.py COM5 r                 manda 'R' (correr hasta el HALT) y muestra el
                                             volcado. Enter = mandar 'I' (interrumpir)
  python uart_test.py COM5 terminal          modo interactivo: lo que escribis se manda,
                                             lo que vuelve se muestra en hex y ASCII

En Linux el puerto es algo como /dev/ttyUSB1 (en la Basys 3 suele ser el de
numero mas alto: el otro es el JTAG). En Windows: COM3, COM5, etc.

Formato de los programas (.hex): una instruccion de 32 bits en hexadecimal por
linea, en orden (la primera va a la direccion 0). El prefijo 0x es opcional y
todo lo que sigue a un '#' es comentario. Es el formato que leen $readmemh de
Verilog y el "Dump Memory -> Hexadecimal Text" de RARS. Ejemplo:
    00500093    # addi x1, x0, 5
    00308113    # addi x2, x1, 3
    00000000    # HALT

Cerrá cualquier terminal serie (PuTTY, RealTerm...) antes de correr el script:
un puerto serie solo puede estar abierto por un programa a la vez.
"""
import argparse
import sys
import threading
import time

try:
    import serial
    import serial.tools.list_ports
except ImportError:
    sys.exit("Falta pyserial. Instalalo con:  pip install pyserial")

BAUD = 115200
FRAME_S = 10 / BAUD          # tiempo de un byte (start + 8 datos + stop)
TIMEOUT_S = 0.5              # espera maxima por una respuesta


def abrir(puerto):
    """Abre el puerto con la configuracion de la FPGA: 115200 8N1."""
    return serial.serial_for_url(puerto, baudrate=BAUD, bytesize=8, parity="N",
                                 stopbits=1, timeout=TIMEOUT_S)


def mostrar(datos):
    """Bytes como hex + ASCII imprimible, ej: 4B 'K'."""
    hexa = " ".join(f"{b:02X}" for b in datos)
    asc = "".join(chr(b) if 32 <= b < 127 else "." for b in datos)
    return f"{hexa}   '{asc}'"


def listar():
    puertos = list(serial.tools.list_ports.comports())
    if not puertos:
        print("No se encontro ningun puerto serie. ¿Esta conectada la placa?")
    for p in puertos:
        print(f"{p.device:15s} {p.description}")


def prueba_echo(ser, texto):
    """Paso 1 (echo_ctrl): cada byte tiene que volver igual."""
    enviado = texto.encode("latin-1")
    ser.reset_input_buffer()
    errores = 0
    for b in enviado:
        # Protocolo pedido -> respuesta: se manda un byte y se espera su eco
        # antes del siguiente (el buffer de recepcion de la FPGA es de 1 byte).
        ser.write(bytes([b]))
        r = ser.read(1)
        if r != bytes([b]):
            errores += 1
            print(f"  mandado {b:02X}  recibido {mostrar(r) if r else '(nada)'}")
    if errores == 0:
        print(f"OK: {len(enviado)} bytes con eco correcto  ->  {mostrar(enviado)}")
    else:
        print(f"FALLO: {errores} de {len(enviado)} bytes con error")
    return errores == 0


def prueba_x(ser):
    """Paso 3 (debug_unit v1): 'X' -> 'K'; un byte que no es comando -> nada."""
    ok = True
    ser.reset_input_buffer()

    ser.write(b"X")
    r = ser.read(1)
    print(f"'X' -> {mostrar(r) if r else '(nada)'}")
    if r != b"K":
        print("  FALLO: se esperaba 'K' (4B)")
        ok = False

    ser.write(b"?")
    r = ser.read(1)            # espera TIMEOUT_S: no deberia llegar nada
    print(f"'?' -> {mostrar(r) if r else '(nada)'}")
    if r:
        print("  FALLO: un byte que no es comando no deberia tener respuesta")
        ok = False

    print("OK: comando 'X' correcto" if ok else "FALLO")
    return ok


#------------------------------------------------------------------ volcado ('D')
# Formato (params.vh, seccion 6). Valores de 32 bits en little-endian.
DUMP_LEN = 314
DUMP_HEADER = 0xA5
OFF_PC, OFF_CYC, OFF_ST, OFF_REG, OFF_LAT, OFF_MEM = 1, 5, 9, 10, 138, 186
N_REGS, N_LATCH_WORDS, N_MEM_WORDS = 32, 12, 32


def word(data, pos):
    """Palabra de 32 bits little-endian que empieza en data[pos]."""
    return int.from_bytes(data[pos:pos + 4], "little")


def decode_dump(data):
    """Convierte los 314 bytes del volcado en un diccionario con nombre.
    Es la operacion inversa del dump_mux (y el embrion de state_decoder.py)."""
    if len(data) != DUMP_LEN:
        raise ValueError(f"el volcado tiene {len(data)} bytes, se esperaban {DUMP_LEN}")
    if data[0] != DUMP_HEADER:
        raise ValueError(f"cabecera {data[0]:02X}, se esperaba {DUMP_HEADER:02X}")
    return {
        "pc":      word(data, OFF_PC),
        "cycles":  word(data, OFF_CYC),
        "halted":  bool(data[OFF_ST] & 1),           # bit 0
        "interrupted": bool(data[OFF_ST] & 2),       # bit 1: el 'R' se corto con 'I'
        "status":  data[OFF_ST],
        "regs":    [word(data, OFF_REG + 4 * i) for i in range(N_REGS)],
        "latches": [word(data, OFF_LAT + 4 * i) for i in range(N_LATCH_WORDS)],
        "mem":     [word(data, OFF_MEM + 4 * i) for i in range(N_MEM_WORDS)],
    }


def mostrar_dump(d):
    print(f"PC      = 0x{d['pc']:08X}")
    print(f"ciclos  = {d['cycles']}")
    print(f"estado  = 0x{d['status']:02X}   (halted = {int(d['halted'])}, "
          f"interrumpido = {int(d['interrupted'])})")

    print("\nRegistros")
    for fila in range(8):
        celdas = []
        for col in range(4):
            i = fila + 8 * col
            celdas.append(f"x{i:<2} = 0x{d['regs'][i]:08X}")
        print("  " + "    ".join(celdas))

    print("\nLatches (palabra k = bits [32k+31 : 32k] de o_latches)")
    for fila in range(3):
        celdas = []
        for col in range(4):
            k = fila * 4 + col
            celdas.append(f"[{k:2}] 0x{d['latches'][k]:08X}")
        print("  " + "    ".join(celdas))

    print("\nMemoria de datos (palabras 0..31)")
    for fila in range(8):
        celdas = []
        for col in range(4):
            i = fila * 4 + col
            celdas.append(f"[{i:2}] 0x{d['mem'][i]:08X}")
        print("  " + "    ".join(celdas))


def pedir_dump(ser, cmd=b"D"):
    """Manda un comando que responde enseguida con volcado ('D' o 'S') y devuelve los
    bytes recibidos (314 si todo salio bien)."""
    ser.reset_input_buffer()
    ser.write(cmd)
    # 314 bytes a 115200 tardan ~27 ms; se deja margen de sobra.
    old = ser.timeout
    ser.timeout = 1.0
    data = ser.read(DUMP_LEN)
    ser.timeout = old
    return data


def prueba_d(ser, raw=False, cmd=b"D"):
    data = pedir_dump(ser, cmd)
    if raw:
        for i in range(0, len(data), 16):
            print(f"  {i:3}: " + " ".join(f"{b:02X}" for b in data[i:i + 16]))
        print()
    try:
        d = decode_dump(data)
    except ValueError as e:
        print(f"FALLO: {e}")
        return False
    mostrar_dump(d)
    print(f"\nOK: volcado de {len(data)} bytes con cabecera correcta")
    return True


def diferencias(antes, ahora):
    """Lista de lineas con lo que cambio entre dos volcados decodificados."""
    lineas = []
    for campo, fmt in (("pc", "0x{:08X}"), ("cycles", "{}"), ("halted", "{}"),
                       ("interrupted", "{}")):
        if antes[campo] != ahora[campo]:
            va, vb = int(antes[campo]), int(ahora[campo])
            lineas.append(f"{campo:11} {fmt.format(va)} -> {fmt.format(vb)}")
    for nombre, clave in (("x", "regs"), ("latch ", "latches"), ("mem ", "mem")):
        for i, (a, b) in enumerate(zip(antes[clave], ahora[clave])):
            if a != b:
                lineas.append(f"{nombre}{i:<6} 0x{a:08X} -> 0x{b:08X}")
    return lineas


def paso_a_paso(ser):
    """Modo interactivo: cada Enter manda un 'S' y muestra solo lo que cambio."""
    print("Paso a paso. Enter = 'S' (un ciclo) | d = volcado completo | "
          "x = reset del procesador | q = salir")
    try:
        prev = decode_dump(pedir_dump(ser, b"D"))
    except ValueError as e:
        print(f"FALLO al leer el estado inicial: {e}")
        return False
    print(f"Estado inicial: PC = 0x{prev['pc']:08X}, ciclos = {prev['cycles']}, "
          f"halted = {int(prev['halted'])}")
    try:
        while True:
            op = input("> ").strip().lower()
            if op == "q":
                break
            if op == "x":
                ser.reset_input_buffer()
                ser.write(b"X")
                r = ser.read(1)
                print("  reset del procesador: " + ("OK ('K')" if r == b"K" else f"FALLO ({r!r})"))
                op = "d"                     # mostrar como quedo
            cmd = b"D" if op == "d" else b"S"
            try:
                ahora = decode_dump(pedir_dump(ser, cmd))
            except ValueError as e:
                print(f"  FALLO: {e}")
                continue
            if op == "d":
                mostrar_dump(ahora)
            else:
                cambios = diferencias(prev, ahora)
                print(f"  ciclo {ahora['cycles']}:")
                for linea in cambios or ["sin cambios (¿procesador detenido?)"]:
                    print("    " + linea)
            prev = ahora
    except (KeyboardInterrupt, EOFError):
        print()
    return True


#------------------------------------------------------------------ corrida ('R')
ESPERA_TRAS_I_S = 2.0        # despues de mandar 'I', el volcado llega en ~27 ms


def correr(ser, raw=False):
    """Manda 'R' y espera el volcado. Mientras tanto, Enter manda 'I'.

    Hay dos "hilos" (threads), es decir, dos cosas que pasan a la vez:
      - el principal lee el puerto de a poco (timeout corto) hasta juntar los
        314 bytes del volcado;
      - otro hilo se queda esperando un Enter del teclado; cuando llega, avisa
        con un Event y el principal manda la 'I'.
    Haga lo que haga el usuario, la FPGA responde UN solo volcado: o porque el
    programa llego al HALT, o porque llego la 'I'. Si la 'I' llega tarde (el
    programa ya termino), la FPGA la ignora.
    """
    enter = threading.Event()

    def esperar_enter():
        try:
            input()
            enter.set()
        except EOFError:
            pass

    ser.reset_input_buffer()
    ser.write(b"R")
    print("Corriendo...  Enter = interrumpir (manda 'I')")
    threading.Thread(target=esperar_enter, daemon=True).start()

    data = b""
    t_inicio = time.monotonic()
    t_I = None                                   # cuando se mando la 'I'
    old = ser.timeout
    ser.timeout = 0.1                            # lecturas cortas: se puede mirar el Enter
    try:
        while len(data) < DUMP_LEN:
            data += ser.read(DUMP_LEN - len(data))
            if enter.is_set() and t_I is None:
                ser.write(b"I")
                t_I = time.monotonic()
                print("  'I' enviada, esperando el volcado...")
            if t_I is not None and time.monotonic() - t_I > ESPERA_TRAS_I_S:
                print(f"FALLO: se mando 'I' y llegaron {len(data)} de {DUMP_LEN} bytes")
                return False
    except KeyboardInterrupt:
        # No dejar la placa en RUN (ahi ignora todo menos la 'I').
        ser.write(b"I")
        ser.timeout = 1.0
        ser.read(DUMP_LEN - len(data))           # se descarta el volcado
        print("\nCancelado: se mando 'I' para dejar la placa en IDLE")
        return False
    finally:
        ser.timeout = old
    t_total = time.monotonic() - t_inicio

    if raw:
        for i in range(0, len(data), 16):
            print(f"  {i:3}: " + " ".join(f"{b:02X}" for b in data[i:i + 16]))
        print()
    try:
        d = decode_dump(data)
    except ValueError as e:
        print(f"FALLO: {e}")
        return False

    if d["interrupted"]:
        print(f"Interrumpido en PC = 0x{d['pc']:08X} despues de {d['cycles']} ciclos")
    elif d["halted"]:
        extra = "  (la 'I' llego tarde y se ignoro)" if t_I is not None else ""
        print(f"Termino (HALT) en PC = 0x{d['pc']:08X}, ciclos = {d['cycles']}{extra}")
    else:
        print("FALLO: el volcado no indica ni HALT ni interrupcion")
        return False
    print(f"(respuesta en {t_total:.2f} s)\n")
    mostrar_dump(d)
    return True


#------------------------------------------------------------------ carga ('L')
IMEM_WORDS = 256             # palabras de la memoria de programa
INSTR_HALT = 0x00000000


def leer_hex(ruta):
    """Lee un .hex (una palabra por linea, '#' = comentario) y devuelve la
    lista de palabras. Corta con un mensaje claro si una linea no es valida."""
    palabras = []
    with open(ruta, encoding="utf-8") as f:
        for n, linea in enumerate(f, start=1):
            texto = linea.split("#")[0].strip()
            if not texto:
                continue
            try:
                v = int(texto, 16)
            except ValueError:
                sys.exit(f"{ruta}, linea {n}: '{texto}' no es un numero hexadecimal")
            if not 0 <= v <= 0xFFFFFFFF:
                sys.exit(f"{ruta}, linea {n}: {texto} no entra en 32 bits")
            palabras.append(v)
    return palabras


def armar_carga(palabras):
    """Bytes del comando: 'L', N (2 bytes, LSB primero) y cada palabra en
    little-endian. Recorta a 256 palabras y avisa lo que va a hacer la FPGA."""
    if len(palabras) > IMEM_WORDS:
        print(f"AVISO: el programa tiene {len(palabras)} palabras y la memoria {IMEM_WORDS}: "
              f"se mandan solo las primeras {IMEM_WORDS}")
        palabras = palabras[:IMEM_WORDS]
    if len(palabras) == IMEM_WORDS and palabras[-1] != INSTR_HALT:
        print(f"AVISO: la palabra {IMEM_WORDS - 1} (0x{palabras[-1]:08X}) se reemplaza por HALT: "
              "la ultima palabra de la memoria siempre es HALT")
    datos = b"L" + len(palabras).to_bytes(2, "little")
    for p in palabras:
        datos += p.to_bytes(4, "little")
    return palabras, datos


def cargar(ser, ruta, verificar=False):
    """Manda el programa con 'L' y espera la 'K' (carga terminada y procesador
    reseteado). La FPGA escribe HALT en el resto de la memoria."""
    palabras, datos = armar_carga(leer_hex(ruta))
    n = len(palabras)
    print(f"Cargando {n} palabras ({len(datos)} bytes)...")
    ser.reset_input_buffer()
    ser.write(datos)                       # todo seguido: la FPGA lo consume al vuelo
    old = ser.timeout
    ser.timeout = len(datos) * FRAME_S + 1.0
    r = ser.read(1)
    ser.timeout = old
    if r != b"K":
        print(f"FALLO: se esperaba 'K' y llego {mostrar(r) if r else '(nada)'}")
        return False
    print(f"OK: {n} palabras cargadas, resto de la memoria en HALT, procesador reseteado ('K')")
    if not verificar:
        return True

    # Solo con el cpu_stub: el volcado muestra la memoria de PROGRAMA (palabras 0..31)
    try:
        d = decode_dump(pedir_dump(ser, b"D"))
    except ValueError as e:
        print(f"FALLO al verificar: {e}")
        return False
    esperado = [(palabras[i] if i < n and i != IMEM_WORDS - 1 else INSTR_HALT)
                for i in range(N_MEM_WORDS)]
    malas = [i for i in range(N_MEM_WORDS) if d["mem"][i] != esperado[i]]
    for i in malas[:8]:
        print(f"  palabra {i}: 0x{d['mem'][i]:08X}, esperado 0x{esperado[i]:08X}")
    if malas:
        print(f"FALLO: {len(malas)} de las primeras {N_MEM_WORDS} palabras no coinciden")
        return False
    print(f"OK: las primeras {N_MEM_WORDS} palabras coinciden (verificado con 'D', cpu_stub)")
    return True


def terminal(ser):
    """Modo interactivo. Ctrl+C para salir."""
    print("Escribí texto y Enter (se manda sin el Enter). Ctrl+C para salir.")
    print("Tip: '\\x58' manda el byte 0x58 en crudo.")
    try:
        while True:
            linea = input("> ")
            datos = linea.encode("latin-1").decode("unicode_escape").encode("latin-1")
            if not datos:
                continue
            ser.reset_input_buffer()
            ser.write(datos)
            time.sleep(FRAME_S * len(datos) * 2 + 0.05)
            r = ser.read(ser.in_waiting or 1)
            print(f"  recibido: {mostrar(r) if r else '(nada)'}")
    except (KeyboardInterrupt, EOFError):
        print()


def main():
    ap = argparse.ArgumentParser(description="Prueba de la UART de la FPGA")
    ap.add_argument("--list", action="store_true", help="listar puertos serie")
    ap.add_argument("puerto", nargs="?", help="ej: COM5 o /dev/ttyUSB1")
    ap.add_argument("modo", nargs="?", choices=["echo", "x", "l", "d", "s", "r", "step", "terminal"])
    ap.add_argument("texto", nargs="?", default=None,
                    help="modo echo: texto a mandar; modo l: archivo .hex")
    ap.add_argument("--verificar", action="store_true",
                    help="modo l: comparar con un 'D' (solo con el cpu_stub)")
    ap.add_argument("--raw", action="store_true", help="modos d, s y r: mostrar tambien los bytes en hex")
    a = ap.parse_args()

    if a.list or not a.puerto:
        listar()
        return
    if not a.modo:
        ap.error("falta el modo: echo, x, l, d, s, r, step o terminal")
    if a.modo == "l" and not a.texto:
        ap.error("modo l: falta el archivo .hex (ej: uart_test.py /dev/ttyUSB1 l prog.hex)")

    try:
        ser = abrir(a.puerto)
    except serial.SerialException as e:
        sys.exit(f"No se pudo abrir {a.puerto}: {e}\n"
                 "¿Puerto correcto? ¿Hay otro programa usandolo?")

    with ser:
        if a.modo == "echo":
            ok = prueba_echo(ser, a.texto or "Hola FPGA 0123456789")
        elif a.modo == "l":
            ok = cargar(ser, a.texto, a.verificar)
        elif a.modo == "x":
            ok = prueba_x(ser)
        elif a.modo == "d":
            ok = prueba_d(ser, a.raw)
        elif a.modo == "s":
            ok = prueba_d(ser, a.raw, cmd=b"S")
        elif a.modo == "r":
            ok = correr(ser, a.raw)
        elif a.modo == "step":
            ok = paso_a_paso(ser)
        else:
            terminal(ser)
            ok = True
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
