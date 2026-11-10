"""
vista_latches.py - Los 4 latches del pipeline como un arbol: cada latch es una
rama y cada campo una hoja con su nombre, su valor y un tooltip que lo explica
(tabla de src/params.vh, seccion 4b).

  * Controles de 1 bit: "ON" (verde) / "off" (gris).
  * Campos de 32 bits: hexadecimal; las instrucciones, ademas, desensambladas.
  * Un latch con valid = 0 se muestra como "burbuja" (gris).
"""
from PySide6.QtCore import Qt
from PySide6.QtGui import QBrush, QColor
from PySide6.QtWidgets import QLabel, QTreeWidget, QTreeWidgetItem, QVBoxLayout, QWidget

import campos_latches as cl
from app.tema import COLOR, fuente_mono
from desensamblador import desensamblar


def texto_campo(campo):
    if campo.es_control:
        return "ON" if campo.valor else "off"
    if campo.ancho == 32:
        t = f"0x{campo.valor:08X}"
        if campo.nombre == "instr":
            t += f"   {desensamblar(campo.valor)}"
        return t
    return str(campo.valor)


class VistaLatches(QWidget):

    def __init__(self, parent=None):
        super().__init__(parent)
        lay = QVBoxLayout(self)
        lay.setContentsMargins(0, 0, 0, 0)
        self.aviso = QLabel()
        self.aviso.setObjectName("aviso")
        self.aviso.setWordWrap(True)
        self.aviso.hide()
        lay.addWidget(self.aviso)
        self.arbol = QTreeWidget()
        self.arbol.setColumnCount(2)
        self.arbol.setHeaderLabels(["Campo", "Valor"])
        self.arbol.setColumnWidth(0, 170)
        lay.addWidget(self.arbol)
        self.ramas = {}
        for latch in cl.LATCHES:
            rama = QTreeWidgetItem([latch, ""])
            rama.setToolTip(0, cl.DESCRIPCION_LATCH[latch])
            f = rama.font(0)
            f.setBold(True)
            rama.setFont(0, f)
            self.arbol.addTopLevelItem(rama)
            self.ramas[latch] = rama
            for c in cl.CAMPOS:
                if c[0] == latch:
                    hoja = QTreeWidgetItem([c[1], "—"])
                    hoja.setToolTip(0, c[4])
                    hoja.setToolTip(1, c[4])
                    hoja.setFont(1, fuente_mono(10))
                    rama.addChild(hoja)
            rama.setExpanded(True)

    def set_aviso(self, texto):
        """Ej.: en modo simulado los latches no se simulan."""
        self.aviso.setText(texto)
        self.aviso.setVisible(bool(texto))

    def mostrar(self, estado):
        for latch, campos in estado.latches.items():
            rama = self.ramas[latch]
            burbuja = estado.es_burbuja(latch)
            rama.setText(1, "burbuja (valid = 0)" if burbuja else "instrucción válida")
            rama.setForeground(1, QBrush(QColor(COLOR["burbuja"] if burbuja else COLOR["on"])))
            for i, campo in enumerate(campos):
                hoja = rama.child(i)
                hoja.setText(1, texto_campo(campo))
                if campo.es_control:
                    color = COLOR["on"] if campo.valor else COLOR["off"]
                elif burbuja:
                    color = COLOR["burbuja"]
                else:
                    color = COLOR["texto"]
                hoja.setForeground(1, QBrush(QColor(color)))
                hoja.setForeground(0, QBrush(QColor(COLOR["burbuja"] if burbuja else COLOR["texto"])))
                hoja.setData(1, Qt.UserRole, campo.valor)
