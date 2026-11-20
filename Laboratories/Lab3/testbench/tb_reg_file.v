`timescale 1ns / 1ps
`default_nettype none

// Prueba autonoma: reset, escritura, x0, bypass, pausa y puerto de debug.
// Entradas en flanco de bajada; comprobaciones separadas del flanco de subida.
module tb_reg_file;
    reg clk = 1'b0;
    always #5 clk = ~clk;

    reg reset = 1'b1;
    reg enable = 1'b0;
    reg we = 1'b0;
    reg [4:0] rs1 = 0, rs2 = 0, rd = 0, dbg_addr = 0;
    reg [31:0] wdata = 0;
    wire [31:0] rs1_data, rs2_data, dbg_data;
    integer errors = 0;
    integer k;

    reg_file dut (
        .i_clk(clk), .i_reset(reset), .i_enable(enable),
        .i_rs1(rs1), .i_rs2(rs2),
        .o_rs1_data(rs1_data), .o_rs2_data(rs2_data),
        .i_we(we), .i_rd(rd), .i_wdata(wdata),
        .i_dbg_addr(dbg_addr), .o_dbg_data(dbg_data)
    );

    task check;
        input [8*64-1:0] label;
        input [31:0] actual, expected;
        begin
            if (actual !== expected) begin
                $display("ERROR: %0s: recibido %h, esperado %h", label, actual, expected);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        @(negedge clk);
        reset = 0;
        for (k = 0; k < 32; k = k + 1) begin
            dbg_addr = k;
            #1;
            check("reset inicial", dbg_data, 0);
        end

        // Escribir y leer todos los registros modificables, incluido x31.
        for (k = 1; k < 32; k = k + 1) begin
            @(negedge clk);
            enable = 1; we = 1; rd = k; wdata = 32'h1000 + k;
            @(posedge clk); #1;
            dbg_addr = k; #1;
            check("escritura y debug", dbg_data, 32'h1000 + k);
        end

        // Los dos operandos ven el dato nuevo ANTES del flanco; debug no.
        @(negedge clk);
        rd = 3; rs1 = 3; rs2 = 3; dbg_addr = 3; wdata = 8;
        #1;
        check("bypass rs1", rs1_data, 8);
        check("bypass rs2", rs2_data, 8);
        check("debug sin bypass", dbg_data, 32'h1003);
        @(posedge clk); #1;
        check("debug tras flanco", dbg_data, 8);

        // Leer dos registros distintos, sin solicitud de escritura.
        @(negedge clk);
        we = 0; rs1 = 3; rs2 = 31; wdata = 99;
        #1;
        check("sin we no hay bypass", rs1_data, 8);
        check("segunda lectura independiente", rs2_data, 32'h101F);
        @(posedge clk); #1;
        check("sin we no escribe", dbg_data, 8);

        // La pausa bloquea tanto la escritura como el bypass de ambos puertos.
        @(negedge clk);
        enable = 0; we = 1; rs2 = 3;
        #1;
        check("pausa rs1", rs1_data, 8);
        check("pausa rs2", rs2_data, 8);
        @(posedge clk); #1;
        check("pausa conserva registro", dbg_data, 8);

        // x0 no acepta escrituras ni bypass y siempre se lee como cero.
        @(negedge clk);
        enable = 1; rd = 0; rs1 = 0; rs2 = 0; dbg_addr = 0;
        wdata = 32'hFFFFFFFF;
        #1;
        check("x0 rs1", rs1_data, 0);
        check("x0 rs2", rs2_data, 0);
        @(posedge clk); #1;
        check("x0 debug", dbg_data, 0);

        // Reset tiene prioridad incluso con escritura solicitada y CPU pausada.
        @(negedge clk);
        reset = 1; enable = 0; rd = 3; rs1 = 3;
        @(posedge clk); #1;
        @(negedge clk);
        reset = 0; we = 0;
        for (k = 0; k < 32; k = k + 1) begin
            dbg_addr = k; #1;
            check("reset final", dbg_data, 0);
        end

        if (errors != 0)
            $fatal(1, "FAIL: %0d errores", errors);
        $display("PASS: reg_file");
        $finish;
    end
endmodule

`default_nettype wire
