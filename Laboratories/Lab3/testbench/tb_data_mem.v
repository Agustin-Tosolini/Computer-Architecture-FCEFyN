`timescale 1ns / 1ps
`default_nettype none

module tb_data_mem;
    reg clk = 0;
    always #5 clk = ~clk;
    reg reset = 0, enable = 1, re = 0, we = 0;
    reg [31:0] addr = 0, wdata = 0;
    reg [2:0] funct3 = 0;
    reg [7:0] dbg_addr = 0;
    wire [31:0] rdata, dbg_data;
    wire access_error;
    integer errors = 0;
    integer k;

    data_mem dut (
        .i_clk(clk), .i_reset(reset), .i_enable(enable),
        .i_addr(addr), .i_wdata(wdata), .i_re(re), .i_we(we), .i_funct3(funct3),
        .o_rdata(rdata), .o_access_error(access_error),
        .i_dbg_addr(dbg_addr), .o_dbg_data(dbg_data)
    );

    task check;
        input [8*60-1:0] label;
        input [31:0] got, expected;
        begin
            if (got !== expected) begin
                $display("ERROR %0s: recibido %h, esperado %h", label, got, expected);
                errors = errors + 1;
            end
        end
    endtask

    task store;
        input [31:0] address, value;
        input [2:0] kind;
        input expected_error;
        begin
            @(negedge clk); addr = address; wdata = value; funct3 = kind; re = 0; we = 1;
            #1; check("error de STORE", access_error, expected_error);
            @(posedge clk); #1;
            @(negedge clk); we = 0;
        end
    endtask

    task load;
        input [31:0] address;
        input [2:0] kind;
        input [31:0] expected;
        input expected_error;
        begin
            @(negedge clk); addr = address; funct3 = kind; re = 1; we = 0;
            // Antes del flanco siguiente: lectura combinacional.
            #1;
            check("dato de LOAD", rdata, expected);
            check("error de LOAD", access_error, expected_error);
        end
    endtask

    task debug_word;
        input [7:0] address;
        input [31:0] expected;
        begin
            dbg_addr = address; #1;
            check("lectura de debug", dbg_data, expected);
        end
    endtask

    initial begin
        for (k = 0; k < 32; k = k + 1) debug_word(k, 0);
        store(0, 32'h12345678, 3'b010, 0);
        // Cada SB altera solo su byte; los bits altos de wdata se ignoran.
        store(0, 32'hAABBCC11, 3'b000, 0); debug_word(0, 32'h12345611);
        store(1, 32'hAABBCC22, 3'b000, 0); debug_word(0, 32'h12342211);
        store(2, 32'hAABBCC80, 3'b000, 0); debug_word(0, 32'h12802211);
        store(3, 32'hAABBCCFF, 3'b000, 0); debug_word(0, 32'hFF802211);
        load(0, 3'b010, 32'hFF802211, 0);
        load(0, 3'b000, 32'h11, 0);
        load(1, 3'b100, 32'h22, 0);
        load(2, 3'b000, 32'hFFFFFF80, 0);
        load(2, 3'b100, 32'h00000080, 0);
        load(3, 3'b000, 32'hFFFFFFFF, 0);
        load(3, 3'b100, 32'h000000FF, 0);
        load(0, 3'b001, 32'h00002211, 0);
        load(2, 3'b001, 32'hFFFFFF80, 0);
        load(2, 3'b101, 32'h0000FF80, 0);

        store(0, 32'h12348001, 3'b001, 0); debug_word(0, 32'hFF808001);
        store(2, 32'hDEAD7FFF, 3'b001, 0); debug_word(0, 32'h7FFF8001);
        load(0, 3'b001, 32'hFFFF8001, 0);
        load(0, 3'b101, 32'h00008001, 0);
        load(2, 3'b001, 32'h00007FFF, 0);

        // Extremos de RAM y puerto debug independiente del puerto CPU.
        store(124, 32'h89ABCDEF, 3'b010, 0);
        load(124, 3'b010, 32'h89ABCDEF, 0);
        debug_word(0, 32'h7FFF8001);
        debug_word(31, 32'h89ABCDEF);
        store(127, 32'h12, 3'b000, 0); debug_word(31, 32'h12ABCDEF);
        store(126, 32'hFEDC, 3'b001, 0); debug_word(31, 32'hFEDCCDEF);
        load(127, 3'b000, 32'hFFFFFFFE, 0);
        load(126, 3'b101, 32'hFEDC, 0);

        debug_word(32, 0);
        debug_word(63, 0);
        debug_word(255, 0);

        // Errores no deben sobrescribir otra palabra por truncar la direccion.
        store(128, 32'hFFFFFFFF, 3'b010, 1);
        store(32'hFFFFFFFC, 32'hFFFFFFFF, 3'b010, 1);
        store(1, 0, 3'b001, 1);
        store(2, 0, 3'b010, 1);
        store(127, 0, 3'b001, 1);
        for (k = 3; k < 8; k = k + 1) store(0, 0, k, 1);
        debug_word(0, 32'h7FFF8001); debug_word(31, 32'hFEDCCDEF);
        load(128, 3'b010, 0, 1);
        load(32'hFFFFFFFF, 3'b100, 0, 1);
        load(1, 3'b001, 0, 1);
        load(2, 3'b010, 0, 1);
        load(0, 3'b011, 0, 1);
        load(0, 3'b110, 0, 1);
        load(0, 3'b111, 0, 1);

        @(negedge clk); re = 0; we = 0;
        #1; check("sin solicitud no hay error", access_error, 0);
        check("sin LOAD dato cero", rdata, 0);
        @(negedge clk); addr = 0; funct3 = 2; re = 1; we = 1; wdata = 0;
        #1; check("LOAD y STORE simultaneos rechazados", access_error, 1);
        check("lectura conflictiva cero", rdata, 0);
        @(posedge clk); #1; debug_word(0, 32'h7FFF8001);

        @(negedge clk); re = 0; we = 0; enable = 0;
        store(0, 0, 3'b010, 0); debug_word(0, 32'h7FFF8001);
        load(0, 3'b010, 32'h7FFF8001, 0); // La pausa no bloquea lecturas.
        @(negedge clk); reset = 1; enable = 1;
        store(0, 0, 3'b010, 0); debug_word(0, 32'h7FFF8001);
        @(negedge clk); reset = 0;
        debug_word(31, 32'hFEDCCDEF); // Reset conserva toda la RAM.

        // Escritura visible despues del flanco, sin bypass anticipado.
        @(negedge clk); addr = 4; dbg_addr = 1; wdata = 32'hA5A55A5A;
        funct3 = 2; re = 0; we = 1;
        #1; check("antes del flanco", dbg_data, 0);
        @(posedge clk); #1; check("despues del flanco", dbg_data, 32'hA5A55A5A);
        @(negedge clk); we = 0;
        load(4, 3'b010, 32'hA5A55A5A, 0);
        if (errors != 0) $fatal(1, "FAIL: %0d errores", errors);
        $display("PASS: data_mem");
        $finish;
    end

    initial begin
        #20000;
        $fatal(1, "Timeout global");
    end
endmodule

`default_nettype wire
