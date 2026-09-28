`timescale 1ns / 1ps

//------------------------------------------------------------------------------
// Interface del transmisor UART.
//
//   alu_ctrl --(i_wr + i_w_data)--> [ocupado?] --(o_tx_start + o_tx_din)--> tx_fsmd
//            <--(o_tx_full)--                  <--(i_tx_done)--
//
// No guarda el dato: el tx_fsmd lo copia en su propio shift register en el
// mismo ciclo en que recibe tx_start. Lo unico que guarda es el ESTADO:
// si hay una transmision en curso o no.
//------------------------------------------------------------------------------
module tx_intf #
(
    parameter DATA_BITS = 8
)
(
    input  wire                  i_clk,
    input  wire                  i_reset,

    // Lado productor (alu_ctrl)
    input  wire                  i_wr,        // pulso: "mandá este byte"
    input  wire [DATA_BITS-1:0]  i_w_data,    // el byte, valido con i_wr
    output wire                  o_tx_full,   // 1 = transmisor ocupado

    // Lado tx_fsmd
    input  wire                  i_tx_done,   // pulso de 1 ciclo: trama enviada
    output wire                  o_tx_start,  // pulso de 1 ciclo: arrancá
    output wire [DATA_BITS-1:0]  o_tx_din
);

    reg full; // Si el transmisor esta ocupado

    always @(posedge i_clk) begin
        if (i_reset)
            full <= 1'b0;
        else if (i_wr && !full)
            full <= 1'b1;        // arranca una transmision
        else if (i_tx_done)
            full <= 1'b0;        // el tx_fsmd termino y vuelve a IDLE
    end

    // El pedido pasa directo al tx_fsmd, pero solo si esta libre.
    // Con full == 0 el tx_fsmd esta garantizado en IDLE, asi que el
    // pulso nunca se pierde.
    assign o_tx_start = i_wr && !full;
    assign o_tx_din   = i_w_data;
    assign o_tx_full  = full;

endmodule
