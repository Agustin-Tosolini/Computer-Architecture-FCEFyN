`timescale 1ns / 1ps
`default_nettype none

module tb_ex_mem;
    reg clk = 0;
    always #5 clk = ~clk;
    reg reset = 1, enable = 0;
    reg [31:0] result = 0, store_data = 0;
    reg [4:0] rd = 0;
    reg [2:0] funct3 = 0;
    reg reg_write = 0, mem_read = 0, mem_write = 0, result_src = 0;
    reg halt = 0, illegal = 0, valid = 0;
    wire [31:0] out_result, out_store;
    wire [4:0] out_rd;
    wire [2:0] out_funct3;
    wire out_rw, out_mr, out_mw, out_src, out_halt, out_illegal, out_valid;
    wire [78:0] observed = {out_result, out_store, out_rd, out_funct3,
                            out_rw, out_mr, out_mw, out_src,
                            out_halt, out_illegal, out_valid};
    reg [78:0] held;
    integer errors = 0;

    ex_mem dut (
        .i_clk(clk), .i_reset(reset), .i_enable(enable),
        .i_result(result), .i_store_data(store_data), .i_rd(rd), .i_funct3(funct3),
        .i_reg_write(reg_write), .i_mem_read(mem_read), .i_mem_write(mem_write),
        .i_result_src(result_src), .i_halt(halt), .i_illegal(illegal), .i_valid(valid),
        .o_result(out_result), .o_store_data(out_store), .o_rd(out_rd), .o_funct3(out_funct3),
        .o_reg_write(out_rw), .o_mem_read(out_mr), .o_mem_write(out_mw),
        .o_result_src(out_src), .o_halt(out_halt), .o_illegal(out_illegal), .o_valid(out_valid)
    );

    task check;
        input [8*60-1:0] label;
        input [78:0] expected;
        begin
            if (observed !== expected) begin
                $display("ERROR %0s: recibido %h, esperado %h", label, observed, expected);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        @(posedge clk); #1; check("reset con CPU pausada", 79'd0);

        // STORE: direccion y dato son distintos y deben viajar juntos.
        @(negedge clk);
        reset = 0; enable = 1; valid = 1;
        result = 32'h00000044; store_data = 32'h89ABCDEF;
        funct3 = 3'b010; mem_write = 1;
        #1; check("sin captura antes del flanco", 79'd0);
        @(posedge clk); #1;
        check("STORE", {32'h44, 32'h89ABCDEF, 5'd0, 3'b010, 7'b0010001});
        held = observed;

        // La pausa conserva el STORE aunque la entrada pase a burbuja.
        @(negedge clk); enable = 0; valid = 0; result = 0; store_data = 0;
        mem_write = 0;
        repeat (3) begin
            @(posedge clk); #1; check("pausa conserva todos los campos", held);
        end

        // LOAD y resultado EX: comprobar controles y destino x31.
        @(negedge clk); enable = 1; valid = 1;
        result = 32'h00000080; rd = 31; funct3 = 3'b101;
        reg_write = 1; mem_read = 1; result_src = 1;
        @(posedge clk); #1;
        check("LOAD sin signo", {32'h80, 32'd0, 5'd31, 3'b101, 7'b1101001});
        @(negedge clk); result = 32'hFFFFFFFB; rd = 3;
        funct3 = 0; mem_read = 0; result_src = 0;
        @(posedge clk); #1;
        check("resultado de EX", {32'hFFFFFFFB, 32'd0, 5'd3, 3'd0, 7'b1000001});

        // Un JAL/JALR ya llega con PC+4 seleccionado por la logica de EX.
        @(negedge clk); result = 32'h24; rd = 1;
        @(posedge clk); #1;
        check("direccion de retorno", {32'h24, 32'd0, 5'd1, 3'd0, 7'b1000001});

        @(negedge clk); result = 0; rd = 0; reg_write = 0; halt = 1;
        @(posedge clk); #1;
        check("HALT valido se conserva", {72'd0, 7'b0000101});
        @(negedge clk); halt = 0; illegal = 1;
        @(posedge clk); #1;
        check("indicacion de instruccion ilegal", {72'd0, 7'b0000011});

        // Una burbuja elimina incluso controles de entrada activos.
        @(negedge clk); valid = 0; halt = 1;
        reg_write = 1; mem_read = 1; mem_write = 1; result_src = 1;
        result = 32'hFFFFFFFF; store_data = 32'hFFFFFFFF;
        @(posedge clk); #1; check("burbuja sin efectos", 79'd0);
        @(negedge clk); valid = 1;
        @(posedge clk); #1;
        check("recupera captura", {32'hFFFFFFFF, 32'hFFFFFFFF, 5'd0, 3'd0, 7'b1111111});
        @(negedge clk); reset = 1; enable = 0;
        @(posedge clk); #1; check("reset gana a pausa", 79'd0);

        if (errors != 0) $fatal(1, "FAIL: %0d errores", errors);
        $display("PASS: ex_mem");
        $finish;
    end

    initial begin
        #10000;
        $fatal(1, "Timeout global");
    end
endmodule

`default_nettype wire
