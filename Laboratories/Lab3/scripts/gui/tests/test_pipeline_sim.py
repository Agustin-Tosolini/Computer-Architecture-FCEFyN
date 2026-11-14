"""pipeline_sim.py contra el RTL (Icarus Verilog): los 480 bits de los
latches, el PC, halted, fault, los 32 registros y las 32 palabras de memoria
tienen que ser IGUALES en cada ciclo, en todos los programas de ejemplo y en
casos de error. Ademas, contra el modelo de referencia (sin iverilog).

tests/hdl/tb_traza.v se compila una sola vez; si no hay iverilog, los tests
contra el RTL se saltean con un aviso."""
import glob
import os
import shutil
import subprocess

import pytest

import rutas
from ensamblador import ensamblar
from pipeline_sim import PipelineSim
from rv32i_model import ejecutar

IVERILOG = os.environ.get("IVERILOG", "iverilog")
VVP = os.environ.get("VVP", "vvp")


def asm(texto):
    return [ln.word for ln in ensamblar(texto)]


def _programas():
    out = []
    for carpeta in (rutas.PROGRAMAS, rutas.PROGRAMAS_GUI):
        for ruta in sorted(glob.glob(os.path.join(carpeta, "*.asm"))):
            with open(ruta) as f:
                out.append((os.path.basename(ruta)[:-4], asm(f.read()), None))
    # Casos de error y bordes que no estan en los ejemplos.
    out += [
        ("jalr_fuera", asm("addi x1, x0, 1024\njalr x0, 0(x1)\naddi x2, x0, 9"), None),
        ("jalr_impar", asm("addi x1, x0, 2\njalr x0, 0(x1)"), None),
        ("lh_impar", asm("addi x1, x0, 3\nlh x2, 0(x1)\naddi x3, x0, 1\nhalt"), None),
        ("sw_fuera", asm("addi x1, x0, 9\nsw x1, 128(x0)\naddi x2, x0, 99"), None),
        ("mem_previa", asm("lw x1, 8(x0)\nlb x2, 9(x0)\nadd x3, x1, x2\nsw x3, 0(x0)\nhalt"),
         [0x11, 0x22, 0x80FF7F33] + [i * 0x01010101 for i in range(3, 32)]),
        ("halt_tras_salto", asm("beq x0, x0, 8\nhalt\nhalt"), None),
        ("vacio", [], None),
    ]
    return out


PROGRAMAS = _programas()


@pytest.fixture(scope="module")
def tb(tmp_path_factory):
    if not shutil.which(IVERILOG) or not shutil.which(VVP):
        pytest.skip("iverilog/vvp no instalados (sudo apt install iverilog)")
    tmp = tmp_path_factory.mktemp("traza")
    fuentes = [f for f in glob.glob(os.path.join(rutas.LAB, "src", "cpu", "**", "*.v"),
                                    recursive=True) if not f.endswith("cpu_if_id_test.v")]
    subprocess.run([IVERILOG, "-g2005", "-o", str(tmp / "tb.vvp"), "-s", "tb_traza",
                    os.path.join(rutas.GUI, "tests", "hdl", "tb_traza.v")] + fuentes,
                   check=True, capture_output=True, text=True)
    return tmp


def traza_rtl(tmp, nombre, palabras, mem, ciclos):
    (tmp / f"{nombre}.mem").write_text("".join(f"{w:08X}\n" for w in palabras) or "00000000\n")
    args = [VVP, "-n", str(tmp / "tb.vvp"), f"+PROG={tmp / (nombre + '.mem')}",
            f"+N={len(palabras)}", f"+CICLOS={ciclos}", f"+SALIDA={tmp / (nombre + '.txt')}"]
    if mem is not None:
        (tmp / f"{nombre}.dmem").write_text("".join(f"{w:08X}\n" for w in mem))
        args.append(f"+MEM={tmp / (nombre + '.dmem')}")
    r = subprocess.run(args, capture_output=True, text=True, cwd=tmp, timeout=300)
    assert "PASS" in r.stdout, r.stdout + r.stderr
    filas = []
    for linea in (tmp / f"{nombre}.txt").read_text().splitlines():
        v = linea.split()
        filas.append((int(v[0]), int(v[1], 16), int(v[2]), int(v[3]), int(v[4], 16),
                      [int(x, 16) for x in v[5:37]], [int(x, 16) for x in v[37:69]]))
    return filas


def _ciclos(palabras, mem):
    sim = PipelineSim(palabras, mem)
    sim.correr(400)
    return sim.ciclos + 3 if sim.halted else 60     # 3 de mas: no cambia nada


@pytest.mark.parametrize("nombre,palabras,mem", PROGRAMAS, ids=[p[0] for p in PROGRAMAS])
def test_igual_al_rtl_ciclo_a_ciclo(tb, nombre, palabras, mem):
    n = _ciclos(palabras, mem)
    sim = PipelineSim(palabras, mem)
    for ciclo, pc, halted, fault, lat, regs, dmem in traza_rtl(tb, nombre, palabras, mem, n):
        if ciclo:
            sim.paso()
        got = (sim.pc, sim.halted, sim.fault, sim.latches_bits(),
               [sim.reg(i) for i in range(32)], sim.dmem)
        assert got == (pc, halted, fault, lat, regs, dmem), \
            f"{nombre}: distinto despues del ciclo {ciclo} (latches xor {got[3] ^ lat:#x})"


@pytest.mark.parametrize("nombre,palabras,mem", PROGRAMAS, ids=[p[0] for p in PROGRAMAS])
def test_igual_al_modelo(nombre, palabras, mem):
    """Sin iverilog: registros, memoria, PC y estado igual al modelo en cada ciclo."""
    modelo = ejecutar(palabras, mem_inicial=mem, verificar_estable=False)
    sim = PipelineSim(palabras, mem)
    for k, (regs, dmem, pc, st, _) in enumerate(modelo.pasos, start=1):
        sim.paso()
        estado = (sim.fault << 2 | sim.halted) if sim.halted else 0
        estado = 0x05 if sim.fault else estado
        assert ([sim.reg(i) for i in range(32)], sim.dmem, sim.pc, estado) == \
            (regs, dmem, pc, st), f"{nombre}: ciclo {k}"
    if modelo.termina:
        assert sim.halted and sim.ciclos == modelo.ciclos


def test_pc_de_mem_y_wb():
    """El simulador sigue el PC de las instrucciones en EX/MEM y MEM/WB."""
    sim = PipelineSim(asm("addi x1, x0, 1\naddi x2, x0, 2\naddi x3, x0, 3\nhalt"))
    vistos = []
    while not sim.halted:
        sim.paso()
        vistos.append((sim.pc_mem, sim.pc_wb))
    assert vistos[2] == (0x0, None) and vistos[3] == (0x4, 0x0) and vistos[4] == (0x8, 0x4)
    assert vistos[-1] == (None, 0xC)                 # el HALT en WB
