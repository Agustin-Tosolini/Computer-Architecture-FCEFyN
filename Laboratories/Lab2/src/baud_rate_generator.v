module baud_rate_generator #
(
    parameter CLK_FREQ  = 100_000_000,
    parameter BAUD_RATE = 9600,
    parameter OVERSAMP  = 16
)
(
    input  wire i_clk,
    input  wire i_reset,
    output wire o_tick
);
    // Contador modulo N: Nuestros datos = 631
    localparam integer N = CLK_FREQ / (BAUD_RATE * OVERSAMP);
    localparam integer WIDTH = $clog2(N);

    reg [WIDTH-1:0] counter = {WIDTH{1'b0}};

    always @(posedge i_clk) begin
        if (i_reset)              counter <= {WIDTH{1'b0}};
        else if (counter == N-1)  counter <= {WIDTH{1'b0}};
        else                      counter <= counter + 1'b1;
    end

    assign o_tick = (counter == N-1);

endmodule
