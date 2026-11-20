`timescale 1ns / 1ps
`default_nettype none

// Seleccion combinacional de operandos; los mux de datos estan fuera del modulo.
module forwarding_unit
(
    input wire i_ex_valid,             // Instruccion valida en ID/EX.
    input wire i_ex_uses_rs1,           // EX necesita rs1.
    input wire i_ex_uses_rs2,           // EX necesita rs2, incluido STORE.
    input wire [4:0] i_ex_rs1,          // Numero de rs1 en ID/EX.
    input wire [4:0] i_ex_rs2,          // Numero de rs2 en ID/EX.

    input wire i_mem_valid,            // Instruccion valida en EX/MEM.
    input wire i_mem_reg_write,        // EX/MEM escribira un registro.
    input wire i_mem_result_src,       // 1=LOAD: resultado aun no adelantable.
    input wire [4:0] i_mem_rd,          // Destino de EX/MEM.

    input wire i_wb_valid,             // Instruccion valida en MEM/WB.
    input wire i_wb_reg_write,         // MEM/WB escribira un registro.
    input wire [4:0] i_wb_rd,          // Destino de MEM/WB.

    output reg [1:0] o_forward_a,      // rs1: 00=ID/EX, 01=WB, 10=EX/MEM.
    output reg [1:0] o_forward_b       // rs2: 00=ID/EX, 01=WB, 10=EX/MEM.
);
    localparam FROM_ID_EX = 2'b00;
    localparam FROM_WB = 2'b01;
    localparam FROM_EX_MEM = 2'b10;

    wire mem_writes = i_mem_valid && i_mem_reg_write && (i_mem_rd != 5'd0);
    wire wb_writes = i_wb_valid && i_wb_reg_write && (i_wb_rd != 5'd0);

    always @(*) begin
        o_forward_a = FROM_ID_EX;
        o_forward_b = FROM_ID_EX;
        if (i_ex_valid && i_ex_uses_rs1) begin
            if (mem_writes && i_mem_rd == i_ex_rs1) begin
                if (!i_mem_result_src) o_forward_a = FROM_EX_MEM;
                // Un LOAD reciente bloquea tambien un valor viejo de WB.
                // La hazard_unit debe impedir este caso mediante stall previo.
            end
            else if (wb_writes && i_wb_rd == i_ex_rs1)
                o_forward_a = FROM_WB;
        end
        if (i_ex_valid && i_ex_uses_rs2) begin
            if (mem_writes && i_mem_rd == i_ex_rs2) begin
                if (!i_mem_result_src) o_forward_b = FROM_EX_MEM;
            end
            else if (wb_writes && i_wb_rd == i_ex_rs2)
                o_forward_b = FROM_WB;
        end
    end
endmodule

`default_nettype wire
