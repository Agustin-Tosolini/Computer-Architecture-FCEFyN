#!/usr/bin/env bash
# lanzar_depurador.sh — Abre el depurador con el Python del entorno virtual
# (scripts/gui/.venv). Se puede llamar desde cualquier carpeta.
aqui="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
py="$aqui/.venv/bin/python"
if [[ ! -x "$py" ]]; then
    msg="Falta el entorno virtual. En una terminal:\n  python3 -m venv $aqui/.venv\n  $aqui/.venv/bin/python -m pip install -r $aqui/requirements.txt"
    command -v zenity >/dev/null && zenity --error --text="$msg" || echo -e "$msg" >&2
    exit 1
fi
exec "$py" "$aqui/depurador.py" "$@"
