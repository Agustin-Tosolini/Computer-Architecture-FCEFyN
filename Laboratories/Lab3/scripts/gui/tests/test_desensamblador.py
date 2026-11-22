"""desensamblador.py: ida y vuelta con el ensamblador."""
import glob
import os
import random

import pytest

import rutas
from desensamblador import desensamblar, destino, es_soportada
from ensamblador import ensamblar


def _palabras_de_los_ejemplos():
    out = []
    for carpeta in (rutas.PROGRAMAS, rutas.PROGRAMAS_GUI):
        for ruta in glob.glob(os.path.join(carpeta, "*.asm")):
            with open(ruta) as f:
                out += [ln.word for ln in ensamblar(f.read())]
    return sorted(set(out))


@pytest.mark.parametrize("w", _palabras_de_los_ejemplos())
def test_ida_y_vuelta_en_los_ejemplos(w):
    assert ensamblar(desensamblar(w))[0].word == w


def _aleatorias(n=600, semilla=1):
    r = random.Random(semilla)
    x = lambda: f"x{r.randrange(32)}"
    imm12 = lambda: r.randrange(-2048, 2048)
    plantillas = [
        lambda m: f"{m} {x()}, {x()}, {x()}",
        lambda m: f"{m} {x()}, {x()}, {imm12()}",
        lambda m: f"{m} {x()}, {x()}, {r.randrange(32)}",
        lambda m: f"{m} {x()}, {imm12()}({x()})",
        lambda m: f"{m} {x()}, {x()}, {2 * r.randrange(-2048, 2048)}",
        lambda m: f"jal {x()}, {2 * r.randrange(-(1 << 19), 1 << 19)}",
        lambda m: f"lui {x()}, 0x{r.randrange(1 << 20):X}",
    ]
    grupos = [(["add", "sub", "sll", "slt", "sltu", "xor", "srl", "sra", "or", "and"], 0),
              (["addi", "slti", "sltiu", "xori", "ori", "andi", "jalr"], 1),
              (["slli", "srli", "srai"], 2), (["lb", "lh", "lw", "lbu", "lhu", "sb", "sh", "sw"], 3),
              (["beq", "bne"], 4), (["jal"], 5), (["lui"], 6)]
    out = []
    for _ in range(n):
        nombres, k = r.choice(grupos)
        m = r.choice(nombres)
        if m == "jalr":
            out.append(f"jalr {x()}, {imm12()}({x()})")
        else:
            out.append(plantillas[k](m))
    return out


@pytest.mark.parametrize("fuente", _aleatorias())
def test_ida_y_vuelta_aleatoria(fuente):
    w = ensamblar(fuente)[0].word
    texto = desensamblar(w)
    assert ensamblar(texto)[0].word == w, (fuente, texto)


def test_casos_especiales():
    assert desensamblar(0) == "halt"
    assert desensamblar(0x13) == "nop"
    assert desensamblar(0x00500093) == "addi x1, x0, 5"
    assert desensamblar(0xFFFFFFFF) == ".word 0xFFFFFFFF" and not es_soportada(0xFFFFFFFF)
    assert desensamblar(0x02000033) == ".word 0x02000033"        # mul: no soportada
    assert ensamblar(desensamblar(0x02000033))[0].word == 0x02000033
    assert destino(0x00108663, pc=8) == 0x14 and destino(0xFE091EE3, pc=0x20) == 0x1C
    assert destino(0x00500093, pc=0) is None
