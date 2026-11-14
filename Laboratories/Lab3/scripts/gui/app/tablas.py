"""
tablas.py - Tablas de registros, memoria de datos y listado del programa.

Lo que cambio desde el volcado anterior se pinta de amarillo (COLOR["cambio"]).
"""
from PySide6.QtCore import Qt
from PySide6.QtGui import QBrush, QColor
from PySide6.QtWidgets import QAbstractItemView, QHeaderView, QTableWidget, QTableWidgetItem

from app.tema import COLOR, fuente_mono
from decodificador import NOMBRES_ABI
from desensamblador import desensamblar

FORMATOS = ["Hexadecimal", "Decimal con signo", "Decimal sin signo"]


def formatear(v, formato):
    v &= 0xFFFFFFFF
    if formato == "Decimal con signo":
        return str(v - (1 << 32) if v & 0x80000000 else v)
    if formato == "Decimal sin signo":
        return str(v)
    return f"0x{v:08X}"


def _todos_formatos(v):
    return "\n".join(f"{f}: {formatear(v, f)}" for f in FORMATOS)


def _item(texto, mono=True, alinear=Qt.AlignLeft):
    it = QTableWidgetItem(texto)
    it.setFlags(Qt.ItemIsSelectable | Qt.ItemIsEnabled)
    if mono:
        it.setFont(fuente_mono(10))
    it.setTextAlignment(alinear | Qt.AlignVCenter)
    return it


class _TablaBase(QTableWidget):
    def __init__(self, filas, columnas, parent=None):
        super().__init__(filas, len(columnas), parent)
        self.setHorizontalHeaderLabels(columnas)
        self.verticalHeader().setVisible(False)
        self.setEditTriggers(QAbstractItemView.NoEditTriggers)
        self.setSelectionBehavior(QAbstractItemView.SelectRows)
        self.setAlternatingRowColors(False)
        self.verticalHeader().setDefaultSectionSize(22)
        self.horizontalHeader().setStretchLastSection(True)

    def _pintar_fila(self, fila, color):
        brocha = QBrush(QColor(color)) if color else QBrush()
        for c in range(self.columnCount()):
            it = self.item(fila, c)
            if it is not None:
                it.setBackground(brocha)


class TablaRegistros(_TablaBase):
    """x0..x31 con su nombre ABI y el valor en el formato elegido."""

    def __init__(self, parent=None):
        super().__init__(32, ["Registro", "ABI", "Valor"], parent)
        self.formato = FORMATOS[0]
        self.valores = [0] * 32
        self.cambiados = set()
        for i in range(32):
            self.setItem(i, 0, _item(f"x{i}"))
            self.setItem(i, 1, _item(NOMBRES_ABI[i], mono=False))
            self.setItem(i, 2, _item("—", alinear=Qt.AlignRight))
        self.horizontalHeader().setSectionResizeMode(0, QHeaderView.ResizeToContents)
        self.horizontalHeader().setSectionResizeMode(1, QHeaderView.ResizeToContents)

    def mostrar(self, regs, anteriores=None):
        """anteriores: los valores del volcado previo (para resaltar cambios)."""
        self.valores = list(regs)
        self.cambiados = {i for i in range(32)
                          if anteriores is not None and regs[i] != anteriores[i]}
        self._refrescar()

    def set_formato(self, formato):
        self.formato = formato
        self._refrescar()

    def _refrescar(self):
        for i, v in enumerate(self.valores):
            it = self.item(i, 2)
            it.setText(formatear(v, self.formato))
            it.setToolTip(_todos_formatos(v))
            self._pintar_fila(i, COLOR["cambio"] if i in self.cambiados else None)


class TablaMemoria(_TablaBase):
    """Las 32 palabras de la memoria de datos (128 bytes)."""

    def __init__(self, parent=None):
        super().__init__(32, ["Palabra", "Dirección", "Hexadecimal", "Decimal"], parent)
        self.cambiados = set()
        for i in range(32):
            self.setItem(i, 0, _item(f"mem[{i}]"))
            self.setItem(i, 1, _item(f"0x{4 * i:03X}"))
            self.setItem(i, 2, _item("—"))
            self.setItem(i, 3, _item("—", alinear=Qt.AlignRight))
        for c in range(3):
            self.horizontalHeader().setSectionResizeMode(c, QHeaderView.ResizeToContents)

    def mostrar(self, mem, anteriores=None):
        self.cambiados = {i for i in range(32)
                          if anteriores is not None and mem[i] != anteriores[i]}
        for i, v in enumerate(mem):
            self.item(i, 2).setText(formatear(v, "Hexadecimal"))
            self.item(i, 3).setText(formatear(v, "Decimal con signo"))
            self.item(i, 2).setToolTip(_todos_formatos(v))
            self._pintar_fila(i, COLOR["cambio"] if i in self.cambiados else None)


class TablaListado(_TablaBase):
    """Programa ensamblado: direccion, palabra, instruccion (desensamblada) y
    linea de origen. La fila del PC (la que busca IF) queda resaltada."""

    def __init__(self, parent=None):
        super().__init__(0, ["", "Dirección", "Palabra", "Instrucción", "Línea de origen"], parent)
        self.direcciones = []
        self.fila_pc = None
        self.etiquetas = {}               # fila -> texto de la 1.a columna (pipeline)
        self.horizontalHeader().setSectionResizeMode(0, QHeaderView.ResizeToContents)
        for c in (1, 2, 3):
            self.horizontalHeader().setSectionResizeMode(c, QHeaderView.ResizeToContents)

    def mostrar(self, listado):
        """listado: lista de ensamblador.Linea."""
        self.setRowCount(len(listado))
        self.direcciones = []
        for f, ln in enumerate(listado):
            self.direcciones.append(ln.addr)
            self.setItem(f, 0, _item(""))
            self.setItem(f, 1, _item(f"0x{ln.addr:03X}"))
            self.setItem(f, 2, _item(f"{ln.word:08X}"))
            self.setItem(f, 3, _item(desensamblar(ln.word)))
            origen = ln.fuente.split("#", 1)[0].strip()
            self.setItem(f, 4, _item(f"{ln.nro:3d}: {origen}" if ln.nro else origen, mono=True))
        self.fila_pc = None

    def marcar_pc(self, pc):
        if self.fila_pc is not None and self.fila_pc < self.rowCount():
            self.item(self.fila_pc, 0).setText("")
            self._pintar_fila(self.fila_pc, None)
        self.fila_pc = self.direcciones.index(pc) if pc in self.direcciones else None
        if self.fila_pc is not None:
            self.item(self.fila_pc, 0).setText("► PC")
            self._pintar_fila(self.fila_pc, COLOR["pc"])
            self.scrollToItem(self.item(self.fila_pc, 0), QAbstractItemView.EnsureVisible)

    def marcar_pipeline(self, pc, marcas):
        """Resalta las filas de las instrucciones que estan en el pipeline.
        marcas: pc -> [(etapa, se_descarta), ...] (pipeline_view.marcas_listado).
        La fila del PC conserva su "► PC"; cada fila lleva la etiqueta de su(s)
        etapa(s) y el tono de la mas intensa (IF > ID > EX > MEM > WB). Lo que
        se va a descartar va en naranja."""
        from app import tema
        tonos = tema.LISTADO[tema.modo()]
        self.etiquetas = {}
        for f in range(self.rowCount()):
            self.item(f, 0).setText("")
            self._pintar_fila(f, None)
        self.fila_pc = self.direcciones.index(pc) if pc in self.direcciones else None
        for f, addr in enumerate(self.direcciones):
            etapas = marcas.get(addr, [])
            partes = [n for n, _ in etapas]
            if f == self.fila_pc:
                partes = ["► PC"] + [n for n in partes]
            if not partes:
                continue
            texto = " ".join(partes)
            self.item(f, 0).setText(texto)
            self.etiquetas[f] = texto
            if etapas:
                n, descarta = etapas[0]
                color = tonos["descarta"] if descarta else tonos[n]
            else:
                color = tonos["IF"]                   # ► PC sin IF ocupada (parada)
            self._pintar_fila(f, color)
            self.item(f, 0).setToolTip(
                "En el pipeline: " + ", ".join(f"{n}{' (se descarta)' if d else ''}"
                                               for n, d in etapas) if etapas else
                "PC actual (no entra al pipeline: parada en curso)")
        if self.fila_pc is not None:
            self.scrollToItem(self.item(self.fila_pc, 0), QAbstractItemView.EnsureVisible)


def leyenda_listado():
    """Texto HTML de la leyenda que va debajo del listado."""
    from app import tema
    t = tema.LISTADO[tema.modo()]
    cuadro = lambda c: (f"<span style='background:{c}; border:1px solid #9CA3AF'>"
                        "&nbsp;&nbsp;&nbsp;&nbsp;</span>")
    partes = [f"{cuadro(t[n])}&nbsp;{n}" for n in ("IF", "ID", "EX", "MEM", "WB")]
    partes.append(f"{cuadro(t['descarta'])}&nbsp;se descarta (flush)")
    return ("En el pipeline:&nbsp; " + " &nbsp; ".join(partes) +
            "<br><span style='color:#6b7280'>Clic en una fila: seguir esa instrucción en la "
            "vista del pipeline.</span>")
