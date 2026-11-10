#!/usr/bin/env python3
"""
mutaciones.py - Pruebas de mutacion: rompe el diseno a proposito y verifica
que algun test lo detecte.

Para cada mutacion:
  1. copia src/ a una carpeta temporal (el repo NO se toca);
  2. aplica el cambio (si el texto a reemplazar no aparece, la mutacion es
     invalida y el script lo avisa: asi una mutacion nunca "sobrevive" por
     haber quedado mal escrita);
  3. corre tb_cpu_isa, tb_cpu (parte A) y tb_top_cpu +RAPIDO sobre la copia;
  4. anota que tests fallaron. Si ninguno falla, la mutacion SOBREVIVIO.

Uso (desde Laboratories/Lab3, despues de rv32i_model.py --generar):
  python3 scripts/mutaciones.py              todas (~8 min)
  python3 scripts/mutaciones.py 3 7          solo algunas (por numero)
Variables IVERILOG / VVP: igual que run_all_tests.sh.
"""
import os
import shutil
import subprocess
import sys
import tempfile

LAB = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
IVERILOG = os.environ.get("IVERILOG", "iverilog")
VVP = os.environ.get("VVP", "vvp")

# (descripcion, [(archivo, texto original, texto mutado), ...])
MUTACIONES = [
    ("Sin forwarding EX/MEM -> EX", [
        ("src/cpu/hazards/forwarding_unit.v",
         "if (!i_mem_result_src) o_forward_a = FROM_EX_MEM;", ";"),
        ("src/cpu/hazards/forwarding_unit.v",
         "if (!i_mem_result_src) o_forward_b = FROM_EX_MEM;", ";")]),
    ("Sin forwarding MEM/WB -> EX", [
        ("src/cpu/hazards/forwarding_unit.v", "o_forward_a = FROM_WB;", "o_forward_a = FROM_ID_EX;"),
        ("src/cpu/hazards/forwarding_unit.v", "o_forward_b = FROM_WB;", "o_forward_b = FROM_ID_EX;")]),
    ("Sin stall load-use", [
        ("src/cpu/hazards/hazard_unit.v", "wire load_use = i_id_valid &&",
         "wire load_use = 1'b0 && i_id_valid &&")]),
    ("Sin flush de IF/ID en saltos", [
        ("src/cpu/hazards/hazard_unit.v",
         "o_if_id_flush = 1'b1;\n            o_id_ex_flush = 1'b1;",
         "o_if_id_flush = 1'b0;\n            o_id_ex_flush = 1'b1;")]),
    ("Sin flush de ID/EX en saltos", [
        ("src/cpu/hazards/hazard_unit.v",
         "o_if_id_flush = 1'b1;\n            o_id_ex_flush = 1'b1;",
         "o_if_id_flush = 1'b1;\n            o_id_ex_flush = 1'b0;")]),
    ("i_enable ignorado en el registro EX/MEM", [
        ("src/cpu/pipeline/ex_mem.v", "if (i_reset || (i_enable && !i_valid))", "if (i_reset || !i_valid)"),
        ("src/cpu/pipeline/ex_mem.v", "else if (i_enable) begin", "else begin")]),
    ("HALT detectado tarde (o_halted 1 ciclo despues, como antes)", [
        ("src/cpu/cpu.v", "assign o_halted = wb_valid && wb_halt;",
         "reg halted_q = 1'b0;\n"
         "    always @(posedge i_clk)\n"
         "        if (i_cpu_reset) halted_q <= 1'b0;\n"
         "        else if (step && wb_valid && wb_halt) halted_q <= 1'b1;\n"
         "    assign o_halted = halted_q;")]),
    ("LB sin extension de signo", [
        ("src/cpu/mem/data_mem.v", "3'b000: o_rdata = {{24{shifted_word[7]}}, shifted_word[7:0]};",
         "3'b000: o_rdata = {24'd0, shifted_word[7:0]};")]),
    ("SRA hace lo mismo que SRL", [
        ("src/cpu/ex/alu.v", "SRA:  o_result = $signed(i_a) >>> shamt;", "SRA:  o_result = i_a >> shamt;")]),
    ("Sin bypass WB -> ID en el banco de registros", [
        ("src/cpu/id/reg_file.v", "(write_en && i_rd == i_rs1) ? i_wdata : regs[i_rs1]", "regs[i_rs1]"),
        ("src/cpu/id/reg_file.v", "(write_en && i_rd == i_rs2) ? i_wdata : regs[i_rs2]", "regs[i_rs2]")]),
    ("El reset borra la memoria de datos (deberia conservarla: es RAM)", [
        ("src/cpu/mem/data_mem.v", "    always @(posedge i_clk) begin\n        if (write_en) begin",
         "    always @(posedge i_clk) begin\n"
         "        if (i_reset) begin\n"
         "            for (index = 0; index < 32; index = index + 1) mem[index] <= 32'd0;\n"
         "        end\n"
         "        else if (write_en) begin")]),
    ("debug_unit: el estado no informa el error (bit 2)", [
        ("src/debug_unit/control_fsmd.v", "{5'd0, i_fault, interrupted, i_halted}",
         "{5'd0, 1'b0, interrupted, i_halted}")]),
]


def fuentes(raiz, *dirs):
    out = []
    for d in dirs:
        for base, _, archivos in os.walk(os.path.join(raiz, d)):
            out += [os.path.join(base, a) for a in sorted(archivos) if a.endswith(".v")]
    return sorted(out)


def correr(tb, srcs, tmp, g="-g2005", plus=()):
    vvp = os.path.join(tmp, tb + ".vvp")
    c = subprocess.run([IVERILOG, g, "-o", vvp, "-s", tb,
                        os.path.join(LAB, "testbench", tb + ".v")] + srcs,
                       capture_output=True, text=True)
    if c.returncode != 0:
        return "no compila"
    r = subprocess.run([VVP, "-n", vvp] + list(plus), capture_output=True, text=True,
                       cwd=LAB, timeout=900)
    salida = r.stdout + r.stderr
    if "PASS" in salida and "FAIL" not in salida and r.returncode == 0:
        return "PASS"
    return "FALLA"


def main():
    elegidas = [int(a) for a in sys.argv[1:]] or list(range(1, len(MUTACIONES) + 1))
    filas, sobrevivientes = [], 0
    for n in elegidas:
        desc, cambios = MUTACIONES[n - 1]
        tmp = tempfile.mkdtemp(prefix="mut%02d." % n, dir=os.environ.get("TMPDIR"))
        shutil.copytree(os.path.join(LAB, "src"), os.path.join(tmp, "src"))
        for archivo, viejo, nuevo in cambios:
            ruta = os.path.join(tmp, archivo)
            with open(ruta) as f:
                texto = f.read()
            if texto.count(viejo) != 1:
                sys.exit(f"Mutacion {n} invalida: '{viejo}' aparece {texto.count(viejo)} "
                         f"veces en {archivo}")
            with open(ruta, "w") as f:
                f.write(texto.replace(viejo, nuevo))
        cpu = [s for s in fuentes(tmp, "src/cpu") if not s.endswith("cpu_if_id_test.v")]
        todo = fuentes(tmp, "src/debug_unit") + cpu
        res = {
            "tb_cpu_isa": correr("tb_cpu_isa", cpu, tmp),
            "tb_cpu (A)": correr("tb_cpu", cpu, tmp, g="-g2012"),
            "tb_top_cpu": correr("tb_top_cpu", todo, tmp, plus=["+RAPIDO"]),
        }
        detectada = [t for t, v in res.items() if v != "PASS"]
        if not detectada:
            sobrevivientes += 1
        filas.append((n, desc, res, detectada))
        print(f"{n:2d}. {desc:58s} -> " +
              (", ".join(detectada) if detectada else "SOBREVIVIO"), flush=True)
        shutil.rmtree(tmp)

    print("\n| # | Mutacion | tb_cpu_isa | tb_cpu (A) | tb_top_cpu | Detectada |")
    print("|---|---|---|---|---|---|")
    for n, desc, res, det in filas:
        print(f"| {n} | {desc} | {res['tb_cpu_isa']} | {res['tb_cpu (A)']} | "
              f"{res['tb_top_cpu']} | {'si' if det else '**NO**'} |")
    if sobrevivientes:
        print(f"\nFAIL: {sobrevivientes} mutaciones sobrevivieron")
        sys.exit(1)
    print(f"\nPASS: las {len(filas)} mutaciones fueron detectadas")


if __name__ == "__main__":
    main()
