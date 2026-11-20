#!/usr/bin/env bash
# correr_tests.sh — Corre TODOS los tests de Python del depurador (parte C).
#
#   bash scripts/gui/correr_tests.sh          todos (~35 s)
#   bash scripts/gui/correr_tests.sh -k gui   solo los que tengan "gui" en el nombre
#
# Usa el Python de scripts/gui/.venv. La interfaz se prueba sin pantalla
# (QT_QPA_PLATFORM=offscreen). test_captura_rtl necesita iverilog: si no esta
# instalado (sudo apt install iverilog) se saltea con un aviso.
set -uo pipefail
aqui="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
py="$aqui/.venv/bin/python"
if [[ ! -x "$py" ]]; then
    echo "Falta el entorno virtual: python3 -m venv $aqui/.venv &&" \
         "$aqui/.venv/bin/python -m pip install -r $aqui/requirements.txt" >&2
    exit 1
fi
cd "$aqui"
"$py" generar_programas.py > /dev/null || { echo "FAIL: generar_programas.py"; exit 1; }
QT_QPA_PLATFORM=offscreen "$py" -m pytest tests -q -rs "$@"
