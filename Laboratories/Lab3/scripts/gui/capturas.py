#!/usr/bin/env python3
"""
capturas.py - Genera las capturas de pantalla del manual (docs/informe/img/) usando la
propia aplicacion en modo demo (FPGA simulada). No necesita la placa.

    scripts/gui/.venv/bin/python scripts/gui/capturas.py
    (con QT_QPA_PLATFORM=offscreen no abre ninguna ventana)
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


def esperar(cond, ms=4000):
    loop = QEventLoop()
    t = QTimer()
    t.timeout.connect(lambda: loop.quit() if cond() else None)
    t.start(10)
    QTimer.singleShot(ms, loop.quit)
    loop.exec()


def pausa(ms):
    loop = QEventLoop()
    QTimer.singleShot(ms, loop.quit)
    loop.exec()


def guardar(v, nombre):
    pausa(150)
    ruta = os.path.join(DESTINO, nombre)
    v.grab().save(ruta)
    print("captura:", os.path.relpath(ruta, rutas.LAB))


def main():
    app = QApplication(sys.argv)
    tema.aplicar(app)
    ini = os.path.join(tempfile.mkdtemp(), "capturas.ini")
    v = VentanaPrincipal(QSettings(ini, QSettings.IniFormat))
    v.resize(1500, 920)
    v.show()
    v.combo_modo.setCurrentText("Simulado")
    v.conectar_o_desconectar()
    esperar(lambda: v.conectado and not v.ocupado and v.estado is not None)

    # 1. Paso a paso con forwarding: registros que cambian resaltados.
    v.abrir_archivo(os.path.join(rutas.PROGRAMAS_GUI, "demo_forwarding.asm"))
    v.cargar()
    esperar(lambda: not v.ocupado and v.estado.ciclos == 0)
    for k in range(1, 6):
        v.a_paso.trigger()
        esperar(lambda: v.estado.ciclos == k and not v.ocupado)
    v.tabs_programa.setCurrentIndex(1)
    v.tabs_abajo.setCurrentIndex(0)
    guardar(v, "depurador_paso_a_paso.png")

    # 2. Corrida completa de Fibonacci: memoria de datos y latches al terminar.
    v.abrir_archivo(os.path.join(rutas.PROGRAMAS_GUI, "fibonacci.asm"))
    v.cargar()
    esperar(lambda: not v.ocupado and v.estado.ciclos == 0)
    v.a_correr.trigger()
    esperar(lambda: v.estado.detenido and not v.ocupado)
    v.tabs_programa.setCurrentIndex(0)
    v.tabs_abajo.setCurrentIndex(0)
    guardar(v, "depurador_corrida.png")
    v.tabs_abajo.setCurrentIndex(1)
    guardar(v, "depurador_latches.png")

    # 3. Loop infinito interrumpido + log con los bytes en hex.
    v.abrir_archivo(os.path.join(rutas.PROGRAMAS_GUI, "demo_loop_infinito.asm"))
    v.cargar()
    esperar(lambda: not v.ocupado and v.estado.ciclos == 0)
    v.panel_log.ver_bytes.setChecked(True)
    v.a_correr.trigger()
    esperar(lambda: v.corriendo)
    pausa(600)
    v.interrumpir()
    esperar(lambda: not v.corriendo and v.estado.interrumpido)
    v.tabs_abajo.setCurrentIndex(2)
    guardar(v, "depurador_interrumpido_log.png")

    # 4. Error de ensamblado marcado en el editor.
    v.panel_log.ver_bytes.setChecked(False)
    v.editor.setPlainText("# Error a proposito: MUL no esta en la consigna\n"
                          "        li   t0, 6\n        li   t1, 7\n"
                          "        mul  t2, t0, t1\n        halt\n")
    v.ensamblar()
    v.tabs_programa.setCurrentIndex(0)
    guardar(v, "depurador_error_asm.png")
    v.close()


if __name__ == "__main__":
    main()
