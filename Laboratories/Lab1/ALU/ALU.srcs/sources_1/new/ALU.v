`timescale 1ns / 1ps

module ALU#
(
    parameter LENGTH_BITS = 8,
    parameter LENGTH_OPT  = 6
)
(
    output wire [LENGTH_BITS-1 : 0] o_leds,
    output wire                     o_zero,
    output wire                     o_carry,
    output wire                     o_overflow,

    input wire                       i_clk,
    input wire                       i_reset,
    input wire [LENGTH_BITS-1:0]     i_switch,
    input wire                       i_button_1,
    input wire                       i_button_2,
    input wire                       i_button_3
);

    reg [LENGTH_BITS-1 : 0] result;
    reg                     carry;
    reg                     overflow;

    reg [LENGTH_BITS-1 : 0] dato_A = {LENGTH_BITS{1'b0}};
    reg [LENGTH_BITS-1 : 0] dato_B = {LENGTH_BITS{1'b0}};
    reg [LENGTH_OPT-1  : 0] opt    = {LENGTH_OPT{1'b0}};

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

    // Lógica secuencial: carga de operandos y opcode con reset síncrono
    always @(posedge i_clk) begin
        if (i_reset) begin
            dato_A <= {LENGTH_BITS{1'b0}};
            dato_B <= {LENGTH_BITS{1'b0}};
            opt    <= {LENGTH_OPT{1'b0}};
        end else begin
            if      (i_button_1) dato_A <= i_switch;
            else if (i_button_2) dato_B <= i_switch;
            else if (i_button_3) opt    <= i_switch[LENGTH_OPT-1:0];
        end
    end

    // ALU combinacional + cálculo de flags
    always @(*) begin
        // Defaults para evitar latches
        result   = {LENGTH_BITS{1'b0}};
        carry    = 1'b0;
        overflow = 1'b0;

        case (opt)
            ADD: begin
                {carry, result} = {1'b0, dato_A} + {1'b0, dato_B};
                overflow = (dato_A[LENGTH_BITS-1] == dato_B[LENGTH_BITS-1]) &&
                           (result[LENGTH_BITS-1] != dato_A[LENGTH_BITS-1]);
            end
            SUB: begin
                {carry, result} = {1'b0, dato_A} - {1'b0, dato_B};
                overflow = (dato_A[LENGTH_BITS-1] != dato_B[LENGTH_BITS-1]) &&
                           (result[LENGTH_BITS-1] != dato_A[LENGTH_BITS-1]);
            end
            AND_: result = dato_A & dato_B;
            OR_:  result = dato_A | dato_B;
            XOR_: result = dato_A ^ dato_B;
            NOR_: result = ~(dato_A | dato_B);
            SRA:  result = $signed(dato_A) >>> dato_B[SHAMT_BITS-1:0];
            SRL:  result = dato_A         >>  dato_B[SHAMT_BITS-1:0];
            default: result = {LENGTH_BITS{1'b0}};
        endcase
    end

    assign o_leds     = result;
    assign o_zero     = (result == {LENGTH_BITS{1'b0}});
    assign o_carry    = carry;
    assign o_overflow = overflow;

endmodule