"""decodificador.py: bytes del volcado -> Estado."""
import pytest

import decodificador as dec


def _volcado(**k):
    base = dict(pc=0x18, ciclos=9, estado=0x01, regs=[i * 3 for i in range(32)],
                mem=[0xA0000000 + i for i in range(32)], lat_bits=dec.LAT_HALT)
    base.update(k)
    return dec.armar_volcado(**base)


def test_campos_basicos_little_endian():
    datos = _volcado(pc=0x12345678)
    assert len(datos) == 326 and datos[0] == 0xA5
    assert datos[1:5] == bytes([0x78, 0x56, 0x34, 0x12])          # little-endian
    e = dec.decodificar(datos)
    assert e.pc == 0x12345678 and e.ciclos == 9
    assert e.regs[31] == 93 and e.mem[31] == 0xA000001F


def test_bits_de_estado():
    assert dec.decodificar(_volcado(estado=0x01)).texto_estado() == "Terminó (HALT)"
    e = dec.decodificar(_volcado(estado=0x05))
    assert e.detenido and e.error and not e.interrumpido and e.texto_estado() == "Error"
    e = dec.decodificar(_volcado(estado=0x02))
    assert e.interrumpido and not e.detenido and e.texto_estado() == "Interrumpido"
    assert dec.decodificar(_volcado(estado=0)).texto_estado() == "Listo"


def test_patron_de_halt_en_los_latches():
    e = dec.decodificar(_volcado())
    assert e.campo("IF/ID", "instr") == 0x13 and e.es_burbuja("IF/ID")
    assert e.campo("MEM/WB", "valid") == 1 and e.campo("MEM/WB", "halt") == 1
    assert e.campo("MEM/WB", "illegal") == 0
    assert e.es_burbuja("ID/EX") and e.es_burbuja("EX/MEM")


def test_cada_campo_en_su_lugar():
    # Un 1 en el bit bajo de cada campo: solo ese campo vale 1.
    import campos_latches as cl
    for c in cl.CAMPOS:
        e = dec.decodificar(_volcado(lat_bits=1 << c[3]))
        for otro in e.latches[c[0]]:
            assert otro.valor == (1 if otro.nombre == c[1] else 0), (c, otro)


def test_errores_de_formato():
    with pytest.raises(dec.ErrorVolcado, match="325 bytes"):
        dec.decodificar(_volcado()[:-1])
    malo = bytearray(_volcado())
    malo[0] = 0x00
    with pytest.raises(dec.ErrorVolcado, match="cabecera 0x00"):
        dec.decodificar(bytes(malo))
