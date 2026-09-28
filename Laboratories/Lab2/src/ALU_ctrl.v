`timescale 1ns / 1ps

//------------------------------------------------------------------------------
// Control del protocolo UART <-> ALU.
//
// Recibe tres bytes en orden (A, B, opcode), los guarda en registros y escribe
// el resultado de la ALU en el interface de transmision.
//
// Es el unico modulo que conoce el protocolo: la UART solo mueve bytes.
//------------------------------------------------------------------------------
module ALU_ctrl #
(
    parameter DATA_BITS  = 8,
    parameter LENGTH_OPT = 6
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

    // Flags de la ALU (a leds)
    output wire                  o_zero,
    output wire                  o_carry,
    output wire                  o_overflow
);

    //------------------------------------------------ Estados (one-hot)
    localparam [3:0] LOAD_A  = 4'b0001,
                     LOAD_B  = 4'b0010,
                     LOAD_OP = 4'b0100,
                     SEND    = 4'b1000;

    //------------------------------------------------ Registros
    reg [3:0]             state,  next_state;
    reg [DATA_BITS-1:0]   dato_A, dato_A_next;
    reg [DATA_BITS-1:0]   dato_B, dato_B_next;
    reg [LENGTH_OPT-1:0]  opt,    opt_next;

    wire [DATA_BITS-1:0]  result;

    //------------------------------------------------ Logica de memoria
    always @(posedge i_clk) begin
        if (i_reset) begin
            state  <= LOAD_A;
            dato_A <= {DATA_BITS{1'b0}};
            dato_B <= {DATA_BITS{1'b0}};
            opt    <= {LENGTH_OPT{1'b0}};
        end
        else begin
            state  <= next_state;
            dato_A <= dato_A_next;
            dato_B <= dato_B_next;
            opt    <= opt_next;
        end
    end

    //------------------------------------------------ Logica de proximo estado
    always @(*) begin
        // Por defecto todo conserva su valor (evita latches)
        next_state  = state;
        dato_A_next = dato_A;
        dato_B_next = dato_B;
        opt_next    = opt;

        case (state)
            // Los tres primeros estados son iguales salvo el registro destino:
            // existen solo para recordar cuantos bytes llegaron.
            LOAD_A:
                if (!i_rx_empty) begin
                    dato_A_next = i_r_data;
                    next_state  = LOAD_B;
                end

            LOAD_B:
                if (!i_rx_empty) begin
                    dato_B_next = i_r_data;
                    next_state  = LOAD_OP;
                end

            LOAD_OP:
                if (!i_rx_empty) begin
                    opt_next   = i_r_data[LENGTH_OPT-1:0];  // los 6 bits de abajo
                    next_state = SEND;
                end

            // La ALU es combinacional: en este ciclo el resultado ya es valido.
            // Si el transmisor esta ocupado, espera aca.
            SEND:
                if (!i_tx_full)
                    next_state = LOAD_A;

            // Estado invalido: recuperacion
            default:
                next_state = LOAD_A;
        endcase
    end

    //------------------------------------------------ Logica de salida
    // o_rd y o_wr son pulsos de un ciclo: valen 1 solo en el ciclo en que
    // efectivamente se consume o se entrega un byte (salidas Mealy, internas).
    always @(*) begin
        o_rd = 1'b0;
        o_wr = 1'b0;

        case (state)
            LOAD_A, LOAD_B, LOAD_OP: o_rd = ~i_rx_empty;
            SEND:                    o_wr = ~i_tx_full;
            default: ;
        endcase
    end

    //------------------------------------------------ ALU (combinacional)
    ALU #
    (
        .LENGTH_BITS (DATA_BITS),
        .LENGTH_OPT  (LENGTH_OPT)
    )
    u_alu
    (
        .o_result    (result),
        .o_zero      (o_zero),
        .o_carry     (o_carry),
        .o_overflow  (o_overflow),

        .i_dato_A    (dato_A),
        .i_dato_B    (dato_B),
        .i_opt       (opt)
    );

    assign o_w_data = result;

endmodule