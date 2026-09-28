`timescale 1ns / 1ps

//------------------------------------------------------------------------------
// Interface circuit.
// Wrapper sin logica propia: agrupa los dos buffers. rx_intf y tx_intf no
// comparten ninguna senal entre si; estan juntos solo porque forman el bloque
// que separa la UART del resto del sistema.
//
// Hacia la UART: pulsos y bytes crudos.
// Hacia alu_ctrl: las seis senales del diagrama de bloques
//                 (r_data, rd, rx_empty / w_data, wr, tx_full).
//------------------------------------------------------------------------------
module intf #
(
    parameter DATA_BITS = 8
)
(
    input  wire                  i_clk,
    input  wire                  i_reset,

    // ---------------- Lado UART
    input  wire                  i_rx_done,
    input  wire [DATA_BITS-1:0]  i_dout,

    output wire                  o_tx_start,
    output wire [DATA_BITS-1:0]  o_tx_din,
    input  wire                  i_tx_done,

    // ---------------- Lado alu_ctrl
    output wire [DATA_BITS-1:0]  o_r_data,
    output wire                  o_rx_empty,
    input  wire                  i_rd,

    input  wire [DATA_BITS-1:0]  i_w_data,
    input  wire                  i_wr,
    output wire                  o_tx_full
);

    //------------------------------------------------ Buffer de recepcion
    rx_intf #
    (
        .DATA_BITS (DATA_BITS)
    )
    u_rx_intf
    (
        .i_clk      (i_clk),
        .i_reset    (i_reset),
        .i_rx_done  (i_rx_done),
        .i_dout     (i_dout),
        .i_rd       (i_rd),
        .o_r_data   (o_r_data),
        .o_rx_empty (o_rx_empty)
    );

    //------------------------------------------------ Buffer de transmision
    tx_intf #
    (
        .DATA_BITS (DATA_BITS)
    )
    u_tx_intf
    (
        .i_clk       (i_clk),
        .i_reset     (i_reset),
        .i_wr        (i_wr),
        .i_w_data    (i_w_data),
        .o_tx_full   (o_tx_full),
        .i_tx_done   (i_tx_done),
        .o_tx_start  (o_tx_start),
        .o_tx_din    (o_tx_din)
    );

endmodule