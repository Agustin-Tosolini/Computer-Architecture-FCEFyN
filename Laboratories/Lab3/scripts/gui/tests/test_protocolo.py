"""protocolo.py: codificacion del 'L' y la clase Enlace, contra la FPGA
simulada (mismo protocolo a nivel de bytes) y contra transportes "rotos"."""
import threading
import time

import pytest

import decodificador as dec
from ensamblador import ensamblar
from fpga_simulada import FpgaSimulada
from protocolo import (Enlace, ErrorConexion, RespuestaInvalida, SinRespuesta, armar_carga)
from rv32i_model import ejecutar


def asm(texto):
    return [ln.word for ln in ensamblar(texto)]


# -------------------------------------------------------------- comando 'L'
def test_armar_carga_bytes_exactos():
    palabras, datos, avisos = armar_carga([0x00500093, 0x00308113, 0x00000000])
    assert datos == (b"L" + bytes([3, 0]) +
                     bytes([0x93, 0x00, 0x50, 0x00]) +        # little-endian
                     bytes([0x13, 0x81, 0x30, 0x00]) +
                     bytes([0, 0, 0, 0]))
    assert avisos == []


def test_armar_carga_n_grande_lsb_primero_y_recortes():
    _, datos, avisos = armar_carga([0x13] * 300)
    assert datos[1:3] == (256).to_bytes(2, "little")          # recortado a 256
    assert len(datos) == 3 + 4 * 256 and len(avisos) == 2
    _, datos, avisos = armar_carga([])
    assert datos == b"L\x00\x00" and avisos == []


# -------------------------------------------------------------- contra la FPGA simulada
@pytest.fixture
def enlace():
    return Enlace(FpgaSimulada())


def test_cargar_volcar_y_reset(enlace):
    assert enlace.cargar(asm("addi x1, x0, 5\nhalt")) == []
    e = enlace.volcar()
    assert (e.pc, e.ciclos, e.estado) == (0, 0, 0) and e.regs[1] == 0
    assert e.es_burbuja("IF/ID") and e.campo("IF/ID", "instr") == 0x13
    e = enlace.correr()
    assert e.detenido and e.regs[1] == 5 and e.ciclos == 5
    enlace.reset()
    e = enlace.volcar()
    assert e.ciclos == 0 and e.regs[1] == 0 and not e.detenido


def test_paso_a_paso_igual_al_modelo(enlace):
    prog = asm(open(__import__("rutas").PROGRAMAS_GUI + "/demo_load_use.asm").read())
    enlace.cargar(prog)
    modelo = ejecutar(prog)
    for k, (regs, mem, pc, st, _) in enumerate(modelo.pasos, start=1):
        e = enlace.paso()
        assert (e.ciclos, e.pc, e.estado, e.regs, e.mem) == (k, pc, st, regs, mem), k
    e = enlace.paso()                      # detenido: no cambia
    assert e.ciclos == modelo.ciclos and e.detenido


def test_interrumpir_loop_infinito(enlace):
    enlace.cargar(asm("li t0, 0\nbucle: addi t0, t0, 1\nj bucle"))
    cancelar = threading.Event()
    threading.Timer(0.3, cancelar.set).start()
    t0 = time.monotonic()
    e = enlace.correr(cancelar)
    assert time.monotonic() - t0 >= 0.3
    assert e.interrumpido and not e.detenido and e.estado == 0x02
    assert e.ciclos > 100 and e.regs[5] > 10
    e = enlace.paso()                      # 'S' borra el bit de interrumpido
    assert e.estado == 0 and e.ciclos > 100


def test_error_estado_0x05(enlace):
    enlace.cargar(asm("li a0, 1\n.word 0xFFFFFFFF\nhalt"))
    e = enlace.correr()
    assert e.estado == 0x05 and e.error and e.regs[10] == 1


def test_memoria_de_datos_se_conserva(enlace):
    enlace.cargar(asm("li t0, 77\nsw t0, 8(x0)\nhalt"))
    enlace.correr()
    enlace.cargar(asm("halt"))
    e = enlace.volcar()
    assert e.mem[2] == 77 and e.regs[5] == 0     # 'L' resetea registros, no la RAM


def test_fpga_simulada_ignora_bytes_y_carga_como_la_real():
    f = FpgaSimulada()
    f.escribir(b"I?Z")                            # fuera de RUN: se descartan
    assert f.leer(10, 0.05) == b""
    f.escribir(armar_carga([0x13] * 300)[1][:3] + b"\x13\x00\x00\x00" * 256)
    assert f.leer(1, 0.5) == b"K"
    assert f.imem[254] == 0x13 and f.imem[255] == 0     # la 255 siempre es HALT
    f.escribir(b"L\x00\x00")                      # N = 0: todo HALT
    assert f.leer(1, 0.5) == b"K" and set(f.imem) == {0}


# -------------------------------------------------------------- errores de transporte
class Transporte:
    """Transporte de prueba: responde lo que se le diga (o nada)."""

    def __init__(self, respuesta=b"", roto=False):
        self.respuesta = bytearray(respuesta)
        self.roto = roto
        self.enviado = b""

    def escribir(self, datos):
        if self.roto:
            raise ErrorConexion("cable desconectado")
        self.enviado += datos

    def leer(self, n, timeout):
        if not self.respuesta:
            time.sleep(min(timeout, 0.01))
            return b""
        d = bytes(self.respuesta[:n])
        del self.respuesta[:n]
        return d

    def vaciar_entrada(self):
        pass

    def cerrar(self):
        pass


def test_sin_respuesta():
    e = Enlace(Transporte())
    with pytest.raises(SinRespuesta, match="'K'"):
        e.reset()
    with pytest.raises(SinRespuesta, match="volcado"):
        e.volcar()


def test_respuesta_corta_y_ack_incorrecto():
    with pytest.raises(RespuestaInvalida, match="100 de 326"):
        Enlace(Transporte(b"\xA5" + bytes(99))).paso()
    with pytest.raises(RespuestaInvalida, match="0x3F"):
        Enlace(Transporte(b"?")).reset()


def test_cabecera_mala():
    with pytest.raises(dec.ErrorVolcado, match="cabecera"):
        Enlace(Transporte(bytes(326))).volcar()


def test_cable_desconectado():
    with pytest.raises(ErrorConexion):
        Enlace(Transporte(roto=True)).paso()
    f = FpgaSimulada()
    f.desconectar()
    with pytest.raises(ErrorConexion):
        Enlace(f).volcar()


def test_I_que_no_trae_volcado():
    cancelar = threading.Event()
    cancelar.set()
    t = Transporte()
    with pytest.raises(SinRespuesta, match="Interrumpir"):
        Enlace(t).correr(cancelar)
    assert t.enviado == b"RI"
