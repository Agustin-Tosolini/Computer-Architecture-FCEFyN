"""ensamblador.py: codificacion de cada instruccion, pseudo-instrucciones y
mensajes de error (con el numero de linea)."""
import os

import pytest

import rutas
from ensamblador import ErrorAsm, a_hex, ensamblar

# Tabla de la especificacion RV32I: instruccion -> palabra. Sale del archivo de
# la parte A ensamblado con el ensamblador de GNU (programa_if_id.S/.hex) y de
# codificaciones de RARS (testbench/tb_cpu.v). Cubre todas las de la consigna.
TABLA = [
    ("addi x1, x0, 64", 0x04000093), ("addi x2, x0, 3", 0x00300113),
    ("add x3, x1, x2", 0x002081B3), ("sub x3, x1, x2", 0x402081B3),
    ("and x3, x1, x2", 0x0020F1B3), ("or x3, x1, x2", 0x0020E1B3),
    ("xor x3, x1, x2", 0x0020C1B3), ("sll x3, x1, x2", 0x002091B3),
    ("srl x3, x1, x2", 0x0020D1B3), ("sra x3, x1, x2", 0x4020D1B3),
    ("slt x3, x1, x2", 0x0020A1B3), ("sltu x3, x1, x2", 0x0020B1B3),
    ("andi x3, x1, 15", 0x00F0F193), ("ori x3, x1, 1", 0x0010E193),
    ("xori x3, x1, 1", 0x0010C193), ("slli x3, x1, 2", 0x00209193),
    ("srli x3, x1, 2", 0x0020D193), ("srai x3, x1, 2", 0x4020D193),
    ("slti x3, x1, 10", 0x00A0A193), ("sltiu x3, x1, 10", 0x00A0B193),
    ("addi x3, x1, -5", 0xFFB08193),
    ("sb x3, 4(x1)", 0x00308223), ("sh x3, 4(x1)", 0x00309223), ("sw x3, 4(x1)", 0x0030A223),
    ("lb x3, 4(x1)", 0x00408183), ("lbu x3, 4(x1)", 0x0040C183),
    ("lh x3, 4(x1)", 0x00409183), ("lhu x3, 4(x1)", 0x0040D183), ("lw x3, 4(x1)", 0x0040A183),
    ("jalr x0, 0(x4)", 0x00020067), ("lui x3, 0x12345", 0x123451B7),
    ("jal x19, 12", 0x00C009EF), ("bne x18, x0, -4", 0xFE091EE3), ("beq x1, x1, 12", 0x00108663),
    ("halt", 0x00000000), ("nop", 0x00000013),
]


@pytest.mark.parametrize("fuente,palabra", TABLA)
def test_codificacion_rv32i(fuente, palabra):
    assert [ln.word for ln in ensamblar(fuente)] == [palabra]


def test_el_programa_de_la_parte_A_da_lo_mismo_que_gnu_as():
    base = os.path.join(rutas.PROGRAMAS, "programa_if_id")
    with open(base + ".S") as f:
        mio = [ln.word for ln in ensamblar(f.read())]
    with open(base + ".hex") as f:
        gnu = [int(t.split("#")[0], 16) for t in f if t.split("#")[0].strip()]
    assert mio == gnu


@pytest.mark.parametrize("fuente,palabras,expansion", [
    ("mv x5, x6", [0x00030293], ["addi x5, x6, 0"]),
    ("li x5, -8", [0xFF800293], ["addi x5, x0, -8"]),
    ("li x5, 2047", [0x7FF00293], ["addi x5, x0, 2047"]),
    ("li x5, 2048", [0x000012B7, 0x80028293], ["lui x5, 0x1", "addi x5, x5, -2048"]),
    ("li x5, 0x12345678", [0x123452B7, 0x67828293], ["lui x5, 0x12345", "addi x5, x5, 1656"]),
    ("li x5, 0x80000000", [0x800002B7], ["lui x5, 0x80000"]),
    ("li x5, 0xFFFFFFFF", [0xFFF00293], ["addi x5, x0, -1"]),
    ("ret", [0x00008067], ["jalr x0, 0(ra)"]),
    ("call 8", [0x008000EF], ["jal ra, 8"]),
    ("beqz x1, 8", [0x00008463], ["beq x1, x0, 8"]),
    ("bnez x1, -4", [0xFE009EE3], ["bne x1, x0, -4"]),
    ("j 0", [0x0000006F], ["jal x0, 0"]),
])
def test_pseudo_instrucciones(fuente, palabras, expansion):
    lst = ensamblar(fuente)
    assert [ln.word for ln in lst] == palabras
    assert [ln.instr for ln in lst] == expansion


def test_li_corre_las_direcciones_y_el_listado_muestra_la_expansion():
    lst = ensamblar("li t0, 0x12345678\nfin: j fin\n")
    assert [ln.addr for ln in lst] == [0, 4, 8]
    assert lst[2].word == 0x0000006F                 # j fin salta a si mismo (0x08)
    texto = a_hex(lst)
    assert "-> lui t0, 0x12345" in texto and "-> addi t0, t0, 1656" in texto


def test_etiquetas_y_saltos_hacia_atras():
    lst = ensamblar("inicio:\n  addi x1, x0, 1\nloop: addi x1, x1, -1\n  bnez x1, loop\n  call inicio\n")
    assert lst[2].word == 0xFE009EE3                 # bne x1, x0, -4
    assert lst[3].word == 0xFF5FF0EF                 # jal ra, -12


@pytest.mark.parametrize("fuente,linea,mensaje", [
    ("nop\nmul x1, x2, x3", 2, "'mul' es de RISC-V pero no esta soportada"),
    ("nop\nfoo x1", 2, "instruccion desconocida 'foo'"),
    ("blt x1, x2, 8", 1, "no esta soportada"),
    ("addi x1, x0, 2048", 1, "fuera de rango"),
    ("nop\nnop\nadd x1, x2, x32", 3, "'x32' no es un registro"),
    ("beq x1, x2, nada", 1, "etiqueta 'nada' no definida"),
    ("a: nop\na: nop", 2, "repetida"),
    ("beq x1, x2, 3", 1, "impar"),
    ("add x1, x2", 1, "lleva 3 operandos"),
    ("li x1, 0x100000000", 1, "no entra en 32 bits"),
    ("slli x1, x1, 32", 1, "fuera de rango"),
    ("lw x1, 4[x2]", 1, "imm(registro)"),
])
def test_errores_con_numero_de_linea(fuente, linea, mensaje):
    with pytest.raises(ErrorAsm) as e:
        ensamblar(fuente)
    assert f"linea {linea}:" in str(e.value) and mensaje in str(e.value)
