`timescale 1ns / 1ps
`default_nettype none

//------------------------------------------------------------------------------
// Controlador de ECO (paso 1 del apartado B). Modulo TEMPORAL.
//
// Devuelve por TX cada byte que llega por RX. Sirve para validar en la placa
// toda la cadena de comunicacion (pines, baud rate, reset, xdc) antes de
// agregar la debug_unit, que lo va a reemplazar usando la MISMA interfaz con
// el intf (r_data, rx_empty, rd / w_data, tx_full, wr).
//
// Es el ALU_ctrl del TP2 reducido: en vez de juntar tres bytes y mandar el
// resultado de la ALU, junta uno y lo devuelve.
//
//   RECV --(!rx_empty / rd, guarda el byte)--> SEND --(!tx_full / wr)--> RECV
//------------------------------------------------------------------------------
module echo_ctrl #
(
    parameter DATA_BITS = 8
)
(
    input  wire                  i_clk,
    input  wire                  i_reset,

    // Lado receptor
    input  wire [DATA_BITS-1:0]  i_r_data,
    input  wire                  i_rx_empty,
    output reg                   o_rd,

    // Lado transmisor
    output wire [DATA_BITS-1:0]  o_w_data,
    input  wire                  i_tx_full,
    output reg                   o_wr,

    // Ultimo byte recibido (a leds, para depurar en la placa)
    output wire [DATA_BITS-1:0]  o_last_byte
);

    //------------------------------------------------ Estados (one-hot)
    localparam [1:0] RECV = 2'b01,
                     SEND = 2'b10;

    //------------------------------------------------ Registros
    reg [1:0]           state, next_state;
    reg [DATA_BITS-1:0] dato,  dato_next;

    //------------------------------------------------ Logica de memoria
    always @(posedge i_clk) begin
        if (i_reset) begin
            state <= RECV;
            dato  <= {DATA_BITS{1'b0}};
        end
        else begin
            state <= next_state;
            dato  <= dato_next;
        end
    end

    //------------------------------------------------ Logica de proximo estado
    always @(*) begin
        next_state = state;
        dato_next  = dato;

        case (state)
            // Espera un byte y lo guarda.
            RECV:
                if (!i_rx_empty) begin
                    dato_next  = i_r_data;
                    next_state = SEND;
                end

            // Lo devuelve apenas el transmisor este libre.
            SEND:
                if (!i_tx_full)
                    next_state = RECV;

            default:
                next_state = RECV;
        endcase
    end

    //------------------------------------------------ Logica de salida (Mealy)
    // Igual que en ALU_ctrl: o_rd y o_wr valen 1 solo en el ciclo en que
    // efectivamente se consume o se entrega un byte.
    always @(*) begin
        o_rd = 1'b0;
        o_wr = 1'b0;

        case (state)
            RECV:    o_rd = ~i_rx_empty;
            SEND:    o_wr = ~i_tx_full;
            default: ;
        endcase
    end

    assign o_w_data    = dato;
    assign o_last_byte = dato;

endmodule

`default_nettype wire
