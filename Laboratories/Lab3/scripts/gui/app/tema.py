"""
tema.py - Colores y estilo de la aplicacion (un solo lugar para cambiarlos).

Se usa el estilo "Fusion" de Qt (se ve igual en cualquier escritorio) con una
paleta clara. Los colores con nombre (COLOR[...]) los usan las tablas, el log y
los "chips" de estado.
"""
from PySide6.QtGui import QColor, QFont, QPalette

COLOR = {
    "fondo": "#f5f6f8",
    "panel": "#ffffff",
    "texto": "#1f2430",
    "suave": "#6b7280",
    "acento": "#2563eb",
    "cambio": "#fff3bf",          # celda que cambio desde el volcado anterior
    "pc": "#dbeafe",              # fila del listado con el PC
    "error_linea": "#fde2e2",     # linea del editor con error
    "burbuja": "#9ca3af",
    "on": "#15803d",
    "off": "#9ca3af",
    "info": "#1f2430",
    "aviso": "#b45309",
    "error": "#b91c1c",
    "bytes": "#6b7280",
}

# Chips de estado: texto -> (fondo, texto)
CHIPS = {
    "Desconectado": ("#e5e7eb", "#374151"),
    "Listo": ("#dcfce7", "#166534"),
    "Corriendo": ("#dbeafe", "#1e40af"),
    "Trabajando…": ("#e0e7ff", "#3730a3"),
    "Terminó (HALT)": ("#d1fae5", "#065f46"),
    "Interrumpido": ("#fef3c7", "#92400e"),
    "Error": ("#fee2e2", "#991b1b"),
}

ESTILO = """
QMainWindow, QWidget { background: %(fondo)s; color: %(texto)s; }
QTableWidget, QTreeWidget, QPlainTextEdit, QTextEdit {
    background: %(panel)s; border: 1px solid #d9dce3; border-radius: 6px;
    selection-background-color: #bfdbfe; selection-color: %(texto)s;
}
QHeaderView::section { background: #eef0f4; border: none; padding: 4px; font-weight: 600; }
QTabWidget::pane { border: 1px solid #d9dce3; border-radius: 6px; top: -1px; }
QTabBar::tab { padding: 6px 14px; border: 1px solid transparent; }
QTabBar::tab:selected { background: %(panel)s; border: 1px solid #d9dce3;
    border-bottom-color: %(panel)s; border-top-left-radius: 6px; border-top-right-radius: 6px; }
QToolBar { border: none; spacing: 6px; padding: 4px; }
QToolButton { padding: 4px 8px; border-radius: 6px; }
QToolButton:hover { background: #e5e9f2; }
QToolButton:disabled { color: #a0a4ad; }
QPushButton { padding: 5px 12px; border-radius: 6px; border: 1px solid #c9ced8; background: #ffffff; }
QPushButton:hover { background: #eef2ff; }
QPushButton:disabled { color: #a0a4ad; }
QComboBox { padding: 3px 8px; border-radius: 6px; border: 1px solid #c9ced8; background: #ffffff; }
QLabel#titulo { color: %(suave)s; font-size: 11px; font-weight: 600; letter-spacing: 1px; }
QLabel#numero { font-family: monospace; font-size: 22px; font-weight: 700; }
QLabel#aviso { color: %(aviso)s; }
QLabel#error_asm { color: %(error)s; }
""" % COLOR


def aplicar(app):
    app.setStyle("Fusion")
    pal = QPalette()
    pal.setColor(QPalette.Window, QColor(COLOR["fondo"]))
    pal.setColor(QPalette.Base, QColor(COLOR["panel"]))
    pal.setColor(QPalette.Text, QColor(COLOR["texto"]))
    pal.setColor(QPalette.WindowText, QColor(COLOR["texto"]))
    pal.setColor(QPalette.Highlight, QColor("#bfdbfe"))
    pal.setColor(QPalette.HighlightedText, QColor(COLOR["texto"]))
    app.setPalette(pal)
    app.setStyleSheet(ESTILO)


def fuente_mono(tamano=10):
    f = QFont("monospace")
    f.setStyleHint(QFont.Monospace)
    f.setPointSize(tamano)
    return f


def estilo_chip(texto):
    fondo, color = CHIPS.get(texto, CHIPS["Listo"])
    return (f"QLabel {{ background: {fondo}; color: {color}; border-radius: 10px; "
            f"padding: 3px 12px; font-weight: 700; }}")
