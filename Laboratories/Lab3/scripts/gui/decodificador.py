"""
decodificador.py - Convierte los 326 bytes de un volcado en un objeto Estado.

Formato (src/params.vh, seccion 6), todo en little-endian:

    offset  bytes  contenido
    0       1      cabecera 0xA5
    1       4      PC
    5       4      ciclos
    9       1      estado: bit 0 detenido, bit 1 interrumpido, bit 2 error
    10      128    registros x0..x31
    138     60     latches (480 bits; campos en campos_latches.py)
    198     128    memoria de datos, palabras 0..31

Uso:
    estado = decodificar(datos)        # ErrorVolcado si el largo o la cabecera estan mal
    estado.regs[5], estado.mem[0], estado.campo("MEM/WB", "halt")
"""
from dataclasses import dataclass, field

import campos_latches as cl

DUMP_LEN = 326
DUMP_HEADER = 0xA5
OFF_PC, OFF_CYC, OFF_ST, OFF_REG, OFF_LAT, OFF_MEM = 1, 5, 9, 10, 138, 198
N_REGS, N_LATCH_WORDS, N_MEM_WORDS = 32, 15, 32

# Nombres ABI de los registros (para la tabla de la interfaz).
NOMBRES_ABI = ["zero", "ra", "sp", "gp", "tp", "t0", "t1", "t2", "s0/fp", "s1",
               "a0", "a1", "a2", "a3", "a4", "a5", "a6", "a7",
               "s2", "s3", "s4", "s5", "s6", "s7", "s8", "s9", "s10", "s11",
               "t3", "t4", "t5", "t6"]


class ErrorVolcado(Exception):
    """El volcado recibido no tiene el formato esperado."""


@dataclass
class Campo:
    latch: str
    nombre: str
    ancho: int
    valor: int
    descripcion: str

    @property
    def es_control(self):
        return self.ancho == 1


@dataclass
class Estado:
    pc: int
    ciclos: int
    estado: int                      # byte de estado crudo
    regs: list
    mem: list
    lat_bits: int                    # los 480 bits de o_latches
    latches: dict = field(default_factory=dict)   # latch -> [Campo]
    crudo: bytes = b""

    # Bits del byte de estado
    @property
    def detenido(self):
        return bool(self.estado & 1)

    @property
    def interrumpido(self):
        return bool(self.estado & 2)

    @property
    def error(self):
        return bool(self.estado & 4)

    def campo(self, latch, nombre):
        for c in self.latches[latch]:
            if c.nombre == nombre:
                return c.valor
        raise KeyError(f"{latch}.{nombre}")

    def es_burbuja(self, latch):
        return self.campo(latch, "valid") == 0

    def texto_estado(self):
        """Texto corto para el "chip" de estado de la interfaz."""
        if self.error:
            return "Error"
        if self.detenido:
            return "Terminó (HALT)"
        if self.interrumpido:
            return "Interrumpido"
        return "Listo"


def palabra(datos, pos):
    return int.from_bytes(datos[pos:pos + 4], "little")


def decodificar(datos):
    """bytes (326) -> Estado. Lanza ErrorVolcado con un mensaje claro."""
    datos = bytes(datos)
    if len(datos) != DUMP_LEN:
        raise ErrorVolcado(f"el volcado tiene {len(datos)} bytes y se esperaban {DUMP_LEN}")
    if datos[0] != DUMP_HEADER:
        raise ErrorVolcado(f"cabecera 0x{datos[0]:02X}, se esperaba 0x{DUMP_HEADER:02X}")
    lat_bits = int.from_bytes(datos[OFF_LAT:OFF_LAT + cl.LATCHES_W // 8], "little")
    latches = {l: [] for l in cl.LATCHES}
    for c in cl.CAMPOS:
        latches[c[0]].append(Campo(c[0], c[1], cl.ancho(c), cl.valor(lat_bits, c), c[4]))
    return Estado(
        pc=palabra(datos, OFF_PC),
        ciclos=palabra(datos, OFF_CYC),
        estado=datos[OFF_ST],
        regs=[palabra(datos, OFF_REG + 4 * i) for i in range(N_REGS)],
        mem=[palabra(datos, OFF_MEM + 4 * i) for i in range(N_MEM_WORDS)],
        lat_bits=lat_bits,
        latches=latches,
        crudo=datos,
    )


def armar_volcado(pc, ciclos, estado, regs, mem, lat_bits):
    """Operacion inversa (la usa la FPGA simulada y los tests)."""
    out = bytearray(DUMP_LEN)
    out[0] = DUMP_HEADER
    out[OFF_PC:OFF_PC + 4] = (pc & 0xFFFFFFFF).to_bytes(4, "little")
    out[OFF_CYC:OFF_CYC + 4] = (ciclos & 0xFFFFFFFF).to_bytes(4, "little")
    out[OFF_ST] = estado & 0xFF
    for i in range(N_REGS):
        out[OFF_REG + 4 * i:OFF_REG + 4 * i + 4] = (regs[i] & 0xFFFFFFFF).to_bytes(4, "little")
    out[OFF_LAT:OFF_LAT + 60] = lat_bits.to_bytes(60, "little")
    for i in range(N_MEM_WORDS):
        out[OFF_MEM + 4 * i:OFF_MEM + 4 * i + 4] = (mem[i] & 0xFFFFFFFF).to_bytes(4, "little")
    return bytes(out)


# Patron de los latches despues de un reset: todo burbuja, IF/ID.instr = NOP.
LAT_RESET = 0x13 << 416
# Al detenerse por HALT: ademas MEM/WB.valid = MEM/WB.halt = 1.
LAT_HALT = LAT_RESET | 0x5
