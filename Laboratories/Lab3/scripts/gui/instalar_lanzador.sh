#!/usr/bin/env bash
# instalar_lanzador.sh — Agrega "Depurador TP RISC-V" al menu de aplicaciones
# (Linux Mint / Cinnamon) y al escritorio. Correrlo una vez:
#   bash scripts/gui/instalar_lanzador.sh
set -euo pipefail
aqui="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
destino="$HOME/.local/share/applications/tp-riscv-depurador.desktop"
mkdir -p "$(dirname "$destino")"
sed "s|@CARPETA@|$aqui|g" "$aqui/depurador.desktop" > "$destino"
chmod +x "$destino" "$aqui/lanzar_depurador.sh"
escritorio="$(xdg-user-dir DESKTOP 2>/dev/null || echo "$HOME/Escritorio")"
if [[ -d "$escritorio" ]]; then
    cp "$destino" "$escritorio/"
    chmod +x "$escritorio/tp-riscv-depurador.desktop"
    gio set "$escritorio/tp-riscv-depurador.desktop" metadata::trusted true 2>/dev/null || true
fi
echo "Listo: buscá 'Depurador TP RISC-V' en el menú (o el icono del escritorio)."
