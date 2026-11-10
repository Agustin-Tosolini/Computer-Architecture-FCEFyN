#!/usr/bin/env bash
# run_all_tests.sh — Corre TODAS las pruebas del Lab3 y muestra un resumen.
#
# Uso (desde cualquier carpeta):
#   bash scripts/run_all_tests.sh            todo (~4 min: tb_top y tb_top_cpu son lentos)
#   bash scripts/run_all_tests.sh --rapido   sin tb_top y con tb_top_cpu +RAPIDO (~1 min)
#
# Requiere python3 e Icarus Verilog. IVERILOG / VVP permiten elegir los
# ejecutables (por ejemplo, una copia extraida del paquete).
#
# Reglas que verifica:
#   * El RTL (cpu y debug_unit) y los testbenches de la parte B y los nuevos
#     compilan con `iverilog -Wall -g2005` SIN NINGUN warning.
#   * Cada testbench imprime una linea que empieza con "PASS" y ningun WARNING
#     en tiempo de simulacion.
#   * Los testbenches viejos de la parte A se corren con su propio script
#     (scripts/run_cpu_tests.sh, -g2012, usan $fatal).
set -uo pipefail

lab="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$lab"
IVERILOG="${IVERILOG:-iverilog}"
VVP="${VVP:-vvp}"
rapido=0
[[ "${1:-}" == "--rapido" ]] && rapido=1
out="$(mktemp -d "${TMPDIR:-/tmp}/lab3-tests.XXXXXX")"

RTL_B=(src/debug_unit/*.v)
mapfile -t RTL_CPU < <(find src/cpu -name '*.v' | sort)

declare -a nombres resultados
fallos=0
anotar() {   # anotar <nombre> <ok 0/1> <detalle>
    nombres+=("$1")
    if [[ "$2" == 0 ]]; then resultados+=("PASS  $3"); else resultados+=("FAIL  $3"); fallos=$((fallos + 1)); fi
}

#------------------------------------------------------------- Python
for cmd in "scripts/ensamblador.py --test" "scripts/rv32i_model.py --test" \
           "scripts/rv32i_model.py --generar" "scripts/uart_test.py --autoprueba"; do
    echo "== python3 $cmd"
    if python3 $cmd > "$out/py.log" 2>&1; then
        tail -1 "$out/py.log"; anotar "python3 $cmd" 0 "$(tail -1 "$out/py.log")"
    else
        cat "$out/py.log"; anotar "python3 $cmd" 1 "ver arriba"
    fi
done

#------------------------------------------------------------- compilacion sin warnings
compilar() {   # compilar <salida.vvp> <args...>; falla si hay CUALQUIER mensaje
    local vvp="$1"; shift
    if ! "$IVERILOG" -Wall -g2005 -o "$vvp" "$@" > "$out/comp.log" 2>&1; then
        cat "$out/comp.log"; return 1
    fi
    if [[ -s "$out/comp.log" ]]; then
        echo "  warnings:"; cat "$out/comp.log"; return 1
    fi
    return 0
}

echo "== RTL: top con el cpu real y con el stub (-Wall -g2005)"
if compilar "$out/top.vvp" -s top "${RTL_B[@]}" "${RTL_CPU[@]}" &&
   compilar "$out/top_stub.vvp" -s top -Ptop.USE_CPU_STUB=1 "${RTL_B[@]}" "${RTL_CPU[@]}"; then
    anotar "RTL -Wall -g2005" 0 "sin warnings (cpu, debug_unit, top x2)"
else
    anotar "RTL -Wall -g2005" 1 "warnings o errores"
fi

#------------------------------------------------------------- testbenches
correr_tb() {   # correr_tb <tb> <plusargs> <fuentes...>
    local tb="$1" plus="$2"; shift 2
    echo "== $tb $plus"
    if ! compilar "$out/$tb.vvp" -s "$tb" "testbench/$tb.v" "$@"; then
        anotar "$tb" 1 "no compila sin warnings"; return
    fi
    local t0=$SECONDS
    "$VVP" -n "$out/$tb.vvp" $plus > "$out/$tb.log" 2>&1
    local linea; linea="$(grep -E '^(PASS|FAIL)' "$out/$tb.log" | tail -1)"
    if [[ "$linea" == PASS* ]] && ! grep -q WARNING "$out/$tb.log"; then
        echo "  $linea ($((SECONDS - t0)) s)"; anotar "$tb $plus" 0 "$linea"
    else
        grep -E 'ERROR|WARNING|FAIL' "$out/$tb.log" | head -20
        anotar "$tb $plus" 1 "${linea:-sin linea PASS}"
    fi
}

correr_tb tb_dump_mux  "" src/debug_unit/dump_mux.v
correr_tb tb_cpu_stub  "" src/debug_unit/cpu_stub.v
correr_tb tb_cpu_isa   "" "${RTL_CPU[@]}"
if [[ $rapido == 1 ]]; then
    correr_tb tb_top_cpu "+RAPIDO" "${RTL_B[@]}" "${RTL_CPU[@]}"
else
    correr_tb tb_top_cpu "" "${RTL_B[@]}" "${RTL_CPU[@]}"
    correr_tb tb_top     "" "${RTL_B[@]}" "${RTL_CPU[@]}"
fi

#------------------------------------------------------------- parte A (-g2012)
echo "== scripts/run_cpu_tests.sh (testbenches de la parte A, -g2012)"
if IVERILOG="$IVERILOG" VVP="$VVP" bash scripts/run_cpu_tests.sh > "$out/parteA.log" 2>&1 &&
   [[ $(grep -c '^PASS' "$out/parteA.log") -eq 9 ]]; then
    grep '^PASS' "$out/parteA.log" | sed 's/^/  /'
    anotar "parte A (9 testbenches)" 0 "9 PASS"
else
    tail -20 "$out/parteA.log"; anotar "parte A (9 testbenches)" 1 "ver arriba"
fi

#------------------------------------------------------------- resumen
echo
echo "================================ RESUMEN"
for i in "${!nombres[@]}"; do
    printf '  %-42s %s\n' "${nombres[$i]}" "${resultados[$i]}"
done
echo "Archivos de simulacion en $out"
if [[ $fallos == 0 ]]; then echo "PASS: todas las pruebas"; exit 0; fi
echo "FAIL: $fallos pruebas fallaron"; exit 1
