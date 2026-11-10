"""Volcados REALES de simulacion: tests/hdl/tb_captura.v corre el top con el
cpu real (Icarus Verilog), carga un programa por UART y guarda los bytes que
manda la FPGA junto con los valores internos del diseno. Aca se verifica que el
decodificador los interpreta exactamente igual, campo por campo, y que el
resultado de 'R' coincide con el modelo de referencia.

Necesita iverilog y vvp (variables IVERILOG / VVP o en el PATH); si no estan,
el test se saltea con un aviso. Tarda unos 30 s."""
import glob
import os
import shutil
import subprocess

import pytest

import rutas
from decodificador import decodificar
from ensamblador import ensamblar
from rv32i_model import ejecutar

IVERILOG = os.environ.get("IVERILOG", "iverilog")
VVP = os.environ.get("VVP", "vvp")
PROGRAMA = os.path.join(rutas.PROGRAMAS_GUI, "suma_arreglo.asm")


@pytest.fixture(scope="module")
def captura(tmp_path_factory):
    if not shutil.which(IVERILOG) or not shutil.which(VVP):
        pytest.skip("iverilog/vvp no instalados (sudo apt install iverilog)")
    tmp = tmp_path_factory.mktemp("captura")
    with open(PROGRAMA) as f:
        palabras = [ln.word for ln in ensamblar(f.read())]
    (tmp / "prog.mem").write_text("".join(f"{w:08X}\n" for w in palabras))
    fuentes = sorted(glob.glob(os.path.join(rutas.LAB, "src", "debug_unit", "*.v")) +
                     glob.glob(os.path.join(rutas.LAB, "src", "cpu", "**", "*.v"), recursive=True))
    tb = os.path.join(rutas.GUI, "tests", "hdl", "tb_captura.v")
    subprocess.run([IVERILOG, "-g2005", "-o", str(tmp / "tb.vvp"), "-s", "tb_captura", tb] + fuentes,
                   check=True, capture_output=True, text=True)
    r = subprocess.run([VVP, "-n", str(tmp / "tb.vvp"), f"+PROG={tmp / 'prog.mem'}",
                        f"+N={len(palabras)}", f"+SALIDA={tmp / 'captura.txt'}"],
                       capture_output=True, text=True, timeout=600, cwd=tmp)
    assert "PASS" in r.stdout, r.stdout + r.stderr
    lineas = (tmp / "captura.txt").read_text().splitlines()
    pares = []
    for ref, dump in zip(lineas[0::2], lineas[1::2]):
        assert ref.startswith("REF ") and dump.startswith("DUMP ")
        v = [int(x, 16) for x in ref.split()[1:]]
        datos = bytes(int(x, 16) for x in dump.split()[1:])
        pares.append((v, datos))
    return palabras, pares


def test_ocho_volcados(captura):
    _, pares = captura
    assert len(pares) == 8                      # D, S x 5, R, D


def test_decodificador_igual_que_el_diseno(captura):
    _, pares = captura
    for n, (v, datos) in enumerate(pares):
        e = decodificar(datos)
        assert (e.pc, e.ciclos, e.estado) == (v[0], v[1], v[2]), n
        assert e.regs == v[3:35], n
        assert e.mem == v[35:67], n
        assert e.lat_bits == v[67], n           # los 480 bits, todos


def test_paso_a_paso_y_corrida_igual_al_modelo(captura):
    palabras, pares = captura
    modelo = ejecutar(palabras)
    for k in range(1, 6):                       # los 'S'
        e = decodificar(pares[k][1])
        regs, mem, pc, st, _ = modelo.pasos[k - 1]
        assert (e.ciclos, e.pc, e.regs) == (k, pc, regs)
    e = decodificar(pares[6][1])                # 'R'
    assert e.detenido and e.ciclos == modelo.ciclos and e.pc == modelo.pc
    assert e.regs == modelo.regs
    assert [e.mem[i] for i in range(32) if modelo.mascara >> i & 1] == \
           [modelo.mem[i] for i in range(32) if modelo.mascara >> i & 1]
    assert e.campo("MEM/WB", "halt") == 1 and e.es_burbuja("EX/MEM")
    assert decodificar(pares[7][1]).crudo == pares[6][1]     # 'D' despues: igual
