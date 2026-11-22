`timescale 1ns / 1ps
`default_nettype none

// Control combinacional: salto tomado > dependencia LOAD-use > avance normal.
// La pausa global se aplica con i_enable en los registros, no cortando el reloj.
module hazard_unit
(
    input wire i_id_valid,          // Instruccion valida en IF/ID.
    input wire i_id_uses_rs1,        // ID necesita rs1.
    input wire i_id_uses_rs2,        // ID necesita rs2, incluido STORE.
    input wire [4:0] i_id_rs1,       // Numero de rs1 en ID.
    input wire [4:0] i_id_rs2,       // Numero de rs2 en ID.
    input wire i_ex_valid,          // Instruccion valida en ID/EX.
    input wire i_ex_mem_read,       // EX ejecuta un LOAD.
    input wire i_ex_reg_write,      // EX escribira un registro.
    input wire [4:0] i_ex_rd,        // Destino de la instruccion en EX.
    input wire i_ex_redirect,       // Branch tomado o JAL/JALR resuelto en EX.

    output reg o_pc_write,          // Permite actualizar PC, incluido salto.
    output reg o_if_id_write,       // Permite cargar IF/ID.
    output reg o_if_id_flush,       // Descarta la instruccion en ID.
    output reg o_id_ex_flush        // Introduce una burbuja en EX.
);
    wire load_use = i_id_valid && i_ex_valid && i_ex_mem_read &&
                    i_ex_reg_write && (i_ex_rd != 5'd0) &&
                    ((i_id_uses_rs1 && i_id_rs1 == i_ex_rd) ||
                     (i_id_uses_rs2 && i_id_rs2 == i_ex_rd));

    always @(*) begin
        o_pc_write = 1'b1;
        o_if_id_write = 1'b1;
        o_if_id_flush = 1'b0;
        o_id_ex_flush = 1'b0;
        if (i_ex_valid && i_ex_redirect) begin
            o_if_id_flush = 1'b1;
            o_id_ex_flush = 1'b1;
        end
        else if (load_use) begin
            o_pc_write = 1'b0;
            o_if_id_write = 1'b0;
            o_id_ex_flush = 1'b1;
        end
    end
endmodule

`default_nettype wire
