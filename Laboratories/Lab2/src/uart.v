`timescale 1ns / 1ps

//------------------------------------------------------------------------------
// Bloque UART.
// Wrapper sin logica propia: agrupa el baud rate generator y las dos FSMD.
// El tick se genera una sola vez y se reparte a Rx y Tx; no sale del modulo
// porque nadie mas lo necesita.
//
// Hacia afuera del chip: i_rx, o_tx.
// Hacia el intf: bytes y pulsos de handshake.
//------------------------------------------------------------------------------
module uart #
(
    parameter CLK_FREQ     = 100_000_000,
    parameter BAUD_RATE    = 9600,
    parameter OVERSAMP     = 16,
    parameter DATA_BITS    = 8,
    parameter RX_SB_TICK   = 16,   // ticks que el Rx espera en STOP (16 = 1 bit)
    parameter TX_STOP_BITS = 1     // bits de stop que el Tx transmite
)
(
    input  wire                  i_clk,
    input  wire                  i_reset,

    // Lineas serie (pines de la FPGA)
    input  wire                  i_rx,
    output wire                  o_tx,

    // Lado receptor -> intf
    output wire                  o_rx_done,
    output wire [DATA_BITS-1:0]  o_dout,

    // Lado transmisor <- intf
    input  wire                  i_tx_start,
    input  wire [DATA_BITS-1:0]  i_din,
    output wire                  o_tx_done
);

    wire tick;

    //------------------------------------------------ Generador de baud rate
    baud_rate_generator #
    (
        .CLK_FREQ  (CLK_FREQ),
        .BAUD_RATE (BAUD_RATE),
        .OVERSAMP  (OVERSAMP)
    )
    u_baud
    (
        .i_clk   (i_clk),
        .i_reset (i_reset),
        .o_tick  (tick)
    );

    //------------------------------------------------ Receptor
    rx_fsmd #
    (
        .DATA_BITS (DATA_BITS),
        .SB_TICK   (RX_SB_TICK)
    )
    u_rx
    (
        .i_clk     (i_clk),
        .i_reset   (i_reset),
        .i_s_tick  (tick),
        .i_rx      (i_rx),
        .o_rx_done (o_rx_done),
        .o_dout    (o_dout)
    );

    //------------------------------------------------ Transmisor
    tx_fsmd #
    (
        .DATA_BITS (DATA_BITS),
        .STOP_BITS (TX_STOP_BITS)
    )
    u_tx
    (
        .i_clk      (i_clk),
        .i_reset    (i_reset),
        .i_s_tick   (tick),
        .i_tx_start (i_tx_start),
        .i_din      (i_din),
        .o_tx_done  (o_tx_done),
        .o_tx       (o_tx)
    );

endmodule