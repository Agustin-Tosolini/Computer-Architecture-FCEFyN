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


# ============================================================== vista del pipeline
# Cada estado: (fondo, borde, texto, icono). El color nunca es la unica senal:
# cada estado tiene ademas un icono y un texto (y las burbujas una trama, lo
# descartado un tachado y lo desconocido un "?" grande).
PIPELINE = {
    "claro": {
        "util": ("#DCFCE7", "#15803D", "#14532D", "●"),
        "pasa": ("#F0FDF4", "#86EFAC", "#3F6F52", "○"),
        "burbuja": ("#F3F4F6", "#9CA3AF", "#4B5563", "∅"),
        "descarta": ("#FFEDD5", "#C2410C", "#7C2D12", "✕"),
        "no_entra": ("#F3F4F6", "#9CA3AF", "#4B5563", "⏸"),
        "halt": ("#EDE9FE", "#6D28D9", "#4C1D95", "■"),
        "error": ("#FEE2E2", "#B91C1C", "#7F1D1D", "⚠"),
        "desconocida": ("#FFFFFF", "#6B7280", "#374151", "?"),
        "latch": ("#FBF1DC", "#A9792A", "#6E4C10", ""),
        "latch_vacio": ("#F3F2EF", "#A9792A", "#6B6862", ""),
        "fondo": "#F5F6F8", "trama": "#D1D5DB", "forwarding": "#2563EB",
        "stall": "#B45309", "flush": "#C2410C", "seguido": "#111827",
    },
    "oscuro": {
        "util": ("#14532D", "#4ADE80", "#DCFCE7", "●"),
        "pasa": ("#10291C", "#2F7A4E", "#A7D7B8", "○"),
        "burbuja": ("#1F2937", "#6B7280", "#D1D5DB", "∅"),
        "descarta": ("#431407", "#FB923C", "#FFEDD5", "✕"),
        "no_entra": ("#1F2937", "#6B7280", "#D1D5DB", "⏸"),
        "halt": ("#2E1065", "#A78BFA", "#EDE9FE", "■"),
        "error": ("#450A0A", "#F87171", "#FEE2E2", "⚠"),
        "desconocida": ("#111827", "#9CA3AF", "#E5E7EB", "?"),
        "latch": ("#3B2F17", "#D4A64A", "#F5E3BC", ""),
        "latch_vacio": ("#262421", "#8A6E36", "#B8B2A6", ""),
        "fondo": "#16181D", "trama": "#374151", "forwarding": "#60A5FA",
        "stall": "#F59E0B", "flush": "#FB923C", "seguido": "#F9FAFB",
    },
}

# Listado: 5 tonos del mismo azul (IF el mas intenso) y naranja = se descarta.
LISTADO = {
    "claro": {"IF": "#93C5FD", "ID": "#A9CBFA", "EX": "#BFD8FB", "MEM": "#D3E4FC",
              "WB": "#E3EDFD", "descarta": "#FED7AA"},
    "oscuro": {"IF": "#1D4ED8", "ID": "#1E40AF", "EX": "#1E3A8A", "MEM": "#1B2F6B",
               "WB": "#17254F", "descarta": "#9A3412"},
}


def modo():
    """'claro' u 'oscuro' segun el fondo de la paleta de la aplicacion."""
    from PySide6.QtWidgets import QApplication
    app = QApplication.instance()
    if app is None:
        return "claro"
    return "oscuro" if app.palette().window().color().lightness() < 128 else "claro"
