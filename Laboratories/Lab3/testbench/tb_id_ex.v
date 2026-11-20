`timescale 1ns / 1ps
`default_nettype none

module tb_id_ex;
    reg clk = 0;
    always #5 clk = ~clk;
    reg reset = 1, enable = 0, flush = 0;
    reg valid = 1;
    reg [161:0] payload = 0;
    wire [162:0] observed;
    reg [162:0] held;
    integer errors = 0;
    integer k;

    id_ex dut (
        .i_clk(clk), .i_reset(reset), .i_enable(enable), .i_flush(flush),
        .i_pc(payload[130 +: 32]), .o_pc(observed[131 +: 32]),
        .i_rs1_data(payload[98 +: 32]), .o_rs1_data(observed[99 +: 32]),
        .i_rs2_data(payload[66 +: 32]), .o_rs2_data(observed[67 +: 32]),
        .i_imm(payload[34 +: 32]), .o_imm(observed[35 +: 32]),
        .i_rs1(payload[29 +: 5]), .o_rs1(observed[30 +: 5]),
        .i_rs2(payload[24 +: 5]), .o_rs2(observed[25 +: 5]),
        .i_rd(payload[19 +: 5]), .o_rd(observed[20 +: 5]),
        .i_funct3(payload[16 +: 3]), .o_funct3(observed[17 +: 3]),
        .i_funct7_b5(payload[15 +: 1]), .o_funct7_b5(observed[16 +: 1]),
        .i_reg_write(payload[14 +: 1]), .o_reg_write(observed[15 +: 1]),
        .i_alu_src_a(payload[13 +: 1]), .o_alu_src_a(observed[14 +: 1]),
        .i_alu_src_b(payload[12 +: 1]), .o_alu_src_b(observed[13 +: 1]),
        .i_mem_read(payload[11 +: 1]), .o_mem_read(observed[12 +: 1]),
        .i_mem_write(payload[10 +: 1]), .o_mem_write(observed[11 +: 1]),
        .i_result_src(payload[9 +: 1]), .o_result_src(observed[10 +: 1]),
        .i_branch(payload[8 +: 1]), .o_branch(observed[9 +: 1]),
        .i_jump(payload[7 +: 1]), .o_jump(observed[8 +: 1]),
        .i_jalr(payload[6 +: 1]), .o_jalr(observed[7 +: 1]),
        .i_alu_op(payload[4 +: 2]), .o_alu_op(observed[5 +: 2]),
        .i_halt(payload[3 +: 1]), .o_halt(observed[4 +: 1]),
        .i_uses_rs1(payload[2 +: 1]), .o_uses_rs1(observed[3 +: 1]),
        .i_uses_rs2(payload[1 +: 1]), .o_uses_rs2(observed[2 +: 1]),
        .i_illegal(payload[0 +: 1]), .o_illegal(observed[1 +: 1]),
        .i_valid(valid), .o_valid(observed[0 +: 1])
    );

    task check;
        input [8*60-1:0] label;
        input [162:0] expected;
        begin
            if (observed !== expected) begin
                $display("ERROR %0s: recibido %h, esperado %h", label, observed, expected);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        // Reset tiene prioridad sobre pausa y datos de entrada activos.
        payload = {162{1'b1}};
        @(posedge clk); #1; check("reset pausado", 0);
        @(negedge clk); reset = 0; enable = 1;
        #1; check("no captura antes del flanco", 0);
        @(posedge clk); #1; check("captura todos los campos", {payload, valid});
        held = observed;
        // La pausa conserva datos incluso si flush o valid cambian.
        @(negedge clk); enable = 0; flush = 1; valid = 0; payload = 0;
        repeat (3) begin
            @(posedge clk); #1; check("pausa gana a flush", held);
        end
        @(negedge clk); enable = 1; valid = 1;
        payload = {162{1'b1}};
        @(posedge clk); #1; check("flush elimina controles activos y HALT", 0);
        // Cargar patrones distintos para verificar campos y actualizaciones.
        @(negedge clk); flush = 0;
        for (k = 0; k < 16; k = k + 1) begin
            @(negedge clk); payload = {$random, $random, $random, $random, $random, 2'b01};
            @(posedge clk); #1; check("captura patron", {payload, valid});
        end
        @(negedge clk); valid = 0;
        payload = {162{1'b1}};
        @(posedge clk); #1; check("entrada invalida no genera efectos", 0);
        @(negedge clk); valid = 1;
        @(posedge clk); #1; check("recuperacion tras burbuja", {payload, valid});
        @(negedge clk); reset = 1; enable = 0; flush = 1;
        @(posedge clk); #1; check("reset gana a pausa y flush", 0);
        if (errors != 0) $fatal(1, "FAIL: %0d errores", errors);
        $display("PASS: id_ex");
        $finish;
    end

    initial begin
        #10000;
        $fatal(1, "Timeout global");
    end
endmodule

`default_nettype wire
