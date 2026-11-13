`timescale 1ns / 1ps
`default_nettype none

//------------------------------------------------------------------------------
// tb_top_cpu — Testbench de INTEGRACION: top completo con el cpu REAL.
//
// Una segunda copia del modulo uart hace de "PC" y usa el protocolo igual que
// scripts/uart_test.py:
//
//   [ uart "PC" ] --tx--> i_rx [ top: uart > intf > debug_unit > cpu ]
//                 <--rx-- o_tx
//
// Los valores esperados NO salen del DUT: los calcula el modelo de referencia
// (scripts/rv32i_model.py) a partir de scripts/programas/*.asm y quedan en
// testbench/vectores/ (pNN.prog, pNN.exp, pNN.pasos).
//
// BAUD RATE: 1 Mbaud SOLO en este testbench (parametro pasado al top y a la
// uart "PC"); el valor por defecto del diseno sigue siendo 115200.
//
// Pruebas, para cada programa de los vectores:
//   1. 'L' con el programa (bytes seguidos, como la PC) -> 'K'. Despues 'D':
//      PC = 0, ciclos = 0, estado = 0, registros en 0 (el reset del 'L'), y se
//      anota la memoria de datos, que NO se borra: tiene que ser igual a la
//      del ultimo volcado del programa anterior.
//   2. Programa que termina: 'R' -> volcado completo contra el modelo: PC,
//      ciclos, estado (0x01 HALT o 0x05 error), 32 registros, memoria de datos
//      y, en un HALT normal, los 15 latches. En la memoria, las palabras que
//      el programa escribe tienen el valor del modelo y las demas conservan el
//      valor anotado en 1.
//   3. 'D' y otro 'R' (ya detenido) -> el mismo volcado, sin sumar ciclos.
//   4. Programa sin fin (j .): 'R', espera, 'I' -> estado 0x02, registros y
//      memoria del modelo, PC dentro del loop, ciclos > 0.
//   5. En algunos programas, paso a paso: 'X' -> 'K' y un 'S' por ciclo; cada
//      volcado contra el modelo (PC, ciclos, estado, registros y memoria; la
//      memoria previa es la que dejo la corrida anterior, porque 'X' tampoco
//      la borra).
//      Un 'S' de mas con el procesador detenido no cambia nada.
//   Con +RAPIDO se saltean los pasos 3 y 5 (lo usan las pruebas de mutacion).
//
// Uso (desde Laboratories/Lab3):
//   python3 scripts/rv32i_model.py --generar
//   iverilog -Wall -g2005 -o tb_top_cpu.vvp testbench/tb_top_cpu.v \
//            src/debug_unit/*.v src/cpu/*.v src/cpu/*/*.v
//   vvp -n tb_top_cpu.vvp
//
// Resultado: "PASS" o la lista de errores y "FAIL".
//------------------------------------------------------------------------------
module tb_top_cpu;

    localparam CLK_FREQ  = 100_000_000;
    localparam BAUD_RATE = 1_000_000;    // solo simulacion (ver arriba)
    localparam CLK_HALF  = 5;
    localparam FRAME_NS  = 10 * (1_000_000_000 / BAUD_RATE);

    localparam [7:0] CMD_RESET = 8'h58;   // 'X'
    localparam [7:0] CMD_DUMP  = 8'h44;   // 'D'
    localparam [7:0] CMD_STEP  = 8'h53;   // 'S'
    localparam [7:0] CMD_RUN   = 8'h52;   // 'R'
    localparam [7:0] CMD_INT   = 8'h49;   // 'I'
    localparam [7:0] CMD_LOAD  = 8'h4C;   // 'L'
    localparam [7:0] RSP_ACK   = 8'h4B;   // 'K'

    // Formato del volcado (params.vh, seccion 6)
    localparam DUMP_LEN = 326;
    localparam OFF_PC = 1, OFF_CYC = 5, OFF_ST = 9, OFF_REG = 10, OFF_LAT = 138,
               OFF_MEM = 198;

    //------------------------------------------------ Clock y DUT
    reg clk = 1'b0;
    always #CLK_HALF clk = ~clk;

    reg        btn_reset = 1'b0;
    wire       line_pc_to_fpga;
    wire       line_fpga_to_pc;
    wire [7:0] leds;

    top #
    (
        .CLK_FREQ     (CLK_FREQ),      // explicito: el default del top es 70 MHz
        .USE_CLK_WIZ  (0),             // iverilog no simula el IP: clk = i_clk
        .BAUD_RATE    (BAUD_RATE),
        .USE_CPU_STUB (0)              // el cpu real (igual que en la placa)
    )
    dut
    (
        .i_clk   (clk),
        .i_reset (btn_reset),
        .i_rx    (line_pc_to_fpga),
        .o_tx    (line_fpga_to_pc),
        .o_leds  (leds)
    );

    //------------------------------------------------ UART que hace de "PC"
    reg        pc_reset    = 1'b1;
    reg        pc_tx_start = 1'b0;
    reg  [7:0] pc_din      = 8'h00;
    wire       pc_tx_done;
    wire       pc_rx_done;
    wire [7:0] pc_dout;

    uart #
    (
        .CLK_FREQ  (CLK_FREQ),
        .BAUD_RATE (BAUD_RATE)
    )
    pc
    (
        .i_clk      (clk),
        .i_reset    (pc_reset),
        .i_rx       (line_fpga_to_pc),
        .o_tx       (line_pc_to_fpga),
        .o_rx_done  (pc_rx_done),
        .o_dout     (pc_dout),
        .i_tx_start (pc_tx_start),
        .i_din      (pc_din),
        .o_tx_done  (pc_tx_done)
    );

    // Todo byte que llega a la "PC" se guarda en un buffer circular.
    reg [7:0] rx_buf [0:2047];
    integer   n_recv    = 0;
    integer   n_checked = 0;
    always @(posedge clk)
        if (pc_rx_done) begin
            rx_buf[n_recv[10:0]] = pc_dout;
            n_recv = n_recv + 1;
        end

    // Ciclos en que la debug_unit hace avanzar al procesador.
    integer cpu_enable_cycles = 0;
    always @(posedge clk)
        if (dut.cpu_enable && !dut.halted)
            cpu_enable_cycles = cpu_enable_cycles + 1;

    //------------------------------------------------ Utilidades
    integer errors = 0;
    integer shown  = 0;

    task check(input [8*48-1:0] what, input [31:0] got, input [31:0] exp);
        if (got !== exp) begin
            if (shown < 40)
                $display("ERROR: %0s = %h, esperado %h  (t = %0t)", what, got, exp, $time);
            shown  = shown + 1;
            errors = errors + 1;
        end
    endtask

    // La PC manda un byte (espera el fin de la trama).
    task pc_send(input [7:0] b);
        begin
            @(negedge clk);
            pc_din      = b;
            pc_tx_start = 1'b1;
            @(negedge clk);
            pc_tx_start = 1'b0;
            @(posedge pc_tx_done);
            @(posedge clk);
        end
    endtask

    reg got_byte;
    task wait_byte;
        begin
            got_byte = 1'b0;
            fork : espera
                begin
                    wait (n_recv > n_checked);
                    got_byte = 1'b1;
                    disable espera;
                end
                begin
                    #(FRAME_NS * 3);
                    disable espera;
                end
            join
        end
    endtask

    task expect_byte(input [7:0] exp);
        begin
            wait_byte;
            if (!got_byte) begin
                $display("ERROR: timeout esperando %h  (t = %0t)", exp, $time);
                errors = errors + 1;
            end
            else begin
                check("byte recibido", {24'd0, rx_buf[n_checked[10:0]]}, {24'd0, exp});
                n_checked = n_checked + 1;
            end
        end
    endtask

    task expect_silence;
        begin
            #(FRAME_NS * 3);
            if (n_recv != n_checked) begin
                $display("ERROR: llegaron %0d bytes inesperados  (t = %0t)",
                         n_recv - n_checked, $time);
                errors = errors + 1;
                n_checked = n_recv;
            end
        end
    endtask

    //------------------------------------------------ Volcado recibido
    reg [7:0] dump [0:DUMP_LEN-1];
    integer   e;

    // Recibe un volcado completo (con timeout por byte) y verifica que no
    // llegue ni un byte de mas.
    task recv_dump(input [8*32-1:0] name);
        begin
            for (e = 0; e < DUMP_LEN; e = e + 1) begin
                wait_byte;
                if (!got_byte) begin
                    $display("ERROR: %0s: timeout en el byte %0d del volcado", name, e);
                    errors = errors + 1;
                    e = DUMP_LEN;
                end
                else begin
                    dump[e] = rx_buf[n_checked[10:0]];
                    n_checked = n_checked + 1;
                end
            end
            expect_silence;
        end
    endtask

    function [31:0] dword(input integer pos);
        dword = {dump[pos + 3], dump[pos + 2], dump[pos + 1], dump[pos]};
    endfunction

    //------------------------------------------------ Vectores del modelo
    reg [31:0]      prog   [0:255];
    reg [31:0]      vexp   [0:95];
    reg [31:0]      vpasos [0:16383];
    reg [31:0]      mem_ini [0:31];   // memoria de datos antes de correr
    reg [31:0]      mask;
    reg [31:0]      vidx   [0:0];
    reg [8*128-1:0] vec_dir;
    reg [8*160-1:0] fname;
    reg [255:0]     pname;
    integer         p, n_programs, n_prog, n_steps, k, w, base, n_pasos_S;
    integer         rapido;

    task read_vectors(input integer num);
        begin
            $sformat(fname, "%0sp%02d.prog", vec_dir, num);
            $readmemh(fname, prog);
            $sformat(fname, "%0sp%02d.exp", vec_dir, num);
            $readmemh(fname, vexp);
            n_prog  = vexp[1];
            n_steps = vexp[6];
            $sformat(fname, "%0sp%02d.pasos", vec_dir, num);
            $readmemh(fname, vpasos, 0, 67 * n_steps - 1);
            pname = {vexp[8], vexp[9], vexp[10], vexp[11],
                     vexp[12], vexp[13], vexp[14], vexp[15]};
        end
    endtask

    // 'L' + N (2 bytes) + N palabras little-endian, todo seguido -> 'K'.
    task load_prog;
        begin
            pc_send(CMD_LOAD);
            pc_send(n_prog[7:0]);
            pc_send(n_prog[15:8]);
            for (w = 0; w < n_prog; w = w + 1) begin
                pc_send(prog[w][ 7: 0]);
                pc_send(prog[w][15: 8]);
                pc_send(prog[w][23:16]);
                pc_send(prog[w][31:24]);
            end
            expect_byte(RSP_ACK);
            expect_silence;
        end
    endtask

    // Compara el volcado recibido con el estado final del modelo.
    task check_final(input [8*16-1:0] cmd, input check_cycles);
        begin
            check({pname, " cabecera"}, {24'd0, dump[0]}, 32'h0000_00A5);
            check({pname, " PC"},     dword(OFF_PC), vexp[3]);
            if (check_cycles)
                check({pname, " ciclos"}, dword(OFF_CYC), vexp[2]);
            check({pname, " estado"}, {24'd0, dump[OFF_ST]}, vexp[4]);
            mask = vexp[7];
            for (k = 0; k < 32; k = k + 1) begin
                check({pname, " registro"}, dword(OFF_REG + 4 * k), vexp[16 + k]);
                check({pname, " memoria"},  dword(OFF_MEM + 4 * k),
                      mask[k] ? vexp[48 + k] : mem_ini[k]);
            end
            if (vexp[5] == 1)
                for (k = 0; k < 15; k = k + 1)
                    check({pname, " latch"}, dword(OFF_LAT + 4 * k), vexp[80 + k]);
        end
    endtask

    // Compara el volcado con el paso n del modelo (despues de n ciclos).
    task check_step(input integer n);
        begin
            base = 67 * (n - 1);
            mask = vpasos[base + 66];
            check({pname, " S: cabecera"}, {24'd0, dump[0]}, 32'h0000_00A5);
            check({pname, " S: PC"},     dword(OFF_PC), vpasos[base + 64]);
            check({pname, " S: ciclos"}, dword(OFF_CYC), n);
            check({pname, " S: estado"}, {24'd0, dump[OFF_ST]}, vpasos[base + 65]);
            for (k = 0; k < 32; k = k + 1) begin
                check({pname, " S: registro"}, dword(OFF_REG + 4 * k), vpasos[base + k]);
                check({pname, " S: memoria"},  dword(OFF_MEM + 4 * k),
                      mask[k] ? vpasos[base + 32 + k] : mem_ini[k]);
            end
        end
    endtask

    // Anota la memoria de datos del ultimo volcado recibido.
    task capture_mem;
        for (k = 0; k < 32; k = k + 1)
            mem_ini[k] = dword(OFF_MEM + 4 * k);
    endtask

    // Paso a paso del programa ya cargado: 'X' y n_pasos 'S'. La memoria
    // previa es la del ultimo volcado ('X' no la borra).
    integer s, err0;
    task run_steps(input integer n_pasos);
        begin
            capture_mem;
            pc_send(CMD_RESET);
            expect_byte(RSP_ACK);
            err0 = errors;
            for (s = 1; s <= n_pasos; s = s + 1) begin
                pc_send(CMD_STEP);
                recv_dump("S");
                check_step(s);
                if (errors != err0 && shown < 40) begin
                    $display("       ^ %0s, despues del 'S' numero %0d", pname, s);
                    err0 = errors;
                end
            end
            // Ya detenido: un 'S' mas no cambia nada.
            if (vexp[2] != 0 && n_pasos == n_steps) begin
                pc_send(CMD_STEP);
                recv_dump("S detenido");
                check_step(n_steps);
            end
        end
    endtask

    // ¿Se hace el paso a paso con este programa? (los cortos, para no tardar)
    function do_steps(input [255:0] nombre);
        do_steps = (nombre == "sumas_encadenadas               ") ||
                   (nombre == "error_lw                        ") ||
                   (nombre == "nops_5                          ") ||
                   (nombre == "loop_infinito                   ");
    endfunction

    //------------------------------------------------ Secuencia
    integer en0, cyc;
    initial begin
        rapido = $test$plusargs("RAPIDO");
        vec_dir = "testbench/vectores/";
        if ($value$plusargs("VEC=%s", vec_dir)) ;
        $sformat(fname, "%0sindice.mem", vec_dir);
        vidx[0] = 32'd0;
        $readmemh(fname, vidx);
        n_programs = vidx[0];
        if (n_programs == 0) begin
            $display("ERROR: no hay vectores en %0s (correr rv32i_model.py --generar)", vec_dir);
            errors = errors + 1;
        end

        // Arranque: reset de la UART "PC"; el top tiene su reset de encendido.
        repeat (5) @(posedge clk);
        pc_reset = 1'b0;
        repeat (40) @(posedge clk);

        for (p = 0; p < n_programs; p = p + 1) begin
            read_vectors(p);
            load_prog;
            //---------------------------- 1. 'D' despues del 'L'
            pc_send(CMD_DUMP);
            recv_dump("D tras L");
            check({pname, " L: PC"},     dword(OFF_PC), 32'd0);
            check({pname, " L: ciclos"}, dword(OFF_CYC), 32'd0);
            check({pname, " L: estado"}, {24'd0, dump[OFF_ST]}, 32'd0);
            for (k = 0; k < 32; k = k + 1) begin
                check({pname, " L: registro"}, dword(OFF_REG + 4 * k), 32'd0);
                // 'L' no borra la memoria de datos: queda la del programa anterior.
                if (p > 0)
                    check({pname, " L: memoria conservada"}, dword(OFF_MEM + 4 * k), mem_ini[k]);
            end
            capture_mem;
            if (vexp[2] != 0) begin
                //---------------------------- 2. 'R' hasta el HALT / error
                en0 = cpu_enable_cycles;
                pc_send(CMD_RUN);
                recv_dump("R");
                check_final("R", 1'b1);
                check({pname, " ciclos de enable en 'R'"}, cpu_enable_cycles - en0, vexp[2]);
                //---------------------------- 3. 'D' y 'R' ya detenido
                if (!rapido) begin
                    pc_send(CMD_DUMP);
                    recv_dump("D");
                    check_final("D", 1'b1);
                    pc_send(CMD_RUN);
                    recv_dump("R detenido");
                    check_final("R detenido", 1'b1);
                end
            end
            else begin
                //---------------------------- 4. sin fin: 'R' + 'I'
                pc_send(CMD_RUN);
                #(FRAME_NS * 2);
                check({pname, " leds en RUN"}, {28'd0, leds[3:0]}, 32'd6);
                pc_send(CMD_INT);
                recv_dump("R + I");
                check({pname, " estado (interrumpido)"}, {24'd0, dump[OFF_ST]}, 32'h0000_0002);
                mask = vexp[7];
                for (k = 0; k < 32; k = k + 1) begin
                    check({pname, " registro"}, dword(OFF_REG + 4 * k), vexp[16 + k]);
                    check({pname, " memoria"},  dword(OFF_MEM + 4 * k),
                          mask[k] ? vexp[48 + k] : mem_ini[k]);
                end
                // j . en vexp[3]: el PC busca el loop y las 2 siguientes.
                check({pname, " PC dentro del loop"},
                      {31'd0, (dword(OFF_PC) - vexp[3]) <= 32'd8}, 32'd1);
                cyc = dword(OFF_CYC);
                check({pname, " ciclos > 1000"}, {31'd0, cyc > 1000}, 32'd1);
            end
            //---------------------------- 5. paso a paso
            if (!rapido && do_steps(pname)) begin
                n_pasos_S = (vexp[2] != 0) ? n_steps : 12;
                run_steps(n_pasos_S);
            end
            capture_mem;                          // memoria con la que termino
            $display("  programa %0d %0s: %0s%0s", p, pname,
                     (vexp[2] == 0) ? "L, R + I" : (rapido ? "L, R" : "L, R, D, R"),
                     (!rapido && do_steps(pname)) ? ", X + S paso a paso" : "");
        end

        if (errors == 0) $display("PASS: top con el cpu real (%0d programas por UART)", n_programs);
        else             $display("FAIL: %0d errores", errors);
        $finish;
    end

    initial begin
        #2_000_000_000;
        $display("FAIL: timeout global");
        $finish;
    end

endmodule

`default_nettype wire
