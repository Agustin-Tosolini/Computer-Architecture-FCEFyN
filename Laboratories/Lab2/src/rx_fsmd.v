`timescale 1ns / 1ps

//------------------------------------------------------------------------------
// Receptor UART (FSMD).
// Sobremuestreo 16x: i_s_tick tiene que pulsar 16 veces por bit
// (lo genera el baud_rate_generator).
// Entrega el byte en o_dout y un pulso de un ciclo en o_rx_done (salida Moore).
//------------------------------------------------------------------------------
module rx_fsmd #
(
    parameter DATA_BITS = 8,     // bits de datos por trama
    parameter SB_TICK   = 16     // ticks del stop: 16 = 1 bit de stop
)
(
    input  wire                   i_clk,      // reloj del sistema (100 MHz)
    input  wire                   i_reset,
    input  wire                   i_s_tick,   // tick del baud rate generator
    input  wire                   i_rx,       // linea serie (asincronica)

    output reg                    o_rx_done,  // pulso de 1 ciclo: byte listo
    output wire [DATA_BITS-1:0]   o_dout      // byte recibido
);

    //------------------------------------------------ Estados (one-hot)
    localparam [4:0] IDLE  = 5'b00001,
                     START = 5'b00010,
                     DATA  = 5'b00100,
                     STOP  = 5'b01000,
                     DONE  = 5'b10000;

    //------------------------------------------------ Anchos del datapath
    // s tiene que llegar a 15 (bits de dato) y a SB_TICK-1 (stop):
    // se dimensiona para el mayor de los dos.
    localparam S_MAX  = (SB_TICK > 16) ? SB_TICK : 16;
    localparam S_BITS = $clog2(S_MAX);
    localparam N_BITS = $clog2(DATA_BITS);

    //------------------------------------------------ Registros datapath
    reg [4:0]           state, next_state;
    reg [S_BITS-1:0]    s, s_next;      // ticks dentro del bit actual
    reg [N_BITS-1:0]    n, n_next;      // bits de dato recibidos
    reg [DATA_BITS-1:0] b, b_next;      // shift register con el dato

    //------------------------------------------------ Sincronizador de rx
    // i_rx es asincronica respecto a i_clk: dos flip-flops en cascada evitan
    // que la metaestabilidad llegue a la FSM. Arrancan en 1 (linea en reposo)
    // para no detectar un start falso al encender.
    reg rx_meta = 1'b1;
    reg rx_sync = 1'b1;

    always @(posedge i_clk)
    begin
        rx_meta <= i_rx;
        rx_sync <= rx_meta;
    end

    //------------------------------------------------ Logica de memoria
    always @(posedge i_clk) begin
        if (i_reset) begin
            state <= IDLE;
            s     <= {S_BITS{1'b0}};
            n     <= {N_BITS{1'b0}};
            b     <= {DATA_BITS{1'b0}};
        end
        else begin
            state <= next_state;
            s     <= s_next;
            n     <= n_next;
            b     <= b_next;
        end
    end

    //------------------------------------------------ Logica de proximo estado
    always @(*)
    begin
        // Por defecto todo conserva su valor (evita latches)
        next_state = state;
        s_next     = s;
        n_next     = n;
        b_next     = b;

        case (state)
            // Espera el flanco de bajada del bit de start.
            // No depende del tick: la linea se observa a velocidad de reloj.
            IDLE:
                if (~rx_sync)
                begin
                    next_state = START;
                    s_next     = {S_BITS{1'b0}};
                end

            // Cuenta medio bit para ubicarse en el centro del start.
            START:
                if (i_s_tick)
                begin
                    if (s == 7)
                    begin
                        if (~rx_sync)
                        begin          // sigue en 0: start valido
                            next_state = DATA;
                            s_next     = {S_BITS{1'b0}};
                            n_next     = {N_BITS{1'b0}};
                        end
                        else                         // volvio a 1: fue un glitch
                            next_state = IDLE;
                    end
                    else
                        s_next = s + 1'b1;
                end

            // Cada 16 ticks cae en el centro de un bit y lo captura.
            // LSB primero: el bit nuevo entra por la izquierda.
            DATA:
                if (i_s_tick)
                begin
                    if (s == 15)
                    begin
                        s_next = {S_BITS{1'b0}};
                        b_next = {rx_sync, b[DATA_BITS-1:1]};
                        if (n == DATA_BITS-1)
                            next_state = STOP;
                        else
                            n_next = n + 1'b1;
                    end
                    else
                        s_next = s + 1'b1;
                end

            // Espera la duracion del bit de stop.
            STOP:
                if (i_s_tick)
                begin
                    if (s == SB_TICK-1)
                        next_state = DONE;
                    else
                        s_next = s + 1'b1;
                end

            // Dura un solo ciclo: existe para que o_rx_done sea salida Moore.
            DONE:
                next_state = IDLE;

            // Estado invalido (one-hot corrompido): recuperacion
            default:
                next_state = IDLE;
        endcase
    end

    //------------------------------------------------ Logica de salida (Moore)
    always @(*)
    begin
        case (state)
            DONE:    o_rx_done = 1'b1;
            default: o_rx_done = 1'b0;
        endcase
    end

    assign o_dout = b;

endmodule
