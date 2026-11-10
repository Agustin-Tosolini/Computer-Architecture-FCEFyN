#!/usr/bin/env python3
"""
rv32i_model.py - Modelo de referencia del procesador (independiente del RTL).

Ejecuta un programa como lo haria el cpu real y calcula lo que tiene que
mostrar el volcado: registros, memoria de datos, PC, ciclos y estado. No lee
nada del RTL: decodifica las instrucciones por su cuenta y usa un modelo de
tiempos del pipeline escrito a partir del contrato (params.vh) y de las
decisiones de diseno.

Uso:
  python3 rv32i_model.py programa.asm          ejecuta y muestra el resultado
  python3 rv32i_model.py programa.hex          idem con un .hex
  python3 rv32i_model.py --generar             regenera scripts/programas/*.hex y
                                               los vectores de testbench/vectores/
  python3 rv32i_model.py --test                autoprueba del modelo

--------------------------------------------------------------------------------
Modelo de tiempos (un "ciclo" = un flanco con i_enable = 1)

Para cada instruccion ejecutada j se calcula e_j = ciclo en que esta en EX.
  * La primera instruccion: e = 3 (IF en el ciclo 1, ID en el 2, EX en el 3).
  * Siguiente: e_sig = e + 1
                 + 1 si j es un LOAD con rd != 0 y la siguiente lee ese rd
                     (stall load-use de un ciclo)
                 + 2 si j es un salto tomado, jal o jalr (se resuelve en EX y se
                     descartan las 2 instrucciones buscadas de mas).
  * Un registro escrito por j se ve en el banco despues del ciclo e_j + 2 (WB).
  * Un store de j se ve en la memoria despues del ciclo e_j + 1 (MEM).
  * La memoria de datos es RAM y NO se borra con el reset ni con 'L': conserva
    lo que dejo el programa anterior. Por eso el modelo informa, para cada
    palabra, si el programa ya la escribio ("mascara"): en las palabras no
    escritas el volcado muestra el valor que habia antes. Con estricto=True
    (lo usa --generar) un programa que lee una palabra, o escribe solo una
    parte de ella, sin haberla escrito entera antes es un error: su resultado
    dependeria de la basura de la corrida anterior.
  * HALT (o una instruccion ilegal) en la posicion H: o_halted = 1 despues del
    ciclo e_H + 1 (el marcador llego a MEM/WB). Con 5 NOPs + HALT: 9 ciclos.
  * Acceso invalido a memoria en j: se detiene despues del ciclo e_j + 1, sin
    efectos de j ni de las siguientes.
  * PC (direccion de busqueda) despues de cada ciclo: suma 4 por ciclo, salvo
      - en el ciclo e_b de un salto tomado: PC = destino;
      - en el ciclo e_L de un stall: no cambia;
      - desde el ciclo e_H - 1 (HALT o ilegal en ID): no cambia (PC = HALT + 4);
      - en el ciclo del fallo de memoria: no cambia;
      - si el PC esta fuera de la memoria o desalineado: no cambia (y lo que se
        "busca" es una instruccion ilegal).

Estado del volcado: 0x01 = HALT, 0x05 = detenido por error, 0x02 = interrumpido.
--------------------------------------------------------------------------------
"""
import argparse
import glob
import os
import re
import sys

AQUI = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, AQUI)
from ensamblador import ensamblar, a_hex, REGS, ErrorAsm   # noqa: E402

M32 = 0xFFFFFFFF
IMEM_WORDS = 256
DMEM_WORDS = 32               # memoria de datos: 32 palabras (128 bytes)
LATCH_WORDS = 15              # 480 bits
ST_HALT, ST_INT, ST_FAULT = 0x01, 0x02, 0x05


def s32(v):
    v &= M32
    return v - (1 << 32) if v & 0x80000000 else v


def sext(v, bits):
    v &= (1 << bits) - 1
    return v - (1 << bits) if v & (1 << (bits - 1)) else v


#------------------------------------------------------------------ decodificador
def decodificar(w):
    """Palabra -> dict con la informacion que usa el modelo. Propio: no usa
    las tablas del ensamblador."""
    op, rd, f3 = w & 0x7F, (w >> 7) & 0x1F, (w >> 12) & 7
    rs1, rs2, f7 = (w >> 15) & 0x1F, (w >> 20) & 0x1F, (w >> 25) & 0x7F
    d = {"w": w, "rd": rd, "rs1": rs1, "rs2": rs2, "f3": f3, "uses": (),
         "clase": "ilegal"}
    if w == 0:
        d["clase"] = "halt"
    elif op == 0x33:                                         # tipo R
        nombres = {(0, 0): "add", (0x20, 0): "sub", (0, 1): "sll", (0, 2): "slt",
                   (0, 3): "sltu", (0, 4): "xor", (0, 5): "srl", (0x20, 5): "sra",
                   (0, 6): "or", (0, 7): "and"}
        if (f7, f3) in nombres:
            d.update(clase="alu", op=nombres[(f7, f3)], uses=(rs1, rs2), b_reg=True)
    elif op == 0x13:                                         # tipo I aritmetico
        imm = sext(w >> 20, 12)
        if f3 == 1 and f7 == 0:
            d.update(clase="alu", op="sll", uses=(rs1,), imm=rs2)
        elif f3 == 5 and f7 in (0, 0x20):
            d.update(clase="alu", op="sra" if f7 else "srl", uses=(rs1,), imm=rs2)
        elif f3 in (0, 2, 3, 4, 6, 7):
            nombre = {0: "add", 2: "slt", 3: "sltu", 4: "xor", 6: "or", 7: "and"}[f3]
            d.update(clase="alu", op=nombre, uses=(rs1,), imm=imm)
    elif op == 0x03 and f3 in (0, 1, 2, 4, 5):               # loads
        d.update(clase="load", uses=(rs1,), imm=sext(w >> 20, 12))
    elif op == 0x23 and f3 in (0, 1, 2):                     # stores
        d.update(clase="store", uses=(rs1, rs2),
                 imm=sext(((w >> 25) << 5) | ((w >> 7) & 0x1F), 12))
    elif op == 0x63 and f3 in (0, 1):                        # beq / bne
        imm = (((w >> 31) & 1) << 12) | (((w >> 7) & 1) << 11) | \
              (((w >> 25) & 0x3F) << 5) | (((w >> 8) & 0xF) << 1)
        d.update(clase="branch", uses=(rs1, rs2), imm=sext(imm, 13))
    elif op == 0x6F:                                         # jal
        imm = (((w >> 31) & 1) << 20) | (((w >> 12) & 0xFF) << 12) | \
              (((w >> 20) & 1) << 11) | (((w >> 21) & 0x3FF) << 1)
        d.update(clase="jal", imm=sext(imm, 21))
    elif op == 0x67 and f3 == 0:                             # jalr
        d.update(clase="jalr", uses=(rs1,), imm=sext(w >> 20, 12))
    elif op == 0x37:                                         # lui
        d.update(clase="lui", imm=w & 0xFFFFF000)
    return d


def alu(op, a, b):
    sh = b & 0x1F
    if op == "add":  return (a + b) & M32
    if op == "sub":  return (a - b) & M32
    if op == "sll":  return (a << sh) & M32
    if op == "srl":  return (a & M32) >> sh
    if op == "sra":  return (s32(a) >> sh) & M32
    if op == "slt":  return int(s32(a) < s32(b))
    if op == "sltu": return int((a & M32) < (b & M32))
    if op == "xor":  return (a ^ b) & M32
    if op == "or":   return (a | b) & M32
    if op == "and":  return (a & b) & M32
    raise ValueError(op)


#------------------------------------------------------------------ ejecucion
class Resultado:
    """Lo que tiene que verse en el volcado (y paso a paso)."""

    def __init__(self):
        self.regs = [0] * 32
        self.mem = [0] * DMEM_WORDS
        self.pc = 0
        self.ciclos = 0          # ciclos hasta halted (0 si no termina)
        self.estado = 0
        self.latches = None      # solo para HALT normal (patron conocido)
        self.pasos = []          # pasos[k-1] = (regs, mem, pc, estado, mascara) tras el ciclo k
        self.mascara = 0         # bit k = 1: el programa escribio la palabra k
        self.termina = True
        self.instrucciones = 0   # instrucciones ejecutadas (sin contar HALT)
        self.pc_bucle = None     # sin fin: direccion donde quedo dando vueltas


def _acceso_valido(addr, f3, es_store):
    if addr < 0 or addr >= 4 * DMEM_WORDS:
        return False
    if es_store and f3 not in (0, 1, 2):
        return False
    tam = f3 & 3
    return (tam == 0) or (tam == 1 and addr % 2 == 0) or (tam == 2 and addr % 4 == 0)


class ErrorPrograma(Exception):
    """El programa depende del contenido previo de la memoria de datos."""


def ejecutar(prog, max_instr=5000, pasos_sin_fin=40, estricto=False):
    """prog: lista de palabras (las que faltan hasta 256 son HALT).
    La memoria de datos arranca en 0 en el modelo; con estricto=True se exige
    que el programa no lea datos que no escribio (ver arriba)."""
    imem = list(prog[:IMEM_WORDS]) + [0] * (IMEM_WORDS - len(prog[:IMEM_WORDS]))
    imem[IMEM_WORDS - 1] = 0              # la debug_unit fuerza HALT en la 255
    regs, mem = [0] * 32, [0] * DMEM_WORDS
    enteras = set()                      # palabras ya escritas enteras (sw)
    eventos_reg, eventos_mem = [], []    # (ciclo, idx, valor)
    saltos, stalls = {}, set()            # ciclo -> destino ; ciclos de stall
    pc, e, n = 0, 3, 0
    stop_edge = fault_edge = halt_cycle = None
    estado = 0

    def leer(addr):
        if addr % 4 or addr >= 4 * IMEM_WORDS or addr < 0:
            return None                   # fetch fuera de rango o desalineado
        return imem[addr // 4]

    while n < max_instr:
        w = leer(pc)
        d = decodificar(0xFFFFFFFF if w is None else w)
        if d["clase"] in ("halt", "ilegal"):
            halt_cycle, stop_edge = e + 1, e - 1
            estado = ST_HALT if d["clase"] == "halt" else ST_FAULT
            break
        a, b = regs[d["rs1"]], regs[d["rs2"]]
        sig_pc, valor, redirige = pc + 4, None, False
        c = d["clase"]
        if c == "alu":
            valor = alu(d["op"], a, b if d.get("b_reg") else d["imm"] & M32)
        elif c == "lui":
            valor = d["imm"]
        elif c in ("jal", "jalr"):
            valor = (pc + 4) & M32
            sig_pc = (pc + d["imm"]) & M32 if c == "jal" else ((a + d["imm"]) & M32) & ~1
            redirige = True
        elif c == "branch":
            if (a == b) == (d["f3"] == 0):
                sig_pc, redirige = (pc + d["imm"]) & M32, True
        elif c in ("load", "store"):
            addr = s32(a + d["imm"])
            if not _acceso_valido(addr, d["f3"], c == "store"):
                # Fallo en MEM: se detiene en e + 1, sin efectos de j.
                halt_cycle = fault_edge = e + 1
                estado = ST_FAULT
                # La instruccion siguiente (buscada de todos modos) puede
                # congelar el PC un ciclo antes: HALT/ilegal en ID o stall.
                w1 = leer(pc + 4)
                d1 = decodificar(0xFFFFFFFF if w1 is None else w1)
                if d1["clase"] in ("halt", "ilegal"):
                    stop_edge = e
                elif c == "load" and d["rd"] and d["rd"] in d1["uses"]:
                    stalls.add(e)
                break
            word = mem[addr // 4]
            sh = 8 * (addr % 4)
            completa = c == "store" and d["f3"] == 2
            if estricto and not completa and addr // 4 not in enteras:
                que = "lee" if c == "load" else "escribe una parte de"
                raise ErrorPrograma(f"la instruccion de 0x{pc:03X} {que} mem[{addr // 4}] "
                                    "sin haberla inicializado con sw (la memoria de datos "
                                    "no se borra: tendria basura del programa anterior)")
            if completa:
                enteras.add(addr // 4)
            if c == "load":
                f3 = d["f3"]
                if f3 == 2:   valor = word
                elif f3 == 0: valor = sext(word >> sh, 8) & M32
                elif f3 == 4: valor = (word >> sh) & 0xFF
                elif f3 == 1: valor = sext(word >> sh, 16) & M32
                else:         valor = (word >> sh) & 0xFFFF
            else:
                mascara = {0: 0xFF, 1: 0xFFFF, 2: M32}[d["f3"]] << sh
                nuevo = (word & ~mascara | ((b << sh) & mascara)) & M32
                mem[addr // 4] = nuevo
                eventos_mem.append((e + 1, addr // 4, nuevo))
        if valor is not None and d["rd"] != 0:
            regs[d["rd"]] = valor
            eventos_reg.append((e + 2, d["rd"], valor))
        if redirige:
            saltos[e] = sig_pc
        # Tiempo de la siguiente instruccion.
        e_sig = e + 1 + (2 if redirige else 0)
        if c == "load" and d["rd"] != 0 and not redirige:
            w1 = leer(sig_pc)
            d1 = decodificar(0xFFFFFFFF if w1 is None else w1)
            if d["rd"] in d1["uses"]:
                stalls.add(e)
                e_sig += 1
        pc, e, n = sig_pc, e_sig, n + 1

    r = Resultado()
    r.instrucciones = n
    r.termina = halt_cycle is not None
    if r.termina:
        r.ciclos, r.estado, total = halt_cycle, estado, halt_cycle
    else:
        r.ciclos, r.estado, total = 0, ST_INT, pasos_sin_fin

    # Paso a paso: estado despues de cada ciclo k = 1..total.
    regs_k, mem_k, pc_k, masc_k = [0] * 32, [0] * DMEM_WORDS, 0, 0
    ir, im = sorted(eventos_reg), sorted(eventos_mem)
    for k in range(1, total + 1):
        if k == fault_edge:
            pass
        elif k in saltos:
            pc_k = saltos[k]
        elif stop_edge is not None and k >= stop_edge:
            pass
        elif k in stalls:
            pass
        elif leer(pc_k) is None:
            pass
        else:
            pc_k = (pc_k + 4) & M32
        while ir and ir[0][0] <= k:
            _, i, v = ir.pop(0)
            regs_k[i] = v
        while im and im[0][0] <= k:
            _, i, v = im.pop(0)
            mem_k[i] = v
            masc_k |= 1 << i
        st = estado if (r.termina and k >= halt_cycle) else 0
        r.pasos.append((list(regs_k), list(mem_k), pc_k, st, masc_k))

    r.mascara = 0
    for _, i, _ in eventos_mem:
        r.mascara |= 1 << i
    if r.termina:
        r.regs, r.mem, r.pc = regs_k, mem_k, pc_k
        if regs_k != regs or mem_k != mem:
            raise AssertionError("modelo inconsistente: paso a paso != ejecucion")
    else:
        # Sin fin: el estado (regs/mem) tiene que haberse estabilizado.
        if regs_k != regs or mem_k != mem:
            raise AssertionError("programa sin fin cuyo estado no se estabiliza "
                                 f"en {pasos_sin_fin} ciclos")
        r.regs, r.mem, r.pc, r.pc_bucle = regs, mem, None, pc
    if r.estado == ST_HALT:
        # Patron de parada normal (params.vh 4b): MEM/WB.ctrl = valid | halt,
        # IF/ID.instr = NOP; el resto en cero.
        r.latches = [0] * LATCH_WORDS
        r.latches[0], r.latches[13] = 0x5, 0x13
    return r


#------------------------------------------------------------------ anotaciones
_ESP = re.compile(r"#\s*ESPERADO:\s*(.*)$", re.IGNORECASE)


def esperados(texto):
    """Lee las lineas '# ESPERADO: x5 = -8, mem[2] = 0x10, estado = 0x01, ...'."""
    out = []
    for nro, linea in enumerate(texto.splitlines(), start=1):
        m = _ESP.search(linea)
        if not m:
            continue
        for item in m.group(1).split(","):
            if not item.strip():
                continue
            clave, _, val = item.partition("=")
            out.append((nro, clave.strip().lower(), int(val.strip(), 0)))
    return out


def verificar_anotaciones(r, anot, nombre):
    errores = []
    for nro, clave, val in anot:
        if clave in REGS:
            got = r.regs[REGS[clave]]
        elif re.match(r"^mem\[\d+\]$", clave):
            got = r.mem[int(clave[4:-1])]
        elif clave == "estado":
            got = r.estado
        elif clave == "ciclos":
            got = r.ciclos
        elif clave == "pc":
            got = r.pc
        else:
            errores.append(f"{nombre}:{nro}: clave desconocida '{clave}'")
            continue
        if got is None or (got & M32) != (val & M32):
            errores.append(f"{nombre}:{nro}: {clave} = "
                           f"{'-' if got is None else hex(got)}, anotado {hex(val & M32)}")
    return errores


#------------------------------------------------------------------ archivos
def leer_hex(ruta):
    out = []
    with open(ruta, encoding="utf-8") as f:
        for t in f:
            t = t.split("#")[0].strip()
            if t:
                out.append(int(t, 16))
    return out


def resumen(r):
    lineas = []
    if r.termina:
        nombre = {ST_HALT: "HALT", ST_FAULT: "detenido por ERROR"}[r.estado]
        lineas.append(f"estado = 0x{r.estado:02X} ({nombre}), ciclos = {r.ciclos}, "
                      f"PC = 0x{r.pc:08X}")
    else:
        lineas.append("no termina (loop sin fin): cortar con 'I' -> estado = 0x02")
    regs = [f"x{i} = 0x{v:08X}" for i, v in enumerate(r.regs) if v]
    mem = [f"mem[{i}] = 0x{v:08X}" for i, v in enumerate(r.mem) if r.mascara >> i & 1]
    lineas.append("registros distintos de 0: " + (", ".join(regs) if regs else "ninguno"))
    lineas.append("memoria que escribe el programa: " + (", ".join(mem) if mem else "ninguna") +
                  " (el resto conserva lo que habia: la memoria no se borra)")
    return lineas


def _envolver(texto, ancho=76):
    out, actual = [], ""
    for parte in texto.split(", "):
        if actual and len(actual) + len(parte) + 2 > ancho:
            out.append(actual + ",")
            actual = "    " + parte
        else:
            actual = parte if not actual else actual + ", " + parte
    out.append(actual)
    return out


def escribir_vectores(r, prog, nombre, dir_vec, idx):
    """Tres archivos para $readmemh, con la cantidad EXACTA de palabras:
      pNN.prog   256 palabras: el programa y HALT en el resto (como el CLEAR de 'L')
      pNN.exp     96 palabras: cabecera y estado final
      pNN.pasos   67 palabras por ciclo: estado despues de cada ciclo"""
    imem = list(prog) + [0] * (IMEM_WORDS - len(prog))
    imem[IMEM_WORDS - 1] = 0
    with open(os.path.join(dir_vec, f"p{idx:02d}.prog"), "w") as f:
        f.write(f"// {nombre}: {len(prog)} palabras + HALT hasta la 255 "
                "(generado por rv32i_model.py)\n")
        for w in imem:
            f.write(f"{w:08X}\n")
    nom = nombre.encode()[:32].ljust(32, b" ")
    cab = [0x52563332, len(prog), r.ciclos, r.pc if r.termina else r.pc_bucle, r.estado,
           int(r.latches is not None), len(r.pasos), r.mascara]
    cab += [int.from_bytes(nom[4 * i:4 * i + 4], "big") for i in range(8)]
    cuerpo = cab + r.regs + r.mem + (r.latches or [0] * LATCH_WORDS) + [0]
    assert len(cuerpo) == 96
    with open(os.path.join(dir_vec, f"p{idx:02d}.exp"), "w") as f:
        f.write(f"// {nombre}: resultado esperado (generado por rv32i_model.py)\n")
        f.write("// [0] magia 'RV32', [1] palabras, [2] ciclos hasta halted (0 = sin fin),\n")
        f.write("// [3] PC final (sin fin: direccion del loop), [4] estado, [5] latches validos, [6] pasos,\n")
        f.write("// [7] mascara (bit k = el programa escribe mem[k]; las demas conservan su valor), [8..15] nombre,\n")
        f.write("// [16..47] registros, [48..79] memoria, [80..94] latches\n")
        for v in cuerpo:
            f.write(f"{v & M32:08X}\n")
    with open(os.path.join(dir_vec, f"p{idx:02d}.pasos"), "w") as f:
        f.write(f"// {nombre}: {len(r.pasos)} pasos; paso k en [67*(k-1)]: "
                "32 registros, 32 palabras de memoria, PC, estado, mascara\n")
        for regs, mem, pc, st, masc in r.pasos:
            for v in regs + mem + [pc, st, masc]:
                f.write(f"{v & M32:08X}\n")


def generar():
    """Ensambla scripts/programas/*.asm, verifica las anotaciones, escribe los
    .hex (con el resultado esperado en la cabecera) y los vectores."""
    dir_prog = os.path.join(AQUI, "programas")
    dir_vec = os.path.join(AQUI, "..", "testbench", "vectores")
    os.makedirs(dir_vec, exist_ok=True)
    for viejo in glob.glob(os.path.join(dir_vec, "p*.prog")) + \
            glob.glob(os.path.join(dir_vec, "p*.exp")) + \
            glob.glob(os.path.join(dir_vec, "p*.pasos")):
        os.remove(viejo)
    errores, n = [], 0
    for ruta in sorted(glob.glob(os.path.join(dir_prog, "*.asm"))):
        nombre = os.path.splitext(os.path.basename(ruta))[0]
        with open(ruta, encoding="utf-8") as f:
            texto = f.read()
        listado = ensamblar(texto)
        prog = [ln.word for ln in listado]
        try:
            r = ejecutar(prog, estricto=True)
        except ErrorPrograma as e:
            errores.append(f"{nombre}.asm: {e}")
            continue
        errores += verificar_anotaciones(r, esperados(texto), nombre + ".asm")
        desc = [ln[1:].strip() for ln in texto.splitlines()
                if ln.startswith("#") and "ESPERADO" not in ln.upper()]
        cab = [f"{nombre}.hex - generado por ensamblador.py desde {nombre}.asm "
               "(no editar a mano)"] + desc[:6] + ["",
               "Resultado esperado con el cpu real (rv32i_model.py):"]
        for linea in resumen(r):
            cab += ["  " + x for x in _envolver(linea)]
        with open(os.path.join(dir_prog, nombre + ".hex"), "w", encoding="utf-8") as f:
            f.write(a_hex(listado, "\n".join(cab)))
        escribir_vectores(r, prog, nombre, dir_vec, n)
        print(f"p{n:02d} {nombre:22s} {len(prog):3d} palabras  " + resumen(r)[0])
        n += 1
    with open(os.path.join(dir_vec, "indice.mem"), "w") as f:
        f.write("// cantidad de programas en este directorio (generado por rv32i_model.py)\n")
        f.write(f"{n:08X}\n")
    for e in errores:
        print("ERROR:", e)
    if errores:
        sys.exit(f"FAIL: {len(errores)} anotaciones no coinciden con el modelo")
    print(f"OK: {n} programas, anotaciones verificadas -> {os.path.normpath(dir_vec)}")


#------------------------------------------------------------------ autoprueba
def autoprueba():
    """Casos de tiempos que salen del contrato y de las decisiones de diseno."""
    ok = True

    def chk(nombre, got, exp):
        nonlocal ok
        if got != exp:
            print(f"ERROR: {nombre}: {got}, esperado {exp}")
            ok = False

    def asm(t):
        return [ln.word for ln in ensamblar(t)]

    r = ejecutar(asm("nop\nnop\nnop\nnop\nnop\nhalt"))
    chk("5 NOPs + HALT: ciclos", r.ciclos, 9)
    chk("5 NOPs + HALT: PC", r.pc, 0x18)
    chk("5 NOPs + HALT: PC paso a paso", [p[2] for p in r.pasos],
        [4, 8, 12, 16, 20, 24, 24, 24, 24])
    r = ejecutar(asm("lw x1, 0(x0)\nadd x2, x1, x1\nhalt"))
    chk("load-use: ciclos (1 stall)", r.ciclos, 7)
    chk("load-use: PC paso a paso", [p[2] for p in r.pasos], [4, 8, 8, 12, 12, 12, 12])
    r = ejecutar(asm("beq x0, x0, 8\naddi x1, x0, 1\nhalt"))
    chk("beq tomado: ciclos (+2)", r.ciclos, 7)
    chk("beq tomado: x1 no se escribe", r.regs[1], 0)
    r = ejecutar(asm("halt"))
    chk("HALT inmediato: ciclos", r.ciclos, 4)
    r = ejecutar(asm("addi x1, x0, 1024\njalr x0, 0(x1)"))
    chk("fetch fuera de rango: estado", r.estado, ST_FAULT)
    chk("fetch fuera de rango: PC", r.pc, 1024)
    r = ejecutar(asm("addi x1, x0, 42\nlw x1, 128(x0)\nnop\nnop\nhalt"))
    chk("lw fuera de rango: estado", r.estado, ST_FAULT)
    chk("lw fuera de rango: x1", r.regs[1], 42)
    chk("lw fuera de rango: PC (lw + 12)", r.pc, 4 + 12)
    print("PASS: modelo" if ok else "FAIL: modelo")
    return ok


def main():
    ap = argparse.ArgumentParser(description="Modelo de referencia RV32I del Trabajo Final")
    ap.add_argument("programa", nargs="?", help=".asm o .hex")
    ap.add_argument("--generar", action="store_true", help="regenera .hex y vectores")
    ap.add_argument("--test", action="store_true", help="autoprueba")
    a = ap.parse_args()
    if a.test:
        sys.exit(0 if autoprueba() else 1)
    if a.generar:
        try:
            generar()
        except ErrorAsm as e:
            sys.exit(f"FAIL: {e}")
        return
    if not a.programa:
        ap.error("falta el programa (o --generar / --test)")
    if a.programa.endswith(".asm"):
        with open(a.programa, encoding="utf-8") as f:
            texto = f.read()
        prog = [ln.word for ln in ensamblar(texto)]
        r = ejecutar(prog)
        for e in verificar_anotaciones(r, esperados(texto), a.programa):
            print("ERROR:", e)
    else:
        r = ejecutar(leer_hex(a.programa))
    for linea in resumen(r):
        print(linea)


if __name__ == "__main__":
    main()
