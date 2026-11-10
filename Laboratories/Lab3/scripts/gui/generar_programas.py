#!/usr/bin/env python3
"""
generar_programas.py - Ensambla scripts/gui/programas/*.asm, verifica las
lineas "# ESPERADO:" contra el modelo de referencia y escribe cada .hex con el
resultado esperado en la cabecera.

    python3 scripts/gui/generar_programas.py

(Los programas de scripts/programas/ los genera rv32i_model.py --generar; estos
quedan aparte para no tocar los vectores de testbench/.)
"""
import glob
import os
import sys

import rutas
from ensamblador import a_hex, ensamblar
from rv32i_model import ejecutar, esperados, resumen, verificar_anotaciones


def procesar(ruta):
    """Devuelve (listado, resultado, errores) de un .asm."""
    with open(ruta, encoding="utf-8") as f:
        texto = f.read()
    listado = ensamblar(texto)
    sin_fin = "estado = 0x02" in texto
    r = ejecutar([ln.word for ln in listado], estricto=True, verificar_estable=not sin_fin)
    return texto, listado, r, verificar_anotaciones(r, esperados(texto), os.path.basename(ruta))


def main():
    errores = []
    for ruta in sorted(glob.glob(os.path.join(rutas.PROGRAMAS_GUI, "*.asm"))):
        texto, listado, r, err = procesar(ruta)
        errores += err
        nombre = os.path.splitext(os.path.basename(ruta))[0]
        desc = [ln[1:].strip() for ln in texto.splitlines()
                if ln.startswith("#") and "ESPERADO" not in ln.upper()][:5]
        cab = [f"{nombre}.hex - generado desde {nombre}.asm (no editar a mano)"] + desc + \
              ["", "Resultado esperado (rv32i_model.py):"] + ["  " + x for x in resumen(r)]
        with open(os.path.join(rutas.PROGRAMAS_GUI, nombre + ".hex"), "w", encoding="utf-8") as f:
            f.write(a_hex(listado, "\n".join(cab)))
        print(f"{nombre:22s} {len(listado):3d} palabras  {resumen(r)[0]}")
    for e in errores:
        print("ERROR:", e)
    return 1 if errores else 0


if __name__ == "__main__":
    sys.exit(main())
