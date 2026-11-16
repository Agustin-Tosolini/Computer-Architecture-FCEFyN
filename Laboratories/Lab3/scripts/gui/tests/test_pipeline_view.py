"""pipeline_view.py: que instruccion hay en cada etapa y los indicadores
(forwarding, stall, flush), con volcados de la FPGA simulada (que trae los
latches reales, ver test_pipeline_sim.py).

La referencia de "que hay en cada etapa" es INDEPENDIENTE de pipeline_sim: sale
de la traza de tiempos del modelo de referencia (rv32i_model.py), que da el
ciclo e en que cada instruccion esta en EX. Despues de k ciclos:
    ID/EX (EX)  = la instruccion con e = k + 1
    EX/MEM (MEM) = la instruccion con e = k
    MEM/WB (WB)  = la instruccion con e = k - 1
(las instrucciones del camino equivocado nunca llegan a EX: se descartan antes)."""
import glob
import os

import pytest

import decodificador as dec
import rutas
from ensamblador import ensamblar
from fpga_simulada import FpgaSimulada
from pipeline_sim import control_unit
from pipeline_view import (BURBUJA, DESCARTA, DESCONOCIDA, ERROR, HALT, NO_ENTRA, PASA, UTIL,
                           Contexto, deducir, marcas_listado)
from protocolo import Enlace
from rv32i_model import ejecutar


def leer(nombre):
    for carpeta in (rutas.PROGRAMAS_GUI, rutas.PROGRAMAS):
        ruta = os.path.join(carpeta, nombre + ".asm")
        if os.path.exists(ruta):
            with open(ruta) as f:
                return [ln.word for ln in ensamblar(f.read())]
    return [ln.word for ln in ensamblar(nombre)]           # texto directo


def paso_a_paso(palabras, n_max=60):
    """Carga, 'D' y 'S' hasta halted (o n_max). Devuelve [(Estado, Vista)]."""
    enlace = Enlace(FpgaSimulada())
    enlace.cargar(palabras)
    e = enlace.volcar()
    ctx = Contexto(palabras, e.mem)
    out = [(e, deducir(e, None, ctx))]
    while not e.detenido and len(out) <= n_max:
        e = enlace.paso()
        out.append((e, deducir(e, out[-1][1], ctx)))
    return out


def ocupacion_modelo(palabras):
    """k -> {"EX": pc, "MEM": pc, "WB": pc} segun la traza del modelo."""
    traza = ejecutar(palabras, verificar_estable=False, pasos_sin_fin=80).traza
    por_e = {}
    for pc, e in traza:
        por_e[e] = pc
    return lambda k: {"EX": por_e.get(k + 1), "MEM": por_e.get(k), "WB": por_e.get(k - 1)}


PROGRAMAS = sorted(os.path.basename(p)[:-4] for c in (rutas.PROGRAMAS_GUI, rutas.PROGRAMAS)
                   for p in glob.glob(os.path.join(c, "*.asm")))


# ============================================================== 1. deduccion
@pytest.mark.parametrize("nombre", PROGRAMAS)
def test_paso_a_paso_igual_al_modelo(nombre):
    """En TODOS los ejemplos (load-use, flush, forwarding, loops, HALT, errores):
    MEM y WB deducidos con volcados consecutivos = la traza del modelo, y nunca '?'."""
    palabras = leer(nombre)
    esperado = ocupacion_modelo(palabras)
    for e, v in paso_a_paso(palabras):
        k = e.ciclos
        for etapa in ("EX", "MEM", "WB"):
            got = v.etapas[etapa]
            assert got.estado != DESCONOCIDA, (nombre, k, etapa, got.motivo)
            pc = esperado(k)[etapa]
            if pc is None and etapa == "EX" and v.error_mem:
                # El modelo corta en el acceso invalido; la instruccion que esta en
                # EX existe de verdad y se descarta (no llega a MEM).
                assert got.estado == DESCARTA, (nombre, k, got)
            elif pc is None:
                assert got.estado == BURBUJA, (nombre, k, etapa, got)
            else:
                assert got.pc == pc, (nombre, k, etapa, got.pc, pc)
        assert v.avisos == []


def test_reset_todo_burbuja_menos_if():
    e, v = paso_a_paso(leer("demo_forwarding"))[0]
    assert v.etapas["IF"].estado == UTIL and v.etapas["IF"].pc == 0
    for n in ("ID", "EX", "MEM", "WB"):
        assert v.etapas[n].estado == BURBUJA and v.etapas[n].origen == "reset"


def test_load_use_burbuja_de_stall():
    seq = paso_a_paso(leer("demo_load_use"))
    # Despues de 4 ciclos: lw t1 (0x08) en EX y add t2,t1,t1 (0x0C) en ID -> stall.
    v4 = seq[4][1]
    assert v4.stall and v4.etapas["ID"].pc == 0x0C and "load-use" in v4.etapas["ID"].nota
    assert v4.etapas["IF"].nota.startswith("se repite")
    # Ciclo 5: la burbuja entro a EX; el add sigue en ID y el PC no cambio.
    v5 = seq[5][1]
    assert v5.etapas["EX"].estado == BURBUJA and v5.etapas["EX"].origen == "stall"
    assert v5.etapas["ID"].pc == 0x0C and seq[5][0].pc == seq[4][0].pc
    # La burbuja sigue a MEM y a WB con su origen.
    assert seq[6][1].etapas["MEM"].origen == "stall"
    assert seq[7][1].etapas["WB"].origen == "stall"


def test_flush_naranja_y_burbujas_de_flush():
    seq = paso_a_paso(leer("demo_flush"))
    v4 = seq[4][1]                 # beq x5, x5, 12 (0x08) en EX, tomado
    assert v4.flush and v4.etapas["EX"].pc == 0x08 and "TOMADO" in v4.etapas["EX"].nota
    assert v4.etapas["ID"].estado == DESCARTA and v4.etapas["ID"].pc == 0x0C
    assert v4.etapas["IF"].estado == DESCARTA and v4.etapas["IF"].pc == 0x10
    assert marcas_listado(v4)[0x0C] == [("ID", True)]
    v5 = seq[5][1]
    assert seq[5][0].pc == 0x14 and v5.etapas["IF"].pc == 0x14      # el destino del salto
    assert v5.etapas["ID"].origen == "flush" and v5.etapas["EX"].origen == "flush"


def test_misma_instruccion_en_dos_etapas():
    """`fin: j fin`: el mismo PC se busca otra vez mientras sigue en el pipeline."""
    seq = paso_a_paso(leer("loop_infinito"), n_max=20)
    dobles = [(e.ciclos, pc, m) for e, v in seq for pc, m in marcas_listado(v).items()
              if len(m) >= 2]
    assert dobles, "no aparecio ningun ciclo con la misma instruccion en dos etapas"
    k, pc, m = dobles[0]
    assert pc == 0x08 and [n for n, _ in m][0] == "IF"


def test_halt():
    seq = paso_a_paso(leer("demo_forwarding"))
    e, v = seq[-1]
    assert e.detenido and v.detenido
    assert v.etapas["WB"].estado == HALT and v.etapas["WB"].pc == 0x14
    for n in ("ID", "EX", "MEM"):
        assert v.etapas[n].estado == BURBUJA and v.etapas[n].origen == "parada"
    assert v.etapas["IF"].estado == NO_ENTRA
    # Cuando el HALT esta en ID: deja de buscar.
    k_id = next(i for i, (_, vv) in enumerate(seq) if vv.etapas["ID"].estado == HALT)
    assert seq[k_id][1].etapas["IF"].estado == NO_ENTRA


def test_instruccion_ilegal():
    seq = paso_a_paso(leer("demo_error_ilegal"))
    k_id = next(i for i, (_, v) in enumerate(seq) if v.etapas["ID"].estado == ERROR)
    assert seq[k_id][1].etapas["ID"].pc == 0x04
    e, v = seq[-1]
    assert e.error and v.etapas["WB"].estado == ERROR and v.etapas["WB"].pc == 0x04


def test_error_de_memoria():
    seq = paso_a_paso(leer("demo_error_memoria"))
    k = next(i for i, (_, v) in enumerate(seq) if v.error_mem)
    v = seq[k][1]                       # lw 128(x0) en MEM: acceso invalido
    assert v.etapas["MEM"].estado == ERROR and v.etapas["MEM"].pc == 0x08
    assert v.etapas["EX"].estado == DESCARTA and v.etapas["ID"].estado == DESCARTA
    assert seq[-1][1].etapas["WB"].estado == ERROR and seq[-1][1].etapas["WB"].pc == 0x08


def test_D_despues_de_R_deduce_con_simulacion():
    palabras = leer("fibonacci")
    enlace = Enlace(FpgaSimulada())
    enlace.cargar(palabras)
    ctx = Contexto(palabras, enlace.volcar().mem)
    enlace.correr()
    e = enlace.volcar()
    v = deducir(e, None, ctx)
    assert v.fuente == "simulación" and v.avisos == []
    assert v.etapas["WB"].estado == HALT and v.etapas["WB"].pc == 0x30
    # Un loop interrumpido: WB segun la traza del modelo en ese ciclo.
    palabras = leer("demo_loop_infinito")
    enlace.cargar(palabras)
    ctx = Contexto(palabras, enlace.volcar().mem)
    import threading
    cancelar = threading.Event()
    threading.Timer(0.2, cancelar.set).start()
    e = enlace.correr(cancelar)
    v = deducir(e, None, ctx)
    traza = ejecutar(palabras, verificar_estable=False, max_instr=e.ciclos + 50,
                     pasos_sin_fin=e.ciclos + 5).traza
    por_e = {ee: pc for pc, ee in traza}
    for etapa, ee in (("MEM", e.ciclos), ("WB", e.ciclos - 1)):
        esperado = por_e.get(ee)
        assert (v.etapas[etapa].pc == esperado) if esperado is not None else \
            v.etapas[etapa].estado == BURBUJA


# ============================================================== "?"
def _cambiar(e, latch, campo, valor):
    """Volcado con un campo de latch cambiado a mano (caso inconsistente)."""
    import campos_latches as cl
    c = next(x for x in cl.CAMPOS if x[0] == latch and x[1] == campo)
    ancho = cl.ancho(c)
    bits = (e.lat_bits & ~(((1 << ancho) - 1) << c[3])) | (valor << c[3])
    return dec.decodificar(dec.armar_volcado(e.pc, e.ciclos, e.estado, e.regs, e.mem, bits))


def test_inconsistente_da_signo_de_pregunta():
    seq = paso_a_paso(leer("sumas_encadenadas"))
    (e4, v4), (e5, _) = seq[4], seq[5]
    assert deducir(e5, v4, Contexto(leer("sumas_encadenadas"), e4.mem)).etapas["MEM"].pc is not None
    malo = _cambiar(e5, "EX/MEM", "rd", 31)         # el rd no es el de la instruccion deducida
    v = deducir(malo, v4, Contexto(leer("sumas_encadenadas"), e4.mem))
    assert v.etapas["MEM"].estado == DESCONOCIDA and "no coincide" in v.etapas["MEM"].motivo
    assert any("MEM" in a for a in v.avisos)
    # El volcado siguiente no puede saber WB (MEM era '?'): tambien '?'.
    _, _, = seq[6]
    v6 = deducir(seq[6][0], v, Contexto(leer("sumas_encadenadas"), e4.mem))
    assert v6.etapas["WB"].estado == DESCONOCIDA


def test_sin_programa_o_simulacion_distinta_da_signo_de_pregunta():
    palabras = leer("fibonacci")
    enlace = Enlace(FpgaSimulada())
    enlace.cargar(palabras)
    mem0 = enlace.volcar().mem
    e = enlace.correr()
    v = deducir(e, None, None)                      # programa no cargado desde la GUI
    assert v.etapas["WB"].estado == DESCONOCIDA and "GUI" in v.etapas["WB"].motivo
    assert v.etapas["WB"].texto == "?"
    malo = _cambiar(e, "MEM/WB", "result", 0x1234)  # un bit distinto del simulado
    v = deducir(malo, None, Contexto(palabras, mem0))
    assert v.etapas["WB"].estado == DESCONOCIDA and "simulación" in v.etapas["WB"].motivo
    from pipeline_view import LIMITE_SIMULACION
    lejos = dec.decodificar(dec.armar_volcado(e.pc, LIMITE_SIMULACION + 1, e.estado, e.regs,
                                              e.mem, e.lat_bits))
    assert "demasiados" in deducir(lejos, None, Contexto(palabras, mem0)).etapas["WB"].motivo


# ============================================================== 2. indicadores
# Valores calculados A MANO. Notacion: k = ciclos del volcado; la instruccion
# con e = k + 1 esta en EX (ID/EX), la de e = k en EX/MEM y la de e = k - 1 en
# MEM/WB. Primera instruccion: e = 3; cada una +1; load-use +1; salto tomado +2.
#
# demo_forwarding: li t0 (e3) · addi t1,t0 (e4) · add t2,t1,t0 (e5) ·
#                  sub t3,t2,t1 (e6) · sw t3,0(x0) (e7) · halt (e8)
#   k=3: EX=addi usa t0, EX/MEM=li escribe t0               -> rs1 desde EX/MEM
#   k=4: EX=add: t1 de EX/MEM (addi), t0 de MEM/WB (li)     -> rs1 EX/MEM, rs2 MEM/WB
#   k=5: EX=sub: t2 de EX/MEM (add), t1 de MEM/WB (addi)    -> rs1 EX/MEM, rs2 MEM/WB
#   k=6: EX=sw: t3 (rs2) de EX/MEM (sub); rs1 = x0 no se adelanta -> rs2 EX/MEM
# demo_load_use: li t0 (e3) · sw t0 (e4) · lw t1 (e5) · [stall] · add t2,t1,t1 (e7) ·
#                lw t3 (e8) · nop (e9) · add t4,t3,t3 (e10) · halt (e11)
#   k=3: EX=sw usa t0 (rs2), EX/MEM=li                       -> rs2 EX/MEM
#   k=4: EX=lw t1 y en ID el add que lo usa                  -> STALL
#   k=6: EX=add: EX/MEM es la burbuja, MEM/WB=lw t1          -> rs1 y rs2 MEM/WB
#   k=9: EX=add t4: EX/MEM=nop (escribe x0: no), MEM/WB=lw t3 -> rs1 y rs2 MEM/WB
#   (k=7: lw t3 en EX pero en ID hay un nop: NO hay stall)
# demo_flush: li t0 (e3) · beq t0,x0 (e4, no tomado) · beq t0,t0 (e5, TOMADO) ·
#             li t3 (e8) · j fin (e9, tomado) · halt (e12)
#   k=3: EX=beq t0,x0: t0 de EX/MEM                          -> rs1 EX/MEM
#   k=4: EX=beq t0,t0 tomado: t0 de MEM/WB (EX/MEM es el otro beq, no escribe)
#                                                            -> rs1 y rs2 MEM/WB; FLUSH
#   k=8: EX=j fin                                            -> FLUSH
ESPERADO = {
    "demo_forwarding": ({3: {("EX/MEM", "rs1")},
                         4: {("EX/MEM", "rs1"), ("MEM/WB", "rs2")},
                         5: {("EX/MEM", "rs1"), ("MEM/WB", "rs2")},
                         6: {("EX/MEM", "rs2")}}, set(), set()),
    "demo_load_use": ({3: {("EX/MEM", "rs2")},
                       6: {("MEM/WB", "rs1"), ("MEM/WB", "rs2")},
                       9: {("MEM/WB", "rs1"), ("MEM/WB", "rs2")}}, {4}, set()),
    "demo_flush": ({3: {("EX/MEM", "rs1")},
                    4: {("MEM/WB", "rs1"), ("MEM/WB", "rs2")}}, set(), {4, 8}),
}


@pytest.mark.parametrize("nombre", sorted(ESPERADO))
def test_indicadores_a_mano(nombre):
    fwd, stall, flush = ESPERADO[nombre]
    for e, v in paso_a_paso(leer(nombre)):
        k = e.ciclos
        assert {(f.origen, f.operando) for f in v.forwarding} == fwd.get(k, set()), (nombre, k)
        assert v.stall == (k in stall), (nombre, k)
        assert v.flush == (k in flush), (nombre, k)


def _indicadores_modelo(palabras):
    """Los mismos indicadores derivados de la traza del modelo (independiente):
    stall en k = e_load - 1 si la siguiente usa el rd del load (y tarda 2);
    flush en k = e - 1 si la siguiente instruccion tarda 3 (salto tomado);
    forwarding: la instruccion con e = k+1 lee rs; si la de e = k lo escribe
    (y no es load) -> EX/MEM; si no, si la de e = k-1 lo escribe -> MEM/WB."""
    traza = ejecutar(palabras, verificar_estable=False, pasos_sin_fin=80).traza
    por_e = {e: pc for pc, e in traza}
    pal = {i * 4: w for i, w in enumerate(palabras)}
    stall, flush, fwd = set(), set(), {}
    for (pc, e), (pc2, e2) in zip(traza, traza[1:]):
        d = control_unit(pal.get(pc, 0), 1)
        if e2 - e == 3:
            flush.add(e - 1)
        if d["mem_read"] and e2 - e == 2:
            stall.add(e - 1)
    for k in range(0, max(por_e) + 1):
        pc = por_e.get(k + 1)
        if pc is None:
            continue
        w = pal.get(pc, 0)
        d = control_unit(w, 1)
        for op, usa, rs in (("rs1", d["uses_rs1"], (w >> 15) & 31),
                            ("rs2", d["uses_rs2"], (w >> 20) & 31)):
            if not usa or rs == 0:
                continue
            for origen, ee in (("EX/MEM", k), ("MEM/WB", k - 1)):
                p = por_e.get(ee)
                if p is None:
                    continue
                wp = pal.get(p, 0)
                dp = control_unit(wp, 1)
                if dp["reg_write"] and (wp >> 7) & 31 == rs:
                    if not (origen == "EX/MEM" and dp["mem_read"]):
                        fwd.setdefault(k, set()).add((origen, op))
                    break
    return fwd, stall, flush


@pytest.mark.parametrize("nombre", PROGRAMAS)
def test_indicadores_igual_al_modelo(nombre):
    palabras = leer(nombre)
    fwd, stall, flush = _indicadores_modelo(palabras)
    if nombre in ESPERADO:
        assert (fwd, stall, flush) == ESPERADO[nombre]      # la cuenta a mano = el modelo
    seq = paso_a_paso(palabras)
    ultimo = seq[-1][0].ciclos
    for e, v in seq:
        k = e.ciclos
        if seq[-1][0].detenido or k < ultimo:
            assert {(f.origen, f.operando) for f in v.forwarding} == fwd.get(k, set()), (nombre, k)
            assert v.stall == (k in stall), (nombre, k)
            assert v.flush == (k in flush), (nombre, k)


def test_nop_y_sin_trabajo_util():
    seq = paso_a_paso(leer("demo_load_use"))
    v = seq[9][1]                        # el nop (0x14) en MEM; lw t3 en WB
    assert v.etapas["MEM"].pc == 0x14 and v.etapas["MEM"].estado == PASA
    v = seq[3][1]                        # beq/sw: sw en EX; en MEM el li (sin acceso a memoria)
    assert v.etapas["MEM"].estado == PASA and "sin acceso" in v.etapas["MEM"].nota
