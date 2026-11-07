`timescale 1ns / 1ps
`default_nettype none

//------------------------------------------------------------------------------
// control_fsmd — FSM + registros de la debug_unit (el "protocolo").
// VERSION 5: comandos 'L', 'X', 'D', 'S', 'R' e 'I' (protocolo completo).
//
// Recibe los comandos de la PC (via intf), los ejecuta sobre el procesador y
// arma las respuestas. Es el unico modulo que conoce el protocolo.
//
// Comandos implementados:
//   'L' (0x4C)  cargar programa        ->  responde 'K' (0x4B)
//               Formato: 'L', N (2 bytes, LSB primero), N palabras de 4 bytes
//               en little-endian. Ver "Como funciona la carga".
//   'X' (0x58)  reset del procesador   ->  responde 'K' (0x4B)
//   'D' (0x44)  volcado del estado     ->  responde los 314 bytes del volcado
//   'S' (0x53)  un ciclo de clock      ->  responde los 314 bytes del volcado
//   'R' (0x52)  correr hasta el HALT   ->  responde los 314 bytes del volcado
//   'I' (0x49)  interrumpir un 'R'     ->  (la respuesta es el volcado del 'R')
//               Solo tiene efecto DURANTE un 'R'; en cualquier otro momento
//               se consume y se descarta como un byte desconocido.
//   cualquier otro byte: se consume y se descarta (sin respuesta)
//
//   IDLE --('X' / rd)--> RESET --(siempre, 1 ciclo)--> ACK --(!tx_full / wr)--> IDLE
//   IDLE --('L' / rd, byte_cnt = 0)--> LOAD_LEN
//   LOAD_LEN  --(1.er byte / rd, N[7:0])--> LOAD_LEN
//   LOAD_LEN  --(2.o byte y N != 0 / rd, N[15:8], idx = 0)--> LOAD_WORD
//   LOAD_LEN  --(2.o byte y N == 0 / rd, idx = 0)--> CLEAR
//   LOAD_WORD --(byte 1..3 / rd, word = {byte, word[31:8]})--> LOAD_WORD
//   LOAD_WORD --(4.o byte  / rd, word = {byte, word[31:8]})--> WRITE
//   WRITE --(faltan palabras / idx++)--> LOAD_WORD
//   WRITE --(ultima palabra e idx < 255 / idx++)--> CLEAR
//   WRITE --(ultima palabra e idx >= 255)--> RESET
//   CLEAR --(idx < 255 / idx++)--> CLEAR
//   CLEAR --(idx == 255)--> RESET
//   IDLE --('D' / rd, dump_idx = 0)--> DUMP
//   IDLE --('S' / rd, interrupted = 0)--> STEP --(siempre, 1 ciclo; dump_idx = 0)--> DUMP
//   IDLE --('R' / rd, interrupted = 0)--> RUN
//   RUN  --(halted / dump_idx = 0)--> DUMP                       (termino solo)
//   RUN  --(!halted y llega 'I' / rd, dump_idx = 0, interrupted = 1)--> DUMP
//   RUN  --(otro byte / rd)--> RUN                               (se descarta)
//   DUMP --(!tx_full y quedan bytes / wr, dump_idx++)--> DUMP
//   DUMP --(!tx_full y ultimo byte  / wr, dump_idx = 0)--> IDLE
//   IDLE --(otro byte, incluida 'I' / rd)--> IDLE
//
// Salidas Moore (dependen solo del estado):
//   RESET : o_cpu_reset = 1          (dura exactamente 1 ciclo)
//   WRITE : o_imem_we = (idx < 256), o_imem_data = word (HALT si idx == 255)
//   CLEAR : o_imem_we = 1,           o_imem_data = HALT
//   WRITE y CLEAR: o_imem_addr = idx[7:0]
//   STEP  : o_cpu_enable = 1         (dura exactamente 1 ciclo: el procesador
//                                     recibe UN flanco habilitado)
//   ACK   : o_w_data    = 'K'
//   DUMP  : o_w_data    = i_dump_byte (el byte que el dump_mux eligio para dump_idx)
// Salidas Mealy (estado + entrada, igual que en ALU_ctrl):
//   IDLE, LOAD_LEN, LOAD_WORD : o_rd = !i_rx_empty
//   RUN       : o_rd = !i_rx_empty   (todo byte se consume: el buffer nunca
//                                     queda lleno durante la corrida)
//               o_cpu_enable = !i_halted
//   ACK, DUMP : o_wr = !i_tx_full
//
// Como funciona el volcado:
//   control_fsmd solo decide CUANDO se manda cada byte y en que ORDEN (dump_idx
//   = 0, 1, ..., 313). QUE byte va en cada posicion lo decide el dump_mux, que
//   es combinacional: con dump_idx estable, i_dump_byte esta listo en el mismo
//   ciclo. Por cada byte entregado (o_wr = 1) dump_idx avanza uno; mientras el
//   transmisor esta ocupado (i_tx_full = 1) dump_idx no cambia, asi que el byte
//   que ve la UART es siempre el correcto.
//
// Como funciona el paso a paso ('S'):
//   STEP dura un ciclo con o_cpu_enable = 1, asi que el procesador avanza
//   exactamente un flanco: el PC y los 4 latches se actualizan una vez (cada
//   instruccion del pipeline baja una etapa). En el ciclo siguiente la FSM ya
//   esta en DUMP con o_cpu_enable = 0: el procesador queda congelado y el
//   volcado muestra el estado DESPUES del paso. Si el procesador ya estaba
//   detenido (halted), ignora el enable y el volcado sale igual al anterior:
//   'S' siempre responde con el volcado.
//
// Como funciona la corrida ('R'):
//   En RUN, o_cpu_enable = !i_halted (Mealy): el procesador avanza un flanco
//   por ciclo mientras no este detenido. En el ciclo en que i_halted vale 1 el
//   enable ya es 0 (no depende de que el cpu ignore el enable cuando esta
//   detenido) y la FSM pasa a DUMP. El volcado sale con status.bit0 = 1.
//   Si al llegar 'R' el procesador ya estaba detenido, RUN dura 1 ciclo, con
//   enable = 0, y el volcado sale igual al anterior (0 ciclos sumados).
//
// Como funciona la interrupcion ('I'):
//   Un programa sin HALT (o con un loop infinito) nunca termina. Durante RUN
//   se lee todo byte que llega: si es 'I' se corta la corrida, se marca
//   interrupted = 1 y se manda el volcado (status.bit1 = 1); cualquier otro
//   byte se descarta y la corrida sigue. Si 'I' llega en el mismo ciclo en que
//   el procesador se detiene, gana el HALT (interrupted queda en 0): el
//   programa termino solo. En los dos casos la PC recibe UN volcado.
//   En el ciclo en que se detecta la 'I' el procesador todavia avanza ese
//   flanco (y se cuenta en cycles); desde el ciclo siguiente la FSM ya esta en
//   DUMP con o_cpu_enable = 0: el volcado muestra el estado congelado. Un
//   nuevo 'R' continua desde ese punto (el PC y los registros no se tocan).
//
// Como funciona la carga ('L'):
//   La PC manda los 3 + 4N bytes seguidos, sin esperar respuesta. Alcanza con
//   el buffer de 1 byte de rx_intf porque la FSM consume cada byte en el ciclo
//   siguiente a su llegada y el proximo tarda ~8680 ciclos (115200 baud).
//   En la debug_unit nunca hay mas de UNA palabra: se arma en el registro word
//   con un desplazamiento a derecha (el primer byte termina en [7:0], es decir
//   little-endian) y apenas esta completa, WRITE la escribe en la memoria del
//   procesador (1 ciclo con o_imem_we = 1). Despues word se reutiliza.
//   Mientras se carga, NINGUN byte es comando (un 0x58 dentro de una palabra
//   es solo un dato): la FSM consume siempre exactamente 4N bytes.
//   Al terminar:
//     - CLEAR escribe HALT (0x00000000) en las palabras N..255: despues de un
//       'L' la memoria tiene exactamente el programa y el resto es HALT (un
//       salto a memoria "vacia" se detiene, y no quedan restos de programas
//       anteriores). Con N = 0 la memoria queda toda en HALT.
//     - La palabra 255 SIEMPRE es HALT: si N >= 256, la palabra que llega en
//       esa posicion se reemplaza por HALT, y las palabras 256 en adelante se
//       consumen (para no desincronizarse) pero no se escriben.
//     - RESET + ACK, igual que 'X': el procesador arranca de cero (PC = 0,
//       pipeline vacio, cycles = 0, interrupted = 0) y la PC recibe 'K'.
//       'K' confirma un reset ('X') o una carga ('L') terminados.
//   Si se cortara la transmision a mitad de una carga, la FSM queda esperando
//   bytes: se recupera con el boton de reset. (Se asume que la PC y la UART
//   funcionan; no hay timeout.)
//
// Registros del datapath:
//   n_words     : N, cantidad de palabras del 'L' en curso (16 bits).
//   idx         : palabra actual de la carga / borrado (16 bits; la direccion
//                 de memoria son los 8 bits bajos).
//   word        : palabra que se esta armando (4 bytes).
//   byte_cnt    : que byte de N o de la palabra llego (0..3).
//   cycles      : ciclos que el procesador avanzo (enable = 1 y no halted).
//                 Vuelve a 0 con el reset global y con 'X'.
//   dump_idx    : indice del byte del volcado (0..313).
//   interrupted : 1 = la ultima corrida 'R' se corto con 'I'. Vuelve a 0 con el
//                 reset global, con 'X' y al empezar un 'R' o un 'S'. 'D' no
//                 lo cambia (muestra como quedo la ultima ejecucion).
// El byte de estado del volcado (o_status) tambien lo arma este modulo:
//   bit 0 = halted, bit 1 = interrupted, bits 7..2 = 0.
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
    output wire [7:0]    o_status,         // bit 0 = halted, bit 1 = interrupted
    input  wire [7:0]    i_dump_byte,      // byte del volcado en la posicion o_dump_idx

    // ---------------- Depuracion
    output reg  [3:0]    o_state_code      // estado en binario (para leds)
);

    //------------------------------------------------ Protocolo (params.vh sec. 6)
    localparam [7:0] CMD_LOAD  = 8'h4C,   // 'L'
                     CMD_RUN   = 8'h52,   // 'R'
                     CMD_STEP  = 8'h53,   // 'S'
                     CMD_DUMP  = 8'h44,   // 'D'
                     CMD_RESET = 8'h58,   // 'X'
                     CMD_INT   = 8'h49,   // 'I'  (solo durante RUN)
                     RSP_ACK   = 8'h4B;   // 'K'

    // Ultima posicion del volcado: 314 bytes -> indices 0..313
    localparam [8:0] DUMP_LAST = 9'd313;

    // Memoria de programa: 256 palabras (0..255)
    localparam [15:0] IMEM_LAST  = 16'd255;
    localparam [31:0] INSTR_HALT = 32'h0000_0000;

    //------------------------------------------------ Estados (one-hot)
    localparam [9:0] IDLE      = 10'b00_0000_0001,
                     LOAD_LEN  = 10'b00_0000_0010,
                     LOAD_WORD = 10'b00_0000_0100,
                     WRITE     = 10'b00_0000_1000,
                     RESET     = 10'b00_0001_0000,
                     ACK       = 10'b00_0010_0000,
                     RUN       = 10'b00_0100_0000,
                     STEP      = 10'b00_1000_0000,
                     DUMP      = 10'b01_0000_0000,
                     CLEAR     = 10'b10_0000_0000;

    //------------------------------------------------ Registros
    reg [9:0]  state,    next_state;
    reg [31:0] cycles,   cycles_next;
    reg [8:0]  dump_idx, dump_idx_next;
    reg        interrupted, interrupted_next;
    reg [15:0] n_words,  n_words_next;
    reg [15:0] idx,      idx_next;
    reg [31:0] word,     word_next;
    reg [1:0]  byte_cnt, byte_cnt_next;

    wire       last_word = (idx + 16'd1 == n_words);   // la palabra idx es la ultima

    //------------------------------------------------ Logica de memoria
    always @(posedge i_clk) begin
        if (i_reset) begin
            state       <= IDLE;
            cycles      <= 32'd0;
            dump_idx    <= 9'd0;
            interrupted <= 1'b0;
            n_words     <= 16'd0;
            idx         <= 16'd0;
            word        <= 32'd0;
            byte_cnt    <= 2'd0;
        end
        else begin
            state       <= next_state;
            cycles      <= cycles_next;
            dump_idx    <= dump_idx_next;
            interrupted <= interrupted_next;
            n_words     <= n_words_next;
            idx         <= idx_next;
            word        <= word_next;
            byte_cnt    <= byte_cnt_next;
        end
    end

    //------------------------------------------------ Logica de proximo estado
    always @(*) begin
        next_state       = state;
        cycles_next      = cycles;
        dump_idx_next    = dump_idx;
        interrupted_next = interrupted;
        n_words_next     = n_words;
        idx_next         = idx;
        word_next        = word;
        byte_cnt_next    = byte_cnt;

        // Contador de ciclos: suma cada ciclo en que el procesador avanza.
        if (o_cpu_enable && !i_halted)
            cycles_next = cycles + 32'd1;

        case (state)
            // Espera un comando. Si llega un byte, se consume siempre (o_rd):
            // los que no son comando se descartan y se sigue esperando.
            // 'I' aca no es comando: cae en default y se descarta.
            IDLE:
                if (!i_rx_empty) begin
                    case (i_r_data)
                        CMD_RESET: next_state = RESET;
                        CMD_LOAD: begin
                            byte_cnt_next = 2'd0;
                            next_state    = LOAD_LEN;
                        end
                        CMD_STEP: begin
                            interrupted_next = 1'b0;       // nueva ejecucion
                            next_state       = STEP;
                        end
                        CMD_RUN: begin
                            interrupted_next = 1'b0;       // nueva ejecucion
                            next_state       = RUN;
                        end
                        CMD_DUMP: begin
                            dump_idx_next = 9'd0;          // el volcado arranca en la cabecera
                            next_state    = DUMP;
                        end
                        default:   next_state = IDLE;      // byte desconocido
                    endcase
                end

            // Recibe N en 2 bytes (el menos significativo primero).
            LOAD_LEN:
                if (!i_rx_empty) begin
                    if (byte_cnt == 2'd0) begin
                        n_words_next[7:0] = i_r_data;
                        byte_cnt_next     = 2'd1;
                    end
                    else begin
                        n_words_next[15:8] = i_r_data;
                        byte_cnt_next      = 2'd0;
                        idx_next           = 16'd0;
                        if ({i_r_data, n_words[7:0]} == 16'd0)
                            next_state = CLEAR;            // N = 0: solo borrar
                        else
                            next_state = LOAD_WORD;
                    end
                end

            // Arma una palabra con 4 bytes: cada byte entra por arriba y los
            // anteriores bajan 8 bits. Con el 4.o la palabra esta completa.
            LOAD_WORD:
                if (!i_rx_empty) begin
                    word_next     = {i_r_data, word[31:8]};
                    byte_cnt_next = byte_cnt + 2'd1;       // 3 -> 0 al completar
                    if (byte_cnt == 2'd3)
                        next_state = WRITE;
                end

            // Un ciclo con o_imem_we (si idx < 256). Despues, la proxima
            // palabra, el borrado del resto de la memoria o el reset.
            WRITE:
                if (!last_word) begin
                    idx_next   = idx + 16'd1;
                    next_state = LOAD_WORD;
                end
                else if (idx < IMEM_LAST) begin
                    idx_next   = idx + 16'd1;
                    next_state = CLEAR;
                end
                else
                    next_state = RESET;                    // ya se llego a la 255

            // Escribe HALT en las palabras idx..255, una por ciclo.
            CLEAR:
                if (idx == IMEM_LAST)
                    next_state = RESET;
                else
                    idx_next = idx + 16'd1;

            // Un solo ciclo con o_cpu_reset = 1; el contador de ciclos y la
            // bandera de interrupcion vuelven a 0 junto con el procesador.
            RESET: begin
                cycles_next      = 32'd0;
                interrupted_next = 1'b0;
                next_state       = ACK;
            end

            // Manda 'K' apenas el transmisor este libre.
            ACK:
                if (!i_tx_full)
                    next_state = IDLE;

            // Un solo ciclo con o_cpu_enable = 1 (el procesador avanza un
            // flanco) y despues se manda el volcado del estado resultante.
            STEP: begin
                dump_idx_next = 9'd0;
                next_state    = DUMP;
            end

            // El procesador corre (o_cpu_enable = !i_halted) hasta que:
            //   - se detiene solo (HALT)       -> volcado, interrupted = 0
            //   - la PC manda 'I'              -> volcado, interrupted = 1
            // El HALT tiene prioridad: si los dos pasan en el mismo ciclo, el
            // programa termino solo. Los demas bytes se leen y se descartan.
            RUN:
                if (i_halted) begin
                    dump_idx_next = 9'd0;
                    next_state    = DUMP;
                end
                else if (!i_rx_empty && (i_r_data == CMD_INT)) begin
                    dump_idx_next    = 9'd0;
                    interrupted_next = 1'b1;
                    next_state       = DUMP;
                end

            // Manda los 314 bytes, uno por cada vez que el transmisor se libera.
            // En el ciclo en que se entrega un byte (o_wr = 1) se avanza al
            // siguiente; despues del ultimo se vuelve a IDLE.
            DUMP:
                if (!i_tx_full) begin
                    if (dump_idx == DUMP_LAST) begin
                        dump_idx_next = 9'd0;
                        next_state    = IDLE;
                    end
                    else
                        dump_idx_next = dump_idx + 9'd1;
                end

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
            IDLE:      o_rd = ~i_rx_empty;             // Mealy
            LOAD_LEN:  o_rd = ~i_rx_empty;             // Mealy
            LOAD_WORD: o_rd = ~i_rx_empty;             // Mealy

            WRITE: o_imem_we = (idx <= IMEM_LAST);     // Moore: las palabras 256+
                                                       // se descartan
            CLEAR: o_imem_we = 1'b1;                   // Moore

            RESET: o_cpu_reset = 1'b1;                 // Moore

            STEP:  o_cpu_enable = 1'b1;                // Moore

            RUN: begin
                o_cpu_enable = ~i_halted;              // Mealy
                o_rd         = ~i_rx_empty;            // Mealy: todo byte se consume
            end

            ACK: begin
                o_w_data = RSP_ACK;                    // Moore
                o_wr     = ~i_tx_full;                 // Mealy
            end

            DUMP: begin
                o_w_data = i_dump_byte;                // Moore (via dump_idx)
                o_wr     = ~i_tx_full;                 // Mealy
            end

            default: ;
        endcase
    end

    //------------------------------------------------ Salidas del datapath
    // En WRITE se escribe la palabra armada, salvo en la 255, que siempre es
    // HALT. En CLEAR (y en los demas estados, donde o_imem_we = 0) va HALT.
    assign o_imem_addr = idx[7:0];
    assign o_imem_data = (state == WRITE && idx != IMEM_LAST) ? word : INSTR_HALT;
    assign o_dump_idx  = dump_idx;
    assign o_cycles    = cycles;
    assign o_status    = {6'd0, interrupted, i_halted};

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
            CLEAR:     o_state_code = 4'd9;
            default:   o_state_code = 4'hF;
        endcase
    end

endmodule

`default_nettype wire
