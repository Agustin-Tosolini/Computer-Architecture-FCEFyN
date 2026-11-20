"""Los programas de ejemplo de la parte C: ensamblan, no dependen de memoria
sin inicializar, sus "# ESPERADO:" coinciden con el modelo y el .hex esta al dia."""
import glob
import os

import pytest

import rutas
from ensamblador import a_hex
from generar_programas import procesar

PROGRAMAS = sorted(glob.glob(os.path.join(rutas.PROGRAMAS_GUI, "*.asm")))


def test_estan_los_pedidos():
    nombres = {os.path.basename(p)[:-4] for p in PROGRAMAS}
    assert {"fibonacci", "suma_arreglo", "demo_forwarding", "demo_load_use", "demo_flush",
            "demo_error_ilegal", "demo_error_memoria", "demo_loop_infinito"} <= nombres


@pytest.mark.parametrize("ruta", PROGRAMAS, ids=os.path.basename)
def test_anotaciones(ruta):
    texto, listado, r, errores = procesar(ruta)
    assert errores == []
    assert "ESPERADO" in texto


@pytest.mark.parametrize("ruta", PROGRAMAS, ids=os.path.basename)
def test_hex_actualizado(ruta):
    _, listado, _, _ = procesar(ruta)
    with open(ruta[:-4] + ".hex") as f:
        palabras = [int(t.split("#")[0], 16) for t in f if t.split("#")[0].strip()]
    assert palabras == [ln.word for ln in listado], "correr generar_programas.py"
