`timescale 1ns / 1ps
`default_nettype none
module tb_forwarding_unit;
    reg ex_valid = 1, uses1 = 1, uses2 = 1;
    reg [4:0] rs1 = 3, rs2 = 4, mem_rd = 0, wb_rd = 0;
    reg mem_valid = 1, mem_write = 1, mem_load = 0;
    reg wb_valid = 1, wb_write = 1;
    wire [1:0] a, b;
    integer k;
    forwarding_unit dut (
        .i_ex_valid(ex_valid), .i_ex_uses_rs1(uses1), .i_ex_uses_rs2(uses2),
        .i_ex_rs1(rs1), .i_ex_rs2(rs2),
        .i_mem_valid(mem_valid), .i_mem_reg_write(mem_write),
        .i_mem_result_src(mem_load), .i_mem_rd(mem_rd),
        .i_wb_valid(wb_valid), .i_wb_reg_write(wb_write), .i_wb_rd(wb_rd),
        .o_forward_a(a), .o_forward_b(b)
    );
    task check;
        input [1:0] expected_a, expected_b;
        begin
            #1;
            if ({a,b} !== {expected_a,expected_b})
                $fatal(1, "forwarding: %b/%b esperado %b/%b", a,b,expected_a,expected_b);
        end
    endtask
    initial begin
        check(0,0);
        mem_rd = 3; wb_rd = 4; check(2,1);
        mem_rd = 4; wb_rd = 3; check(1,2);
        // Prioridad del escritor reciente para ambos operandos, incluido x31.
        for (k = 1; k < 32; k = k + 1) begin
            rs1 = k; rs2 = k; mem_rd = k; wb_rd = k; check(2,2);
            mem_load = 1; check(0,0); // No usar WB viejo ni direccion de LOAD.
            mem_valid = 0; check(1,1); // LOAD ya disponible en WB.
            mem_valid = 1; mem_load = 0;
        end
        mem_write = 0; check(1,1);
        wb_write = 0; check(0,0);
        wb_write = 1; wb_valid = 0; check(0,0);
        mem_write = 1; wb_valid = 1;
        uses1 = 0; check(0,2);
        uses1 = 1; uses2 = 0; check(2,0);
        uses2 = 1; ex_valid = 0; check(0,0);
        ex_valid = 1;
        rs1 = 0; rs2 = 0; mem_rd = 0; wb_rd = 0; check(0,0);
        // Sin dependencia del LOAD, WB sigue disponible para el otro operando.
        rs1 = 3; rs2 = 4; mem_rd = 3; wb_rd = 4; mem_load = 1; check(0,1);
        $display("PASS: forwarding_unit");
        $finish;
    end
endmodule
`default_nettype wire
