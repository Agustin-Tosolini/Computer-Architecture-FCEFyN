`timescale 1ns / 1ps
`default_nettype none
module tb_hazard_unit;
    reg id_valid = 1, uses1 = 1, uses2 = 1;
    reg [4:0] rs1 = 3, rs2 = 4, rd = 5;
    reg ex_valid = 1, mem_read = 1, reg_write = 1, redirect = 0;
    wire pc_write, if_write, if_flush, ex_flush;
    integer k;
    hazard_unit dut (
        .i_id_valid(id_valid), .i_id_uses_rs1(uses1), .i_id_uses_rs2(uses2),
        .i_id_rs1(rs1), .i_id_rs2(rs2), .i_ex_valid(ex_valid),
        .i_ex_mem_read(mem_read), .i_ex_reg_write(reg_write), .i_ex_rd(rd),
        .i_ex_redirect(redirect), .o_pc_write(pc_write),
        .o_if_id_write(if_write), .o_if_id_flush(if_flush), .o_id_ex_flush(ex_flush)
    );
    task check;
        input [3:0] expected;
        begin
            #1;
            if ({pc_write,if_write,if_flush,ex_flush} !== expected)
                $fatal(1, "hazard: recibido %b esperado %b",
                       {pc_write,if_write,if_flush,ex_flush}, expected);
        end
    endtask
    initial begin
        check(4'b1100); // LOAD independiente.
        for (k = 1; k < 32; k = k + 1) begin
            rd = k; rs1 = k; rs2 = 0; check(4'b0001);
            rs1 = 0; rs2 = k; check(4'b0001); // Incluye dato de STORE.
        end
        uses2 = 0; check(4'b1100);
        uses2 = 1; uses1 = 0; rs1 = 31; rs2 = 0; check(4'b1100);
        uses1 = 1; check(4'b0001);
        id_valid = 0; check(4'b1100);
        id_valid = 1; ex_valid = 0; check(4'b1100);
        ex_valid = 1; mem_read = 0; check(4'b1100); // ALU: forwarding alcanza.
        mem_read = 1; reg_write = 0; check(4'b1100);
        reg_write = 1; rs1 = 0; rd = 0; check(4'b1100); // x0 nunca depende.
        rd = 3; rs1 = 3; check(4'b0001);
        redirect = 1; check(4'b1111); // Salto gana aun con dependencia activa.
        mem_read = 0; check(4'b1111);
        id_valid = 0; check(4'b1111); // Descarta IF aunque ID ya sea burbuja.
        ex_valid = 0; check(4'b1100); // Salto de instruccion invalida ignorado.
        redirect = 0; id_valid = 1; mem_read = 1;
        check(4'b1100); // Tras insertar burbuja en EX se libera el stall.
        $display("PASS: hazard_unit");
        $finish;
    end
endmodule
`default_nettype wire
