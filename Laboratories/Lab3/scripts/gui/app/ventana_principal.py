"""
ventana_principal.py - La ventana del depurador.

Zonas:
    barra de conexion   modo (Placa / Simulado), puerto, Conectar, indicador
    barra de ejecucion  Cargar (L), Reset (X), Paso (S, F10), Correr (R, F5),
                        Interrumpir (I, Esc), Volcar (D)
    izquierda           Editor de ensamblador | Listado del programa
    centro              PC, ciclos y estado (chip de color)
    derecha             Registros x0..x31
    abajo               Memoria de datos | Latches | Log

La ventana nunca habla con la FPGA: le pide cosas al Trabajador (otro hilo)
con señales y recibe las respuestas tambien por señales (hilo_serie.py).

Estados de la interfaz (deciden que botones se habilitan):
    desconectado -> conectado (libre) <-> ocupado (comando en curso)
                                      <-> corriendo (un 'R' en curso)
"""
import logging
import os
import re

from PySide6.QtCore import QSettings, QSize, Qt, QThread, QTimer, Signal
from PySide6.QtGui import QAction, QIcon, QKeySequence
from PySide6.QtWidgets import (QComboBox, QFileDialog, QGridLayout, QHBoxLayout, QLabel,
                               QMainWindow, QMessageBox, QPushButton, QSplitter, QStyle,
                               QTabWidget, QToolBar, QVBoxLayout, QWidget)

import rutas
from app.editor import EditorCodigo
from app.panel_log import PanelLog, configurar_archivo
from app.tablas import FORMATOS, TablaListado, TablaMemoria, TablaRegistros
from app.tema import estilo_chip
from app.vista_latches import VistaLatches
from desensamblador import desensamblar
from ensamblador import ErrorAsm, a_hex, ensamblar
from hilo_serie import MODO_PLACA, MODO_SIMULADO, Trabajador
from transporte import listar_puertos

log = logging.getLogger("depurador")

AVISO_SIMULADO = ("Modo simulado: los latches no se simulan (se muestran como burbujas, "
                  "salvo al terminar por HALT). Registros, memoria, PC y ciclos salen del "
                  "modelo de referencia (rv32i_model.py).")

ATAJOS = """<table cellpadding=3>
<tr><td><b>F10</b></td><td>Paso ('S'): avanza un ciclo de clock y trae el volcado</td></tr>
<tr><td><b>F5</b></td><td>Correr ('R'): corre hasta el HALT (o hasta Interrumpir)</td></tr>
<tr><td><b>Esc</b></td><td>Interrumpir ('I'): corta una corrida</td></tr>
<tr><td><b>Ctrl+L</b></td><td>Cargar ('L'): ensambla y manda el programa (resetea el procesador)</td></tr>
<tr><td><b>Ctrl+Shift+R</b></td><td>Reset ('X'): reset del procesador (el programa y la memoria de datos se conservan)</td></tr>
<tr><td><b>Ctrl+D</b></td><td>Volcar ('D'): trae el estado sin ejecutar</td></tr>
<tr><td><b>Ctrl+B</b></td><td>Ensamblar el editor</td></tr>
<tr><td><b>Ctrl+O / Ctrl+S</b></td><td>Abrir / guardar el programa</td></tr>
</table>"""


def _icono(widget, tema, estandar):
    """Icono del tema del escritorio (Mint-Y, etc.) o, si no esta, uno de Qt."""
    return QIcon.fromTheme(tema, widget.style().standardIcon(estandar))


class VentanaPrincipal(QMainWindow):
    # Pedidos al Trabajador (cruzan al otro hilo)
    pedir_conectar = Signal(str, str)
    pedir_desconectar = Signal()
    pedir_cargar = Signal(list)
    pedir_reset = Signal()
    pedir_paso = Signal()
    pedir_correr = Signal()
    pedir_volcar = Signal()

    def __init__(self, ajustes=None):
        super().__init__()
        self.ajustes = ajustes or QSettings("FCEFyN", "TP-RISCV-Depurador")
        self.setWindowTitle("TP RISC-V — Depurador")
        self.setWindowIcon(QIcon(os.path.join(rutas.GUI, "app", "iconos", "depurador.svg")))
        self.resize(1400, 860)
        # Estado de la interfaz
        self.conectado = False
        self.ocupado = False
        self.corriendo = False
        self.modo_conectado = None
        self.listado = None              # programa ensamblado (lista de Linea)
        self.listado_desactualizado = True
        self.ruta_programa = None
        self.estado = None               # ultimo volcado (decodificador.Estado)
        self.resaltar_cambios = False
        self.ultimo_error = ""
        self.ruta_log = configurar_archivo()

        self._crear_acciones()
        self._crear_barras()
        self._crear_centro()
        self._crear_menus()
        self._crear_hilo()
        self._restaurar_ajustes()
        self.actualizar_puertos()
        self._actualizar_acciones()
        self.vigilante = QTimer(self, interval=1500, timeout=self._vigilar_puerto)
        self.vigilante.start()
        log.info(f"Depurador iniciado. Log en {self.ruta_log}")

    # ================================================== construccion
    def _accion(self, texto, atajo, tema, estandar, slot, ayuda):
        a = QAction(_icono(self, tema, estandar), texto, self)
        if atajo:
            a.setShortcut(QKeySequence(atajo))
            a.setShortcutContext(Qt.ApplicationShortcut)
        a.setToolTip(f"{ayuda} ({atajo})" if atajo else ayuda)
        a.setStatusTip(ayuda)
        a.triggered.connect(slot)
        return a

    def _crear_acciones(self):
        S = QStyle.StandardPixmap
        self.a_cargar = self._accion("Cargar", "Ctrl+L", "document-send", S.SP_ArrowUp,
                                     self.cargar, "Ensambla y manda el programa ('L')")
        self.a_reset = self._accion("Reset", "Ctrl+Shift+R", "view-refresh", S.SP_BrowserReload,
                                    self.pedir_reset.emit, "Reset del procesador ('X')")
        self.a_paso = self._accion("Paso", "F10", "media-skip-forward", S.SP_MediaSkipForward,
                                   self.pedir_paso.emit, "Un ciclo de clock ('S')")
        self.a_correr = self._accion("Correr", "F5", "media-playback-start", S.SP_MediaPlay,
                                     self.pedir_correr.emit, "Corre hasta el HALT ('R')")
        self.a_interrumpir = self._accion("Interrumpir", "Esc", "media-playback-stop", S.SP_MediaStop,
                                          self.interrumpir, "Corta la corrida ('I')")
        self.a_volcar = self._accion("Volcar", "Ctrl+D", "document-preview", S.SP_FileDialogContentsView,
                                     self.pedir_volcar.emit, "Trae el estado sin ejecutar ('D')")
        self.a_ensamblar = self._accion("Ensamblar", "Ctrl+B", "system-run", S.SP_DialogApplyButton,
                                        self.ensamblar, "Ensambla el editor y muestra el listado")
        self.a_abrir = self._accion("Abrir…", "Ctrl+O", "document-open", S.SP_DialogOpenButton,
                                    self.abrir, "Abre un programa .asm o .hex")
        self.a_guardar = self._accion("Guardar .asm", "Ctrl+S", "document-save", S.SP_DialogSaveButton,
                                      self.guardar_asm, "Guarda el editor como .asm")
        self.a_guardar_hex = self._accion("Guardar .hex…", "", "document-save-as", S.SP_DialogSaveButton,
                                          self.guardar_hex, "Ensambla y guarda el .hex")

    def _crear_barras(self):
        # --- conexion
        bc = QToolBar("Conexión", self)
        bc.setObjectName("barra_conexion")
        bc.setMovable(False)
        self.combo_modo = QComboBox()
        self.combo_modo.addItems([MODO_PLACA, MODO_SIMULADO])
        self.combo_modo.setToolTip("Placa: la Basys 3 por USB. Simulado: una FPGA de "
                                   "mentira que usa el modelo de referencia (sin placa).")
        self.combo_modo.currentTextChanged.connect(lambda _: self._actualizar_acciones())
        self.combo_puerto = QComboBox()
        self.combo_puerto.setMinimumWidth(260)
        self.combo_puerto.setToolTip("Puerto serie. ★ = parece la UART de la Basys 3")
        self.b_actualizar = QPushButton(_icono(self, "view-refresh", QStyle.SP_BrowserReload), "")
        self.b_actualizar.setToolTip("Actualizar la lista de puertos")
        self.b_actualizar.clicked.connect(self.actualizar_puertos)
        self.b_conectar = QPushButton("Conectar")
        self.b_conectar.clicked.connect(self.conectar_o_desconectar)
        self.indicador = QLabel()
        for w in (QLabel(" Modo: "), self.combo_modo, QLabel("  Puerto: "), self.combo_puerto,
                  self.b_actualizar, self.b_conectar, QLabel("  "), self.indicador):
            bc.addWidget(w)
        self.addToolBar(bc)
        self.addToolBarBreak()
        # --- ejecucion
        be = QToolBar("Ejecución", self)
        be.setObjectName("barra_ejecucion")
        be.setMovable(False)
        be.setToolButtonStyle(Qt.ToolButtonTextUnderIcon)
        be.setIconSize(QSize(26, 26))
        for a in (self.a_cargar, self.a_reset, None, self.a_paso, self.a_correr,
                  self.a_interrumpir, None, self.a_volcar):
            be.addSeparator() if a is None else be.addAction(a)
        self.addToolBar(be)

    def _crear_centro(self):
        # --- izquierda: editor y listado
        self.editor = EditorCodigo()
        self.editor.textChanged.connect(self._editor_cambio)
        self.lbl_asm = QLabel("Escribí o abrí un programa y apretá Ensamblar.")
        self.lbl_asm.setWordWrap(True)
        b_ens = QPushButton("Ensamblar")
        b_ens.clicked.connect(self.ensamblar)
        b_hex = QPushButton("Guardar .hex…")
        b_hex.clicked.connect(self.guardar_hex)
        pie = QHBoxLayout()
        pie.addWidget(self.lbl_asm, 1)
        pie.addWidget(b_ens)
        pie.addWidget(b_hex)
        caja_editor = QWidget()
        le = QVBoxLayout(caja_editor)
        le.setContentsMargins(0, 0, 0, 0)
        le.addWidget(self.editor)
        le.addLayout(pie)
        self.tabla_listado = TablaListado()
        self.tabs_programa = QTabWidget()
        self.tabs_programa.addTab(caja_editor, "Editor")
        self.tabs_programa.addTab(self.tabla_listado, "Listado")

        # --- centro: PC, ciclos, estado
        centro = QWidget()
        g = QGridLayout(centro)
        self.lbl_pc = QLabel("—", objectName="numero")
        self.lbl_ciclos = QLabel("—", objectName="numero")
        self.chip = QLabel()
        self.lbl_if = QLabel("—")
        self.lbl_id = QLabel("—")
        self.lbl_conexion = QLabel("Sin conexión")
        for w in (self.lbl_if, self.lbl_id):
            w.setTextInteractionFlags(Qt.TextSelectableByMouse)
        for fila, (titulo, w) in enumerate([("PC", self.lbl_pc), ("CICLOS", self.lbl_ciclos),
                                            ("ESTADO", self.chip),
                                            ("PRÓXIMA A BUSCAR (IF)", self.lbl_if),
                                            ("EN DECODIFICACIÓN (IF/ID)", self.lbl_id),
                                            ("CONEXIÓN", self.lbl_conexion)]):
            t = QLabel(titulo, objectName="titulo")
            g.addWidget(t, 2 * fila, 0)
            g.addWidget(w, 2 * fila + 1, 0, Qt.AlignLeft)
        g.setRowStretch(12, 1)
        self._set_chip("Desconectado")

        # --- derecha: registros
        der = QWidget()
        ld = QVBoxLayout(der)
        ld.setContentsMargins(0, 0, 0, 0)
        fila = QHBoxLayout()
        fila.addWidget(QLabel("Registros", objectName="titulo"))
        fila.addStretch(1)
        self.combo_formato = QComboBox()
        self.combo_formato.addItems(FORMATOS)
        fila.addWidget(self.combo_formato)
        ld.addLayout(fila)
        self.tabla_regs = TablaRegistros()
        self.combo_formato.currentTextChanged.connect(self.tabla_regs.set_formato)
        ld.addWidget(self.tabla_regs)

        arriba = QSplitter(Qt.Horizontal)
        arriba.addWidget(self.tabs_programa)
        arriba.addWidget(centro)
        arriba.addWidget(der)
        arriba.setSizes([560, 330, 380])

        # --- abajo: memoria, latches, log
        self.tabla_mem = TablaMemoria()
        self.vista_latches = VistaLatches()
        self.panel_log = PanelLog()
        self.tabs_abajo = QTabWidget()
        self.tabs_abajo.addTab(self.tabla_mem, "Memoria de datos")
        self.tabs_abajo.addTab(self.vista_latches, "Latches")
        self.tabs_abajo.addTab(self.panel_log, "Log")

        self.split = QSplitter(Qt.Vertical)
        self.split.addWidget(arriba)
        self.split.addWidget(self.tabs_abajo)
        self.split.setSizes([520, 300])
        self.split_arriba = arriba
        self.setCentralWidget(self.split)
        self.statusBar().showMessage("Listo")

    def _crear_menus(self):
        m = self.menuBar().addMenu("&Archivo")
        for a in (self.a_abrir, self.a_guardar, self.a_guardar_hex):
            m.addAction(a)
        m.addSeparator()
        m.addAction("Salir", self.close, QKeySequence("Ctrl+Q"))
        self.menu_ejemplos = self.menuBar().addMenu("E&jemplos")
        for titulo, carpeta in (("Demostraciones (parte C)", rutas.PROGRAMAS_GUI),
                                ("Pruebas de la integración", rutas.PROGRAMAS)):
            sub = self.menu_ejemplos.addMenu(titulo)
            if os.path.isdir(carpeta):
                for nombre in sorted(os.listdir(carpeta)):
                    if nombre.endswith(".asm"):
                        ruta = os.path.join(carpeta, nombre)
                        sub.addAction(nombre[:-4], lambda r=ruta: self.abrir_archivo(r))
        m = self.menuBar().addMenu("E&jecutar")
        for a in (self.a_ensamblar, None, self.a_cargar, self.a_reset, self.a_paso,
                  self.a_correr, self.a_interrumpir, self.a_volcar):
            m.addSeparator() if a is None else m.addAction(a)
        m = self.menuBar().addMenu("Ay&uda")
        m.addAction("Atajos y comandos", self.mostrar_atajos, QKeySequence("F1"))
        m.addAction("Acerca de…", self.mostrar_acerca)

    def _crear_hilo(self):
        self.hilo = QThread(self)
        self.trabajador = Trabajador()
        self.trabajador.moveToThread(self.hilo)
        t = self.trabajador
        self.pedir_conectar.connect(t.conectar)
        self.pedir_desconectar.connect(t.desconectar)
        self.pedir_cargar.connect(t.cargar)
        self.pedir_reset.connect(t.reset)
        self.pedir_paso.connect(t.paso)
        self.pedir_correr.connect(t.correr)
        self.pedir_volcar.connect(t.volcar)
        t.conectado.connect(self._al_conectar)
        t.desconectado.connect(self._al_desconectar)
        t.volcado.connect(self._al_volcado)
        t.ack.connect(self._al_ack)
        t.error.connect(self._al_error)
        t.ocupado.connect(self._al_ocupado)
        t.corriendo.connect(self._al_corriendo)
        t.bytes_tx.connect(lambda b: log.log(15, "TX " + b.hex(" ").upper()))
        t.bytes_rx.connect(lambda b: log.log(15, "RX " + b.hex(" ").upper()))
        self.hilo.start()

    # ================================================== ajustes (QSettings)
    def _restaurar_ajustes(self):
        geo = self.ajustes.value("geometria")
        if geo is not None:
            self.restoreGeometry(geo)
        modo = self.ajustes.value("modo", MODO_PLACA)
        if modo in (MODO_PLACA, MODO_SIMULADO):
            self.combo_modo.setCurrentText(modo)
        fmt = self.ajustes.value("formato_regs", FORMATOS[0])
        if fmt in FORMATOS:
            self.combo_formato.setCurrentText(fmt)
        for nombre, split in (("split", self.split), ("split_arriba", self.split_arriba)):
            estado = self.ajustes.value(nombre)
            if estado is not None:
                split.restoreState(estado)

    def _guardar_ajustes(self):
        self.ajustes.setValue("geometria", self.saveGeometry())
        self.ajustes.setValue("modo", self.combo_modo.currentText())
        self.ajustes.setValue("formato_regs", self.combo_formato.currentText())
        self.ajustes.setValue("split", self.split.saveState())
        self.ajustes.setValue("split_arriba", self.split_arriba.saveState())

    # ================================================== conexion
    def actualizar_puertos(self):
        actual = self.combo_puerto.currentData() or self.ajustes.value("puerto", "")
        self.combo_puerto.clear()
        puertos = listar_puertos()
        recomendado = None
        for p in puertos:
            self.combo_puerto.addItem(("★ " if p.recomendado else "") +
                                      f"{p.dispositivo}  {p.descripcion}", p.dispositivo)
            if p.recomendado:
                recomendado = p.dispositivo
        elegido = actual if actual in [p.dispositivo for p in puertos] else recomendado
        if elegido:
            self.combo_puerto.setCurrentIndex(self.combo_puerto.findData(elegido))
        if not puertos:
            self.combo_puerto.addItem("(no hay puertos serie)", "")
        self._actualizar_acciones()

    def conectar_o_desconectar(self):
        if self.conectado:
            self.pedir_desconectar.emit()
            return
        modo = self.combo_modo.currentText()
        puerto = self.combo_puerto.currentData() or ""
        if modo == MODO_PLACA and not puerto:
            self._mostrar_error("No hay puerto", "No se encontró ningún puerto serie. ¿Está "
                                "conectada la placa? Probá con Actualizar, o usá el modo Simulado.")
            return
        log.info(f"Conectando ({modo}{': ' + puerto if modo == MODO_PLACA else ''})…")
        self.b_conectar.setEnabled(False)
        self.pedir_conectar.emit(modo, puerto)

    def _al_conectar(self, descripcion):
        self.conectado = True
        self.modo_conectado = self.combo_modo.currentText()
        self.puerto_conectado = self.combo_puerto.currentData() or ""
        if self.modo_conectado == MODO_PLACA:
            self.ajustes.setValue("puerto", self.puerto_conectado)
        self.lbl_conexion.setText(descripcion)
        self.vista_latches.set_aviso(AVISO_SIMULADO if self.modo_conectado == MODO_SIMULADO else "")
        log.info(f"Conectado: {descripcion}")
        self.resaltar_cambios = False
        self._actualizar_acciones()
        self.pedir_volcar.emit()                    # mostrar como esta el procesador

    def _al_desconectar(self, motivo):
        era = self.conectado
        self.conectado = self.ocupado = self.corriendo = False
        self.lbl_conexion.setText("Sin conexión")
        self._set_chip("Desconectado")
        self._actualizar_acciones()
        if motivo and era:
            log.error(f"Se perdió la conexión: {motivo}")
            self._mostrar_error("Conexión perdida", f"Se perdió la conexión con la FPGA.\n\n{motivo}"
                                "\n\nRevisá el cable USB y volvé a conectar.")
        elif not motivo:
            log.info("Desconectado")

    def _vigilar_puerto(self):
        """Si se desenchufa la placa estando quieta, nadie lee el puerto: se
        detecta mirando la lista de puertos."""
        if self.conectado and self.modo_conectado == MODO_PLACA and not self.ocupado:
            if self.puerto_conectado not in [p.dispositivo for p in listar_puertos()]:
                self.pedir_desconectar.emit()
                self._al_desconectar(f"el puerto {self.puerto_conectado} desapareció "
                                     "(¿se desconectó el cable?)")
                self.actualizar_puertos()

    # ================================================== programa
    def _editor_cambio(self):
        self.listado_desactualizado = True
        if self.editor.linea_error is not None:
            self.editor.marcar_error(None)

    def ensamblar(self):
        """Ensambla el editor. Devuelve True si salio bien."""
        try:
            listado = ensamblar(self.editor.toPlainText())
        except ErrorAsm as e:
            m = re.search(r"linea (\d+)", str(e))
            self.editor.marcar_error(int(m.group(1)) if m else None)
            self.lbl_asm.setObjectName("error_asm")
            self.lbl_asm.setStyleSheet("color: #b91c1c;")
            self.lbl_asm.setText(f"Error: {e}")
            self.tabs_programa.setCurrentIndex(0)
            log.warning(f"Error al ensamblar: {e}")
            return False
        self.listado = listado
        self.listado_desactualizado = False
        self.editor.marcar_error(None)
        self.lbl_asm.setStyleSheet("color: #166534;")
        self.lbl_asm.setText(f"OK: {len(listado)} palabras ({4 * len(listado)} bytes).")
        self.tabla_listado.mostrar(listado)
        if self.estado is not None:
            self.tabla_listado.marcar_pc(self.estado.pc)
        log.info(f"Ensamblado: {len(listado)} palabras")
        self._actualizar_acciones()
        return True

    def abrir(self):
        carpeta = os.path.dirname(self.ruta_programa) if self.ruta_programa else rutas.PROGRAMAS_GUI
        ruta, _ = QFileDialog.getOpenFileName(self, "Abrir programa", carpeta,
                                              "Programas (*.asm *.hex *.S);;Todos (*)")
        if ruta:
            self.abrir_archivo(ruta)

    def abrir_archivo(self, ruta):
        try:
            with open(ruta, encoding="utf-8") as f:
                texto = f.read()
            if ruta.endswith(".hex"):
                from rv32i_model import leer_hex
                palabras = leer_hex(ruta)
                texto = (f"# Desensamblado de {os.path.basename(ruta)} ({len(palabras)} palabras)\n"
                         + "\n".join(f"        {desensamblar(w):28s} # 0x{4 * i:03X}"
                                     for i, w in enumerate(palabras)) + "\n")
        except (OSError, ValueError) as e:
            self._mostrar_error("No se pudo abrir", f"{ruta}\n\n{e}")
            return
        self.editor.setPlainText(texto)
        self.ruta_programa = ruta
        self.setWindowTitle(f"TP RISC-V — Depurador — {os.path.basename(ruta)}")
        log.info(f"Abierto {ruta}")
        self.ensamblar()

    def guardar_asm(self):
        sugerido = self.ruta_programa if (self.ruta_programa or "").endswith(".asm") else "programa.asm"
        ruta, _ = QFileDialog.getSaveFileName(self, "Guardar programa", sugerido, "Ensamblador (*.asm)")
        if ruta:
            with open(ruta, "w", encoding="utf-8") as f:
                f.write(self.editor.toPlainText())
            self.ruta_programa = ruta
            log.info(f"Guardado {ruta}")

    def guardar_hex(self):
        if not self.ensamblar():
            return
        base = os.path.splitext(self.ruta_programa or "programa.asm")[0] + ".hex"
        ruta, _ = QFileDialog.getSaveFileName(self, "Guardar .hex", base, "Programa (*.hex)")
        if ruta:
            with open(ruta, "w", encoding="utf-8") as f:
                f.write(a_hex(self.listado, f"Generado por el depurador desde "
                                            f"{os.path.basename(self.ruta_programa or 'el editor')}"))
            log.info(f"Guardado {ruta}")

    # ================================================== ejecucion
    def cargar(self):
        if self.listado is None or self.listado_desactualizado:
            if not self.ensamblar():
                return
        palabras = [ln.word for ln in self.listado]
        log.info(f"Cargando {len(palabras)} palabras ('L')…")
        self.pedir_cargar.emit(palabras)

    def interrumpir(self):
        if self.corriendo:
            log.info("Interrumpiendo ('I')…")
            self.trabajador.interrumpir()

    def _al_ocupado(self, ocupado):
        self.ocupado = ocupado
        if ocupado and not self.corriendo:
            self._set_chip("Trabajando…")
        self._actualizar_acciones()

    def _al_corriendo(self, corriendo):
        self.corriendo = corriendo
        if corriendo:
            self._set_chip("Corriendo")
            log.info("Corriendo ('R')… Esc o Interrumpir para cortar")
        self._actualizar_acciones()

    def _al_ack(self, comando, avisos):
        for a in avisos:
            log.warning(a)
        if comando == "L":
            log.info("Programa cargado; el procesador quedó reseteado ('K')")
        else:
            log.info("Reset del procesador ('K')")
        self.resaltar_cambios = False             # nuevo arranque: nada "cambio"
        self.pedir_volcar.emit()

    def _al_volcado(self, estado, comando):
        anterior = self.estado if self.resaltar_cambios else None
        self.estado = estado
        self.resaltar_cambios = True
        self.tabla_regs.mostrar(estado.regs, anterior.regs if anterior else None)
        self.tabla_mem.mostrar(estado.mem, anterior.mem if anterior else None)
        self.vista_latches.mostrar(estado)
        self.lbl_pc.setText(f"0x{estado.pc:08X}")
        self.lbl_ciclos.setText(str(estado.ciclos))
        self._set_chip(estado.texto_estado())
        self.lbl_if.setText(self._instr_en(estado.pc))
        if self.modo_conectado == MODO_SIMULADO and not estado.detenido:
            self.lbl_id.setText("(no simulado: ver la pestaña Latches)")
        elif estado.es_burbuja("IF/ID"):
            self.lbl_id.setText("burbuja")
        else:
            self.lbl_id.setText(f"0x{estado.campo('IF/ID', 'pc'):03X}: "
                                f"{desensamblar(estado.campo('IF/ID', 'instr'))}")
        self.tabla_listado.marcar_pc(estado.pc)
        nombres = {"D": "Volcado", "S": "Paso", "R": "Corrida"}
        msg = (f"{nombres.get(comando, comando)} ('{comando}'): {estado.texto_estado()}, "
               f"PC = 0x{estado.pc:08X}, ciclos = {estado.ciclos}")
        if estado.error:
            log.warning(msg + ". El procesador se detuvo por ERROR (instrucción ilegal, "
                        "fetch fuera de rango o acceso inválido a la memoria de datos).")
        else:
            log.info(msg)
        self.statusBar().showMessage(msg, 8000)

    def _instr_en(self, pc):
        if self.listado:
            for ln in self.listado:
                if ln.addr == pc:
                    return f"0x{pc:03X}: {desensamblar(ln.word)}"
        if pc >= 1024 or pc % 4:
            return f"0x{pc:X}: fuera de la memoria de programa"
        return f"0x{pc:03X}: (fuera del programa: HALT)"

    def _al_error(self, mensaje):
        log.error(mensaje)
        self.statusBar().showMessage("Error: " + mensaje, 10000)
        if self.conectado:
            self._set_chip(self.estado.texto_estado() if self.estado else "Listo")
        self._mostrar_error("Error de comunicación", mensaje)

    # ================================================== habilitacion
    def _set_chip(self, texto):
        self.chip.setText(texto)
        self.chip.setStyleSheet(estilo_chip(texto))
        color = {"Desconectado": "#9ca3af", "Corriendo": "#2563eb"}.get(texto, "#16a34a")
        estado = "desconectado" if texto == "Desconectado" else ("corriendo" if texto == "Corriendo"
                                                                 else "conectado")
        self.indicador.setText(f'<span style="color:{color}; font-size:16px">●</span> {estado}')

    def _actualizar_acciones(self):
        libre = self.conectado and not self.ocupado and not self.corriendo
        for a in (self.a_reset, self.a_paso, self.a_correr, self.a_volcar):
            a.setEnabled(libre)
        self.a_cargar.setEnabled(libre and bool(self.editor.toPlainText().strip()))
        self.a_interrumpir.setEnabled(self.corriendo)
        self.b_conectar.setText("Desconectar" if self.conectado else "Conectar")
        self.b_conectar.setEnabled(not self.ocupado and not self.corriendo)
        placa = self.combo_modo.currentText() == MODO_PLACA
        self.combo_modo.setEnabled(not self.conectado)
        self.combo_puerto.setEnabled(not self.conectado and placa)
        self.b_actualizar.setEnabled(not self.conectado and placa)

    # ================================================== dialogos
    def _mostrar_error(self, titulo, texto):
        """Cuadro de error que no bloquea (asi la app sigue respondiendo)."""
        self.ultimo_error = texto
        caja = QMessageBox(QMessageBox.Warning, titulo, texto, QMessageBox.Ok, self)
        caja.setAttribute(Qt.WA_DeleteOnClose)
        caja.open()

    def mostrar_atajos(self):
        QMessageBox.information(self, "Atajos y comandos", ATAJOS)

    def mostrar_acerca(self):
        QMessageBox.about(self, "Acerca de", (
            "<h3>TP RISC-V — Depurador</h3>"
            "<p>Procesador RISC-V RV32I con pipeline de 5 etapas y Debug Unit por UART "
            "(115200 8N1) en una Basys 3.</p>"
            "<p><b>Arquitectura de Computadoras</b><br>Ingeniería en Computación — FCEFyN, "
            "Universidad Nacional de Córdoba</p>"
            "<p><b>Integrantes:</b> Brigido, Tomás Andrés · Tosolini, Agustín<br>"
            "<b>Docente:</b> Pereyra, Martín</p>"))

    # ================================================== cierre
    def closeEvent(self, evento):
        """Si hay una corrida, se manda 'I' para no dejar la placa en RUN."""
        if self.corriendo:
            log.info("Cerrando durante una corrida: se manda 'I'")
            self.trabajador.interrumpir()
            espera = QTimer()
            espera.setSingleShot(True)
            espera.start(3000)
            while self.corriendo and espera.isActive():
                self.hilo.wait(20)
                from PySide6.QtWidgets import QApplication
                QApplication.processEvents()
        self.vigilante.stop()
        self._guardar_ajustes()
        self.pedir_desconectar.emit()
        self.hilo.quit()
        self.hilo.wait(3000)
        self.panel_log.desconectar_log()
        super().closeEvent(evento)
