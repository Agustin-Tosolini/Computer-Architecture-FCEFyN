`timescale 1ns / 1ps

//------------------------------------------------------------------------------
// Top / interfaz de la ALU para la placa.
// Se encarga de la parte secuencial: capturar los switches en registros
// cuando se aprieta cada boton, y mostrar el resultado en los leds.
// La logica de calculo vive en el modulo alu.
//------------------------------------------------------------------------------
module ALU_top #
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

    //----------------------------------------------Registros de entrada
    reg [LENGTH_BITS-1 : 0] dato_A = {LENGTH_BITS{1'b0}};
    reg [LENGTH_BITS-1 : 0] dato_B = {LENGTH_BITS{1'b0}};
    reg [LENGTH_OPT-1  : 0] opt    = {LENGTH_OPT{1'b0}};

    always @(posedge i_clk) begin
        if (i_reset) begin
            dato_A <= {LENGTH_BITS{1'b0}};
            dato_B <= {LENGTH_BITS{1'b0}};
            opt    <= {LENGTH_OPT{1'b0}};
        end
        else if (i_button_1) dato_A <= i_switch;
        else if (i_button_2) dato_B <= i_switch;
        else if (i_button_3) opt    <= i_switch[LENGTH_OPT-1:0];
    end

    //----------------------------------------------Instancia de la ALU
    ALU #
    (
        .LENGTH_BITS (LENGTH_BITS),
        .LENGTH_OPT  (LENGTH_OPT)
    )
    u_alu
    (
        .o_result    (o_leds),
        .o_zero      (o_zero),
        .o_carry     (o_carry),
        .o_overflow  (o_overflow),

        .i_dato_A    (dato_A),
        .i_dato_B    (dato_B),
        .i_opt       (opt)
    );

endmodule
