"""
panel_log.py - Registro de eventos: hora, nivel (info / aviso / error) y
mensaje, con colores, filtro por nivel, "Limpiar", "Guardar…" y la opcion de
ver los bytes enviados y recibidos en hexadecimal.

Todo mensaje pasa por el logger de Python "depurador", que ademas lo copia a
un archivo (ver configurar_archivo). El panel recibe los mensajes con un
handler que emite una señal de Qt: asi se pueden loguear desde cualquier hilo.
"""
import html
import logging
import os
import time

from PySide6.QtCore import QObject, Signal
from PySide6.QtWidgets import (QCheckBox, QComboBox, QFileDialog, QHBoxLayout, QPushButton,
                               QTextEdit, QVBoxLayout, QWidget)

from app.tema import COLOR, fuente_mono

log = logging.getLogger("depurador")
NIVEL_BYTES = 15                       # entre DEBUG e INFO: bytes en hex
logging.addLevelName(NIVEL_BYTES, "BYTES")
NOMBRE = {NIVEL_BYTES: "bytes", logging.INFO: "info", logging.WARNING: "aviso",
          logging.ERROR: "error", logging.CRITICAL: "error"}
FILTROS = ["Todos", "Avisos y errores", "Solo errores"]


def carpeta_logs():
    """~/.local/state/tp_riscv (o TP_RISCV_LOG_DIR, que usan los tests)."""
    base = os.environ.get("TP_RISCV_LOG_DIR") or os.path.join(
        os.environ.get("XDG_STATE_HOME") or os.path.expanduser("~/.local/state"), "tp_riscv")
    os.makedirs(base, exist_ok=True)
    return base


def configurar_archivo():
    """Copia de todo el log en depurador.log (se agrega al final)."""
    ruta = os.path.join(carpeta_logs(), "depurador.log")
    if not any(isinstance(h, logging.FileHandler) for h in log.handlers):
        h = logging.FileHandler(ruta, encoding="utf-8")
        h.setFormatter(logging.Formatter("%(asctime)s %(levelname)-7s %(message)s"))
        log.addHandler(h)
    log.setLevel(NIVEL_BYTES)
    return ruta


class _Puente(QObject):
    mensaje = Signal(float, int, str)


class _Handler(logging.Handler):
    def __init__(self, puente):
        super().__init__(NIVEL_BYTES)
        self.puente = puente

    def emit(self, registro):
        try:
            texto = registro.getMessage()
            if registro.exc_info:
                texto += "\n" + logging.Formatter().formatException(registro.exc_info)
            self.puente.mensaje.emit(registro.created, registro.levelno, texto)
        except RuntimeError:           # el panel ya se destruyo (al cerrar)
            pass


class PanelLog(QWidget):

    def __init__(self, parent=None):
        super().__init__(parent)
        self.entradas = []                         # (hora, nivel, texto)
        lay = QVBoxLayout(self)
        lay.setContentsMargins(0, 0, 0, 0)
        barra = QHBoxLayout()
        self.filtro = QComboBox()
        self.filtro.addItems(FILTROS)
        self.ver_bytes = QCheckBox("Ver bytes (hex)")
        limpiar = QPushButton("Limpiar")
        guardar = QPushButton("Guardar…")
        barra.addWidget(self.filtro)
        barra.addWidget(self.ver_bytes)
        barra.addStretch(1)
        barra.addWidget(limpiar)
        barra.addWidget(guardar)
        lay.addLayout(barra)
        self.texto = QTextEdit(readOnly=True)
        self.texto.setFont(fuente_mono(10))
        lay.addWidget(self.texto)
        self.filtro.currentIndexChanged.connect(self._redibujar)
        self.ver_bytes.toggled.connect(self._redibujar)
        limpiar.clicked.connect(self.limpiar)
        guardar.clicked.connect(self.guardar)
        self._puente = _Puente()
        self._puente.mensaje.connect(self._agregar)
        self._handler = _Handler(self._puente)
        log.addHandler(self._handler)

    def desconectar_log(self):
        log.removeHandler(self._handler)

    def _visible(self, nivel):
        if nivel == NIVEL_BYTES:
            return self.ver_bytes.isChecked()
        minimo = [logging.INFO, logging.WARNING, logging.ERROR][self.filtro.currentIndex()]
        return nivel >= minimo

    def _html(self, hora, nivel, texto):
        color = {NIVEL_BYTES: COLOR["bytes"], logging.WARNING: COLOR["aviso"]}.get(
            nivel, COLOR["error"] if nivel >= logging.ERROR else COLOR["info"])
        h = time.strftime("%H:%M:%S", time.localtime(hora))
        t = html.escape(texto).replace("\n", "<br>&nbsp;&nbsp;&nbsp;&nbsp;")
        return (f'<span style="color:{COLOR["suave"]}">{h}</span> '
                f'<b style="color:{color}">{NOMBRE.get(nivel, "info"):5s}</b> '
                f'<span style="color:{color}">{t}</span>')

    def _agregar(self, hora, nivel, texto):
        self.entradas.append((hora, nivel, texto))
        if self._visible(nivel):
            self.texto.append(self._html(hora, nivel, texto))

    def _redibujar(self, *_):
        self.texto.clear()
        self.texto.append("<br>".join(self._html(*e) for e in self.entradas if self._visible(e[1])))

    def limpiar(self):
        self.entradas.clear()
        self.texto.clear()

    def texto_plano(self):
        return "\n".join(f"{time.strftime('%H:%M:%S', time.localtime(h))} "
                         f"{NOMBRE.get(n, 'info'):5s} {t}"
                         for h, n, t in self.entradas if self._visible(n))

    def guardar(self):
        ruta, _ = QFileDialog.getSaveFileName(self, "Guardar log", "depurador_log.txt",
                                              "Texto (*.txt)")
        if ruta:
            with open(ruta, "w", encoding="utf-8") as f:
                f.write(self.texto_plano() + "\n")
            log.info(f"Log guardado en {ruta}")
