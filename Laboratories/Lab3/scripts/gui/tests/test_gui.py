"""Pruebas de humo de la interfaz (pytest-qt, sin pantalla: offscreen), en
modo demo (FPGA simulada)."""
import os

import pytest
from PySide6.QtCore import QSettings

import rutas
from app.ventana_principal import VentanaPrincipal

TIEMPO = 5000            # ms maximos para cada espera


@pytest.fixture
def ventana(qtbot, tmp_path):
    v = VentanaPrincipal(QSettings(str(tmp_path / "ajustes.ini"), QSettings.IniFormat))
    qtbot.addWidget(v)
    v.show()
    yield v
    v.close()


def conectar_demo(qtbot, v):
    v.combo_modo.setCurrentText("Simulado")
    v.conectar_o_desconectar()
    qtbot.waitUntil(lambda: v.conectado and not v.ocupado and v.estado is not None, timeout=TIEMPO)


def cargar(qtbot, v, nombre):
    v.abrir_archivo(os.path.join(rutas.PROGRAMAS_GUI, nombre))
    v.estado = None
    v.cargar()
    qtbot.waitUntil(lambda: v.estado is not None and not v.ocupado, timeout=TIEMPO)


def test_botones_sin_conexion(ventana):
    v = ventana
    assert not v.conectado and v.chip.text() == "Desconectado"
    for a in (v.a_cargar, v.a_reset, v.a_paso, v.a_correr, v.a_interrumpir, v.a_volcar):
        assert not a.isEnabled(), a.text()
    assert v.a_ensamblar.isEnabled()


def test_conectar_cargar_y_pasos(qtbot, ventana):
    v = ventana
    conectar_demo(qtbot, v)
    assert v.lbl_conexion.text().startswith("FPGA simulada")
    assert v.vista_latches.aviso.text()                       # aviso "no simulados"
    assert v.a_paso.isEnabled() and not v.a_interrumpir.isEnabled()
    cargar(qtbot, v, "demo_forwarding.asm")
    assert v.estado.ciclos == 0 and v.tabla_listado.rowCount() == 6
    for k in range(1, 6):
        v.a_paso.trigger()
        qtbot.waitUntil(lambda: v.estado.ciclos == k and not v.ocupado, timeout=TIEMPO)
    # La 1.a instruccion (li t0, 10) esta en EX en el ciclo 3 y escribe en WB al
    # final del ciclo 5: recien ahi cambia x5, y se resalta en amarillo.
    assert v.tabla_regs.item(5, 2).text() == "0x0000000A"
    assert v.tabla_regs.cambiados == {5}
    assert v.tabla_listado.fila_pc == 5 and v.lbl_pc.text() == "0x00000014"
    v.combo_formato.setCurrentText("Decimal con signo")
    assert v.tabla_regs.item(5, 2).text() == "10"


def test_correr_hasta_halt(qtbot, ventana):
    v = ventana
    conectar_demo(qtbot, v)
    cargar(qtbot, v, "fibonacci.asm")
    v.a_correr.trigger()
    qtbot.waitUntil(lambda: v.estado.detenido and not v.ocupado, timeout=TIEMPO)
    assert v.chip.text() == "Terminó (HALT)" and v.lbl_ciclos.text() == "106"
    assert v.tabla_regs.item(10, 2).text() == "0x00000037"          # a0 = 55
    assert v.tabla_mem.item(10, 2).text() == "0x00000037"           # mem[10] = 55
    raiz = v.vista_latches.ramas["MEM/WB"]
    assert raiz.text(1) == "instrucción válida"
    hijos = {raiz.child(i).text(0): raiz.child(i).text(1) for i in range(raiz.childCount())}
    assert hijos["halt"] == "ON" and hijos["illegal"] == "off"


def test_correr_e_interrumpir_loop(qtbot, ventana):
    v = ventana
    conectar_demo(qtbot, v)
    cargar(qtbot, v, "demo_loop_infinito.asm")
    v.a_correr.trigger()
    qtbot.waitUntil(lambda: v.corriendo, timeout=TIEMPO)
    assert v.chip.text() == "Corriendo" and v.a_interrumpir.isEnabled()
    assert not v.a_paso.isEnabled() and not v.a_cargar.isEnabled()
    assert not v.b_conectar.isEnabled()
    qtbot.wait(300)
    v.a_interrumpir.trigger()
    qtbot.waitUntil(lambda: not v.corriendo and v.estado.interrumpido, timeout=TIEMPO)
    assert v.chip.text() == "Interrumpido" and v.estado.estado == 0x02
    assert v.a_paso.isEnabled() and not v.a_interrumpir.isEnabled()


def test_error_del_programa(qtbot, ventana):
    v = ventana
    conectar_demo(qtbot, v)
    cargar(qtbot, v, "demo_error_memoria.asm")
    v.a_correr.trigger()
    qtbot.waitUntil(lambda: v.estado.detenido and not v.ocupado, timeout=TIEMPO)
    assert v.chip.text() == "Error" and v.estado.estado == 0x05


def test_error_de_ensamblado_marca_la_linea(ventana):
    v = ventana
    v.editor.setPlainText("addi x1, x0, 5\n\nmul x2, x1, x1\nhalt\n")
    assert v.ensamblar() is False
    assert v.editor.linea_error == 3
    assert "linea 3" in v.lbl_asm.text() and "mul" in v.lbl_asm.text()
    v.editor.setPlainText("addi x1, x0, 5\nhalt\n")
    assert v.ensamblar() and v.editor.linea_error is None


def test_abrir_hex_lo_desensambla(qtbot, ventana):
    v = ventana
    v.abrir_archivo(os.path.join(rutas.PROGRAMAS_GUI, "demo_flush.hex"))
    assert "beq x5, x5, 12" in v.editor.toPlainText()
    from generar_programas import procesar
    _, listado, _, _ = procesar(os.path.join(rutas.PROGRAMAS_GUI, "demo_flush.asm"))
    assert [ln.word for ln in v.listado] == [ln.word for ln in listado]


def test_cable_desconectado(qtbot, ventana):
    v = ventana
    conectar_demo(qtbot, v)
    v.trabajador.transporte.desconectar()             # como si se sacara el USB
    v.a_paso.trigger()
    qtbot.waitUntil(lambda: not v.conectado, timeout=TIEMPO)
    assert v.chip.text() == "Desconectado" and "desconectada" in v.ultimo_error
    assert not v.a_paso.isEnabled() and v.b_conectar.text() == "Conectar"


def test_log_filtro_y_bytes(qtbot, ventana):
    v = ventana
    conectar_demo(qtbot, v)
    v.panel_log.ver_bytes.setChecked(True)
    v.a_volcar.trigger()
    qtbot.waitUntil(lambda: "RX A5" in v.panel_log.texto_plano(), timeout=TIEMPO)
    assert "TX 44" in v.panel_log.texto_plano()                  # 'D' = 0x44
    v.panel_log.filtro.setCurrentText("Solo errores")
    assert "RX A5" in v.panel_log.texto_plano()                  # los bytes siguen
    v.panel_log.ver_bytes.setChecked(False)
    assert "Conectado" not in v.panel_log.texto_plano()
    v.panel_log.limpiar()
    assert v.panel_log.texto_plano() == ""


def test_recuerda_el_modo(qtbot, tmp_path):
    ruta = str(tmp_path / "a.ini")
    v = VentanaPrincipal(QSettings(ruta, QSettings.IniFormat))
    qtbot.addWidget(v)
    v.combo_modo.setCurrentText("Simulado")
    v.close()
    v2 = VentanaPrincipal(QSettings(ruta, QSettings.IniFormat))
    qtbot.addWidget(v2)
    assert v2.combo_modo.currentText() == "Simulado"
    v2.close()


def test_cerrar_durante_una_corrida_manda_I(qtbot, tmp_path):
    v = VentanaPrincipal(QSettings(str(tmp_path / "b.ini"), QSettings.IniFormat))
    qtbot.addWidget(v)
    conectar_demo(qtbot, v)
    cargar(qtbot, v, "demo_loop_infinito.asm")
    v.panel_log.ver_bytes.setChecked(True)
    v.a_correr.trigger()
    qtbot.waitUntil(lambda: v.corriendo, timeout=TIEMPO)
    v.close()
    assert not v.corriendo
    assert "TX 49" in v.panel_log.texto_plano()                  # 'I' = 0x49
