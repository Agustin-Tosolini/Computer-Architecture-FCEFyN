`timescale 1ns / 1ps
`default_nettype none
module tb_mem_wb;
    reg clk = 0;
    always #5 clk = ~clk;
    reg reset = 1, enable = 0;
    // result, mem_data, rd, reg_write, result_src, halt, illegal, valid.
    reg [73:0] payload = 0;
    wire [73:0] observed;
    reg [73:0] held;
    mem_wb dut (
        .i_clk(clk), .i_reset(reset), .i_enable(enable),
        .i_result(payload[73:42]), .i_mem_data(payload[41:10]),
        .i_rd(payload[9:5]), .i_reg_write(payload[4]),
        .i_result_src(payload[3]), .i_halt(payload[2]),
        .i_illegal(payload[1]), .i_valid(payload[0]),
        .o_result(observed[73:42]), .o_mem_data(observed[41:10]),
        .o_rd(observed[9:5]), .o_reg_write(observed[4]),
        .o_result_src(observed[3]), .o_halt(observed[2]),
        .o_illegal(observed[1]), .o_valid(observed[0])
    );
    task check;
        input [73:0] expected;
        begin
            if (observed !== expected)
                $fatal(1, "MEM/WB recibido %h esperado %h", observed, expected);
        end
    endtask
    initial begin
        @(posedge clk); #1; check(74'd0);
        // LOAD: direccion EX y dato leido distintos, destino x31.
        @(negedge clk); reset = 0; enable = 1;
        payload = {32'd124, 32'hFFFFFF80, 5'd31, 5'b11001};
        #1; check(74'd0);
        @(posedge clk); #1; check(payload); held = observed;
        // Pausa conserva incluso cuando llega una burbuja.
        @(negedge clk); enable = 0; payload = 0;
        repeat (3) begin @(posedge clk); #1; check(held); end
        @(negedge clk); enable = 1;
        @(posedge clk); #1; check(74'd0);
        // ALU y PC+4 usan resultado EX, no dato de memoria.
        @(negedge clk); payload = {32'hFFFFFFFB, 32'h12345678, 5'd3, 5'b10001};
        @(posedge clk); #1; check(payload);
        @(negedge clk); payload = {32'h24, 32'd0, 5'd1, 5'b10001};
        @(posedge clk); #1; check(payload);
        @(negedge clk); payload = {69'd0, 5'b00101};
        @(posedge clk); #1; check(payload); // HALT valido.
        @(negedge clk); payload = {69'd0, 5'b00011};
        @(posedge clk); #1; check(payload); // Ilegal valido.
        // Burbuja elimina datos y controles activos.
        @(negedge clk); payload = {73{1'b1}} << 1;
        @(posedge clk); #1; check(74'd0);
        @(negedge clk); payload = {74{1'b1}};
        @(posedge clk); #1; check(payload);
        @(negedge clk); reset = 1; enable = 0;
        #1; check(payload); // Reset sincronico.
        @(posedge clk); #1; check(74'd0);
        $display("PASS: mem_wb");
        $finish;
    end
    initial begin #10000; $fatal(1, "Timeout"); end
endmodule
`default_nettype wire
