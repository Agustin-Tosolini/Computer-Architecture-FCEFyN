"""
desensamblador.py - Palabra de 32 bits -> texto en ensamblador.

El texto usa la MISMA sintaxis que acepta scripts/ensamblador.py, asi que
ensamblar(desensamblar(w)) == w para toda instruccion soportada (lo verifica
tests/test_desensamblador.py).

    desensamblar(0x00500093)       -> "addi x1, x0, 5"
    desensamblar(0x00000013)       -> "nop"
    desensamblar(0x00000000)       -> "halt"
    desensamblar(0xFFFFFFFF)       -> ".word 0xFFFFFFFF"   (no soportada)
    destino(0x00108663, pc=8)      -> 0x14                 (a donde salta)

Los saltos (beq, bne, jal) se muestran con el desplazamiento en bytes,
relativo a la instruccion, como en el ensamblador de GNU.
"""

R = {(0x00, 0): "add", (0x20, 0): "sub", (0x00, 1): "sll", (0x00, 2): "slt",
     (0x00, 3): "sltu", (0x00, 4): "xor", (0x00, 5): "srl", (0x20, 5): "sra",
     (0x00, 6): "or", (0x00, 7): "and"}
I_ARIT = {0: "addi", 2: "slti", 3: "sltiu", 4: "xori", 6: "ori", 7: "andi"}
LOADS = {0: "lb", 1: "lh", 2: "lw", 4: "lbu", 5: "lhu"}
STORES = {0: "sb", 1: "sh", 2: "sw"}


def _sext(v, bits):
    v &= (1 << bits) - 1
    return v - (1 << bits) if v & (1 << (bits - 1)) else v


def _campos(w):
    return (w & 0x7F, (w >> 7) & 0x1F, (w >> 12) & 7, (w >> 15) & 0x1F,
            (w >> 20) & 0x1F, (w >> 25) & 0x7F)


def _imm_b(w):
    return _sext((((w >> 31) & 1) << 12) | (((w >> 7) & 1) << 11) |
                 (((w >> 25) & 0x3F) << 5) | (((w >> 8) & 0xF) << 1), 13)


def _imm_j(w):
    return _sext((((w >> 31) & 1) << 20) | (((w >> 12) & 0xFF) << 12) |
                 (((w >> 20) & 1) << 11) | (((w >> 21) & 0x3FF) << 1), 21)


def desensamblar(w):
    """Palabra -> texto. Lo que no es una instruccion soportada se muestra
    como '.word 0x...' (asi la ida y vuelta tambien funciona)."""
    w &= 0xFFFFFFFF
    if w == 0:
        return "halt"
    if w == 0x13:
        return "nop"
    op, rd, f3, rs1, rs2, f7 = _campos(w)
    x = lambda n: f"x{n}"
    if op == 0x33 and (f7, f3) in R:
        return f"{R[(f7, f3)]} {x(rd)}, {x(rs1)}, {x(rs2)}"
    if op == 0x13:
        if f3 == 1 and f7 == 0:
            return f"slli {x(rd)}, {x(rs1)}, {rs2}"
        if f3 == 5 and f7 in (0, 0x20):
            return f"{'srai' if f7 else 'srli'} {x(rd)}, {x(rs1)}, {rs2}"
        if f3 in I_ARIT:
            return f"{I_ARIT[f3]} {x(rd)}, {x(rs1)}, {_sext(w >> 20, 12)}"
    if op == 0x03 and f3 in LOADS:
        return f"{LOADS[f3]} {x(rd)}, {_sext(w >> 20, 12)}({x(rs1)})"
    if op == 0x23 and f3 in STORES:
        imm = _sext(((w >> 25) << 5) | ((w >> 7) & 0x1F), 12)
        return f"{STORES[f3]} {x(rs2)}, {imm}({x(rs1)})"
    if op == 0x63 and f3 in (0, 1):
        return f"{'beq' if f3 == 0 else 'bne'} {x(rs1)}, {x(rs2)}, {_imm_b(w)}"
    if op == 0x6F:
        return f"jal {x(rd)}, {_imm_j(w)}"
    if op == 0x67 and f3 == 0:
        return f"jalr {x(rd)}, {_sext(w >> 20, 12)}({x(rs1)})"
    if op == 0x37:
        return f"lui {x(rd)}, 0x{w >> 12:X}"
    return f".word 0x{w:08X}"


def es_soportada(w):
    return not desensamblar(w).startswith(".word")


def destino(w, pc):
    """Direccion a la que salta un beq/bne/jal ubicado en pc (None si no es uno)."""
    op = w & 0x7F
    if op == 0x63:
        return (pc + _imm_b(w)) & 0xFFFFFFFF
    if op == 0x6F:
        return (pc + _imm_j(w)) & 0xFFFFFFFF
    return None
