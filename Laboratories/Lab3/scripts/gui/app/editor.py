"""
editor.py - Editor de ensamblador: numeros de linea, resaltado de sintaxis y
la linea con error marcada en rojo.

Basado en el ejemplo "Code Editor" de la documentacion de Qt: un
QPlainTextEdit con un widget angosto a la izquierda donde se pintan los
numeros de linea.
"""
import re

from PySide6.QtCore import QRect, QSize, Qt
from PySide6.QtGui import QColor, QPainter, QSyntaxHighlighter, QTextCharFormat, QTextFormat
from PySide6.QtWidgets import QPlainTextEdit, QTextEdit, QWidget

import rutas  # noqa: F401
from ensamblador import REGS, TIPO_R, TIPO_I, SHIFT_I, LOADS, STORES, BRANCH
from app.tema import COLOR, fuente_mono

MNEMONICOS = (set(TIPO_R) | set(TIPO_I) | set(SHIFT_I) | set(LOADS) | set(STORES) |
              set(BRANCH) | {"jal", "jalr", "lui", "halt"})
PSEUDO = {"nop", "j", "mv", "li", "beqz", "bnez", "call", "ret"}


def _formato(color, negrita=False, italica=False):
    f = QTextCharFormat()
    f.setForeground(QColor(color))
    if negrita:
        f.setFontWeight(700)
    f.setFontItalic(italica)
    return f


class Resaltador(QSyntaxHighlighter):
    """Colores: instrucciones (azul), pseudo-instrucciones (violeta), registros
    (verde), numeros (naranja), etiquetas (negrita) y comentarios (gris)."""

    def __init__(self, documento):
        super().__init__(documento)
        palabras = "|".join(sorted(MNEMONICOS, key=len, reverse=True))
        pseudo = "|".join(sorted(PSEUDO, key=len, reverse=True))
        regs = "|".join(sorted(REGS, key=len, reverse=True))
        self.reglas = [
            (re.compile(rf"\b({palabras})\b", re.I), _formato("#1d4ed8", negrita=True)),
            (re.compile(rf"\b({pseudo})\b", re.I), _formato("#7c3aed", negrita=True)),
            (re.compile(r"\.\w+"), _formato("#7c3aed")),
            (re.compile(rf"\b({regs})\b"), _formato("#047857")),
            (re.compile(r"(?<![\w])[-+]?(0x[0-9a-fA-F]+|\d+)\b"), _formato("#c2410c")),
            (re.compile(r"^\s*[A-Za-z_.][\w.]*\s*:"), _formato("#111827", negrita=True)),
        ]
        self.comentario = _formato(COLOR["suave"], italica=True)

    def highlightBlock(self, texto):
        codigo = texto.split("#", 1)[0]
        for patron, formato in self.reglas:
            for m in patron.finditer(codigo):
                self.setFormat(m.start(), m.end() - m.start(), formato)
        if "#" in texto:
            i = texto.index("#")
            self.setFormat(i, len(texto) - i, self.comentario)


class _AreaNumeros(QWidget):
    def __init__(self, editor):
        super().__init__(editor)
        self.editor = editor

    def sizeHint(self):
        return QSize(self.editor.ancho_numeros(), 0)

    def paintEvent(self, evento):
        self.editor.pintar_numeros(evento)


class EditorCodigo(QPlainTextEdit):

    def __init__(self, parent=None):
        super().__init__(parent)
        self.setFont(fuente_mono(11))
        self.setLineWrapMode(QPlainTextEdit.NoWrap)
        self.setTabStopDistance(4 * self.fontMetrics().horizontalAdvance(" "))
        self.area = _AreaNumeros(self)
        self.resaltador = Resaltador(self.document())
        self.linea_error = None
        self.blockCountChanged.connect(self._actualizar_ancho)
        self.updateRequest.connect(self._actualizar_area)
        self._actualizar_ancho()

    # -------------------------------------------------- numeros de linea
    def ancho_numeros(self):
        digitos = len(str(max(1, self.blockCount())))
        return 14 + self.fontMetrics().horizontalAdvance("9") * max(3, digitos)

    def _actualizar_ancho(self, *_):
        self.setViewportMargins(self.ancho_numeros(), 0, 0, 0)

    def _actualizar_area(self, rect, dy):
        if dy:
            self.area.scroll(0, dy)
        else:
            self.area.update(0, rect.y(), self.area.width(), rect.height())

    def resizeEvent(self, evento):
        super().resizeEvent(evento)
        cr = self.contentsRect()
        self.area.setGeometry(QRect(cr.left(), cr.top(), self.ancho_numeros(), cr.height()))

    def pintar_numeros(self, evento):
        p = QPainter(self.area)
        p.fillRect(evento.rect(), QColor("#eef0f4"))
        bloque = self.firstVisibleBlock()
        n = bloque.blockNumber()
        arriba = round(self.blockBoundingGeometry(bloque).translated(self.contentOffset()).top())
        abajo = arriba + round(self.blockBoundingRect(bloque).height())
        while bloque.isValid() and arriba <= evento.rect().bottom():
            if bloque.isVisible() and abajo >= evento.rect().top():
                es_error = self.linea_error == n + 1
                p.setPen(QColor(COLOR["error"] if es_error else COLOR["suave"]))
                p.drawText(0, arriba, self.area.width() - 6, self.fontMetrics().height(),
                           Qt.AlignRight, ("◆ " if es_error else "") + str(n + 1))
            bloque = bloque.next()
            arriba = abajo
            abajo = arriba + round(self.blockBoundingRect(bloque).height())
            n += 1

    # -------------------------------------------------- errores
    def marcar_error(self, linea):
        """Pinta de rojo la linea (1 = primera) y lleva el cursor ahi.
        linea = None borra la marca."""
        self.linea_error = linea
        extras = []
        if linea is not None:
            bloque = self.document().findBlockByNumber(linea - 1)
            if bloque.isValid():
                sel = QTextEdit.ExtraSelection()
                sel.format.setBackground(QColor(COLOR["error_linea"]))
                sel.format.setProperty(QTextFormat.FullWidthSelection, True)
                cursor = self.textCursor()
                cursor.setPosition(bloque.position())
                sel.cursor = cursor
                extras.append(sel)
                self.setTextCursor(cursor)
                self.centerCursor()
        self.setExtraSelections(extras)
        self.area.update()
