"""Demos de la defensa (scripts/programas/defensa/): cada programa se ensambla,
se corre en el modo simulado (la misma FPGA simulada de la GUI) y se verifican
los valores anotados en su encabezado:
  # ESPERADO:   registros, memoria, estado, ciclos y PC
  # VERIFICADO: instrucciones, stalls, saltos tomados y CPI (contra el modelo)
  # PASO k clave   (demo_pipeline) en que 'S' aparece cada fenomeno, EXACTO
Ademas, contra el RTL (Icarus Verilog, tests/hdl/tb_traza.v): los 480 bits de
los latches, registros, memoria, PC y estado en cada ciclo, igual que el
simulador. Y el menu Ejemplos -> Defensa de la GUI, en orden."""
import glob
import os
import re
import shutil
import subprocess
import threading

import pytest

import rutas
from ensamblador import ensamblar
from fpga_simulada import FpgaSimulada
from pipeline_sim import PipelineSim
from pipeline_view import BURBUJA, HALT, Contexto, deducir
from protocolo import Enlace
from rv32i_model import ejecutar, esperados

NOMBRES = [n for n, _ in rutas.DEMOS_DEFENSA]


def leer(nombre):
    with open(os.path.join(rutas.PROGRAMAS_DEFENSA, nombre + ".asm")) as f:
        texto = f.read()
    return texto, [ln.word for ln in ensamblar(texto)]


def verificado(texto):
    m = re.search(r"#\s*VERIFICADO:\s*(.*)", texto)
    return {k.strip(): float(v) for k, v in (p.split("=") for p in m.group(1).split(","))}


def correr_simulado(palabras, sin_fin):
    enlace = Enlace(FpgaSimulada())
    enlace.cargar(palabras)
    if not sin_fin:
        return enlace.correr()
    cancelar = threading.Event()
    threading.Timer(0.2, cancelar.set).start()
    return enlace.correr(cancelar)


def test_estan_todos_y_no_pisan_los_ejemplos():
    assert sorted(os.path.basename(p)[:-4] for p in
                  glob.glob(os.path.join(rutas.PROGRAMAS_DEFENSA, "*.asm"))) == sorted(NOMBRES)
    # Los ejemplos de antes siguen en su lugar (la carpeta defensa es aparte).
    for viejo in ("demo_loop_infinito", "demo_flush", "fibonacci"):
        assert os.path.exists(os.path.join(rutas.PROGRAMAS_GUI, viejo + ".asm"))


@pytest.mark.parametrize("nombre", NOMBRES)
def test_valores_anotados_en_modo_simulado(nombre):
    texto, palabras = leer(nombre)
    sin_fin = "estado = 0x02" in texto
    e = correr_simulado(palabras, sin_fin)
    from ensamblador import REGS
    for nro, clave, valor in esperados(texto):
        if clave in REGS:
            got = e.regs[REGS[clave]]
        elif clave.startswith("mem["):
            got = e.mem[int(clave[4:-1])]
        else:
            got = {"estado": e.estado, "ciclos": e.ciclos, "pc": e.pc}[clave]
        assert got == valor & 0xFFFFFFFF, f"{nombre}:{nro}: {clave} = {got:#x}, anotado {valor:#x}"
    if sin_fin:
        assert e.interrumpido and not e.detenido and e.ciclos > 0


@pytest.mark.parametrize("nombre", [n for n in NOMBRES if n != "demo_loop_infinito"])
def test_instrucciones_stalls_saltos_y_cpi(nombre):
    texto, palabras = leer(nombre)
    r = ejecutar(palabras, estricto=True)
    dif = [b[1] - a[1] for a, b in zip(r.traza, r.traza[1:])]
    v = verificado(texto)
    assert r.instrucciones == v["instrucciones"]
    assert dif.count(2) == v["stalls"] and dif.count(3) == v["saltos_tomados"]
    assert r.ciclos == r.instrucciones + 4 + dif.count(2) + 2 * dif.count(3)
    assert round(r.ciclos / r.instrucciones, 2) == round(v["cpi"], 2)


# -------------------------------------------------------------- demo_pipeline: pasos
FENOMENOS = {
    "fwd_exmem": lambda v: any(f.origen == "EX/MEM" for f in v.forwarding),
    "fwd_memwb": lambda v: any(f.origen == "MEM/WB" for f in v.forwarding),
    "bypass": lambda v: bool(v.bypass),
    "stall": lambda v: v.stall,
    "burbuja_stall": lambda v: v.etapas["EX"].estado == BURBUJA and v.etapas["EX"].origen == "stall",
    "beq_no_tomado": lambda v: "no tomado" in v.etapas["EX"].nota,
    "flush": lambda v: v.flush,
    "burbuja_flush": lambda v: v.etapas["ID"].estado == BURBUJA and v.etapas["ID"].origen == "flush",
    "halt_en_id": lambda v: v.etapas["ID"].estado == HALT,
    "detenido": lambda v: v.detenido,
}


def test_demo_pipeline_cada_fenomeno_en_su_paso_exacto():
    texto, palabras = leer("demo_pipeline")
    anotados = {}
    for k, clave in re.findall(r"^#\s*PASO\s+(\d+)\s+(\w+)\s*$", texto, re.M):
        anotados.setdefault(clave, set()).add(int(k))
    assert set(anotados) == set(FENOMENOS)
    enlace = Enlace(FpgaSimulada())
    enlace.cargar(palabras)
    e = enlace.volcar()
    ctx = Contexto(palabras, e.mem)
    v = deducir(e, None, ctx)
    vistos = {c: set() for c in FENOMENOS}
    while True:
        assert v.avisos == [], (e.ciclos, v.avisos)
        for clave, f in FENOMENOS.items():
            if f(v):
                vistos[clave].add(e.ciclos)
        if e.detenido:
            break
        e = enlace.paso()
        v = deducir(e, v, ctx)
    assert vistos == anotados
    # Detalles que dice el guion:
    enlace.cargar(palabras)
    e = enlace.volcar()
    seq = [deducir(e, None, ctx)]
    for _ in range(17):
        e = enlace.paso()
        seq.append(deducir(e, seq[-1], ctx))
    assert seq[9].bypass == [5] and "bypass" in seq[9].etapas["ID"].nota
    assert seq[12].etapas["ID"].texto == "add x8, x7, x7"
    assert seq[13].etapas["ID"].pc == seq[12].etapas["ID"].pc == 0x2C     # congelado
    assert {f.valor for f in seq[14].forwarding} == {10}                   # x7 = 10
    assert seq[16].etapas["IF"].estado == "descarta" and seq[16].etapas["ID"].estado == "descarta"
    assert seq[17].etapas["IF"].pc == 0x40                                  # salto: addi x12


# -------------------------------------------------------------- contra el RTL
IVERILOG = os.environ.get("IVERILOG", "iverilog")
VVP = os.environ.get("VVP", "vvp")


@pytest.fixture(scope="module")
def tb(tmp_path_factory):
    if not shutil.which(IVERILOG) or not shutil.which(VVP):
        pytest.skip("iverilog/vvp no instalados (sudo apt install iverilog)")
    tmp = tmp_path_factory.mktemp("traza_defensa")
    fuentes = [f for f in glob.glob(os.path.join(rutas.LAB, "src", "cpu", "**", "*.v"),
                                    recursive=True) if not f.endswith("cpu_if_id_test.v")]
    subprocess.run([IVERILOG, "-g2005", "-o", str(tmp / "tb.vvp"), "-s", "tb_traza",
                    os.path.join(rutas.GUI, "tests", "hdl", "tb_traza.v")] + fuentes,
                   check=True, capture_output=True, text=True)
    return tmp


@pytest.mark.parametrize("nombre", NOMBRES)
def test_igual_al_rtl_ciclo_a_ciclo(tb, nombre):
    from test_pipeline_sim import traza_rtl
    _, palabras = leer(nombre)
    sim = PipelineSim(palabras)
    sim.correr(1000)
    n = sim.ciclos + 3 if sim.halted else 60
    sim = PipelineSim(palabras)
    for ciclo, pc, halted, fault, lat, regs, dmem in traza_rtl(tb, nombre, palabras, None, n):
        if ciclo:
            sim.paso()
        assert (sim.pc, sim.halted, sim.fault, sim.latches_bits(),
                [sim.reg(i) for i in range(32)], sim.dmem) == (pc, halted, fault, lat, regs, dmem), \
            f"{nombre}: el RTL y el simulador difieren despues del ciclo {ciclo}"
    modelo = ejecutar(palabras, verificar_estable=False)
    if modelo.termina:                     # y el RTL termina igual que el modelo
        assert (halted, sim.ciclos, pc, regs) == (1, modelo.ciclos, modelo.pc, modelo.regs)


# -------------------------------------------------------------- menu de la GUI
def test_menu_defensa_en_orden(qtbot, tmp_path):
    from PySide6.QtCore import QSettings
    from app.ventana_principal import VentanaPrincipal
    v = VentanaPrincipal(QSettings(str(tmp_path / "a.ini"), QSettings.IniFormat))
    qtbot.addWidget(v)
    acciones = [a.text() for a in v.menu_defensa.actions()]
    assert acciones == [vis for _, vis in rutas.DEMOS_DEFENSA]
    titulos = [a.text() for a in v.menu_ejemplos.actions()]
    assert titulos == ["Demostraciones (parte C)", "Pruebas de la integración", "Defensa"]
    v.menu_defensa.actions()[1].trigger()                         # demo_pipeline
    assert v.ruta_programa.endswith(os.path.join("defensa", "demo_pipeline.asm"))
    assert len(v.listado) == 18
    v.close()
