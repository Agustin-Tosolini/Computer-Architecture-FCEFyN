"""Las constantes de Python tienen que coincidir con src/params.vh (la fuente
de verdad del protocolo): tamano y offsets del volcado, comandos y la tabla de
campos de los latches. Tambien con scripts/uart_test.py (la herramienta de
consola), para que las dos lean el volcado igual."""
import re

import pytest

import campos_latches as cl
import decodificador as dec
import protocolo
import rutas


@pytest.fixture(scope="module")
def params():
    with open(rutas.PARAMS_VH, encoding="utf-8") as f:
        return f.read()


def _define(texto, nombre):
    m = re.search(rf"`define\s+{nombre}\s+(\d+)'h([0-9A-Fa-f]+)", texto)
    if m:
        return int(m.group(2), 16)
    return int(re.search(rf"`define\s+{nombre}\s+(\d+)", texto).group(1))


def test_tamano_y_offsets_del_volcado(params):
    filas = re.findall(r"^//\s+(\d+)\s+(\d+)\s+(\S.*)$", params, re.M)
    offsets = {desc.split()[0]: (int(o), int(n)) for o, n, desc in filas}
    assert offsets["DUMP_HEADER"] == (0, 1)
    assert offsets["PC"] == (dec.OFF_PC, 4)
    assert offsets["Contador"] == (dec.OFF_CYC, 4)
    assert offsets["Estado:"] == (dec.OFF_ST, 1)
    assert offsets["Registros"] == (dec.OFF_REG, 4 * dec.N_REGS)
    assert offsets["Latches"] == (dec.OFF_LAT, cl.LATCHES_W // 8)
    assert offsets["Memoria"] == (dec.OFF_MEM, 4 * dec.N_MEM_WORDS)
    total = int(re.search(r"^//\s+Total\s+(\d+)", params, re.M).group(1))
    assert total == dec.DUMP_LEN == dec.OFF_MEM + 4 * dec.N_MEM_WORDS
    assert _define(params, "LATCHES_W") == cl.LATCHES_W == 32 * dec.N_LATCH_WORDS
    assert _define(params, "DUMP_MEM_WORDS") == dec.N_MEM_WORDS


def test_comandos(params):
    for nombre, valor in [("CMD_LOAD", protocolo.CMD_LOAD), ("CMD_RUN", protocolo.CMD_RUN),
                          ("CMD_INT", protocolo.CMD_INT), ("CMD_STEP", protocolo.CMD_STEP),
                          ("CMD_DUMP", protocolo.CMD_DUMP), ("CMD_RESET", protocolo.CMD_RESET),
                          ("RSP_ACK", protocolo.RSP_ACK)]:
        assert bytes([_define(params, nombre)]) == valor, nombre
    assert _define(params, "DUMP_HEADER") == dec.DUMP_HEADER
    assert _define(params, "BAUD_RATE") == protocolo.BAUD == 115200


def test_tabla_de_latches_igual_a_params(params):
    tabla = []
    for linea in params.splitlines():
        m = re.match(r"^//\s+(IF/ID|ID/EX|EX/MEM|MEM/WB)\s+(\w+)\s+(\d+)(?::(\d+))?\s", linea)
        if m and m.group(2) != "relleno":
            hi = int(m.group(3))
            tabla.append((m.group(1), m.group(2), hi, int(m.group(4)) if m.group(4) else hi))
    assert tabla == [c[:4] for c in cl.CAMPOS]


def test_tabla_sin_solapamientos():
    usados = set()
    for c in cl.CAMPOS:
        bits = set(range(c[3], c[2] + 1))
        assert not bits & usados, c
        assert c[2] < cl.LATCHES_W
        usados |= bits


def test_igual_que_uart_test():
    import uart_test
    assert uart_test.DUMP_LEN == dec.DUMP_LEN
    assert (uart_test.OFF_PC, uart_test.OFF_CYC, uart_test.OFF_ST, uart_test.OFF_REG,
            uart_test.OFF_LAT, uart_test.OFF_MEM) == (dec.OFF_PC, dec.OFF_CYC, dec.OFF_ST,
                                                      dec.OFF_REG, dec.OFF_LAT, dec.OFF_MEM)
    assert uart_test.CAMPOS_LATCHES == [c[:4] for c in cl.CAMPOS]
