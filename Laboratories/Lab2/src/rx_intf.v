module rx_intf #
(
    parameter DATA_BITS = 8
)
(
    input wire [DATA_BITS-1:0]  i_dout,
    input wire                  i_rx_done,
    input wire                  i_clk,
    input wire                  i_reset,
    input wire                  i_rd,

    output wire [DATA_BITS-1:0] o_rdata,
    output wire                 o_rx_empty
);

//Cosas

endmodule
