"""
pipeline_view.py - Que instruccion hay en cada etapa del pipeline y que esta
pasando (forwarding, stall, flush), a partir de los volcados. Funciones puras:
no usa Qt; la ventana solo dibuja el resultado (app/vista_pipeline.py).

Regla de oro: NUNCA inventar. Si no se puede saber con certeza que instruccion
hay en una etapa, la etapa queda "desconocida" ("?") con el motivo.

De donde sale cada etapa (los latches guardan el PC solo en IF/ID e ID/EX):
  IF   el PC del volcado y la palabra del programa cargado en esa direccion.
  ID   IF/ID.pc e IF/ID.instr (o burbuja si valid = 0).
  EX   ID/EX.pc (o burbuja si valid = 0).
  MEM  y WB:
     - volcados CONSECUTIVOS (ciclos = anterior + 1): EX/MEM y MEM/WB avanzan
       en todo flanco habilitado (el stall y el flush solo tocan IF/ID e
       ID/EX), asi que MEM ahora = EX antes y WB ahora = MEM antes. Excepcion:
       un error de memoria convierte la instruccion de EX en burbuja; por eso
       se confirma con el bit valid del latch.
     - si no: se simula el programa cargado desde el reset (pipeline_sim.py,
       verificado bit a bit contra el RTL) y se usa SOLO si los 480 bits y el
       PC simulados son iguales a los del volcado.
  Ademas, la instruccion deducida tiene que coincidir con los campos del
  latch (rd, reg_write, mem_read, mem_write, halt); si no, "?".

Indicadores (calculados con los campos del volcado, igual que el hardware):
  forwarding  forwarding_unit.v: EX/MEM -> EX y MEM/WB -> EX para rs1/rs2.
  stall       hazard_unit.v: load en ID/EX cuyo rd usa la instruccion de IF/ID.
  flush       salto tomado en EX (operandos ya adelantados), si no hay un error
              de memoria en MEM (el error tiene prioridad).
"""
from dataclasses import dataclass, field

from desensamblador import desensamblar
from pipeline_sim import M32, NOP, PipelineSim, alu, alu_control, control_unit, data_mem

ETAPAS = ["IF", "ID", "EX", "MEM", "WB"]
LIMITE_SIMULACION = 200_000      # ciclos maximos que se simulan para deducir MEM y WB

# Estados de una etapa (la interfaz les da color + icono + texto)
UTIL, PASA, BURBUJA, DESCARTA, NO_ENTRA = "util", "pasa", "burbuja", "descarta", "no_entra"
HALT, ERROR, DESCONOCIDA = "halt", "error", "desconocida"


@dataclass
class Etapa:
    nombre: str
    estado: str
    pc: int = None                 # None: burbuja (o PC desconocido)
    palabra: int = None            # None: no se conoce la instruccion
    texto: str = ""                # instruccion desensamblada
    tipo: str = ""                 # chip: R, I, I·load, S, B, U, J, HALT, ilegal
    nota: str = ""                 # que hace en esta etapa
    motivo: str = ""               # por que es desconocida (tooltip y log)
    origen: str = ""               # burbuja: stall, flush, reset, parada o ""

    @property
    def ocupada(self):
        """Hay una instruccion conocida (para el listado)."""
        return self.pc is not None and self.estado not in (BURBUJA, DESCONOCIDA)


@dataclass
class Forwarding:
    origen: str                    # "EX/MEM" o "MEM/WB"
    operando: str                  # "rs1" o "rs2"
    registro: int
    valor: int


@dataclass
class Vista:
    ciclos: int
    etapas: dict
    forwarding: list = field(default_factory=list)
    stall: bool = False            # STALL en el proximo paso
    flush: bool = False            # FLUSH en el proximo paso (salto tomado)
    error_mem: bool = False        # error de memoria en MEM: se descarta lo de atras
    parada: bool = False           # HALT o error en camino a WB (no se busca mas)
    detenido: bool = False         # halted = 1
    fuente: str = ""               # como se dedujeron MEM y WB
    avisos: list = field(default_factory=list)
    crudo: bytes = b""
    bypass: list = field(default_factory=list)   # registros que ID lee por el bypass WB -> ID


# ============================================================== contexto
class Contexto:
    """Lo que la interfaz sabe del programa: las palabras que mando con 'L' y la
    memoria de datos al momento del reset (la RAM no se borra). Con eso se
    puede simular desde el reset. programa = None: no se cargo desde la GUI."""

    def __init__(self, programa=None, mem_inicial=None):
        self.programa = None if programa is None else (
            list(programa[:256]) + [0] * (256 - len(programa[:256])))
        if self.programa is not None:
            self.programa[255] = 0
        self.mem_inicial = None if mem_inicial is None else list(mem_inicial)
        self._sim = None

    def palabra(self, pc):
        """Palabra que busca IF en pc (0xFFFFFFFF si el fetch es invalido)."""
        if self.programa is None:
            return None
        if (pc >> 10) or (pc & 3):
            return M32
        return self.programa[(pc >> 2) & 0xFF]

    def simular(self, ciclos):
        """PipelineSim despues de `ciclos` ciclos desde el reset, o None."""
        if self.programa is None or self.mem_inicial is None or ciclos > LIMITE_SIMULACION:
            return None
        if self._sim is None or self._sim.ciclos > ciclos:
            self._sim = PipelineSim(self.programa, self.mem_inicial)
        while self._sim.ciclos < ciclos and self._sim.paso():
            pass
        return self._sim


# ============================================================== utilidades
def tipo_de(w):
    if w is None:
        return ""
    if w == 0:
        return "HALT"
    op = w & 0x7F
    if control_unit(w, 1)["illegal"]:
        return "ilegal"
    return {0x33: "R", 0x13: "I", 0x03: "I·load", 0x67: "I", 0x23: "S", 0x63: "B",
            0x37: "U", 0x6F: "J"}.get(op, "?")


def _wb_dato(e):
    return e.campo("MEM/WB", "mem_data") if e.campo("MEM/WB", "result_src") else \
        e.campo("MEM/WB", "result")


def _valid(e, latch):
    return e.campo(latch, "valid") == 1


def _marcador(e, latch):
    return _valid(e, latch) and e.campo(latch, "halt") == 1


# ============================================================== indicadores
def indicadores(e):
    """Forwarding, stall, flush y error de memoria con los campos del volcado.
    Devuelve (forwarding, stall, flush, error_mem, valores) donde valores tiene
    los operandos ya adelantados, el resultado de la ALU y lo de MEM."""
    c = lambda l, n: e.campo(l, n)
    ex_valid = _valid(e, "ID/EX")
    wb_write = _valid(e, "MEM/WB") and c("MEM/WB", "reg_write") and not c("MEM/WB", "illegal")
    mem_writes = _valid(e, "EX/MEM") and c("EX/MEM", "reg_write") and c("EX/MEM", "rd") != 0
    wb_writes = wb_write and c("MEM/WB", "rd") != 0
    fwd = []
    valores = {}
    for op in ("rs1", "rs2"):
        rs, dato = c("ID/EX", op), c("ID/EX", op + "_data")
        if ex_valid and c("ID/EX", "uses_" + op):
            if mem_writes and c("EX/MEM", "rd") == rs:
                if not c("EX/MEM", "result_src"):        # un load en MEM no se adelanta
                    dato = c("EX/MEM", "result")
                    fwd.append(Forwarding("EX/MEM", op, rs, dato))
            elif wb_writes and c("MEM/WB", "rd") == rs:
                dato = _wb_dato(e)
                fwd.append(Forwarding("MEM/WB", op, rs, dato))
        valores[op] = dato
    a = 0 if c("ID/EX", "alu_src_a") else valores["rs1"]
    b = c("ID/EX", "imm") if c("ID/EX", "alu_src_b") else valores["rs2"]
    res = alu(a, b, alu_control(c("ID/EX", "alu_op"), c("ID/EX", "funct3"), c("ID/EX", "funct7_b5")))
    taken = c("ID/EX", "branch") and ((c("ID/EX", "funct3") == 0 and res == 0) or
                                      (c("ID/EX", "funct3") == 1 and res != 0))
    redirect = ex_valid and not c("ID/EX", "illegal") and (c("ID/EX", "jump") or taken)
    if c("ID/EX", "jalr"):
        destino = (valores["rs1"] + c("ID/EX", "imm")) & 0xFFFFFFFE
    else:
        destino = (c("ID/EX", "pc") + c("ID/EX", "imm")) & M32
    rdata, err, _ = data_mem(e.mem, c("EX/MEM", "result"), c("EX/MEM", "store_data"),
                             _valid(e, "EX/MEM") and c("EX/MEM", "mem_read"),
                             _valid(e, "EX/MEM") and c("EX/MEM", "mem_write"),
                             c("EX/MEM", "funct3"))
    error_mem = bool(_valid(e, "EX/MEM") and err)
    # hazard_unit: load-use (el salto tiene prioridad)
    dec = control_unit(c("IF/ID", "instr"), c("IF/ID", "valid"))
    instr = c("IF/ID", "instr")
    rd_ex = c("ID/EX", "rd")
    load_use = bool(_valid(e, "IF/ID") and ex_valid and c("ID/EX", "mem_read") and
                    c("ID/EX", "reg_write") and rd_ex != 0 and
                    ((dec["uses_rs1"] and (instr >> 15) & 0x1F == rd_ex) or
                     (dec["uses_rs2"] and (instr >> 20) & 0x1F == rd_ex)))
    if e.detenido:                       # nada avanza
        return [], False, False, False, dict(valores, res=res, destino=destino, taken=False,
                                             rdata=rdata)
    flush = bool(redirect) and not error_mem
    stall = load_use and not redirect and not error_mem
    valores.update(res=res, destino=destino, taken=bool(taken), rdata=rdata)
    return fwd, stall, flush, error_mem, valores


# ============================================================== deduccion de MEM y WB
def _coincide(palabra, e, latch):
    """La instruccion `palabra` es compatible con los campos del latch?"""
    d = control_unit(palabra, 1)
    marcador = int(d["halt"] or d["illegal"])
    c = lambda n: e.campo(latch, n)
    if latch == "EX/MEM":
        return (c("reg_write") == d["reg_write"] and c("mem_read") == d["mem_read"] and
                c("mem_write") == d["mem_write"] and c("halt") == marcador and
                (not d["reg_write"] or c("rd") == (palabra >> 7) & 0x1F))
    # MEM/WB: un acceso a memoria que fallo llega con halt = illegal = 1 y sin escritura
    if c("halt") and c("illegal") and not marcador:
        return bool(d["mem_read"] or d["mem_write"])
    return (c("reg_write") == d["reg_write"] and c("halt") == marcador and
            (not d["reg_write"] or c("rd") == (palabra >> 7) & 0x1F))


def _pcs_mem_wb(e, anterior, ctx, avisos):
    """(pc_mem, pc_wb, fuente, motivo_mem, motivo_wb). pc None + motivo = '?'."""
    v_mem, v_wb = _valid(e, "EX/MEM"), _valid(e, "MEM/WB")
    if e.ciclos == 0:
        return None, None, "reset", "", ""
    if anterior is not None and e.ciclos == anterior.ciclos + 1:
        prev_ex, prev_mem = anterior.etapas["EX"], anterior.etapas["MEM"]
        m_mem = m_wb = ""
        pc_mem = pc_wb = None
        if v_mem:
            if prev_ex.pc is None:
                m_mem = ("EX/MEM tiene una instrucción, pero en el volcado anterior EX "
                         "era una burbuja: los volcados no son coherentes")
            else:
                pc_mem = prev_ex.pc
        if v_wb:
            if prev_mem.estado == DESCONOCIDA:
                m_wb = "en el volcado anterior no se sabía qué había en MEM"
            elif prev_mem.pc is None:
                m_wb = ("MEM/WB tiene una instrucción, pero en el volcado anterior MEM "
                        "era una burbuja: los volcados no son coherentes")
            else:
                pc_wb = prev_mem.pc
        return pc_mem, pc_wb, "consecutivo", m_mem, m_wb
    if anterior is not None and e.ciclos == anterior.ciclos and e.crudo == anterior.crudo:
        return (anterior.etapas["MEM"].pc, anterior.etapas["WB"].pc, anterior.fuente,
                anterior.etapas["MEM"].motivo, anterior.etapas["WB"].motivo)
    # Sin volcados consecutivos: simular desde el reset y exigir los 480 bits.
    if ctx is None or ctx.programa is None:
        motivo = "no hay volcados consecutivos y el programa no se cargó desde la GUI"
    elif ctx.mem_inicial is None:
        motivo = ("no hay volcados consecutivos y no se conoce la memoria de datos "
                  "al momento del reset")
    elif e.ciclos > LIMITE_SIMULACION:
        motivo = (f"no hay volcados consecutivos y {e.ciclos} ciclos son demasiados para "
                  f"simular (límite {LIMITE_SIMULACION})")
    else:
        sim = ctx.simular(e.ciclos)
        if sim.ciclos == e.ciclos and sim.pc == e.pc and sim.latches_bits() == e.lat_bits:
            return sim.pc_mem, sim.pc_wb, "simulación", "", ""
        motivo = ("la simulación desde el reset no coincide con el volcado (¿el programa o "
                  "la memoria de datos cambiaron?)")
    return (None, None, "desconocida", motivo if v_mem else "", motivo if v_wb else "")


# ============================================================== una etapa
def _etapa_con_palabra(nombre, pc, palabra, estado, nota):
    if palabra is None:
        return Etapa(nombre, DESCONOCIDA, pc, None, "?", "", nota,
                     "el programa no se cargó desde la GUI: se conoce el PC, no la instrucción")
    if palabra == NOP and estado == UTIL:
        estado, nota = PASA, "nop (no hace nada)"
    return Etapa(nombre, estado, pc, palabra, desensamblar(palabra), tipo_de(palabra), nota)


def _burbuja(nombre, origen):
    return Etapa(nombre, BURBUJA, origen=origen,
                 nota=f"burbuja ({origen})" if origen else "burbuja")


def deducir(e, anterior=None, ctx=None):
    """Volcado (decodificador.Estado) -> Vista. `anterior` es la Vista del
    volcado previo (o None) y `ctx` un Contexto (o None)."""
    avisos = []
    fwd, stall, flush, error_mem, val = indicadores(e)
    c = lambda l, n: e.campo(l, n)
    parada = any(_marcador(e, l) for l in ("ID/EX", "EX/MEM", "MEM/WB"))
    prev = anterior if (anterior is not None and e.ciclos == anterior.ciclos + 1) else None
    reset = e.ciclos == 0

    def origen_nuevo(etapa_prev_nombre=None):
        """Origen de una burbuja segun lo que paso en el volcado anterior."""
        if reset:
            return "reset"
        if prev is None:
            return ""
        if etapa_prev_nombre and prev.etapas[etapa_prev_nombre].estado == BURBUJA:
            return prev.etapas[etapa_prev_nombre].origen
        if prev.error_mem or prev.parada or prev.etapas["ID"].estado in (HALT, ERROR):
            return "parada"
        return ""

    et = {}
    # ---------------- IF
    pc = e.pc
    palabra = ctx.palabra(pc) if ctx is not None else None
    if e.detenido:
        et["IF"] = Etapa("IF", NO_ENTRA, pc, palabra, desensamblar(palabra) if palabra is not None
                         else "?", tipo_de(palabra), "procesador detenido: no se busca")
    elif parada or (_valid(e, "IF/ID") and control_unit(c("IF/ID", "instr"), 1)["halt"]
                    or (_valid(e, "IF/ID") and control_unit(c("IF/ID", "instr"), 1)["illegal"])):
        et["IF"] = Etapa("IF", NO_ENTRA, pc, palabra, desensamblar(palabra) if palabra is not None
                         else "?", tipo_de(palabra), "no entra: parada en curso (PC congelado)")
    elif error_mem:
        et["IF"] = _etapa_con_palabra("IF", pc, palabra, DESCARTA, "se descarta (error en MEM)")
    elif flush:
        et["IF"] = _etapa_con_palabra("IF", pc, palabra, DESCARTA, "se descarta (flush)")
    elif (pc >> 10) or (pc & 3):
        et["IF"] = Etapa("IF", ERROR, pc, M32, "fetch inválido", "ilegal",
                         "PC fuera de la memoria o desalineado → instrucción ilegal")
    else:
        et["IF"] = _etapa_con_palabra("IF", pc, palabra, UTIL,
                                      "se repite (stall)" if stall else "busca la instrucción")
    # ---------------- ID
    # Bypass WB -> ID (reg_file.v): WB escribe el registro que ID esta leyendo.
    bypass = []
    if _valid(e, "IF/ID") and _valid(e, "MEM/WB") and c("MEM/WB", "reg_write") and \
            not c("MEM/WB", "illegal") and c("MEM/WB", "rd") != 0 and not e.detenido:
        d_id = control_unit(c("IF/ID", "instr"), 1)
        for s_, usa in ((15, d_id["uses_rs1"]), (20, d_id["uses_rs2"])):
            r = (c("IF/ID", "instr") >> s_) & 0x1F
            if usa and r == c("MEM/WB", "rd") and r not in bypass:
                bypass.append(r)
    if not _valid(e, "IF/ID"):
        origen = origen_nuevo()
        if prev is not None and not origen:
            origen = "flush" if prev.flush else ("parada" if prev.parada else "")
        et["ID"] = _burbuja("ID", origen)
    else:
        w = c("IF/ID", "instr")
        d = control_unit(w, 1)
        if error_mem:
            st, nota = DESCARTA, "se descarta (error en MEM)"
        elif flush:
            st, nota = DESCARTA, "se descarta (flush)"
        elif d["halt"]:
            st, nota = HALT, "HALT detectado: se deja de buscar"
        elif d["illegal"]:
            st, nota = ERROR, "instrucción ilegal: el cpu se va a detener"
        elif stall:
            st, nota = UTIL, "espera 1 ciclo (load-use)"
        else:
            regs = [f"x{(w >> s) & 0x1F}" for s, u in ((15, d["uses_rs1"]), (20, d["uses_rs2"])) if u]
            st, nota = UTIL, "decodifica" + (", lee " + " y ".join(dict.fromkeys(regs)) if regs else "")
            if bypass:
                nota += f" ({', '.join(f'x{r}' for r in bypass)} llega desde WB: bypass)"
        et["ID"] = _etapa_con_palabra("ID", c("IF/ID", "pc"), w, st, nota)
    # ---------------- EX
    if not _valid(e, "ID/EX"):
        origen = origen_nuevo("ID")
        if prev is not None:
            if prev.stall:
                origen = "stall"
            elif prev.flush:
                origen = "flush"
        et["EX"] = _burbuja("EX", origen)
    else:
        pc_ex = c("ID/EX", "pc")
        w = ctx.palabra(pc_ex) if ctx is not None else None
        if c("ID/EX", "illegal"):
            st, nota = ERROR, "ilegal: baja como marcador de parada"
        elif c("ID/EX", "halt"):
            st, nota = HALT, "HALT: baja hacia WB"
        elif error_mem:
            st, nota = DESCARTA, "se descarta (error en MEM)"
        elif c("ID/EX", "branch"):
            st, nota = UTIL, (f"salto TOMADO → 0x{val['destino']:X}" if val["taken"]
                              else "salto no tomado (sigue)")
        elif c("ID/EX", "jump"):
            st, nota = UTIL, f"salta a 0x{val['destino']:X}, guarda PC+4"
        elif c("ID/EX", "mem_read") or c("ID/EX", "mem_write"):
            st, nota = UTIL, f"calcula la dirección 0x{val['res']:X}"
        else:
            st, nota = UTIL, f"calcula 0x{val['res']:X}"
        et["EX"] = _etapa_con_palabra("EX", pc_ex, w, st, nota)
    # ---------------- MEM y WB
    pc_mem, pc_wb, fuente, m_mem, m_wb = _pcs_mem_wb(e, anterior, ctx, avisos)
    for nombre, latch, pc_x, motivo, prev_nombre in (("MEM", "EX/MEM", pc_mem, m_mem, "EX"),
                                                     ("WB", "MEM/WB", pc_wb, m_wb, "MEM")):
        if not _valid(e, latch):
            origen = origen_nuevo(prev_nombre)
            if prev is not None and nombre == "MEM" and prev.error_mem:
                origen = "parada"
            et[nombre] = _burbuja(nombre, origen)
            continue
        if pc_x is None:
            et[nombre] = Etapa(nombre, DESCONOCIDA, None, None, "?", "", "", motivo)
            avisos.append(f"{nombre}: no se sabe qué instrucción hay ({motivo})")
            continue
        w = ctx.palabra(pc_x) if ctx is not None else None
        if w is not None and not _coincide(w, e, latch):
            m = (f"la instrucción deducida (0x{pc_x:X}: {desensamblar(w)}) no coincide con "
                 f"los campos de {latch}")
            et[nombre] = Etapa(nombre, DESCONOCIDA, None, None, "?", "", "", m)
            avisos.append(f"{nombre}: {m}")
            continue
        if nombre == "MEM":
            if c(latch, "illegal") and c(latch, "halt"):
                st, nota = ERROR, "ilegal: marcador de parada"
            elif c(latch, "halt"):
                st, nota = HALT, "HALT: baja hacia WB"
            elif error_mem:
                st, nota = ERROR, f"acceso inválido a 0x{c(latch, 'result'):X} → error"
            elif c(latch, "mem_read"):
                st, nota = UTIL, f"lee 0x{val['rdata']:X} de 0x{c(latch, 'result'):X}"
            elif c(latch, "mem_write"):
                st, nota = UTIL, (f"escribe 0x{c(latch, 'store_data'):X} en "
                                  f"0x{c(latch, 'result'):X}")
            else:
                st, nota = PASA, "sin acceso a memoria"
        else:
            rd = c(latch, "rd")
            if c(latch, "halt"):
                st, nota = ((ERROR, "detenido por error") if c(latch, "illegal")
                            else (HALT, "detenido (HALT)"))
            elif c(latch, "reg_write") and rd:
                st, nota = UTIL, f"escribe x{rd} = 0x{_wb_dato(e):X}"
            else:
                st, nota = PASA, "no escribe" + (" (rd = x0)" if c(latch, "reg_write") else "")
        et[nombre] = _etapa_con_palabra(nombre, pc_x, w, st, nota)
        if et[nombre].estado == DESCONOCIDA:
            avisos.append(f"{nombre}: {et[nombre].motivo}")
    for n in ("IF", "EX"):
        if et[n].estado == DESCONOCIDA and et[n].motivo:
            avisos.append(f"{n}: {et[n].motivo}")
    return Vista(e.ciclos, et, fwd, stall, flush, error_mem, parada, e.detenido, fuente,
                 avisos, e.crudo, bypass)


# ============================================================== listado
def marcas_listado(vista):
    """pc -> lista de (etapa, se_descarta), en orden IF..WB. Las burbujas, las
    desconocidas y las que no entran (parada) no marcan ninguna fila."""
    out = {}
    for n in ETAPAS:
        et = vista.etapas[n]
        if et.ocupada and et.estado != NO_ENTRA:
            out.setdefault(et.pc, []).append((n, et.estado == DESCARTA))
    return out
