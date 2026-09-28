`timescale 1ns / 1ps

//------------------------------------------------------------------------------
// Top del TP: UART + ALU.
//
// Es la frontera del chip: sus puertos son los pines de la placa, y son los
// nombres que busca el archivo de constraints (uart_alu.xdc).
//
// No tiene logica propia. Solo instancia los tres bloques y los cablea:
//
//   i_rx --> [ uart ] --> [ intf ] --> [ alu_ctrl + alu ]
//   o_tx <--         <--          <--
//
//------------------------------------------------------------------------------
module uart_alu_top #
(
    parameter CLK_FREQ     = 100_000_000,   // reloj de la Basys 3
    parameter BAUD_RATE    = 9600,
    parameter OVERSAMP     = 16,
    parameter DATA_BITS    = 8,
    parameter LENGTH_OPT   = 6,
    parameter RX_SB_TICK   = 16,            // el Rx espera 1 bit de stop
    parameter TX_STOP_BITS = 1              // el Tx manda 1 bit de stop
)
(
    input  wire        i_clk,       // W5  - 100 MHz
    input  wire        i_reset,     // U18 - btnC
    input  wire        i_rx,        // B18 - salida del puente USB-UART
    output wire        o_tx,        // A18 - entrada del puente USB-UART
    output wire [2:0]  o_leds       // U16, E19, U19 - zero, carry, overflow
);

    //------------------------------------------------ Senales internas
    // uart <-> intf
    wire                  rx_done;
    wire [DATA_BITS-1:0]  dout;
    wire                  tx_start;
    wire [DATA_BITS-1:0]  tx_din;
    wire                  tx_done;

    // intf <-> alu_ctrl (las seis senales del diagrama de bloques)
    wire [DATA_BITS-1:0]  r_data;
    wire                  rx_empty;
    wire                  rd;
    wire [DATA_BITS-1:0]  w_data;
    wire                  wr;
    wire                  tx_full;

    // flags de la ALU
    wire                  zero, carry, overflow;

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
        .i_reset    (i_reset),

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
        .i_reset    (i_reset),

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

    //================================================ Control + ALU
    ALU_ctrl #
    (
        .DATA_BITS  (DATA_BITS),
        .LENGTH_OPT (LENGTH_OPT)
    )
    u_alu_ctrl
    (
        .i_clk      (i_clk),
        .i_reset    (i_reset),

        .i_r_data   (r_data),
        .i_rx_empty (rx_empty),
        .o_rd       (rd),

        .o_w_data   (w_data),
        .i_tx_full  (tx_full),
        .o_wr       (wr),

        .o_zero     (zero),
        .o_carry    (carry),
        .o_overflow (overflow)
    );

    //================================================ Salidas a leds
    assign o_leds = {overflow, carry, zero};   // led[0]=zero, led[1]=carry, led[2]=overflow

endmodule