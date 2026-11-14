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
    assert not v.vista_latches.aviso.text()       # el modo demo ya simula los latches
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


# ============================================================== vista del pipeline
def pasos(qtbot, v, n):
    for _ in range(n):
        k = v.estado.ciclos + 1
        v.a_paso.trigger()
        qtbot.waitUntil(lambda: v.estado.ciclos == k and not v.ocupado, timeout=TIEMPO)


def test_pipeline_paso_normal_y_listado(qtbot, ventana):
    v = ventana
    conectar_demo(qtbot, v)
    cargar(qtbot, v, "demo_forwarding.asm")
    et = v.vista_pipe.etapas
    assert et["IF"].estado == "util" and all(et[n].estado == "burbuja" for n in
                                            ("ID", "EX", "MEM", "WB"))
    pasos(qtbot, v, 4)
    et = v.vista_pipe.etapas
    # Despues de 4 ciclos: IF 0x10 (sw), ID 0x0C (sub), EX 0x08 (add), MEM 0x04, WB 0x00.
    assert [et[n].pc for n in ("IF", "ID", "EX", "MEM", "WB")] == [0x10, 0x0C, 0x08, 0x04, 0x00]
    assert et["EX"].texto == "add x7, x6, x5" and et["EX"].tipo == "R"
    assert et["WB"].nota == "escribe x5 = 0xA" and et["MEM"].nota == "sin acceso a memoria"
    assert {(f.origen, f.operando) for f in v.vista_pipe.forwarding} == \
        {("EX/MEM", "rs1"), ("MEM/WB", "rs2")}
    # Listado: las 5 etiquetas y las 5 tonalidades (IF la mas intensa).
    from app import tema
    tonos = tema.LISTADO["claro"]
    t = v.tabla_listado
    assert t.etiquetas == {0: "WB", 1: "MEM", 2: "EX", 3: "ID", 4: "► PC IF"}
    for fila, etapa in ((0, "WB"), (1, "MEM"), (2, "EX"), (3, "ID"), (4, "IF")):
        assert t.item(fila, 3).background().color().name().upper() == tonos[etapa].upper()


def test_pipeline_flush_naranja(qtbot, ventana):
    v = ventana
    conectar_demo(qtbot, v)
    cargar(qtbot, v, "demo_flush.asm")
    pasos(qtbot, v, 4)
    vp = v.vista_pipe
    assert vp.flush and vp.etapas["IF"].estado == "descarta" and vp.etapas["ID"].estado == "descarta"
    from app import tema
    naranja = tema.LISTADO["claro"]["descarta"].upper()
    t = v.tabla_listado
    assert t.item(3, 3).background().color().name().upper() == naranja      # 0x0C (ID)
    assert t.item(4, 3).background().color().name().upper() == naranja      # 0x10 (IF)
    pasos(qtbot, v, 1)
    assert v.vista_pipe.etapas["ID"].origen == "flush"
    assert 3 not in v.tabla_listado.etiquetas                                 # burbuja: sin fila


def test_pipeline_stall(qtbot, ventana):
    v = ventana
    conectar_demo(qtbot, v)
    cargar(qtbot, v, "demo_load_use.asm")
    pasos(qtbot, v, 4)
    assert v.vista_pipe.stall
    pc = v.estado.pc
    pasos(qtbot, v, 1)
    assert v.estado.pc == pc and v.vista_pipe.etapas["EX"].origen == "stall"


def test_pipeline_signo_de_pregunta(qtbot, ventana):
    """Programa que la GUI no cargo (se conecta con uno ya corriendo): '?'."""
    v = ventana
    conectar_demo(qtbot, v)
    cargar(qtbot, v, "fibonacci.asm")
    v.a_correr.trigger()
    qtbot.waitUntil(lambda: v.estado.detenido and not v.ocupado, timeout=TIEMPO)
    assert v.vista_pipe.etapas["WB"].estado == "halt"           # deducido simulando
    v.programa_cargado = None                                   # "no se cargo desde la GUI"
    v.ctx = __import__("pipeline_view").Contexto()
    v.vista_pipe = None
    v.a_volcar.trigger()
    qtbot.waitUntil(lambda: v.vista_pipe is not None and not v.ocupado, timeout=TIEMPO)
    wb = v.vista_pipe.etapas["WB"]
    assert wb.estado == "desconocida" and "GUI" in wb.motivo
    assert "Vista del pipeline" in v.panel_log.texto_plano()


def test_pipeline_halt_y_seguir_instruccion(qtbot, ventana):
    v = ventana
    conectar_demo(qtbot, v)
    cargar(qtbot, v, "demo_forwarding.asm")
    v.tabs_programa.setCurrentIndex(1)
    v._seguir_fila(1, 0)                                         # sigue addi (0x04)
    assert v.seguido == 0x04 and v.vista_pipeline.lienzo.seguido == 0x04
    pasos(qtbot, v, 3)
    assert v.seguido_visto
    pasos(qtbot, v, 4)                                           # sale por WB
    assert v.seguido is None
    pasos(qtbot, v, 2)
    assert v.estado.detenido and v.vista_pipe.detenido
    assert v.vista_pipe.etapas["WB"].estado == "halt"


def test_clic_en_latch_abre_el_detalle(qtbot, ventana):
    v = ventana
    v._ver_latch("EX/MEM")
    assert v.tabs_abajo.currentWidget() is v.vista_latches
    assert v.vista_latches.arbol.currentItem() is v.vista_latches.ramas["EX/MEM"]
    assert not v.vista_latches.ramas["IF/ID"].isExpanded()


def test_pipeline_se_pliega(qtbot, ventana):
    v = ventana
    v.vista_pipeline.boton.setChecked(False)
    assert not v.vista_pipeline.lienzo.isVisible()
    v.vista_pipeline.boton.setChecked(True)
    assert v.vista_pipeline.lienzo.isVisible()
