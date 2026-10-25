`timescale 1ns / 1ps
`default_nettype none

//------------------------------------------------------------------------------
// ALU combinacional de 32 bits para el procesador RISC-V.
// No tiene reloj ni registros: alu_control selecciona la operacion y los
// registros del pipeline guardan el resultado cuando corresponde.
//
// i_op es un codigo INTERNO, no el opcode de 7 bits de la instruccion.
// alu_control lo obtiene de ALUOp, funct3 y, cuando corresponde, funct7[5].
// La suma y la resta conservan los 32 bits inferiores del resultado.
// o_zero se usa internamente para los saltos; no es un registro de flags.
//------------------------------------------------------------------------------
module alu
(
    input  wire [31:0] i_a,
    input  wire [31:0] i_b,
    input  wire [3:0]  i_op,

    output reg  [31:0] o_result,
    output wire        o_zero
);

    localparam [3:0] ADD  = 4'b0000,
                     SUB  = 4'b1000,
                     SLL  = 4'b0001,
                     SLT  = 4'b0010,
                     SLTU = 4'b0011,
                     XOR_ = 4'b0100,
                     SRL  = 4'b0101,
                     SRA  = 4'b1101,
                     OR_  = 4'b0110,
                     AND_ = 4'b0111;

    // RV32 usa solo los 5 bits inferiores para desplazar entre 0 y 31 lugares (shift amount).
    wire [4:0] shamt = i_b[4:0];

    always @(*) begin
        o_result = 32'd0;

        case (i_op)
            ADD:  o_result = i_a + i_b;
            SUB:  o_result = i_a - i_b;
            SLL:  o_result = i_a << shamt;
            SLT:  o_result = ($signed(i_a) < $signed(i_b)) ? 32'd1 : 32'd0;
            SLTU: o_result = (i_a < i_b) ? 32'd1 : 32'd0;
            XOR_: o_result = i_a ^ i_b;
            SRL:  o_result = i_a >> shamt;
            SRA:  o_result = $signed(i_a) >>> shamt;
            OR_:  o_result = i_a | i_b;
            AND_: o_result = i_a & i_b;
            default: o_result = 32'd0;
        endcase
    end

    assign o_zero = (o_result == 32'd0);

endmodule

`default_nettype wire

//------------------------------------------------------------------------------
// Referencia rapida de operaciones de la ALU
// Operacion | Que hace
// ----------|------------------------------------------------------------------
// ADD       | Suma A + B.
// SUB       | Resta A - B.
// SLL       | Desplaza A a la izquierda; rellena con ceros.
// SRL       | Desplaza A a la derecha; rellena con ceros.
// SRA       | Desplaza A a la derecha; conserva el signo.
// SLT       | Devuelve 1 si A < B con signo; si no, 0.
// SLTU      | Devuelve 1 si A < B sin signo; si no, 0.
// XOR_      | Por bit: 1 si los bits de A y B son distintos.
// OR_       | Por bit: 1 si al menos uno de los bits es 1.
// AND_      | Por bit: 1 si ambos bits son 1.
// Los desplazamientos usan shamt = B[4:0] (0 a 31 posiciones).
//------------------------------------------------------------------------------
