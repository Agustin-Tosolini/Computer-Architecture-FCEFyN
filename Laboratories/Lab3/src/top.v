`timescale 1ns / 1ps
`default_nettype none

//------------------------------------------------------------------------------
// Top del Trabajo Final — PASO 1: eco por UART.
//
// Es la frontera del chip: sus puertos son los pines de la placa y son los
// nombres que busca el archivo de constraints (top.xdc).
//
//   i_rx --> [ uart ] --> [ intf ] --> [ echo_ctrl ]
//   o_tx <--          <--          <--
//
//   i_reset (boton) --> [ reset_gen ] --> reset global
//
// Evolucion prevista:
//   paso 2/3: echo_ctrl se reemplaza por debug_unit (+ dump_mux) y se agrega
//             cpu_stub (y despues el cpu real) del otro lado de la debug_unit.
//   paso 4:   se agrega clk_wiz; su salida "locked" va a reset_gen.i_locked y
//             CLK_FREQ pasa a ser la frecuencia que genera.
//------------------------------------------------------------------------------
module top #
(
    parameter CLK_FREQ     = 100_000_000,   // reloj de la Basys 3 (sin clk_wiz)
    parameter BAUD_RATE    = 115200,
    parameter OVERSAMP     = 16,
    parameter DATA_BITS    = 8,
    parameter RX_SB_TICK   = 16,            // el Rx espera 1 bit de stop
    parameter TX_STOP_BITS = 1,             // el Tx manda 1 bit de stop
    parameter POR_CYCLES   = 16             // ciclos de reset al encender
)
(
    input  wire        i_clk,       // W5  - 100 MHz
    input  wire        i_reset,     // U18 - btnC
    input  wire        i_rx,        // B18 - salida del puente USB-UART
    output wire        o_tx,        // A18 - entrada del puente USB-UART
    output wire [7:0]  o_leds       // LD0..LD7 - ultimo byte recibido
);

    //------------------------------------------------ Senales internas
    wire                  reset;          // reset global, sincronico

    // uart <-> intf
    wire                  rx_done;
    wire [DATA_BITS-1:0]  dout;
    wire                  tx_start;
    wire [DATA_BITS-1:0]  tx_din;
    wire                  tx_done;

    // intf <-> controlador (las seis senales del diagrama de bloques)
    wire [DATA_BITS-1:0]  r_data;
    wire                  rx_empty;
    wire                  rd;
    wire [DATA_BITS-1:0]  w_data;
    wire                  wr;
    wire                  tx_full;

    wire [DATA_BITS-1:0]  last_byte;

    //================================================ Reset global
    reset_gen #
    (
        .POR_CYCLES (POR_CYCLES)
    )
    u_reset_gen
    (
        .i_clk    (i_clk),
        .i_btn    (i_reset),
        .i_locked (1'b1),       // sin clk_wiz todavia: clock siempre estable
        .o_reset  (reset)
    );

    //================================================ UART
    uart #
    (
        .CLK_FREQ     (CLK_FREQ),
        .BAUD_RATE    (BAUD_RATE),
        .OVERSAMP     (OVERSAMP),
        .DATA_BITS    (DATA_BITS),
        .RX_SB_TICK   (RX_SB_TICK),
        .TX_STOP_BITS (TX_STOP_BITS)
    )
    u_uart
    (
        .i_clk      (i_clk),
        .i_reset    (reset),

        .i_rx       (i_rx),
        .o_tx       (o_tx),

        .o_rx_done  (rx_done),
        .o_dout     (dout),

        .i_tx_start (tx_start),
        .i_din      (tx_din),
        .o_tx_done  (tx_done)
    );

    //================================================ Interface circuit
    intf #
    (
        .DATA_BITS (DATA_BITS)
    )
    u_intf
    (
        .i_clk      (i_clk),
        .i_reset    (reset),

        .i_rx_done  (rx_done),
        .i_dout     (dout),

        .o_tx_start (tx_start),
        .o_tx_din   (tx_din),
        .i_tx_done  (tx_done),

        .o_r_data   (r_data),
        .o_rx_empty (rx_empty),
        .i_rd       (rd),

        .i_w_data   (w_data),
        .i_wr       (wr),
        .o_tx_full  (tx_full)
    );

    //================================================ Controlador (eco)
    echo_ctrl #
    (
        .DATA_BITS (DATA_BITS)
    )
    u_echo_ctrl
    (
        .i_clk       (i_clk),
        .i_reset     (reset),

        .i_r_data    (r_data),
        .i_rx_empty  (rx_empty),
        .o_rd        (rd),

        .o_w_data    (w_data),
        .i_tx_full   (tx_full),
        .o_wr        (wr),

        .o_last_byte (last_byte)
    );

    //================================================ Salidas a leds
    assign o_leds = last_byte;

endmodule

`default_nettype wire
