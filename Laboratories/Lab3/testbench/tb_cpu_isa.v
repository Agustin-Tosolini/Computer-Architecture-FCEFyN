`timescale 1ns / 1ps
`default_nettype none

//------------------------------------------------------------------------------
// tb_cpu_isa — Testbench del cpu real SOLO (sin UART), contra el contrato.
//
// Maneja las senales del contrato a mano, como lo hace la debug_unit.
// Convencion: las entradas cambian en el flanco de BAJADA y se verifican
// despues del flanco de SUBIDA (#1). Las lecturas de debug (registros y
// memoria) se hacen entre flancos: el dato tiene que estar en el mismo ciclo
// (lectura asincronica).
//
// Parte A — pruebas explicitas (valores calculados a mano en este archivo):
//   A1. x0 por el puerto de debug vale 0 incluso antes del primer reset.
//   A2. i_cpu_reset: PC = 0, latches en el patron de reset, registros en 0,
//       halted = fault = 0 (la memoria de datos arranca en 0 por la
//       inicializacion de la FPGA, no por el reset).
//   A3. i_imem_we con i_enable = 1 se ignora (la carga es solo en pausa).
//   A4. Latencia del HALT: 5 NOPs + HALT -> halted = 0 tras 8 ciclos y 1 tras
//       exactamente 9. PC paso a paso 4, 8, ..., 24 (= HALT + 4). Patron final
//       de los latches: solo el marcador de HALT en MEM/WB.
//   A5. Con halted = 1, i_enable se ignora (nada cambia en 5 ciclos).
//   A6. Load-use: exactamente 1 ciclo de stall (traza del PC). Con una
//       instruccion en el medio no hay stall.
//   A7. Flush: un beq tomado descarta las 2 instrucciones buscadas de mas.
//   A8. i_enable = 0 congela todo: PC, latches, los 32 registros y las 32
//       palabras de memoria no cambian durante 50 ciclos; despues el programa
//       termina igual que sin pausa.
//   A9. i_cpu_reset a mitad de una corrida: borra PC, latches y registros;
//       NO borra la memoria de datos (RAM: las 32 palabras quedan igual) ni la
//       memoria de programa (se vuelve a correr y da lo mismo).
//   A10. Error: instruccion ilegal -> halted = fault = 1, quedan en 1 con
//        enable y el reset los baja.
//   A11. Campos de los latches: en cada ciclo de un programa con loads,
//        stores y forwarding, cada campo de la tabla de params.vh (4b) es la
//        senal interna correspondiente, y el relleno vale 0.
//
// Parte B — programas del modelo de referencia (scripts/rv32i_model.py):
//   Para cada programa de testbench/vectores/ (generados desde
//   scripts/programas/*.asm) se carga la memoria con i_imem_we, se resetea y
//   se avanza de a un ciclo. Despues de CADA ciclo se comparan los 32
//   registros, las 32 palabras de memoria, el PC y el estado (halted/fault)
//   con lo que calculo el modelo. La memoria de datos NO se borra entre
//   programas: antes de correr se lee como quedo, y en las palabras que el
//   programa todavia no escribio (mascara del modelo) se espera ese valor
//   previo, intacto. Al final: ciclos hasta halted, estado,
//   y el patron de los latches (en un HALT normal).
//
// Uso (desde Laboratories/Lab3):
//   python3 scripts/rv32i_model.py --generar
//   iverilog -Wall -g2005 -o tb_cpu_isa.vvp testbench/tb_cpu_isa.v src/cpu/*.v src/cpu/*/*.v
//   vvp -n tb_cpu_isa.vvp            (opcional: +VEC=otra/carpeta/)
//
// Resultado: "PASS" o la lista de errores y "FAIL".
//------------------------------------------------------------------------------
module tb_cpu_isa;

    localparam [479:0] LAT_RESET = {32'd0, 32'h0000_0013, 32'd0, 384'd0};
    localparam [479:0] LAT_HALT  = LAT_RESET | 480'h5;   // MEM/WB: valid + halt
    localparam [31:0]  NOP  = 32'h0000_0013;
    localparam [31:0]  HALT = 32'h0000_0000;

    //------------------------------------------------ Clock y DUT
    reg clk = 1'b0;
    always #5 clk = ~clk;

    reg         cpu_reset = 1'b0;
    reg         enable    = 1'b0;
    reg         imem_we   = 1'b0;
    reg  [7:0]  imem_addr = 8'd0;
    reg  [31:0] imem_data = 32'd0;
    reg  [4:0]  reg_addr  = 5'd0;
    reg  [7:0]  mem_addr  = 8'd0;
    wire [31:0] reg_data, mem_data, pc;
    wire [479:0] latches;
    wire        halted, fault;

    cpu dut
    (
        .i_clk          (clk),
        .i_cpu_reset    (cpu_reset),
        .i_enable       (enable),
        .i_imem_we      (imem_we),
        .i_imem_addr    (imem_addr),
        .i_imem_data    (imem_data),
        .i_dbg_reg_addr (reg_addr),
        .o_dbg_reg_data (reg_data),
        .i_dbg_mem_addr (mem_addr),
        .o_dbg_mem_data (mem_data),
        .o_pc           (pc),
        .o_latches      (latches),
        .o_halted       (halted),
        .o_fault        (fault)
    );

    //------------------------------------------------ Verificacion
    integer errors = 0;
    integer shown  = 0;

    task check(input [8*48-1:0] what, input [31:0] got, input [31:0] exp);
        begin
            if (got !== exp) begin
                if (shown < 40)
                    $display("ERROR: %0s: %h, esperado %h (t=%0t)", what, got, exp, $time);
                shown  = shown + 1;
                errors = errors + 1;
            end
        end
    endtask

    //------------------------------------------------ Programa en memoria
    reg [31:0] prog [0:255];
    integer    n_prog;
    integer    i, k, w;

    // Escribe una palabra de programa (pulso de 1 ciclo, con enable = 0).
    task imem_write(input [7:0] a, input [31:0] d);
        begin
            @(negedge clk);
            imem_addr = a; imem_data = d; imem_we = 1'b1;
            @(negedge clk);
            imem_we = 1'b0;
        end
    endtask

    // Carga prog[0..n-1] y HALT en el resto (como hace el CLEAR de 'L').
    task load_prog(input integer n);
        begin
            for (w = 0; w < 256; w = w + 1)
                imem_write(w[7:0], (w < n && w != 255) ? prog[w] : HALT);
        end
    endtask

    task do_reset;
        begin
            @(negedge clk); enable = 1'b0; cpu_reset = 1'b1;
            @(negedge clk); cpu_reset = 1'b0;
        end
    endtask

    // Un ciclo habilitado. Deja enable = 1 (el siguiente ciclo sigue corrido);
    // pause lo vuelve a 0.
    task cycle;
        begin
            @(negedge clk); enable = 1'b1;
            @(posedge clk); #1;
        end
    endtask

    task pause;
        begin
            @(negedge clk); enable = 1'b0;
        end
    endtask

    // Lecturas de debug: cambiar la direccion y leer en el mismo ciclo.
    reg [31:0] rd_val;
    task rreg(input [4:0] n);  begin reg_addr = n; #1; rd_val = reg_data; end endtask
    task rmem(input [7:0] n);  begin mem_addr = n; #1; rd_val = mem_data; end endtask

    // Copia del estado observable (para comparar antes/despues).
    reg [31:0]  snap_regs [0:31];
    reg [31:0]  snap_mem  [0:31];
    reg [31:0]  snap_pc;
    reg [479:0] snap_lat;
    task take_snapshot;
        begin
            snap_pc  = pc;
            snap_lat = latches;
            for (k = 0; k < 32; k = k + 1) begin
                rreg(k[4:0]); snap_regs[k] = rd_val;
                rmem(k[7:0]); snap_mem[k]  = rd_val;
            end
        end
    endtask
    task compare_snapshot(input [8*48-1:0] what);
        begin
            check(what, pc, snap_pc);
            if (latches !== snap_lat) begin
                $display("ERROR: %0s: latches cambiaron", what);
                errors = errors + 1;
            end
            for (k = 0; k < 32; k = k + 1) begin
                rreg(k[4:0]); check(what, rd_val, snap_regs[k]);
                rmem(k[7:0]); check(what, rd_val, snap_mem[k]);
            end
        end
    endtask

    task check_regs_zero(input [8*48-1:0] what);
        begin
            for (k = 0; k < 32; k = k + 1) begin
                rreg(k[4:0]); check(what, rd_val, 32'd0);
            end
        end
    endtask

    task check_mem_snapshot(input [8*48-1:0] what);
        begin
            for (k = 0; k < 32; k = k + 1) begin
                rmem(k[7:0]); check(what, rd_val, snap_mem[k]);
            end
        end
    endtask

    // Corre hasta halted (o max ciclos) y devuelve en n_cycles los ciclos.
    integer n_cycles;
    task run_to_halt(input integer max);
        begin
            n_cycles = 0;
            while (halted !== 1'b1 && n_cycles < max) begin
                cycle;
                n_cycles = n_cycles + 1;
            end
            pause;
        end
    endtask

    // Traza del PC despues de cada ciclo (para A4, A6, A7).
    reg [31:0] trace [0:15];
    task run_trace(input integer n);
        begin
            for (i = 0; i < n; i = i + 1) begin
                cycle;
                trace[i] = pc;
            end
            pause;
        end
    endtask

    // A11: cada campo de la tabla de params.vh (4b), en su rango de bits,
    // tiene que ser la senal interna del cpu (referencias jerarquicas, solo
    // simulacion). Asi la tabla, el RTL y uart_test.py no se desincronizan.
    task check_fields;
        begin
            check("A11 IF/ID.pc", latches[479:448], dut.id_pc);
            check("A11 IF/ID.instr", latches[447:416], dut.id_instr);
            check("A11 IF/ID.valid", {31'd0, latches[384]}, {31'd0, dut.id_valid});
            check("A11 ID/EX.pc", latches[383:352], dut.ex_pc);
            check("A11 ID/EX.rs1_data", latches[351:320], dut.ex_rs1_data);
            check("A11 ID/EX.rs2_data", latches[319:288], dut.ex_rs2_data);
            check("A11 ID/EX.imm", latches[287:256], dut.ex_imm);
            check("A11 ID/EX.rs1", {27'd0, latches[242:238]}, {27'd0, dut.ex_rs1});
            check("A11 ID/EX.rs2", {27'd0, latches[237:233]}, {27'd0, dut.ex_rs2});
            check("A11 ID/EX.rd", {27'd0, latches[232:228]}, {27'd0, dut.ex_rd});
            check("A11 ID/EX.funct3", {29'd0, latches[227:225]}, {29'd0, dut.ex_funct3});
            check("A11 ID/EX.funct7_b5", {31'd0, latches[224]}, {31'd0, dut.ex_funct7_b5});
            check("A11 ID/EX.reg_write", {31'd0, latches[207]}, {31'd0, dut.ex_reg_write});
            check("A11 ID/EX.alu_src_a", {31'd0, latches[206]}, {31'd0, dut.ex_alu_src_a});
            check("A11 ID/EX.alu_src_b", {31'd0, latches[205]}, {31'd0, dut.ex_alu_src_b});
            check("A11 ID/EX.mem_read", {31'd0, latches[204]}, {31'd0, dut.ex_mem_read});
            check("A11 ID/EX.mem_write", {31'd0, latches[203]}, {31'd0, dut.ex_mem_write});
            check("A11 ID/EX.result_src", {31'd0, latches[202]}, {31'd0, dut.ex_result_src});
            check("A11 ID/EX.branch", {31'd0, latches[201]}, {31'd0, dut.ex_branch});
            check("A11 ID/EX.jump", {31'd0, latches[200]}, {31'd0, dut.ex_jump});
            check("A11 ID/EX.jalr", {31'd0, latches[199]}, {31'd0, dut.ex_jalr});
            check("A11 ID/EX.alu_op", {30'd0, latches[198:197]}, {30'd0, dut.ex_alu_op});
            check("A11 ID/EX.halt", {31'd0, latches[196]}, {31'd0, dut.ex_halt});
            check("A11 ID/EX.uses_rs1", {31'd0, latches[195]}, {31'd0, dut.ex_uses_rs1});
            check("A11 ID/EX.uses_rs2", {31'd0, latches[194]}, {31'd0, dut.ex_uses_rs2});
            check("A11 ID/EX.illegal", {31'd0, latches[193]}, {31'd0, dut.ex_illegal});
            check("A11 ID/EX.valid", {31'd0, latches[192]}, {31'd0, dut.ex_valid});
            check("A11 EX/MEM.result", latches[191:160], dut.mem_result);
            check("A11 EX/MEM.store_data", latches[159:128], dut.mem_store_data);
            check("A11 EX/MEM.rd", {27'd0, latches[110:106]}, {27'd0, dut.mem_rd});
            check("A11 EX/MEM.funct3", {29'd0, latches[105:103]}, {29'd0, dut.mem_funct3});
            check("A11 EX/MEM.reg_write", {31'd0, latches[102]}, {31'd0, dut.mem_reg_write});
            check("A11 EX/MEM.mem_read", {31'd0, latches[101]}, {31'd0, dut.mem_mem_read});
            check("A11 EX/MEM.mem_write", {31'd0, latches[100]}, {31'd0, dut.mem_mem_write});
            check("A11 EX/MEM.result_src", {31'd0, latches[99]}, {31'd0, dut.mem_result_src});
            check("A11 EX/MEM.halt", {31'd0, latches[98]}, {31'd0, dut.mem_halt});
            check("A11 EX/MEM.illegal", {31'd0, latches[97]}, {31'd0, dut.mem_illegal});
            check("A11 EX/MEM.valid", {31'd0, latches[96]}, {31'd0, dut.mem_valid});
            check("A11 MEM/WB.result", latches[95:64], dut.wb_result);
            check("A11 MEM/WB.mem_data", latches[63:32], dut.wb_mem_data);
            check("A11 MEM/WB.rd", {27'd0, latches[9:5]}, {27'd0, dut.wb_rd});
            check("A11 MEM/WB.reg_write", {31'd0, latches[4]}, {31'd0, dut.wb_reg_write});
            check("A11 MEM/WB.result_src", {31'd0, latches[3]}, {31'd0, dut.wb_result_src});
            check("A11 MEM/WB.halt", {31'd0, latches[2]}, {31'd0, dut.wb_halt});
            check("A11 MEM/WB.illegal", {31'd0, latches[1]}, {31'd0, dut.wb_illegal});
            check("A11 MEM/WB.valid", {31'd0, latches[0]}, {31'd0, dut.wb_valid});
            check("A11 relleno 415:385", {1'd0, latches[415:385]}, 32'd0);
            check("A11 relleno 255:243", {19'd0, latches[255:243]}, 32'd0);
            check("A11 relleno 223:208", {16'd0, latches[223:208]}, 32'd0);
            check("A11 relleno 127:111", {15'd0, latches[127:111]}, 32'd0);
            check("A11 relleno 31:10", {10'd0, latches[31:10]}, 32'd0);
        end
    endtask

    //------------------------------------------------ Parte B: vectores
    reg [31:0]    vexp [0:95];          // cabecera y estado final
    reg [31:0]    vpasos [0:16383];     // 67 palabras por ciclo
    reg [31:0]    mem_ini [0:31];       // memoria antes de correr el programa
    reg [31:0]    mask;
    reg [31:0]    vidx [0:0];
    reg [8*128-1:0] vec_dir;
    reg [8*160-1:0] fname;
    reg [255:0]   pname;
    integer       p, n_programs, n_steps, base, step_err;
    reg [31:0]    st_cpu;

    task run_vector(input integer num);
        begin
            $sformat(fname, "%0sp%02d.prog", vec_dir, num);
            $readmemh(fname, prog);               // 256 palabras
            $sformat(fname, "%0sp%02d.exp", vec_dir, num);
            $readmemh(fname, vexp);               // 96 palabras
            pname = {vexp[8], vexp[9], vexp[10], vexp[11],
                     vexp[12], vexp[13], vexp[14], vexp[15]};
            if (vexp[0] !== 32'h5256_3332) begin
                $display("ERROR: %0s: archivo de vectores invalido", fname);
                errors = errors + 1;
            end
            n_prog  = vexp[1];
            n_steps = vexp[6];
            $sformat(fname, "%0sp%02d.pasos", vec_dir, num);
            $readmemh(fname, vpasos, 0, 67 * n_steps - 1);
            load_prog(256);                       // el .prog ya trae los HALT
            do_reset;
            // La memoria de datos no se borra: se anota como quedo.
            for (k = 0; k < 32; k = k + 1) begin
                rmem(k[7:0]); mem_ini[k] = rd_val;
            end
            step_err = errors;
            for (i = 1; i <= n_steps; i = i + 1) begin
                cycle;
                pause;                            // congelado mientras se lee
                base = 67 * (i - 1);
                mask = vpasos[base + 66];
                for (k = 0; k < 32; k = k + 1) begin
                    rreg(k[4:0]); check(pname, rd_val, vpasos[base + k]);
                    rmem(k[7:0]);
                    check(pname, rd_val, mask[k] ? vpasos[base + 32 + k] : mem_ini[k]);
                end
                check(pname, pc, vpasos[base + 64]);
                st_cpu = {29'd0, fault, 1'b0, halted};
                check(pname, st_cpu, vpasos[base + 65]);
                if (errors != step_err && shown < 40) begin
                    $display("       ^ %0s, despues del ciclo %0d", pname, i);
                    step_err = errors;
                end
            end
            // Con halted, enable se ignora: 3 ciclos mas no cambian nada.
            if (vexp[2] != 0) begin
                check("pasos = ciclos hasta halted", n_steps, vexp[2]);
                repeat (3) cycle;
                pause;
                check("estado final", {29'd0, fault, 1'b0, halted}, vexp[4]);
                check("PC final", pc, vexp[3]);
                mask = vexp[7];
                for (k = 0; k < 32; k = k + 1) begin
                    rreg(k[4:0]); check("registro final", rd_val, vexp[16 + k]);
                    rmem(k[7:0]);
                    check("memoria final", rd_val, mask[k] ? vexp[48 + k] : mem_ini[k]);
                end
                if (vexp[5] == 1) begin
                    for (k = 0; k < 15; k = k + 1)
                        check("latches finales", latches[32*k +: 32], vexp[80 + k]);
                end
                // Ciclos hasta halted, contados de nuevo desde un reset.
                do_reset;
                run_to_halt(5000);
                check("ciclos hasta halted", n_cycles, vexp[2]);
            end
            $display("  programa %0d %0s: %0d pasos verificados", num, pname, n_steps);
        end
    endtask

    //------------------------------------------------ Secuencia
    initial begin
        vec_dir = "testbench/vectores/";
        if ($value$plusargs("VEC=%s", vec_dir)) ;

        //------------------------------------ A1. x0 antes del primer reset
        rreg(5'd0); check("A1 x0 antes del reset", rd_val, 32'd0);

        //------------------------------------ A2. reset
        do_reset; #1;
        check("A2 PC tras reset", pc, 32'd0);
        check("A2 halted tras reset", {31'd0, halted}, 32'd0);
        check("A2 fault tras reset", {31'd0, fault}, 32'd0);
        if (latches !== LAT_RESET) begin
            $display("ERROR: A2 latches tras reset = %h", latches);
            errors = errors + 1;
        end
        check_regs_zero("A2 registros tras reset");
        for (k = 0; k < 32; k = k + 1) begin
            rmem(k[7:0]); check("A2 memoria inicial (FPGA recien configurada)", rd_val, 32'd0);
        end

        //------------------------------------ A3 + A4. HALT con 5 NOPs
        for (i = 0; i < 5; i = i + 1) prog[i] = NOP;
        prog[5] = HALT;
        load_prog(6);
        do_reset;
        // Ciclo 1 con enable = 1 Y un intento de escribir HALT en la palabra 3:
        // tiene que ignorarse (si no, el programa pararia antes).
        @(negedge clk);
        enable = 1'b1; imem_we = 1'b1; imem_addr = 8'd3; imem_data = HALT;
        @(posedge clk); #1;
        trace[0] = pc;
        @(negedge clk); imem_we = 1'b0;
        @(posedge clk); #1;
        trace[1] = pc;
        for (i = 2; i < 8; i = i + 1) begin
            @(negedge clk); @(posedge clk); #1;
            trace[i] = pc;
        end
        check("A4 halted tras 8 ciclos", {31'd0, halted}, 32'd0);
        @(negedge clk); @(posedge clk); #1;
        trace[8] = pc;
        pause;
        check("A4 halted tras 9 ciclos", {31'd0, halted}, 32'd1);
        check("A4 fault en HALT normal", {31'd0, fault}, 32'd0);
        for (i = 0; i < 9; i = i + 1)
            check("A4 PC paso a paso", trace[i], (i < 6) ? 4 * (i + 1) : 32'd24);
        if (latches !== LAT_HALT) begin
            $display("ERROR: A4 latches al detenerse = %h", latches);
            errors = errors + 1;
        end
        // A3: la palabra 3 sigue siendo NOP (no se escribio con enable = 1).
        // Se verifica indirectamente: el HALT llego a los 9 ciclos, no a los 7.

        //------------------------------------ A5. halted ignora enable
        take_snapshot;
        repeat (5) cycle;
        pause;
        compare_snapshot("A5 halted + enable");
        check("A5 halted se mantiene", {31'd0, halted}, 32'd1);

        //------------------------------------ A6. load-use: 1 stall exacto
        prog[0] = 32'h01500193;   // addi x3, x0, 21
        prog[1] = 32'h00302023;   // sw   x3, 0(x0)
        prog[2] = 32'h00002083;   // lw   x1, 0(x0)
        prog[3] = 32'h00108133;   // add  x2, x1, x1   (usa x1: stall)
        prog[4] = HALT;
        load_prog(5);
        do_reset;
        run_trace(9);
        check("A6 halted (stall)", {31'd0, halted}, 32'd1);
        rreg(5'd2); check("A6 x2 = 2 * 21", rd_val, 32'd42);
        // El PC se repite UNA vez (ciclo 5: stall) antes del HALT.
        check("A6 PC ciclo 1", trace[0], 32'd4);
        check("A6 PC ciclo 2", trace[1], 32'd8);
        check("A6 PC ciclo 3", trace[2], 32'd12);
        check("A6 PC ciclo 4", trace[3], 32'd16);
        check("A6 PC ciclo 5 (stall)", trace[4], 32'd16);
        check("A6 PC ciclo 6", trace[5], 32'd20);
        check("A6 PC ciclo 7", trace[6], 32'd20);
        // Sin stall si hay una instruccion en el medio: 1 ciclo menos en total.
        prog[3] = 32'h00700213;   // addi x4, x0, 7   (no usa x1)
        prog[4] = 32'h00108133;   // add  x2, x1, x1
        prog[5] = HALT;
        load_prog(6);
        do_reset;
        run_to_halt(50);
        check("A6 ciclos sin stall (5 instr + 4)", n_cycles, 32'd9);
        rreg(5'd2); check("A6 x2 sin stall", rd_val, 32'd42);

        //------------------------------------ A7. flush en beq tomado
        prog[0] = 32'h00000663;   // beq  x0, x0, 12   -> 0x0C
        prog[1] = 32'h00100093;   // addi x1, x0, 1    (descartada)
        prog[2] = 32'h00200113;   // addi x2, x0, 2    (descartada)
        prog[3] = 32'h00300193;   // addi x3, x0, 3
        prog[4] = HALT;
        load_prog(5);
        do_reset;
        run_trace(8);
        check("A7 halted en 8 ciclos (2 de penalidad)", {31'd0, halted}, 32'd1);
        rreg(5'd1); check("A7 x1 descartada", rd_val, 32'd0);
        rreg(5'd2); check("A7 x2 descartada", rd_val, 32'd0);
        rreg(5'd3); check("A7 x3 destino", rd_val, 32'd3);
        check("A7 PC ciclo 2", trace[1], 32'd8);
        check("A7 PC ciclo 3 (salto)", trace[2], 32'd12);
        check("A7 PC ciclo 5", trace[4], 32'd20);

        //------------------------------------ A8. enable = 0 congela todo
        // Programa: loop_bne (suma 10..1 = 55 en x2), escrito a mano.
        prog[0]  = 32'h00a00093;  // addi x1, x0, 10
        prog[1]  = 32'h00000113;  // addi x2, x0, 0
        prog[2]  = 32'h00110133;  // loop: add x2, x2, x1
        prog[3]  = 32'hfff08093;  // addi x1, x1, -1
        prog[4]  = 32'hfe009ce3;  // bne  x1, x0, loop
        prog[5]  = 32'h00202023;  // sw   x2, 0(x0)
        prog[6]  = HALT;
        load_prog(7);
        do_reset;
        repeat (20) cycle;
        pause;
        take_snapshot;
        for (i = 0; i < 50; i = i + 1) begin
            @(posedge clk); #1;
            if (pc !== snap_pc || latches !== snap_lat) begin
                $display("ERROR: A8 PC/latches cambiaron con enable = 0 (ciclo %0d)", i);
                errors = errors + 1;
            end
        end
        compare_snapshot("A8 enable = 0 (50 ciclos)");
        run_to_halt(500);
        // 7 instr. antes del HALT: 2 + 3*10 + 1 = 33; 9 saltos tomados (+18).
        check("A8 ciclos totales (20 + resto)", n_cycles + 20, 32'd55);
        rreg(5'd2); check("A8 x2 = 55", rd_val, 32'd55);
        rmem(8'd0); check("A8 mem[0] = 55", rd_val, 32'd55);

        //------------------------------------ A9. reset a mitad de corrida
        do_reset;
        repeat (25) cycle;
        pause;
        rreg(5'd2); check("A9 x2 a mitad de corrida != 0", (rd_val != 0), 32'd1);
        take_snapshot;                       // memoria antes del reset
        do_reset; #1;
        check("A9 PC tras reset", pc, 32'd0);
        if (latches !== LAT_RESET) begin
            $display("ERROR: A9 latches tras reset = %h", latches);
            errors = errors + 1;
        end
        check_regs_zero("A9 registros tras reset");
        check_mem_snapshot("A9 la memoria de datos NO se borra");
        rmem(8'd0); check("A9 mem[0] conserva 55", rd_val, 32'd55);
        run_to_halt(500);
        check("A9 mismo programa, mismos ciclos", n_cycles, 32'd55);
        rreg(5'd2); check("A9 memoria de programa conservada", rd_val, 32'd55);

        //------------------------------------ A10. parada por error
        prog[0] = 32'h00700093;   // addi x1, x0, 7
        prog[1] = 32'hffffffff;   // ilegal
        prog[2] = 32'h06300113;   // addi x2, x0, 99 (no se ejecuta)
        load_prog(3);
        do_reset;
        run_to_halt(50);
        check("A10 halted por error", {31'd0, halted}, 32'd1);
        check("A10 fault", {31'd0, fault}, 32'd1);
        check("A10 ciclos (como un HALT)", n_cycles, 32'd5);
        rreg(5'd2); check("A10 x2 no se escribe", rd_val, 32'd0);
        repeat (4) cycle;
        pause;
        check("A10 fault se mantiene con enable", {31'd0, fault}, 32'd1);
        do_reset; #1;
        check("A10 halted tras reset", {31'd0, halted}, 32'd0);
        check("A10 fault tras reset", {31'd0, fault}, 32'd0);

        //------------------------------------ A11. campos de los latches
        // Programa con loads, stores y forwarding (memoria.asm, vector 6):
        // se mira cada ciclo hasta el HALT.
        $sformat(fname, "%0sp06.prog", vec_dir);
        $readmemh(fname, prog);
        load_prog(256);
        do_reset;
        check_fields;
        for (i = 0; i < 32; i = i + 1) begin
            cycle;
            check_fields;
        end
        pause;

        //------------------------------------ Parte B
        $sformat(fname, "%0sindice.mem", vec_dir);
        vidx[0] = 32'd0;
        $readmemh(fname, vidx);
        n_programs = vidx[0];
        if (n_programs == 0) begin
            $display("ERROR: no hay vectores en %0s (correr rv32i_model.py --generar)", vec_dir);
            errors = errors + 1;
        end
        for (p = 0; p < n_programs; p = p + 1)
            run_vector(p);

        if (errors == 0) $display("PASS: cpu cumple el contrato (partes A y B, %0d programas)", n_programs);
        else             $display("FAIL: %0d errores", errors);
        $finish;
    end

    initial begin
        #50_000_000;
        $display("FAIL: timeout");
        $finish;
    end

endmodule

`default_nettype wire
