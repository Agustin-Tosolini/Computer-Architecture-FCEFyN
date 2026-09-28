`timescale 1ns / 1ps

//------------------------------------------------------------------------------
// Interface del receptor UART.
// Buffer de un byte entre el rx_fsmd (que muestra el dato un solo ciclo)
// y el consumidor (alu_ctrl).
//
//   rx_fsmd  --(i_rx_done + i_dout)-->  [buffer]  --(o_r_data + o_rx_empty)-->  alu_ctrl
//                                                 <--(i_rd)--
//
// No sabe que representan los bytes: eso es asunto del protocolo, que vive
// en alu_ctrl.
//------------------------------------------------------------------------------
module rx_intf #
(
    parameter DATA_BITS = 8
)
(
    input  wire                  i_clk,
    input  wire                  i_reset,

    // Lado rx_fsmd
    input  wire                  i_rx_done,   // pulso de 1 ciclo: hay un byte
    input  wire [DATA_BITS-1:0]  i_dout,      // el byte, valido con i_rx_done

    // Lado consumidor
    input  wire                  i_rd,        // pulso: "ya lo lei"
    output wire [DATA_BITS-1:0]  o_r_data,    // byte disponible
    output wire                  o_rx_empty   // 1 = no hay nada para leer
);

    reg [DATA_BITS-1:0] buffer;
    reg                 full;

    // Se acepta el byte nuevo si el buffer esta libre, o si en este mismo
    // ciclo lo estan vaciando. Si llega con el buffer lleno y nadie lee,
    // se descarta y queda el viejo (overrun).
    wire accept = i_rx_done && (!full || i_rd);

    always @(posedge i_clk) begin
        if (i_reset)
            buffer <= {DATA_BITS{1'b0}};
        else if (accept)
            buffer <= i_dout;
    end

    always @(posedge i_clk) begin
        if (i_reset)     full <= 1'b0;
        else if (accept) full <= 1'b1;   // entro un byte
        else if (i_rd)   full <= 1'b0;   // lo consumieron
    end

    assign o_r_data   = buffer;
    assign o_rx_empty = ~full;

endmodule
