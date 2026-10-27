`timescale 1ns / 1ps
`default_nettype none

//------------------------------------------------------------------------------
// control_fsmd — FSM + registros de la debug_unit (el "protocolo").
// VERSION 1: solo comando 'X'.
//
// Recibe los comandos de la PC (via intf), los ejecuta sobre el procesador y
// arma las respuestas. Es el unico modulo que conoce el protocolo.
//
// Comandos implementados en esta version:
//   'X' (0x58)  reset del procesador  ->  responde 'K' (0x4B)
//   cualquier otro byte: se consume y se descarta (sin respuesta)
//
//   IDLE --('X' / rd)--> RESET --(siempre, 1 ciclo)--> ACK --(!tx_full / wr)--> IDLE
//   IDLE --(otro byte / rd)--> IDLE
//
// Salidas Moore (dependen solo del estado):
//   RESET : o_cpu_reset = 1   (dura exactamente 1 ciclo)
//   ACK   : o_w_data    = 'K'
// Salidas Mealy (estado + entrada, igual que en ALU_ctrl):
//   IDLE  : o_rd = !i_rx_empty
//   ACK   : o_wr = !i_tx_full
//
// Registros del datapath que ya existen (los va a usar el volcado 'D'):
//   cycles   : ciclos que el procesador avanzo (enable = 1 y no halted).
//              Vuelve a 0 con el reset global y con 'X'.
//   dump_idx : indice del byte del volcado (0..313). Por ahora queda en 0.
// El byte de estado del volcado (o_status) tambien lo arma este modulo.
//------------------------------------------------------------------------------
module control_fsmd
(
    input  wire          i_clk,
    input  wire          i_reset,          // reset GLOBAL (reset_gen)

    // ---------------- Lado intf
    input  wire [7:0]    i_r_data,
    input  wire          i_rx_empty,
    output reg           o_rd,

    output reg  [7:0]    o_w_data,
    input  wire          i_tx_full,
    output reg           o_wr,

    // ---------------- Control del procesador
    output reg           o_cpu_enable,
    output reg           o_cpu_reset,
    output reg           o_imem_we,
    output wire [7:0]    o_imem_addr,
    output wire [31:0]   o_imem_data,
    input  wire          i_halted,

    // ---------------- Hacia / desde el dump_mux
    output wire [8:0]    o_dump_idx,       // 0..313
    output wire [31:0]   o_cycles,
    output wire [7:0]    o_status,         // bit 0 = halted
    input  wire [7:0]    i_dump_byte,      // (se usa con 'D')

    // ---------------- Depuracion
    output reg  [3:0]    o_state_code      // estado en binario (para leds)
);

    //------------------------------------------------ Protocolo (params.vh sec. 6)
    localparam [7:0] CMD_LOAD  = 8'h4C,   // 'L'  (pendiente)
                     CMD_RUN   = 8'h52,   // 'R'  (pendiente)
                     CMD_STEP  = 8'h53,   // 'S'  (pendiente)
                     CMD_DUMP  = 8'h44,   // 'D'  (pendiente)
                     CMD_RESET = 8'h58,   // 'X'
                     RSP_ACK   = 8'h4B;   // 'K'

    //------------------------------------------------ Estados (one-hot)
    // Se declaran todos los del diagrama para fijar la codificacion desde ya.
    // Los marcados "pendiente" todavia no se alcanzan nunca.
    localparam [8:0] IDLE      = 9'b0_0000_0001,
                     LOAD_LEN  = 9'b0_0000_0010,   // pendiente ('L')
                     LOAD_WORD = 9'b0_0000_0100,   // pendiente ('L')
                     WRITE     = 9'b0_0000_1000,   // pendiente ('L')
                     RESET     = 9'b0_0001_0000,
                     ACK       = 9'b0_0010_0000,
                     RUN       = 9'b0_0100_0000,   // pendiente ('R')
                     STEP      = 9'b0_1000_0000,   // pendiente ('S')
                     DUMP      = 9'b1_0000_0000;   // pendiente ('D')

    //------------------------------------------------ Registros
    reg [8:0]  state,    next_state;
    reg [31:0] cycles,   cycles_next;
    reg [8:0]  dump_idx, dump_idx_next;

    //------------------------------------------------ Logica de memoria
    always @(posedge i_clk) begin
        if (i_reset) begin
            state    <= IDLE;
            cycles   <= 32'd0;
            dump_idx <= 9'd0;
        end
        else begin
            state    <= next_state;
            cycles   <= cycles_next;
            dump_idx <= dump_idx_next;
        end
    end

    //------------------------------------------------ Logica de proximo estado
    always @(*) begin
        next_state    = state;
        cycles_next   = cycles;
        dump_idx_next = dump_idx;

        // Contador de ciclos: suma cada ciclo en que el procesador avanza.
        if (o_cpu_enable && !i_halted)
            cycles_next = cycles + 32'd1;

        case (state)
            // Espera un comando. Si llega un byte, se consume siempre (o_rd):
            // los que no son comando se descartan y se sigue esperando.
            IDLE:
                if (!i_rx_empty) begin
                    case (i_r_data)
                        CMD_RESET: next_state = RESET;
                        default:   next_state = IDLE;     // byte desconocido
                    endcase
                end

            // Un solo ciclo con o_cpu_reset = 1; el contador de ciclos
            // vuelve a 0 junto con el procesador.
            RESET: begin
                cycles_next = 32'd0;
                next_state  = ACK;
            end

            // Manda 'K' apenas el transmisor este libre.
            ACK:
                if (!i_tx_full)
                    next_state = IDLE;

            // Estados pendientes o invalidos: recuperacion
            default:
                next_state = IDLE;
        endcase
    end

    //------------------------------------------------ Logica de salida
    always @(*) begin
        // Por defecto todo en 0 (las salidas no listadas en un estado valen 0)
        o_rd         = 1'b0;
        o_wr         = 1'b0;
        o_w_data     = 8'h00;
        o_cpu_enable = 1'b0;
        o_cpu_reset  = 1'b0;
        o_imem_we    = 1'b0;

        case (state)
            IDLE:  o_rd = ~i_rx_empty;                 // Mealy

            RESET: o_cpu_reset = 1'b1;                 // Moore

            ACK: begin
                o_w_data = RSP_ACK;                    // Moore
                o_wr     = ~i_tx_full;                 // Mealy
            end

            default: ;
        endcase
    end

    //------------------------------------------------ Salidas del datapath
    assign o_imem_addr = 8'd0;          // se usan con 'L'
    assign o_imem_data = 32'd0;
    assign o_dump_idx  = dump_idx;
    assign o_cycles    = cycles;
    assign o_status    = {7'd0, i_halted};

    //------------------------------------------------ Codigo de estado (leds)
    always @(*) begin
        case (state)
            IDLE:      o_state_code = 4'd0;
            LOAD_LEN:  o_state_code = 4'd1;
            LOAD_WORD: o_state_code = 4'd2;
            WRITE:     o_state_code = 4'd3;
            RESET:     o_state_code = 4'd4;
            ACK:       o_state_code = 4'd5;
            RUN:       o_state_code = 4'd6;
            STEP:      o_state_code = 4'd7;
            DUMP:      o_state_code = 4'd8;
            default:   o_state_code = 4'hF;
        endcase
    end

endmodule

`default_nettype wire
