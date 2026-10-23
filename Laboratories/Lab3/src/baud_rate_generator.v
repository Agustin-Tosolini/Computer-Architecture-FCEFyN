`timescale 1ns / 1ps
`default_nettype none

//------------------------------------------------------------------------------
// Generador de baud rate.
// Emite un pulso de un ciclo (o_tick) OVERSAMP veces por bit.
//
//   N = CLK_FREQ / (BAUD_RATE * OVERSAMP), redondeado al entero mas cercano.
//
//   100 MHz, 115200 baud, 16x  ->  N = 54   (baud real 115741, error +0.47 %)
//   100 MHz,   9600 baud, 16x  ->  N = 651  (baud real   9601, error +0.01 %)
//
// El error tiene que quedar por debajo de ~2 %. Si se cambia el clock con el
// clk_wiz, CLK_FREQ tiene que ser la frecuencia REAL que llega a i_clk.
//------------------------------------------------------------------------------
module baud_rate_generator #
(
    parameter CLK_FREQ  = 100_000_000,
    parameter BAUD_RATE = 115200,
    parameter OVERSAMP  = 16
)
(
    input  wire i_clk,
    input  wire i_reset,
    output wire o_tick
);
    // Contador modulo N. Se suma medio divisor antes de dividir para
    // redondear en lugar de truncar.
    localparam integer DIV   = BAUD_RATE * OVERSAMP;
    localparam integer N     = (CLK_FREQ + DIV / 2) / DIV;
    localparam integer WIDTH = (N > 1) ? $clog2(N) : 1;

    reg [WIDTH-1:0] counter = {WIDTH{1'b0}};

    always @(posedge i_clk) begin
        if (i_reset)              counter <= {WIDTH{1'b0}};
        else if (counter == N-1)  counter <= {WIDTH{1'b0}};
        else                      counter <= counter + 1'b1;
    end

    assign o_tick = (counter == N-1);

endmodule

`default_nettype wire
