`timescale 1ns / 1ps
`default_nettype none

//------------------------------------------------------------------------------
// Control combinacional de la ALU. No es el controlador UART del TP2.
// ALUOp viene de control_unit; funct3 y funct7[5] vienen de la instruccion.
// Estos campos deberan viajar juntos hasta EX por el registro ID/EX.
// La validacion de instrucciones y sus efectos corresponde al control principal.
//------------------------------------------------------------------------------
module alu_control
(
    input  wire [1:0] i_alu_op,
    input  wire [2:0] i_funct3,
    input  wire       i_funct7_b5,  // Bit 30 de la instruccion.
    output reg  [3:0] o_alu_ctrl    // Conectar a i_op de alu.
);

    localparam [1:0] ALU_ADD = 2'b00,
                     ALU_SUB = 2'b01,
                     ALU_R   = 2'b10,
                     ALU_I   = 2'b11;

    always @(*) begin
        o_alu_ctrl = 4'b0000;
        case (i_alu_op)
            ALU_ADD: o_alu_ctrl = 4'b0000;
            ALU_SUB: o_alu_ctrl = 4'b1000;

            // Tipo R: funct7[5] distingue ADD/SUB y SRL/SRA.
            ALU_R: o_alu_ctrl = {i_funct7_b5, i_funct3};

            // Tipo I: el bit 30 suele ser parte del inmediato, no una orden
            // de restar. Solo se usa para distinguir SRLI de SRAI (funct3=101).
            ALU_I: o_alu_ctrl = {(i_funct3 == 3'b101) ? i_funct7_b5 : 1'b0,
                                i_funct3};

            default: o_alu_ctrl = 4'b0000;
        endcase
    end

endmodule

`default_nettype wire

//------------------------------------------------------------------------------
// Referencia rapida de entradas y salidas
// Senal        | Funcion
// -------------|---------------------------------------------------------------
// i_alu_op     | Entrada: categoria de operacion elegida por control_unit.
// i_funct3     | Entrada: bits [14:12] de la instruccion.
// i_funct7_b5  | Entrada: bit 30 de la instruccion.
// o_alu_ctrl   | Salida: codigo interno de 4 bits para la ALU.
//
// ALUOp | Accion
// ------|----------------------------------------------------------------------
// 00    | Sumar (por ejemplo, direcciones de loads/stores y JALR).
// 01    | Restar (comparar igualdad para BEQ/BNE).
// 10    | Operacion tipo R, segun funct3 y funct7[5].
// 11    | Operacion inmediata, segun funct3; bit 30 solo para SRLI/SRAI.
// Ejemplo: ADDI con -1 tiene bit 30=1, pero debe sumar, no restar.
//------------------------------------------------------------------------------
