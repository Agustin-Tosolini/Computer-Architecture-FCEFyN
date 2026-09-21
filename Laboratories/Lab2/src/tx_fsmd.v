`timescale 1ns / 1ps

//------------------------------------------------------------------------------
// Transmisor UART (FSMD) - trama completa en un shift register.
// Al recibir i_tx_start se arma {stop, dato, start} y se envia b[0]
// durante 16 ticks por bit, desplazando e insertando unos por la izquierda.
// o_tx_done: pulso de un ciclo al terminar el ultimo bit de stop (salida Moore).
//------------------------------------------------------------------------------
module tx_fsmd #
(
    parameter DATA_BITS = 8,    // bits de datos por trama
    parameter STOP_BITS = 1     // bits de stop
)
(
    input  wire                 i_clk,        // reloj del sistema (100 MHz)
    input  wire                 i_reset,
    input  wire                 i_s_tick,     // tick del baud rate generator
    input  wire                 i_tx_start,   // pulso de 1 ciclo: transmitir i_din
    input  wire [DATA_BITS-1:0] i_din,        // byte a transmitir

    output reg                  o_tx_done,    // pulso de 1 ciclo: trama enviada
    output wire                 o_tx          // linea serie
);

    //------------------------------------------------ Trama
    localparam START_BIT  = 1'b0;
    localparam STOP_BIT   = 1'b1;
    localparam FRAME_BITS = 1 + DATA_BITS + STOP_BITS;

    //------------------------------------------------ Estados (one-hot)
    localparam [2:0] IDLE = 3'b001,
                     SEND = 3'b010,
                     DONE = 3'b100;

    //------------------------------------------------ Anchos del datapath
    localparam S_BITS = 4;                       // s cuenta 0..15 (un bit)
    localparam N_BITS = $clog2(FRAME_BITS);      // n cuenta 0..FRAME_BITS-1

    //------------------------------------------------ Registros
    reg [2:0]            state, next_state;
    reg [S_BITS-1:0]     s, s_next;       // ticks dentro del bit actual
    reg [N_BITS-1:0]     n, n_next;       // bits de la trama ya enviados
    reg [FRAME_BITS-1:0] b, b_next;       // trama; b[0] es lo que esta en la linea

    //------------------------------------------------ Logica de memoria
    always @(posedge i_clk) begin
        if (i_reset) begin
            state <= IDLE;
            s     <= {S_BITS{1'b0}};
            n     <= {N_BITS{1'b0}};
            b     <= {FRAME_BITS{1'b1}};    // linea en reposo: todo en 1
        end
        else begin
            state <= next_state;
            s     <= s_next;
            n     <= n_next;
            b     <= b_next;
        end
    end

    //------------------------------------------------ Logica de proximo estado
    always @(*) begin
        // Por defecto todo conserva su valor (evita latches)
        next_state = state;
        s_next     = s;
        n_next     = n;
        b_next     = b;

        case (state)
            // Espera el pedido. La trama se arma en este mismo ciclo,
            // mientras i_din es valido.
            IDLE:
                if (i_tx_start) begin
                    b_next     = {{STOP_BITS{STOP_BIT}}, i_din, START_BIT};
                    s_next     = {S_BITS{1'b0}};
                    n_next     = {N_BITS{1'b0}};
                    next_state = SEND;
                end

            // Cada 16 ticks termina un bit: desplaza y mete un 1 por la izquierda.
            SEND:
                if (i_s_tick) begin
                    if (s == 15) begin
                        s_next = {S_BITS{1'b0}};
                        b_next = {1'b1, b[FRAME_BITS-1:1]};
                        if (n == FRAME_BITS-1)
                            next_state = DONE;
                        else
                            n_next = n + 1'b1;
                    end
                    else
                        s_next = s + 1'b1;
                end

            DONE:
                next_state = IDLE;

            // Estado invalido: recuperacion
            default:
                next_state = IDLE;
        endcase
    end

    //------------------------------------------------ Logica de salida.
    always @(*) begin
        case (state)
            DONE:    o_tx_done = 1'b1;
            default: o_tx_done = 1'b0;
        endcase
    end

    assign o_tx = b[0];

endmodule
