"""
rutas.py - Carpetas del proyecto, para que los modulos del depurador encuentren
el ensamblador y el modelo (que viven en scripts/) y el contrato (src/params.vh).

Importar este modulo antes que ensamblador o rv32i_model:
    import rutas            # agrega scripts/ al camino de busqueda de Python
    from ensamblador import ensamblar
"""
import os
import sys

GUI = os.path.dirname(os.path.abspath(__file__))           # scripts/gui
SCRIPTS = os.path.dirname(GUI)                               # scripts
LAB = os.path.dirname(SCRIPTS)                               # Laboratories/Lab3
PARAMS_VH = os.path.join(LAB, "src", "params.vh")
PROGRAMAS_GUI = os.path.join(GUI, "programas")               # ejemplos de la parte C
PROGRAMAS = os.path.join(SCRIPTS, "programas")               # ejemplos de la integracion
PROGRAMAS_DEFENSA = os.path.join(PROGRAMAS, "defensa")       # demos de la defensa (aparte)

# Demos de la defensa, en el orden del menu Ejemplos -> Defensa: (archivo, nombre visible)
DEMOS_DEFENSA = [
    ("demo_wow_fibonacci", "Fibonacci en memoria"),
    ("demo_pipeline", "Recorrido del pipeline (paso a paso)"),
    ("demo_loop_infinito", "Loop infinito (interrumpir con I)"),
    ("demo_sin_halt", "Programa sin HALT"),
    ("demo_error", "Error: acceso fuera de memoria"),
    ("demo_signo", "Con signo y sin signo (reserva)"),
    ("demo_subrutina", "Subrutina con jal / jalr (reserva)"),
]

for carpeta in (SCRIPTS, GUI):
    if carpeta not in sys.path:
        sys.path.insert(0, carpeta)
