"""
vista_pipeline.py - La franja grafica del pipeline:

    [ IF ] [IF/ID] [ ID ] [ID/EX] [ EX ] [EX/MEM] [ MEM ] [MEM/WB] [ WB ]

Solo DIBUJA lo que calculo pipeline_view.deducir() (una Vista) y el volcado:
  * cada etapa: PC, instruccion, chip de tipo y una nota (que hace ahi);
  * cada latch: los campos importantes (clic -> su detalle en el arbol);
  * carteles "STALL en el proximo paso" y "FLUSH en el proximo paso";
  * flechas de forwarding EX/MEM -> EX y MEM/WB -> EX;
  * una instruccion "seguida" (clic en el listado) con un borde grueso.
El color nunca es la unica senal: cada estado tiene icono y texto (y trama,
tachado o "?"). Se puede plegar con el boton "Pipeline".
"""
from PySide6.QtCore import QPointF, QRectF, QSize, Qt, Signal
from PySide6.QtGui import QBrush, QColor, QFont, QPainter, QPen, QPolygonF
from PySide6.QtWidgets import QToolButton, QToolTip, QVBoxLayout, QWidget

from app import tema
from pipeline_view import BURBUJA, DESCARTA, DESCONOCIDA, ETAPAS, PASA

ORDEN = ["IF", "IF/ID", "ID", "ID/EX", "EX", "EX/MEM", "MEM", "MEM/WB", "WB"]
TEXTO_ESTADO = {"util": "", "pasa": "", "burbuja": "burbuja", "descarta": "se descarta",
                "no_entra": "no entra", "halt": "HALT", "error": "error",
                "desconocida": "desconocida"}
ALTO_ETAPA = 150


def _wb_dato(e):
    return e.campo("MEM/WB", "mem_data") if e.campo("MEM/WB", "result_src") else \
        e.campo("MEM/WB", "result")


def resumen_latch(e, nombre):
    """Lineas de texto con los campos importantes de un latch (o 'burbuja')."""
    c = lambda n: e.campo(nombre, n)
    if c("valid") == 0:
        return ["burbuja", "valid = 0"]
    if nombre == "IF/ID":
        return [f"pc 0x{c('pc'):03X}"]
    if nombre == "ID/EX":
        lin = [f"rd x{c('rd')}"] if c("reg_write") else []
        if c("uses_rs1"):
            lin.append(f"x{c('rs1')} = 0x{c('rs1_data'):X}")
        if c("uses_rs2"):
            lin.append(f"x{c('rs2')} = 0x{c('rs2_data'):X}")
        if c("alu_src_b") or c("jump") or c("branch"):
            imm = c("imm")
            lin.append(f"imm {imm - (1 << 32) if imm & 0x80000000 else imm}")
        chips = [n for k, n in (("reg_write", "RegWrite"), ("mem_read", "MemRead"),
                                ("mem_write", "MemWrite"), ("branch", "Branch"),
                                ("jump", "Jump")) if c(k)]
        return lin + chips
    if nombre == "EX/MEM":
        lin = [f"result 0x{c('result'):X}"]
        if c("reg_write"):
            lin.append(f"rd x{c('rd')}")
        if c("mem_write"):
            lin.append(f"dato 0x{c('store_data'):X}")
        return lin
    lin = [f"valor 0x{_wb_dato(e):X}"]
    lin.append(f"rd x{c('rd')}" if c("reg_write") else "no escribe")
    return lin


class LienzoPipeline(QWidget):
    latch_elegido = Signal(str)

    def __init__(self, parent=None):
        super().__init__(parent)
        self.vista = None
        self.estado = None
        self.seguido = None
        self.rects = {}
        self.setMouseTracking(True)
        self.setMinimumHeight(250)

    def sizeHint(self):
        return QSize(1300, 250)

    def mostrar(self, vista, estado):
        self.vista, self.estado = vista, estado
        self.update()

    def set_seguido(self, pc):
        self.seguido = pc
        self.update()

    # -------------------------------------------------- geometria
    def _geometria(self):
        ancho = max(self.width() - 16, 900)
        u = ancho / (5 * 1.5 + 4 * 1.0 + 8 * 0.06)       # etapa = 1.5u, latch = 1u
        x, y = 8.0, 42.0
        rects = {}
        for n in ORDEN:
            w = u * (1.0 if "/" in n else 1.5)
            rects[n] = QRectF(x, y, w, ALTO_ETAPA)
            x += w + u * 0.06
        return rects

    # -------------------------------------------------- dibujo
    def paintEvent(self, _):
        p = QPainter(self)
        p.setRenderHint(QPainter.Antialiasing)
        pal = tema.PIPELINE[tema.modo()]
        p.fillRect(self.rect(), QColor(pal["fondo"]))
        self.rects = self._geometria()
        if self.vista is None:
            p.setPen(QColor(tema.COLOR["suave"]))
            p.drawText(self.rect(), Qt.AlignCenter,
                       "Conectá y cargá un programa: acá se ve qué instrucción hay en cada etapa.")
            return
        v, e = self.vista, self.estado
        for n in ORDEN:
            if "/" in n:
                self._latch(p, pal, self.rects[n], n, e)
            else:
                self._etapa(p, pal, self.rects[n], v.etapas[n])
        r_if, r_id = self.rects["IF"], self.rects["ID"]
        banda = QRectF(r_if.left(), 6, r_id.right() - r_if.left(), 30)
        if v.flush:
            self._cartel(p, banda, "⟲  FLUSH en el próximo paso (salto tomado en EX)", pal["flush"])
        elif v.stall:
            self._cartel(p, banda, "⏸  STALL en el próximo paso (load-use)", pal["stall"])
        elif v.error_mem:
            self._cartel(p, banda, "⚠  Error en MEM: se descarta lo que viene detrás",
                         tema.PIPELINE["claro"]["error"][1])
        if v.detenido:
            r = QRectF(self.rects["EX"].left(), 6,
                       self.rects["WB"].right() - self.rects["EX"].left(), 30)
            self._cartel(p, r, "■  Procesador detenido" + (" por ERROR" if e.error else " (HALT)"),
                         pal["error"][1] if e.error else pal["halt"][1])
        for i, f in enumerate(v.forwarding):
            self._flecha(p, pal, f, i)

    def _cartel(self, p, r, texto, color):
        c = QColor(color)
        p.setPen(QPen(c, 2))
        p.setBrush(c.lighter(185) if tema.modo() == "claro" else c.darker(260))
        p.drawRoundedRect(r, 6, 6)
        p.setPen(c.darker(140) if tema.modo() == "claro" else c.lighter(140))
        p.setFont(QFont("Sans", 10, QFont.Bold))
        p.drawText(r, Qt.AlignCenter, texto)

    def _etapa(self, p, pal, r, et):
        fondo, borde, texto, icono = pal[et.estado]
        punteado = et.estado in (PASA, DESCONOCIDA)
        p.setPen(QPen(QColor(borde), 2, Qt.DashLine if punteado else Qt.SolidLine))
        p.setBrush(QColor(fondo))
        p.drawRoundedRect(r, 8, 8)
        if et.estado == BURBUJA:
            p.setBrush(QBrush(QColor(pal["trama"]), Qt.BDiagPattern))
            p.drawRoundedRect(r, 8, 8)
        if self.seguido is not None and et.pc == self.seguido and et.ocupada:
            p.setPen(QPen(QColor(pal["seguido"]), 4))
            p.setBrush(Qt.NoBrush)
            p.drawRoundedRect(r.adjusted(-3, -3, 3, 3), 10, 10)
        col = QColor(texto)
        p.setPen(col)
        p.setFont(QFont("Sans", 12, QFont.Bold))
        p.drawText(QRectF(r.x() + 8, r.y() + 6, 60, 20), et.nombre)
        if et.estado == DESCONOCIDA and et.pc is None:
            p.setFont(QFont("Sans", 30, QFont.Bold))
            p.drawText(QRectF(r.x(), r.y() + 26, r.width(), 50), Qt.AlignCenter, "?")
            p.setFont(QFont("Sans", 9))
            p.drawText(QRectF(r.x() + 8, r.y() + 80, r.width() - 14, 62), Qt.TextWordWrap,
                       "desconocida (pasá el mouse: motivo)")
            return
        if et.pc is not None:
            p.setFont(QFont("Monospace", 9))
            p.drawText(QRectF(r.x() + 50, r.y() + 8, r.width() - 56, 20), Qt.AlignRight,
                       f"0x{et.pc:03X}")
        if et.tipo:
            chip = QRectF(r.right() - 64, r.y() + 30, 56, 18)
            p.setPen(QPen(QColor(borde), 1))
            p.setBrush(QColor(pal["fondo"]))
            p.drawRoundedRect(chip, 8, 8)
            p.setPen(col)
            p.setFont(QFont("Sans", 8, QFont.Bold))
            p.drawText(chip, Qt.AlignCenter, et.tipo)
        if et.texto:
            f = QFont("Monospace", 10, QFont.Bold)
            f.setStrikeOut(et.estado == DESCARTA)
            p.setFont(f)
            p.setPen(col)
            p.drawText(QRectF(r.x() + 8, r.y() + 54, r.width() - 14, 22),
                       Qt.AlignLeft | Qt.TextSingleLine, et.texto)
        etiqueta = TEXTO_ESTADO.get(et.estado, "")
        nota = et.nota or etiqueta
        if etiqueta and etiqueta not in nota:
            nota = f"{etiqueta}: {nota}"
        p.setFont(QFont("Sans", 9))
        p.setPen(col)
        p.drawText(QRectF(r.x() + 8, r.y() + 86, r.width() - 14, 60), Qt.TextWordWrap,
                   f"{icono} {nota}")

    def _latch(self, p, pal, r, nombre, e):
        vacio = e.campo(nombre, "valid") == 0
        fondo, borde, texto, _ = pal["latch_vacio" if vacio else "latch"]
        p.setPen(QPen(QColor(borde), 2))
        p.setBrush(QColor(fondo))
        p.drawRoundedRect(r, 6, 6)
        p.setPen(QColor(texto))
        p.setFont(QFont("Sans", 10, QFont.Bold))
        p.drawText(QRectF(r.x(), r.y() + 6, r.width(), 18), Qt.AlignCenter, nombre)
        p.setFont(QFont("Monospace", 8))
        for i, linea in enumerate(resumen_latch(e, nombre)[:7]):
            p.drawText(QRectF(r.x() + 3, r.y() + 28 + 16 * i, r.width() - 6, 16),
                       Qt.AlignCenter, linea)
        p.setFont(QFont("Sans", 7))
        p.drawText(QRectF(r.x(), r.bottom() - 16, r.width(), 14), Qt.AlignCenter, "clic: detalle")

    def _flecha(self, p, pal, f, i):
        color = QColor(pal["forwarding"])
        origen = self.rects[f.origen]
        dest = self.rects["EX"]
        base = dest.bottom()
        y = base + 18 + 22 * i
        xo = origen.center().x() + (8 if i % 2 else -8)
        xd = dest.center().x() + (-14 if f.operando == "rs1" else 14)
        p.setPen(QPen(color, 3))
        p.setBrush(Qt.NoBrush)
        p.drawPolyline([QPointF(xo, base), QPointF(xo, y), QPointF(xd, y), QPointF(xd, base + 4)])
        p.setBrush(color)
        p.drawPolygon(QPolygonF([QPointF(xd, base + 1), QPointF(xd - 6, base + 13),
                                 QPointF(xd + 6, base + 13)]))
        p.setFont(QFont("Sans", 9, QFont.Bold))
        p.drawText(QPointF(min(xd, xo) + 30, y - 4),
                   f"forwarding {f.origen} → EX ({f.operando} = x{f.registro}: 0x{f.valor:X})")

    # -------------------------------------------------- mouse
    def _en(self, pos):
        for n, r in self.rects.items():
            if r.contains(pos):
                return n
        return None

    def mouseMoveEvent(self, ev):
        n = self._en(ev.position())
        if self.vista is None or n is None:
            QToolTip.hideText()
            return
        if "/" in n:
            texto = f"{n}: clic para ver todos sus campos en la pestaña Latches"
        else:
            et = self.vista.etapas[n]
            texto = f"{n}: {et.nota or et.estado}"
            if et.motivo:
                texto = f"{n}: no se sabe qué instrucción hay.\nMotivo: {et.motivo}"
            elif et.origen:
                texto += f"\nBurbuja por {et.origen}."
        QToolTip.showText(ev.globalPosition().toPoint(), texto, self)

    def mousePressEvent(self, ev):
        n = self._en(ev.position())
        if n and "/" in n:
            self.latch_elegido.emit(n)


class VistaPipeline(QWidget):
    """Lienzo + boton para plegar."""

    def __init__(self, parent=None):
        super().__init__(parent)
        lay = QVBoxLayout(self)
        lay.setContentsMargins(4, 0, 4, 0)
        lay.setSpacing(0)
        self.boton = QToolButton()
        self.boton.setText("Pipeline")
        self.boton.setCheckable(True)
        self.boton.setChecked(True)
        self.boton.setArrowType(Qt.DownArrow)
        self.boton.setToolButtonStyle(Qt.ToolButtonTextBesideIcon)
        self.boton.setToolTip("Mostrar u ocultar la vista del pipeline")
        self.boton.toggled.connect(self.plegar)
        lay.addWidget(self.boton)
        self.lienzo = LienzoPipeline()
        lay.addWidget(self.lienzo)

    def plegar(self, visible):
        self.lienzo.setVisible(visible)
        self.boton.setArrowType(Qt.DownArrow if visible else Qt.RightArrow)

    def mostrar(self, vista, estado):
        self.lienzo.mostrar(vista, estado)


__all__ = ["VistaPipeline", "resumen_latch", "ETAPAS"]
