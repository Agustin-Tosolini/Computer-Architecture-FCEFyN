#!/usr/bin/env python3
"""
capturas_defensa.py - Capturas de los momentos clave de la defensa
(docs/guion_defensa.md), generadas por la propia app en modo demo:

    QT_QPA_PLATFORM=offscreen scripts/gui/.venv/bin/python scripts/gui/capturas_defensa.py

Guarda docs/informe/img/defensa_*.png.
"""
import os
import sys
import tempfile

import rutas
from PySide6.QtCore import QEventLoop, QSettings, QTimer
from PySide6.QtWidgets import QApplication

from app import tema
from app.ventana_principal import VentanaPrincipal

DESTINO = os.path.join(rutas.LAB, "docs", "informe", "img")


def esperar(cond, ms=6000):
    loop = QEventLoop()
    t = QTimer()
    t.timeout.connect(lambda: loop.quit() if cond() else None)
    t.start(10)
    QTimer.singleShot(ms, loop.quit)
    loop.exec()


def guardar(v, nombre):
    loop = QEventLoop()
    QTimer.singleShot(150, loop.quit)
    loop.exec()
    ruta = os.path.join(DESTINO, nombre)
    v.grab().save(ruta)
    print("captura:", os.path.relpath(ruta, rutas.LAB))


def cargar(v, nombre):
    v.abrir_archivo(os.path.join(rutas.PROGRAMAS_DEFENSA, nombre + ".asm"))
    v.cargar()
    esperar(lambda: not v.ocupado and v.estado.ciclos == 0 and v.programa_cargado)


def main():
    app = QApplication(sys.argv)
    tema.aplicar(app)
    v = VentanaPrincipal(QSettings(os.path.join(tempfile.mkdtemp(), "c.ini"), QSettings.IniFormat))
    v.resize(1500, 1000)
    v.show()
    v.combo_modo.setCurrentText("Simulado")
    v.conectar_o_desconectar()
    esperar(lambda: v.conectado and not v.ocupado and v.estado is not None)

    # Wow: Fibonacci, memoria llena (columna Decimal)
    cargar(v, "demo_wow_fibonacci")
    v.a_correr.trigger()
    esperar(lambda: v.estado.detenido and not v.ocupado)
    v.tabs_programa.setCurrentIndex(1)
    v.tabs_abajo.setCurrentIndex(0)
    v.combo_formato.setCurrentText("Decimal con signo")
    guardar(v, "defensa_wow_fibonacci.png")

    # Recorrido del pipeline: los pasos de la tabla
    cargar(v, "demo_pipeline")
    v.tabs_programa.setCurrentIndex(1)
    v.tabs_abajo.setCurrentIndex(1)
    momentos = {3: "fwd_exmem", 6: "fwd_memwb", 9: "bypass", 12: "stall_aviso",
                13: "stall_burbuja", 14: "stall_fwd", 15: "beq_no_tomado", 16: "flush",
                17: "flush_burbujas", 22: "halt"}
    for k in range(1, 23):
        if k == 12:
            v._seguir_fila(11, 0)            # seguir add x8, x7, x7 (0x2C)
        v.a_paso.trigger()
        esperar(lambda: v.estado.ciclos == k and not v.ocupado)
        if k in momentos:
            guardar(v, f"defensa_paso{k:02d}_{momentos[k]}.png")
    v.close()


if __name__ == "__main__":
    main()
