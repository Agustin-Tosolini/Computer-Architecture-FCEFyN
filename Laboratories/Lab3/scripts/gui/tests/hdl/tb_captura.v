`timescale 1ns / 1ps
`default_nettype none

//------------------------------------------------------------------------------
// tb_captura — Captura los bytes que manda la FPGA (top completo con el cpu
// real) para probar el decodificador de Python contra volcados REALES.
//
// Lo usa scripts/gui/tests/test_captura_rtl.py (no es parte de testbench/).
//
// Una uart "PC" carga el programa con 'L' y manda la secuencia de comandos
// D S S S S S R D. Por cada volcado escribe en el archivo de salida:
//   REF <pc> <ciclos> <estado> <x0..x31> <mem0..mem31> <latches>
//       valores internos del diseno en ese momento (el procesador esta
//       congelado mientras se manda el volcado)
//   DUMP <los 326 bytes recibidos, en hex>
//
// Plusargs: +PROG=archivo (una palabra hex por linea, $readmemh)
//           +N=cantidad de palabras   +SALIDA=archivo de salida
// A 1 Mbaud solo en simulacion (el diseno sigue en 115200).
//------------------------------------------------------------------------------
module tb_captura;

    localparam CLK_FREQ  = 100_000_000;
    localparam BAUD_RATE = 1_000_000;
    localparam FRAME_NS  = 10 * (1_000_000_000 / BAUD_RATE);
    localparam DUMP_LEN  = 326;

    reg clk = 1'b0;
    always #5 clk = ~clk;

    wire line_pc_to_fpga, line_fpga_to_pc;
    wire [7:0] leds;

    // CLK_FREQ explicito (el default del top es 70 MHz) y sin clk_wiz (iverilog
    // no simula el IP de Xilinx): clk = i_clk, de 10 ns.
    top #(.CLK_FREQ(CLK_FREQ), .USE_CLK_WIZ(0), .BAUD_RATE(BAUD_RATE), .USE_CPU_STUB(0)) dut
    (
        .i_clk(clk), .i_reset(1'b0), .i_rx(line_pc_to_fpga), .o_tx(line_fpga_to_pc), .o_leds(leds)
    );

    reg        pc_reset = 1'b1, pc_tx_start = 1'b0;
    reg  [7:0] pc_din = 8'h00;
    wire       pc_tx_done, pc_rx_done;
    wire [7:0] pc_dout;

    uart #(.CLK_FREQ(CLK_FREQ), .BAUD_RATE(BAUD_RATE)) pc
    (
        .i_clk(clk), .i_reset(pc_reset), .i_rx(line_fpga_to_pc), .o_tx(line_pc_to_fpga),
        .o_rx_done(pc_rx_done), .o_dout(pc_dout), .i_tx_start(pc_tx_start), .i_din(pc_din),
        .o_tx_done(pc_tx_done)
    );

    // Bytes recibidos
    reg [7:0] rx_buf [0:4095];
    integer   n_recv = 0, n_leidos = 0;
    always @(posedge clk)
        if (pc_rx_done) begin
            rx_buf[n_recv[11:0]] = pc_dout;
            n_recv = n_recv + 1;
        end

    task enviar(input [7:0] b);
        begin
            @(negedge clk); pc_din = b; pc_tx_start = 1'b1;
            @(negedge clk); pc_tx_start = 1'b0;
            @(posedge pc_tx_done); @(posedge clk);
        end
    endtask

    task esperar_bytes(input integer n);
        begin : espera
            integer limite;
            limite = 0;
            while (n_recv < n_leidos + n && limite < 100000) begin
                #(FRAME_NS / 10);
                limite = limite + 1;
            end
            if (n_recv < n_leidos + n) begin
                $display("FAIL: timeout esperando %0d bytes", n);
                $finish;
            end
        end
    endtask

    reg [31:0] prog [0:255];
    integer    n_prog, salida, i, k;
    reg [8*256-1:0] f_prog, f_salida;

    // Valores internos (el procesador esta congelado durante el volcado).
    task anotar_ref;
        begin
            $fwrite(salida, "REF %h %h %h", dut.pc, dut.u_debug_unit.cycles, dut.u_debug_unit.status);
            for (k = 0; k < 32; k = k + 1)
                $fwrite(salida, " %h", (k == 0) ? 32'd0 : dut.g_cpu.u_cpu.u_regs.regs[k]);
            for (k = 0; k < 32; k = k + 1)
                $fwrite(salida, " %h", dut.g_cpu.u_cpu.u_dmem.mem[k]);
            $fwrite(salida, " %h\n", dut.latches);
        end
    endtask

    task comando_con_volcado(input [7:0] cmd);
        begin
            enviar(cmd);
            esperar_bytes(1);
            anotar_ref;                       // ya empezo el volcado: congelado
            esperar_bytes(DUMP_LEN);
            $fwrite(salida, "DUMP");
            for (k = 0; k < DUMP_LEN; k = k + 1)
                $fwrite(salida, " %h", rx_buf[(n_leidos + k) % 4096]);
            $fwrite(salida, "\n");
            n_leidos = n_leidos + DUMP_LEN;
            #(FRAME_NS * 2);
        end
    endtask

    initial begin
        if (!$value$plusargs("PROG=%s", f_prog) || !$value$plusargs("N=%d", n_prog) ||
            !$value$plusargs("SALIDA=%s", f_salida)) begin
            $display("FAIL: faltan +PROG, +N o +SALIDA");
            $finish;
        end
        $readmemh(f_prog, prog, 0, n_prog - 1);
        salida = $fopen(f_salida, "w");
        repeat (5) @(posedge clk);
        pc_reset = 1'b0;
        repeat (40) @(posedge clk);
        // 'L' + N + palabras (little-endian)
        enviar(8'h4C); enviar(n_prog[7:0]); enviar(n_prog[15:8]);
        for (i = 0; i < n_prog; i = i + 1) begin
            enviar(prog[i][7:0]); enviar(prog[i][15:8]); enviar(prog[i][23:16]); enviar(prog[i][31:24]);
        end
        esperar_bytes(1);
        if (rx_buf[n_leidos % 4096] !== 8'h4B) begin
            $display("FAIL: no llego 'K'");
            $finish;
        end
        n_leidos = n_leidos + 1;
        comando_con_volcado(8'h44);                         // 'D'
        for (i = 0; i < 5; i = i + 1) comando_con_volcado(8'h53);   // 'S' x 5
        comando_con_volcado(8'h52);                         // 'R'
        comando_con_volcado(8'h44);                         // 'D'
        $fclose(salida);
        $display("PASS: captura terminada");
        $finish;
    end

    initial begin
        #200_000_000;
        $display("FAIL: timeout global");
        $finish;
    end
endmodule

`default_nettype wire
