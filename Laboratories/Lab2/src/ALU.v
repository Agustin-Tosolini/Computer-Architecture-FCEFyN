`timescale 1ns / 1ps

//------------------------------------------------------------------------------
// ALU puramente combinacional.
// No tiene reloj ni registros: el resultado sale del case y nada mas.
// Quien le entrega los operandos es responsabilidad del modulo que la instancia.
//------------------------------------------------------------------------------
module ALU #
(
    parameter LENGTH_BITS = 8,
    parameter LENGTH_OPT  = 6
)
(
    output reg  [LENGTH_BITS-1 : 0] o_result,
    output wire                     o_zero,
    output reg                      o_carry,
    output reg                      o_overflow,

    input wire [LENGTH_BITS-1 : 0]  i_dato_A,
    input wire [LENGTH_BITS-1 : 0]  i_dato_B,
    input wire [LENGTH_OPT-1  : 0]  i_opt
);

    //----------------------------------------------Parametros locales
    localparam [5:0] ADD  = 6'b100000,
                     SUB  = 6'b100010,
                     AND_ = 6'b100100,
                     OR_  = 6'b100101,
                     XOR_ = 6'b100110,
                     NOR_ = 6'b100111,
                     SRA  = 6'b000011,
                     SRL  = 6'b000010;

    localparam SHAMT_BITS = $clog2(LENGTH_BITS);

    always @(*) begin
        o_result   = {LENGTH_BITS{1'b0}};
        o_carry    = 1'b0;
        o_overflow = 1'b0;

        case (i_opt)
            ADD: begin
                {o_carry, o_result} = {1'b0, i_dato_A} + {1'b0, i_dato_B};
                o_overflow = (i_dato_A[LENGTH_BITS-1] == i_dato_B[LENGTH_BITS-1]) &&
                             (o_result[LENGTH_BITS-1] != i_dato_A[LENGTH_BITS-1]);
            end
            SUB: begin
                {o_carry, o_result} = {1'b0, i_dato_A} - {1'b0, i_dato_B};
                o_overflow = (i_dato_A[LENGTH_BITS-1] != i_dato_B[LENGTH_BITS-1]) &&
                             (o_result[LENGTH_BITS-1] != i_dato_A[LENGTH_BITS-1]);
            end
            AND_: o_result = i_dato_A & i_dato_B;
            OR_:  o_result = i_dato_A | i_dato_B;
            XOR_: o_result = i_dato_A ^ i_dato_B;
            NOR_: o_result = ~(i_dato_A | i_dato_B);
            SRA:  o_result = $signed(i_dato_A) >>> i_dato_B[SHAMT_BITS-1:0];
            SRL:  o_result = i_dato_A          >>  i_dato_B[SHAMT_BITS-1:0];
            default: o_result = {LENGTH_BITS{1'b0}};
        endcase
    end

    assign o_zero = (o_result == {LENGTH_BITS{1'b0}});

endmodule
