#!/usr/bin/env bash
# Uso: bash Laboratories/Lab3/scripts/run_cpu_tests.sh
# Requiere Icarus Verilog. IVERILOG/VVP permiten elegir los ejecutables.
# Para una copia extraida del paquete: IVERILOG_LIB indica la carpeta ivl (-B).
set -euo pipefail

lab_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
sim_dir="$(mktemp -d "${TMPDIR:-/tmp}/lab3-cpu-tests.XXXXXX")"
iverilog_bin="${IVERILOG:-iverilog}"
vvp_bin="${VVP:-vvp}"
compiler_args=(-g2012 -Wall)
if [[ -n "${IVERILOG_LIB:-}" ]]; then
    compiler_args+=(-B "$IVERILOG_LIB")
fi

command -v "$iverilog_bin" >/dev/null
command -v "$vvp_bin" >/dev/null
mapfile -d '' cpu_sources < <(find "$lab_dir/src/cpu" -type f -name '*.v' -print0)

for bench in tb_reg_file tb_id_ex tb_ex_mem tb_mem_wb tb_forwarding_unit tb_hazard_unit tb_data_mem tb_cpu_if_id_test tb_cpu; do
    "$iverilog_bin" "${compiler_args[@]}" -s "$bench" \
        -o "$sim_dir/$bench.vvp" "$lab_dir/testbench/$bench.v" "${cpu_sources[@]}"
    "$vvp_bin" "$sim_dir/$bench.vvp"
done
printf 'Simulaciones guardadas en %s\n' "$sim_dir"
