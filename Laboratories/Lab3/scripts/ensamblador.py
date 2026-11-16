#!/usr/bin/env python3
"""
ensamblador.py - Ensamblador minimo RV32I del Trabajo Final.

Traduce un programa en ensamblador (.asm) al formato .hex que carga el comando
'L' (una palabra hex de 32 bits por linea, '#' = comentario).

Uso:
  python3 ensamblador.py programa.asm               escribe programa.hex al lado
  python3 ensamblador.py programa.asm -o otro.hex
  python3 ensamblador.py programa.asm --listado     muestra direccion, palabra y linea
  python3 ensamblador.py --test                     autoprueba (codificaciones conocidas)

Tambien se usa como modulo (lo importan rv32i_model.py y, mas adelante, la
parte C):
  from ensamblador import ensamblar, a_hex
  listado = ensamblar(texto)          # lista de Linea(addr, word, fuente, nro)

Lenguaje aceptado:
  * Las instrucciones de la consigna:
      tipo R : add sub sll srl sra and or xor slt sltu      rd, rs1, rs2
      tipo I : addi andi ori xori slti sltiu                rd, rs1, imm   (-2048..2047)
               slli srli srai                               rd, rs1, shamt (0..31)
               lb lh lw lbu lhu                             rd, imm(rs1)
               jalr                                         rd, imm(rs1)   o  rd, rs1, imm
      tipo S : sb sh sw                                     rs2, imm(rs1)
      tipo B : beq bne                                      rs1, rs2, etiqueta|desplazamiento
      tipo U : lui                                          rd, imm20      (0..0xFFFFF)
      tipo J : jal                                          rd, etiqueta|desplazamiento
  * halt: nuestra instruccion de parada (0x00000000).
  * Pseudo-instrucciones (se traducen a instrucciones de la consigna; el
    listado muestra la expansion):
      nop            = addi x0, x0, 0
      j etiqueta     = jal  x0, etiqueta
      mv rd, rs      = addi rd, rs, 0
      li rd, valor   = addi rd, x0, valor                 (si entra en 12 bits)
                     = lui rd, alto  [+ addi rd, rd, bajo] (si no: 1 o 2 instrucciones)
      beqz rs, et    = beq rs, x0, et
      bnez rs, et    = bne rs, x0, et
      call et        = jal ra, et
      ret            = jalr x0, 0(ra)
  * Etiquetas: "nombre:" al principio de una linea (puede seguir una instruccion).
  * Comentarios: desde '#' hasta el fin de la linea.
  * Registros: x0..x31 o nombres ABI (zero, ra, sp, gp, tp, t0-t6, s0-s11, fp, a0-a7).
  * Numeros: decimal (con signo) o hexadecimal 0x... .
  * Directiva .word valor: pone una palabra cualquiera (sirve para probar una
    instruccion ilegal). Las directivas .text, .globl y .option se ignoran
    (para poder ensamblar archivos escritos para el ensamblador de GNU).

Los desplazamientos numericos de beq/bne/jal estan en BYTES, relativos a la
instruccion (igual que en el ensamblador de GNU): "beq x1, x2, 8" salta dos
instrucciones hacia adelante.
"""
import argparse
import re
import sys
from collections import namedtuple

# instr: la instruccion real que genero esa palabra (para una pseudo-instruccion,
# su expansion; por ejemplo "lui x5, 0x12345" para una parte de un li).
Linea = namedtuple("Linea", "addr word fuente nro instr", defaults=("",))

IMEM_WORDS = 256                 # memoria de programa: 256 palabras
INSTR_HALT = 0x00000000
INSTR_NOP = 0x00000013


class ErrorAsm(Exception):
    """Error con el numero de linea del archivo fuente."""


#------------------------------------------------------------------ registros
_ABI = ["zero", "ra", "sp", "gp", "tp", "t0", "t1", "t2", "s0", "s1",
        "a0", "a1", "a2", "a3", "a4", "a5", "a6", "a7",
        "s2", "s3", "s4", "s5", "s6", "s7", "s8", "s9", "s10", "s11",
        "t3", "t4", "t5", "t6"]
REGS = {f"x{i}": i for i in range(32)}
REGS.update({n: i for i, n in enumerate(_ABI)})
REGS["fp"] = 8

#------------------------------------------------------------------ tablas
# nombre: (funct7, funct3)
TIPO_R = {"add": (0x00, 0), "sub": (0x20, 0), "sll": (0x00, 1), "slt": (0x00, 2),
          "sltu": (0x00, 3), "xor": (0x00, 4), "srl": (0x00, 5), "sra": (0x20, 5),
          "or": (0x00, 6), "and": (0x00, 7)}
TIPO_I = {"addi": 0, "slti": 2, "sltiu": 3, "xori": 4, "ori": 6, "andi": 7}
SHIFT_I = {"slli": (0x00, 1), "srli": (0x00, 5), "srai": (0x20, 5)}
LOADS = {"lb": 0, "lh": 1, "lw": 2, "lbu": 4, "lhu": 5}
STORES = {"sb": 0, "sh": 1, "sw": 2}
BRANCH = {"beq": 0, "bne": 1}

OP_REG, OP_IMM, OP_LOAD, OP_STORE = 0x33, 0x13, 0x03, 0x23
OP_BRANCH, OP_JAL, OP_JALR, OP_LUI = 0x63, 0x6F, 0x67, 0x37

DIRECTIVAS_IGNORADAS = {".text", ".globl", ".global", ".option"}

# Instrucciones RISC-V que existen pero NO estan en la consigna: mensaje claro
# en lugar de "desconocida" (y nunca se ensamblan en silencio).
NO_SOPORTADAS = {"mul", "mulh", "mulhsu", "mulhu", "div", "divu", "rem", "remu",
                 "auipc", "blt", "bge", "bltu", "bgeu", "ecall", "ebreak", "fence",
                 "csrrw", "csrrs", "csrrc", "lwu", "ld", "sd", "neg", "not", "seqz",
                 "snez", "bgt", "ble", "bgtz", "blez", "la", "jr", "tail"}


#------------------------------------------------------------------ codificacion
def _r(f7, rs2, rs1, f3, rd, op):
    return (f7 << 25) | (rs2 << 20) | (rs1 << 15) | (f3 << 12) | (rd << 7) | op


def _i(imm, rs1, f3, rd, op):
    return ((imm & 0xFFF) << 20) | (rs1 << 15) | (f3 << 12) | (rd << 7) | op


def _s(imm, rs2, rs1, f3, op):
    imm &= 0xFFF
    return ((imm >> 5) << 25) | (rs2 << 20) | (rs1 << 15) | (f3 << 12) | \
           ((imm & 0x1F) << 7) | op


def _b(off, rs2, rs1, f3, op):
    off &= 0x1FFF
    return (((off >> 12) & 1) << 31) | (((off >> 5) & 0x3F) << 25) | (rs2 << 20) | \
           (rs1 << 15) | (f3 << 12) | (((off >> 1) & 0xF) << 8) | \
           (((off >> 11) & 1) << 7) | op


def _j(off, rd, op):
    off &= 0x1FFFFF
    return (((off >> 20) & 1) << 31) | (((off >> 1) & 0x3FF) << 21) | \
           (((off >> 11) & 1) << 20) | (((off >> 12) & 0xFF) << 12) | (rd << 7) | op


#------------------------------------------------------------------ operandos
def _numero(txt):
    try:
        return int(txt, 0)
    except ValueError:
        raise ErrorAsm(f"'{txt}' no es un numero") from None


def _reg(txt):
    r = REGS.get(txt.lower())
    if r is None:
        raise ErrorAsm(f"'{txt}' no es un registro")
    return r


def _rango(v, lo, hi, que):
    if not lo <= v <= hi:
        raise ErrorAsm(f"{que} {v} fuera de rango ({lo}..{hi})")
    return v


_MEM = re.compile(r"^(.*)\(\s*([A-Za-z0-9]+)\s*\)$")


def _mem(txt):
    """'imm(rs1)' -> (imm, rs1). 'imm' puede faltar: '(x2)' = 0(x2)."""
    m = _MEM.match(txt)
    if not m:
        raise ErrorAsm(f"se esperaba imm(registro) y llego '{txt}'")
    imm = m.group(1).strip()
    return (_numero(imm) if imm else 0), _reg(m.group(2))


def _destino(txt, etiquetas, addr):
    """Etiqueta o desplazamiento en bytes -> desplazamiento relativo a addr."""
    if txt in etiquetas:
        return etiquetas[txt] - addr
    if re.match(r"^[-+]?(0x[0-9a-fA-F]+|\d+)$", txt):
        return _numero(txt)
    raise ErrorAsm(f"etiqueta '{txt}' no definida")


def _cant(ops, n, mnem):
    if len(ops) != n:
        raise ErrorAsm(f"{mnem} lleva {n} operandos y tiene {len(ops)}")


def codificar(mnem, ops, etiquetas, addr):
    """Una instruccion (ya sin etiqueta ni comentario) -> palabra de 32 bits."""
    if mnem in TIPO_R:
        _cant(ops, 3, mnem)
        f7, f3 = TIPO_R[mnem]
        return _r(f7, _reg(ops[2]), _reg(ops[1]), f3, _reg(ops[0]), OP_REG)
    if mnem in TIPO_I:
        _cant(ops, 3, mnem)
        imm = _rango(_numero(ops[2]), -2048, 2047, "inmediato")
        return _i(imm, _reg(ops[1]), TIPO_I[mnem], _reg(ops[0]), OP_IMM)
    if mnem in SHIFT_I:
        _cant(ops, 3, mnem)
        f7, f3 = SHIFT_I[mnem]
        sh = _rango(_numero(ops[2]), 0, 31, "desplazamiento")
        return _r(f7, sh, _reg(ops[1]), f3, _reg(ops[0]), OP_IMM)
    if mnem in LOADS:
        _cant(ops, 2, mnem)
        imm, rs1 = _mem(ops[1])
        _rango(imm, -2048, 2047, "desplazamiento")
        return _i(imm, rs1, LOADS[mnem], _reg(ops[0]), OP_LOAD)
    if mnem in STORES:
        _cant(ops, 2, mnem)
        imm, rs1 = _mem(ops[1])
        _rango(imm, -2048, 2047, "desplazamiento")
        return _s(imm, _reg(ops[0]), rs1, STORES[mnem], OP_STORE)
    if mnem in BRANCH:
        _cant(ops, 3, mnem)
        off = _destino(ops[2], etiquetas, addr)
        if off % 2:
            raise ErrorAsm(f"desplazamiento impar ({off})")
        _rango(off, -4096, 4094, "desplazamiento de salto")
        return _b(off, _reg(ops[1]), _reg(ops[0]), BRANCH[mnem], OP_BRANCH)
    if mnem == "jal":
        _cant(ops, 2, mnem)
        off = _destino(ops[1], etiquetas, addr)
        if off % 2:
            raise ErrorAsm(f"desplazamiento impar ({off})")
        _rango(off, -(1 << 20), (1 << 20) - 2, "desplazamiento de salto")
        return _j(off, _reg(ops[0]), OP_JAL)
    if mnem == "jalr":
        if len(ops) == 2:                      # jalr rd, imm(rs1)
            imm, rs1 = _mem(ops[1])
        else:                                  # jalr rd, rs1, imm
            _cant(ops, 3, mnem)
            rs1, imm = _reg(ops[1]), _numero(ops[2])
        _rango(imm, -2048, 2047, "inmediato")
        return _i(imm, rs1, 0, _reg(ops[0]), OP_JALR)
    if mnem == "lui":
        _cant(ops, 2, mnem)
        imm = _rango(_numero(ops[1]), 0, 0xFFFFF, "inmediato de lui")
        return (imm << 12) | (_reg(ops[0]) << 7) | OP_LUI
    if mnem == "halt":
        _cant(ops, 0, mnem)
        return INSTR_HALT
    if mnem == "nop":                          # pseudo: addi x0, x0, 0
        _cant(ops, 0, mnem)
        return INSTR_NOP
    if mnem == "j":                            # pseudo: jal x0, destino
        _cant(ops, 1, mnem)
        return codificar("jal", ["x0", ops[0]], etiquetas, addr)
    if mnem == ".word":
        _cant(ops, 1, mnem)
        return _numero(ops[0]) & 0xFFFFFFFF
    if mnem in NO_SOPORTADAS:
        raise ErrorAsm(f"'{mnem}' es de RISC-V pero no esta soportada (no es parte de "
                       "las instrucciones de la consigna); para probar una instruccion "
                       "ilegal usar .word")
    raise ErrorAsm(f"instruccion desconocida '{mnem}'")


#------------------------------------------------------------------ pseudo-instrucciones
def _s32(v):
    v &= 0xFFFFFFFF
    return v - (1 << 32) if v & 0x80000000 else v


def expandir(mnem, ops):
    """Pseudo-instruccion -> lista de (mnemonico, operandos) reales. Una
    instruccion real se devuelve tal cual. Se llama en la pasada 1 (para saber
    cuantas palabras ocupa) y en la 2."""
    if mnem == "nop":
        _cant(ops, 0, mnem)
        return [("addi", ["x0", "x0", "0"])]
    if mnem == "j":
        _cant(ops, 1, mnem)
        return [("jal", ["x0", ops[0]])]
    if mnem == "mv":
        _cant(ops, 2, mnem)
        return [("addi", [ops[0], ops[1], "0"])]
    if mnem in ("beqz", "bnez"):
        _cant(ops, 2, mnem)
        return [("beq" if mnem == "beqz" else "bne", [ops[0], "x0", ops[1]])]
    if mnem == "call":
        _cant(ops, 1, mnem)
        return [("jal", ["ra", ops[0]])]
    if mnem == "ret":
        _cant(ops, 0, mnem)
        return [("jalr", ["x0", "0(ra)"])]
    if mnem == "li":
        _cant(ops, 2, mnem)
        _reg(ops[0])
        v = _numero(ops[1])
        if not -(1 << 31) <= v <= 0xFFFFFFFF:
            raise ErrorAsm(f"li: {ops[1]} no entra en 32 bits")
        v = _s32(v)
        if -2048 <= v <= 2047:
            return [("addi", [ops[0], "x0", str(v)])]
        alto = ((v + 0x800) >> 12) & 0xFFFFF      # redondeo: bajo queda en -2048..2047
        bajo = _s32(v - (alto << 12))
        out = [("lui", [ops[0], f"0x{alto:X}"])]
        if bajo:
            out.append(("addi", [ops[0], ops[0], str(bajo)]))
        return out
    return [(mnem, ops)]


#------------------------------------------------------------------ dos pasadas
_ETIQ = re.compile(r"^([A-Za-z_.][A-Za-z0-9_.]*)\s*:")


def _separar(linea):
    """Devuelve (etiquetas, mnemonico, operandos) de una linea de texto."""
    texto = linea.split("#", 1)[0].strip()
    etiquetas = []
    while True:
        m = _ETIQ.match(texto)
        if not m:
            break
        etiquetas.append(m.group(1))
        texto = texto[m.end():].strip()
    if not texto:
        return etiquetas, None, []
    partes = texto.split(None, 1)
    mnem = partes[0].lower()
    ops = [o.strip() for o in partes[1].split(",")] if len(partes) > 1 else []
    if any(o == "" for o in ops):
        raise ErrorAsm("operando vacio (sobra o falta una coma)")
    return etiquetas, mnem, ops


def ensamblar(texto):
    """Texto del programa -> lista de Linea(addr, word, fuente, nro)."""
    lineas = texto.splitlines()
    # Pasada 1: direccion de cada etiqueta.
    etiquetas, addr, instrs = {}, 0, []
    for nro, linea in enumerate(lineas, start=1):
        try:
            etqs, mnem, ops = _separar(linea)
        except ErrorAsm as e:
            raise ErrorAsm(f"linea {nro}: {e}") from None
        for et in etqs:
            if et in etiquetas:
                raise ErrorAsm(f"linea {nro}: etiqueta '{et}' repetida")
            etiquetas[et] = addr
        if mnem is None or mnem in DIRECTIVAS_IGNORADAS:
            continue
        try:
            partes = expandir(mnem, ops)
        except ErrorAsm as e:
            raise ErrorAsm(f"linea {nro}: {e}  ->  {linea.strip()}") from None
        for m, o in partes:
            instrs.append((addr, m, o, linea.strip(), nro))
            addr += 4
    if addr > 4 * IMEM_WORDS:
        raise ErrorAsm(f"el programa tiene {addr // 4} palabras y la memoria {IMEM_WORDS}")
    # Pasada 2: codificacion.
    salida = []
    for addr, mnem, ops, fuente, nro in instrs:
        try:
            word = codificar(mnem, ops, etiquetas, addr)
        except ErrorAsm as e:
            raise ErrorAsm(f"linea {nro}: {e}  ->  {fuente}") from None
        instr = mnem + (" " + ", ".join(ops) if ops else "")
        salida.append(Linea(addr, word, fuente, nro, instr))
    return salida


def a_hex(listado, cabecera=""):
    """Listado -> texto .hex (una palabra por linea, la instruccion como comentario)."""
    out = []
    for c in cabecera.splitlines():
        out.append(f"# {c}".rstrip())
    for ln in listado:
        fuente = ln.fuente.split("#", 1)[0].strip()
        # Etiqueta adelante ("loop: add ...") se saca para comparar con instr.
        sin_etq = _ETIQ.sub("", fuente).strip()
        while _ETIQ.match(sin_etq):
            sin_etq = _ETIQ.sub("", sin_etq).strip()
        extra = ""
        if ln.instr and " ".join(sin_etq.split()) != " ".join(ln.instr.split()):
            extra = f"   -> {ln.instr}"         # expansion de una pseudo-instruccion
        out.append(f"{ln.word:08X}    # 0x{ln.addr:03X}: {fuente}{extra}")
    return "\n".join(out) + "\n"


#------------------------------------------------------------------ autoprueba
# Codificaciones conocidas (sacadas de testbench/tb_cpu.v, generadas con el
# ensamblador de GNU / RARS).
CONOCIDAS = [
    ("addi x1, x0, 5", 0, 0x00500093), ("addi x1, x1, 2", 0, 0x00208093),
    ("add x2, x1, x1", 0, 0x00108133), ("sw x2, 0(x0)", 0, 0x00202023),
    ("lw x3, 0(x0)", 0, 0x00002183), ("addi x6, x0, -8", 0, 0xFF800313),
    ("sub x8, x6, x7", 0, 0x40730433), ("sll x8, x6, x7", 0, 0x00731433),
    ("sra x8, x6, x7", 0, 0x40735433), ("sltu x8, x6, x7", 0, 0x00733433),
    ("srai x9, x6, 2", 0, 0x40235493), ("sh x6, 6(x0)", 0, 0x00601323),
    ("lbu x11, 100(x0)", 0, 0x06404583), ("lhu x13, 102(x0)", 0, 0x06605683),
    ("jalr x21, 0(x20)", 0, 0x000A0AE7), ("lui x23, 0x12345", 0, 0x12345BB7),
    ("jal x19, 12", 0, 0x00C009EF), ("bne x18, x0, -4", 0, 0xFE091EE3),
    ("beq x1, x1, 12", 0, 0x00108663), ("halt", 0, 0x00000000),
    ("nop", 0, 0x00000013), ("j 0", 0, 0x0000006F), ("sltiu x9, x6, -1", 0, 0xFFF33493),
]

# Pseudo-instrucciones: fuente -> palabras esperadas (escritas a mano a partir
# de su expansion y de las codificaciones de arriba).
PSEUDO = [
    ("mv x5, x6", [0x00030293]),                     # addi x5, x6, 0
    ("li x5, -8", [0xFF800293]),                     # addi x5, x0, -8
    ("li x5, 0x12345678", [0x123452B7, 0x67828293]), # lui x5, 0x12345 ; addi x5, x5, 0x678
    ("li x5, 0x12345800", [0x123462B7, 0x80028293]), # lui 0x12346 ; addi -2048
    ("li x5, 0x80000000", [0x800002B7]),             # solo lui
    ("ret", [0x00008067]),                           # jalr x0, 0(ra)
    ("call 8", [0x008000EF]),                        # jal ra, 8
    ("beqz x1, 8", [0x00008463]),                    # beq x1, x0, 8
    ("bnez x1, -4", [0xFE009EE3]),                   # bne x1, x0, -4
]


def autoprueba(ruta_if_id=None):
    errores = 0
    for fuente, addr, esperado in CONOCIDAS:
        etqs, mnem, ops = _separar(fuente)
        w = codificar(mnem, ops, {}, addr)
        if w != esperado:
            print(f"ERROR: {fuente:22s} -> {w:08X}, esperado {esperado:08X}")
            errores += 1
    for fuente, esperado in PSEUDO:
        got = [ln.word for ln in ensamblar(fuente)]
        if got != esperado:
            print(f"ERROR: {fuente:22s} -> {[hex(x) for x in got]}, esperado "
                  f"{[hex(x) for x in esperado]}")
            errores += 1
    # El programa de cobertura de la parte A trae su .hex generado con GNU as.
    if ruta_if_id:
        import os
        base = os.path.splitext(ruta_if_id)[0]
        with open(ruta_if_id, encoding="utf-8") as f:
            mio = [ln.word for ln in ensamblar(f.read())]
        with open(base + ".hex", encoding="utf-8") as f:
            ref = [int(t.split("#")[0], 16) for t in f if t.split("#")[0].strip()]
        if mio != ref:
            errores += 1
            for i, (a, b) in enumerate(zip(mio, ref)):
                if a != b:
                    print(f"ERROR: {ruta_if_id} palabra {i}: {a:08X}, GNU as {b:08X}")
            if len(mio) != len(ref):
                print(f"ERROR: {len(mio)} palabras, GNU as {len(ref)}")
    print("PASS: ensamblador" if errores == 0 else f"FAIL: {errores} errores")
    return errores == 0


def main():
    ap = argparse.ArgumentParser(description="Ensamblador minimo RV32I (Trabajo Final)")
    ap.add_argument("fuente", nargs="?", help="programa .asm")
    ap.add_argument("-o", "--salida", help="archivo .hex (por defecto, al lado del .asm)")
    ap.add_argument("--listado", action="store_true", help="mostrar direccion, palabra y fuente")
    ap.add_argument("--test", action="store_true", help="autoprueba")
    a = ap.parse_args()
    if a.test:
        import os
        aqui = os.path.dirname(os.path.abspath(__file__))
        sys.exit(0 if autoprueba(os.path.join(aqui, "programas", "programa_if_id.S")) else 1)
    if not a.fuente:
        ap.error("falta el archivo .asm")
    with open(a.fuente, encoding="utf-8") as f:
        texto = f.read()
    try:
        listado = ensamblar(texto)
    except ErrorAsm as e:
        sys.exit(f"{a.fuente}: {e}")
    if a.listado:
        for ln in listado:
            print(f"0x{ln.addr:03X}  {ln.word:08X}  {ln.fuente}")
    salida = a.salida or a.fuente.rsplit(".", 1)[0] + ".hex"
    with open(salida, "w", encoding="utf-8") as f:
        f.write(a_hex(listado, f"Generado por ensamblador.py desde {a.fuente}"))
    print(f"{len(listado)} palabras -> {salida}")


if __name__ == "__main__":
    main()
