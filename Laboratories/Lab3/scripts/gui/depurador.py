#!/usr/bin/env python3
"""
depurador.py - Punto de entrada del depurador grafico (parte C).

    scripts/gui/.venv/bin/python scripts/gui/depurador.py
    (o bash scripts/gui/lanzar_depurador.sh, o el lanzador del menu de Mint)

Instala un "gancho global de excepciones": cualquier error inesperado (en la
interfaz o en otro hilo) va al log y a un cuadro de dialogo, nunca a la consola.
"""
import logging
import sys
import threading
import traceback

import rutas  # noqa: F401  (scripts/ y scripts/gui/ en el path)

log = logging.getLogger("depurador")


def instalar_gancho(ventana_fn):
    """ventana_fn(): devuelve la ventana (o None) para mostrar el dialogo."""
    from PySide6.QtCore import QObject, QTimer, Signal
    from PySide6.QtWidgets import QMessageBox

    class _Avisador(QObject):
        aviso = Signal(str)                  # cruza al hilo de la interfaz

    avisador = _Avisador()

    def mostrar(texto):
        caja = QMessageBox(QMessageBox.Critical, "Error inesperado",
                           "Ocurrió un error inesperado. Quedó registrado en el log.\n\n" + texto,
                           QMessageBox.Ok, ventana_fn())
        caja.open()

    avisador.aviso.connect(mostrar)

    def gancho(tipo, valor, tb):
        log.error("Error inesperado:\n" + "".join(traceback.format_exception(tipo, valor, tb)))
        avisador.aviso.emit(f"{tipo.__name__}: {valor}")

    sys.excepthook = gancho
    threading.excepthook = lambda a: gancho(a.exc_type, a.exc_value, a.exc_traceback)
    return avisador


def main():
    try:
        from PySide6.QtGui import QIcon
        from PySide6.QtWidgets import QApplication
    except ImportError:
        sys.stderr.write("Falta PySide6. Instalar con:\n"
                         "  python3 -m venv scripts/gui/.venv\n"
                         "  scripts/gui/.venv/bin/python -m pip install -r scripts/gui/requirements.txt\n")
        return 1
    from app import tema
    from app.ventana_principal import VentanaPrincipal

    app = QApplication(sys.argv)
    app.setApplicationName("Depurador TP RISC-V")
    app.setOrganizationName("FCEFyN")
    app.setDesktopFileName("tp-riscv-depurador")
    tema.aplicar(app)
    ventana = {"v": None}
    avisador = instalar_gancho(lambda: ventana["v"])   # noqa: F841 (debe seguir vivo)
    ventana["v"] = VentanaPrincipal()
    ventana["v"].show()
    return app.exec()


if __name__ == "__main__":
    sys.exit(main())
