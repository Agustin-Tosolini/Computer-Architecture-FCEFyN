`timescale 1ns / 1ps
`default_nettype none

//------------------------------------------------------------------------------
// Testbench del cpu_stub.
//
// Maneja las senales del contrato directamente (sin UART), haciendo a mano lo
// que despues va a hacer la debug_unit. Cada prueba compara contra el valor
// esperado e imprime ERROR si no coincide. Al final: PASS o FAIL.
//
// Convencion para evitar carreras: las entradas se cambian en el flanco de
// BAJADA y se verifican despues del flanco de SUBIDA.
//
// Pruebas:
//   1. Estado inicial: PC = 0, halted = 0, memoria vacia (todo HALT).
//   2. Carga de programa por el puerto de escritura y verificacion por el
//      puerto de debug.
//   3. Con enable = 0 no cambia nada (ni siquiera mientras se carga memoria).
//   4. Paso a paso: cada ciclo con enable avanza el PC exactamente 4.
//   5. Registros y latches reconocibles en funcion del PC.
//   6. Correr hasta halted: el PC se congela en el HALT y halted sube 3 ciclos
//      despues (misma latencia que el pipeline real).
//   7. Con halted = 1, enable se ignora.
//   8. cpu_reset: PC y halted a 0, la memoria se conserva.
//   9. Reprogramacion dinamica: se pisa una palabra con HALT y se vuelve a
//      correr; ahora para antes.
//------------------------------------------------------------------------------
module tb_cpu_stub;

    //------------------------------------------------ Clock
    reg clk = 1'b0;
    always #5 clk = ~clk;                 // 100 MHz

    //------------------------------------------------ DUT
    reg          cpu_reset    = 1'b0;
    reg          enable       = 1'b0;
    reg          imem_we      = 1'b0;
    reg  [7:0]   imem_addr    = 8'd0;
    reg  [31:0]  imem_data    = 32'd0;
    reg  [4:0]   dbg_reg_addr = 5'd0;
    wire [31:0]  dbg_reg_data;
    reg  [7:0]   dbg_mem_addr = 8'd0;
    wire [31:0]  dbg_mem_data;
    wire [31:0]  pc;
    wire [383:0] latches;
    wire         halted;

    cpu_stub dut
    (
        .i_clk          (clk),
        .i_cpu_reset    (cpu_reset),
        .i_enable       (enable),
        .i_imem_we      (imem_we),
        .i_imem_addr    (imem_addr),
        .i_imem_data    (imem_data),
        .i_dbg_reg_addr (dbg_reg_addr),
        .o_dbg_reg_data (dbg_reg_data),
        .i_dbg_mem_addr (dbg_mem_addr),
        .o_dbg_mem_data (dbg_mem_data),
        .o_pc           (pc),
        .o_latches      (latches),
        .o_halted       (halted)
    );

    //------------------------------------------------ Programa de prueba
    // 4 instrucciones reales (codificadas a mano, ver P&H 2.5) + HALT implicito
    // (la memoria vacia ya vale 0x00000000).
    localparam N_PROG = 4;
    reg [31:0] prog [0:N_PROG-1];
    initial begin
        prog[0] = 32'h0050_0093;   // addi x1, x0, 5
        prog[1] = 32'h0070_0113;   // addi x2, x0, 7
        prog[2] = 32'h0020_81B3;   // add  x3, x1, x2
        prog[3] = 32'h0030_2023;   // sw   x3, 0(x0)
    end                            // [4]  0x00000000 = HALT

    //------------------------------------------------ Utilidades
    integer errors = 0;
    integer i;
    integer n_cycles;

    task check(input [8*40-1:0] what, input [31:0] got, input [31:0] exp);
        if (got !== exp) begin
            $display("ERROR: %0s = %h, esperado %h", what, got, exp);
            errors = errors + 1;
        end
    endtask

    // Escribe una palabra en la memoria de programa (lo que hara la debug_unit).
    task imem_write(input [7:0] addr, input [31:0] data);
        begin
            @(negedge clk);
            imem_we   = 1'b1;
            imem_addr = addr;
            imem_data = data;
            @(negedge clk);
            imem_we   = 1'b0;
        end
    endtask

    // Un pulso de reset del procesador.
    task do_cpu_reset;
        begin
            @(negedge clk);
            cpu_reset = 1'b1;
            @(negedge clk);
            cpu_reset = 1'b0;
        end
    endtask

    // Un solo ciclo con enable = 1 (comando 'S').
    task step;
        begin
            @(negedge clk);
            enable = 1'b1;
            @(negedge clk);
            enable = 1'b0;
        end
    endtask

    // enable = 1 hasta halted o hasta max ciclos (comando 'R').
    // Devuelve en n_cycles cuantos flancos hicieron falta.
    task run_until_halted(input integer max);
        begin
            n_cycles = 0;
            @(negedge clk);
            enable = 1'b1;
            while (!halted && n_cycles < max) begin
                @(posedge clk); #1;
                n_cycles = n_cycles + 1;
            end
            @(negedge clk);
            enable = 1'b0;
        end
    endtask

    //------------------------------------------------ Secuencia
    initial begin
        //---------------------------------------- 1. Estado inicial
        #1;
        check("PC inicial",      pc,     32'd0);
        check("halted inicial",  {31'd0, halted}, 32'd0);
        dbg_mem_addr = 8'd0; #1;
        check("imem[0] inicial", dbg_mem_data, 32'h0000_0000);

        //---------------------------------------- 2 y 3. Carga con enable = 0
        for (i = 0; i < N_PROG; i = i + 1)
            imem_write(i[7:0], prog[i]);

        for (i = 0; i < N_PROG + 1; i = i + 1) begin
            dbg_mem_addr = i[7:0]; #1;
            check("imem leida", dbg_mem_data, (i < N_PROG) ? prog[i] : 32'h0);
        end
        check("PC tras la carga (enable=0)", pc, 32'd0);

        repeat (10) @(posedge clk); #1;
        check("PC con enable=0", pc, 32'd0);

        //---------------------------------------- 4. Paso a paso
        step; #1;  check("PC tras 1 paso",  pc, 32'd4);
        step; #1;  check("PC tras 2 pasos", pc, 32'd8);

        //---------------------------------------- 5. Registros y latches (PC = 8)
        dbg_reg_addr = 5'd0;  #1; check("x0",  dbg_reg_data, 32'h0000_0000);
        dbg_reg_addr = 5'd5;  #1; check("x5",  dbg_reg_data, 32'h0008_0005);
        dbg_reg_addr = 5'd31; #1; check("x31", dbg_reg_data, 32'h0008_001F);
        check("latch palabra 0",  latches[  0 +: 32], 32'hA000_0008);
        check("latch palabra 3",  latches[ 96 +: 32], 32'hA300_0008);
        check("latch palabra 11", latches[352 +: 32], 32'hAB00_0008);

        //---------------------------------------- 6. Correr hasta halted
        // Desde PC = 8: 2 ciclos hasta PC = 0x10 (HALT), 1 ciclo en que el
        // HALT pasa a "ID" y 3 de vaciado  ->  6 ciclos.
        run_until_halted(100);
        check("halted tras correr", {31'd0, halted}, 32'd1);
        check("PC final (en el HALT)", pc, 32'h0000_0010);
        check("ciclos hasta halted", n_cycles, 32'd6);

        //---------------------------------------- 7. enable ignorado si halted
        step; step; #1;
        check("PC con halted + enable", pc, 32'h0000_0010);
        check("halted se mantiene",     {31'd0, halted}, 32'd1);

        //---------------------------------------- 8. cpu_reset
        do_cpu_reset; #1;
        check("PC tras reset",     pc, 32'd0);
        check("halted tras reset", {31'd0, halted}, 32'd0);
        dbg_mem_addr = 8'd0; #1;
        check("imem[0] tras reset (se conserva)", dbg_mem_data, prog[0]);

        //---------------------------------------- 9. Reprogramacion dinamica
        // HALT en la palabra 2: corre 0 -> 4 -> 8 (2 ciclos) + 1 + 3 = 6 ciclos.
        imem_write(8'd2, 32'h0000_0000);
        run_until_halted(100);
        check("PC final reprogramado", pc, 32'h0000_0008);
        check("ciclos reprogramado",   n_cycles, 32'd6);

        //---------------------------------------- Resultado
        if (errors == 0) $display("PASS: cpu_stub cumple el contrato");
        else             $display("FAIL: %0d errores", errors);
        $finish;
    end

endmodule

`default_nettype wire
