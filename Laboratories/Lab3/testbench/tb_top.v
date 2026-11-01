`timescale 1ns / 1ps
`default_nettype none

//------------------------------------------------------------------------------
// Testbench del top — PASO 3, debug_unit version 4 (comandos 'X', 'D', 'S',
// 'R' e 'I').
//
// Una segunda copia del modulo uart hace de "PC": manda comandos del protocolo
// y recibe las respuestas, que se verifican contra lo esperado.
//
//   [ uart "PC" ] --tx--> i_rx [ top: uart > intf > debug_unit > cpu_stub ]
//                 <--rx-- o_tx
//
// Como todavia no existe 'L', el testbench le escribe valores al cpu_stub
// directamente con referencias jerarquicas (dut.u_cpu.pc = ...). Es un recurso
// valido solo en simulacion.
//
// BAUD RATE: este testbench usa 1 Mbaud (parametro BAUD_RATE pasado al top y a
// la uart "PC") para que cada volcado tarde ~3 ms simulados en lugar de 27 ms.
// Los dos extremos usan los mismos parametros, asi que la logica probada es la
// misma. El diseño NO cambia: el valor por defecto de todos los modulos sigue
// siendo 115200 (validado en la placa).
//
// La memoria del cpu_stub arranca con INIT_NOPS = 8 NOPs (igual que en la
// placa) y el modelo del testbench lo tiene en cuenta.
//
// El volcado ESPERADO se arma en el testbench con un modelo propio del
// cpu_stub (mismas formulas que documenta cpu_stub.v), no leyendo al DUT.
//
// Pruebas:
//   1. Arranque: TX en reposo (1) y debug_unit en IDLE (leds = 0).
//   2. 'X' -> 'K', el PC del stub vuelve a 0, cpu_reset dura 1 ciclo.
//   3. Bytes que no son comando (incluida 'I' fuera de RUN) -> sin respuesta
//      y sin reset.
//   4. 'X' otra vez -> sigue funcionando.
//   5. Boton de reset -> tambien resetea el procesador (OR de reset).
//   6. 'D' recien reseteado -> 314 bytes: PC = 0, estado = 0, memoria en 0.
//   7. 'D' con PC, memoria y halted forzados -> 314 bytes con esos valores;
//      durante el volcado los leds muestran el estado DUMP (8).
//   8. 'X' y 'D' -> PC = 0 y halted = 0 otra vez; la memoria se conserva.
//   9. 'S' paso a paso hasta el HALT: PC +4 por paso, ciclos +1, el PC se
//      congela en el HALT, halted sube 4 pasos despues y los 'S' siguientes ya
//      no cambian nada. Cada 'S' da exactamente 1 ciclo de cpu_enable.
//  10. 'X' y 'D' despues de los pasos: PC, ciclos y halted vuelven a 0.
//  11. Totales parciales: cpu_enable solo se activo en los 'S'.
//  12. 'R' hasta el HALT: mismo volcado que S7 (PC 0xC, 7 ciclos, status 0x01)
//      y exactamente 7 ciclos de cpu_enable.
//  13. 'R' con el procesador ya detenido: mismo volcado, 0 ciclos de enable.
//  14. 'I' fuera de RUN (procesador detenido, en IDLE): se ignora.
//  15. Programa sin HALT (todo NOP): 'R' corre indefinidamente; los leds
//      muestran RUN (6); otros bytes ('D','S','X','R','i') se descartan y la
//      corrida sigue; 'I' la corta: volcado con status 0x02,
//      PC = 4 * ciclos y ciclos = ciclos de enable (ni uno de mas).
//  16. 'D' despues de la interrupcion: status sigue en 0x02. Una 'I' mandada
//      en medio del volcado no lo altera y despues se ignora.
//  17. Otro 'R' + 'I': continua desde donde quedo (ciclos y PC siguen sumando).
//  18. 'S' despues de una interrupcion: borra el bit (status 0x00), PC +4.
//  19. 'R' + 'I' y despues 'X': 'X' tambien borra el bit (D -> status 0x00).
//  20. 'R' borra el bit: 'R' + 'I' (0x02), se pone un HALT 3 palabras mas
//      adelante y otro 'R' termina solo con status 0x01.
//  21. Empate: 'I' llega en el mismo ciclo en que el procesador se detiene ->
//      gana el HALT (status 0x01) y se manda un solo volcado.
//  22. Total de cpu_reset.
//
// Resultado: imprime "PASS" o la lista de errores y "FAIL".
//------------------------------------------------------------------------------
module tb_top;

    localparam CLK_FREQ  = 100_000_000;
    localparam BAUD_RATE = 1_000_000;    // solo simulacion (ver arriba)
    localparam INIT_NOPS = 8;            // igual que en el top de la placa
    localparam CLK_HALF  = 5;                                // 100 MHz
    localparam FRAME_NS  = 10 * (1_000_000_000 / BAUD_RATE); // 10 us por byte a 1 Mbaud

    localparam [7:0] CMD_RESET = 8'h58;   // 'X'
    localparam [7:0] CMD_DUMP  = 8'h44;   // 'D'
    localparam [7:0] CMD_STEP  = 8'h53;   // 'S'
    localparam [7:0] CMD_RUN   = 8'h52;   // 'R'
    localparam [7:0] CMD_INT   = 8'h49;   // 'I'
    localparam [7:0] RSP_ACK   = 8'h4B;   // 'K'
    localparam       DUMP_LEN  = 314;

    //------------------------------------------------ Clock
    reg clk = 1'b0;
    always #CLK_HALF clk = ~clk;

    //------------------------------------------------ DUT
    reg        btn_reset = 1'b0;
    wire       line_pc_to_fpga;
    wire       line_fpga_to_pc;
    wire [7:0] leds;

    top #
    (
        .CLK_FREQ       (CLK_FREQ),
        .BAUD_RATE      (BAUD_RATE),
        .STUB_INIT_NOPS (INIT_NOPS)
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

    //------------------------------------------------ Recepcion (en paralelo)
    // Todo byte que llega a la "PC" se guarda; las tareas expect_* lo consumen.
    reg [7:0] rx_buf [0:2047];
    integer   n_recv    = 0;    // bytes recibidos
    integer   n_checked = 0;    // bytes ya verificados

    always @(posedge clk)
        if (pc_rx_done) begin
            rx_buf[n_recv[10:0]] = pc_dout;
            n_recv = n_recv + 1;
        end

    //------------------------------------------------ Monitores
    // Ciclos en que la debug_unit pide reset del procesador.
    integer cpu_reset_cycles = 0;
    always @(posedge clk)
        if (dut.cpu_reset)
            cpu_reset_cycles = cpu_reset_cycles + 1;

    // Ciclos en que la debug_unit hace avanzar al procesador ('S' y 'R').
    integer cpu_enable_cycles = 0;
    always @(posedge clk)
        if (dut.cpu_enable)
            cpu_enable_cycles = cpu_enable_cycles + 1;

    //------------------------------------------------ Modelo del cpu_stub
    // Mismas formulas que documenta cpu_stub.v.
    function [31:0] reg_model(input [4:0] n, input [31:0] pc_v);
        reg_model = (n == 0) ? 32'd0 : {pc_v[15:0], 8'h00, 3'b000, n};
    endfunction

    function [31:0] latch_model(input [3:0] k, input [31:0] pc_v);
        latch_model = {4'hA, k, pc_v[23:0]};
    endfunction

    // Copia de lo que el testbench escribio en la memoria de programa del stub
    // (que el stub devuelve por el puerto de "memoria de datos").
    reg [31:0] mem_model [0:31];
    integer    m;
    initial
        for (m = 0; m < 32; m = m + 1)
            mem_model[m] = (m < INIT_NOPS) ? 32'h0000_0013   // NOP
                                           : 32'h0000_0000;  // HALT

    //------------------------------------------------ Utilidades
    integer errors = 0;

    task check(input [8*48-1:0] what, input [31:0] got, input [31:0] exp);
        if (got !== exp) begin
            $display("ERROR: %0s = %h, esperado %h  (t = %0t)", what, got, exp, $time);
            errors = errors + 1;
        end
    endtask

    // La PC manda un byte. Espera un ciclo despues de o_tx_done porque en el
    // estado DONE el tx_fsmd ignora i_tx_start.
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

    // Espera a que haya un byte nuevo (con timeout). ok = 1 si llego.
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

    // Espera el proximo byte de la FPGA y lo compara.
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

    // Verifica que la FPGA NO mande nada durante un rato.
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

    // Escribe un valor en el PC del stub (solo simulacion).
    task set_stub_pc(input [31:0] v);
        begin
            @(negedge clk);
            dut.u_cpu.pc = v;
            #1;
            check("PC del stub (forzado)", dut.pc, v);
        end
    endtask

    // Escribe una palabra en la memoria del stub y en el modelo (solo simulacion).
    task set_stub_mem(input [7:0] addr, input [31:0] v);
        begin
            @(negedge clk);
            dut.u_cpu.imem[addr] = v;
            if (addr < 32) mem_model[addr] = v;
        end
    endtask

    // Fuerza halted = 1 en el stub (solo simulacion).
    task set_stub_halted;
        begin
            @(negedge clk);
            dut.u_cpu.halting   = 1'b1;
            dut.u_cpu.drain_cnt = 2'd3;
            #1;
            check("halted del stub (forzado)", {31'd0, dut.halted}, 32'd1);
        end
    endtask

    //------------------------------------------------ Volcado esperado
    reg [7:0] expected [0:DUMP_LEN-1];
    integer   e, k;

    task put_word(input integer pos, input [31:0] w);     // little-endian
        begin
            expected[pos    ] = w[ 7: 0];
            expected[pos + 1] = w[15: 8];
            expected[pos + 2] = w[23:16];
            expected[pos + 3] = w[31:24];
        end
    endtask

    // Arma el volcado esperado (formato de params.vh, seccion 6).
    task build_expected(input [31:0] pc_v, input [31:0] cycles_v, input [7:0] status_v);
        begin
            e = 0;
            expected[e] = 8'hA5;                       e = e + 1;   // cabecera
            put_word(e, pc_v);                         e = e + 4;   // PC
            put_word(e, cycles_v);                     e = e + 4;   // ciclos
            expected[e] = status_v;                    e = e + 1;   // estado
            for (k = 0; k < 32; k = k + 1) begin                    // registros
                put_word(e, reg_model(k[4:0], pc_v));  e = e + 4;
            end
            for (k = 0; k < 12; k = k + 1) begin                    // latches
                put_word(e, latch_model(k[3:0], pc_v)); e = e + 4;
            end
            for (k = 0; k < 32; k = k + 1) begin                    // memoria
                put_word(e, mem_model[k]);             e = e + 4;
            end
        end
    endtask

    // Recibe 314 bytes y los compara con "expected". Solo muestra los primeros
    // errores. Despues verifica que no llegue ni un byte de mas.
    integer dump_errors;
    integer en_before;                    // cpu_enable_cycles antes de un comando
    task recv_dump(input [8*32-1:0] name);
        begin
            dump_errors = 0;
            for (e = 0; e < DUMP_LEN; e = e + 1) begin
                wait_byte;
                if (!got_byte) begin
                    $display("ERROR: %0s: timeout en el byte %0d del volcado", name, e);
                    errors = errors + 1;
                    e = DUMP_LEN;                          // corta el bucle
                end
                else begin
                    if (rx_buf[n_checked[10:0]] !== expected[e]) begin
                        if (dump_errors < 8)
                            $display("ERROR: %0s: byte %0d = %h, esperado %h",
                                     name, e, rx_buf[n_checked[10:0]], expected[e]);
                        dump_errors = dump_errors + 1;
                    end
                    n_checked = n_checked + 1;
                end
            end
            if (dump_errors != 0) begin
                $display("ERROR: %0s: %0d bytes distintos en el volcado", name, dump_errors);
                errors = errors + 1;
            end
            expect_silence;                                // ni un byte de mas
        end
    endtask

    // Manda un comando que responde con volcado ('D', 'S' o 'R') y verifica los
    // 314 bytes contra el volcado esperado (armado con el modelo).
    task check_cmd_dump(input [7:0] cmd, input [8*32-1:0] name, input [31:0] pc_v,
                        input [31:0] cycles_v, input [7:0] status_v);
        begin
            build_expected(pc_v, cycles_v, status_v);
            pc_send(cmd);
            recv_dump(name);
        end
    endtask

    // Para un volcado que ya viene en camino y cuyo PC/ciclos no se conocen de
    // antemano (corrida cortada con 'I'): cuando llega la cabecera el procesador
    // ya esta congelado, asi que se toman PC y ciclos del DUT, se arma el
    // volcado esperado con el modelo y se comparan los 314 bytes. Quien llama
    // verifica que snap_pc y snap_cycles sean coherentes (PC = 4 * ciclos, ...).
    reg [31:0] snap_pc, snap_cycles;
    task check_dump_snapshot(input [8*32-1:0] name, input [7:0] status_v);
        begin
            wait_byte;                                     // cabecera (no la consume)
            if (!got_byte) begin
                $display("ERROR: %0s: timeout esperando el volcado", name);
                errors = errors + 1;
            end
            else begin
                snap_pc     = dut.pc;
                snap_cycles = dut.u_debug_unit.u_control_fsmd.cycles;
                build_expected(snap_pc, snap_cycles, status_v);
                recv_dump(name);
                check("PC congelado durante el volcado", dut.pc, snap_pc);
            end
        end
    endtask

    // Un 'R' que termina solo: verifica el volcado y los ciclos de enable.
    task check_run(input [8*32-1:0] name, input [31:0] pc_v, input [31:0] cycles_v,
                   input [7:0] status_v, input [31:0] enables);
        begin
            en_before = cpu_enable_cycles;
            check_cmd_dump(CMD_RUN, name, pc_v, cycles_v, status_v);
            check("ciclos de cpu_enable en el 'R'", cpu_enable_cycles - en_before, enables);
        end
    endtask

    // Un 'R' sobre un programa sin fin, cortado con 'I'. Verifica que el
    // volcado tenga el status pedido, que el PC haya avanzado 4 por ciclo desde
    // (pc0, cyc0) y que los ciclos sumados coincidan con los de enable.
    reg [31:0] run_pc0, run_cyc0;
    task check_run_int(input [8*32-1:0] name, input [7:0] status_v);
        begin
            run_pc0   = dut.pc;
            run_cyc0  = dut.u_debug_unit.u_control_fsmd.cycles;
            en_before = cpu_enable_cycles;
            pc_send(CMD_RUN);
            #(FRAME_NS * 2);                               // corre un rato
            pc_send(CMD_INT);
            check_dump_snapshot(name, status_v);
            $display("  %0s: cortado en PC = 0x%h, ciclos = %0d", name, snap_pc, snap_cycles);
            if (snap_cycles <= run_cyc0) begin
                $display("ERROR: %0s: el procesador no avanzo", name);
                errors = errors + 1;
            end
            check("PC - PC inicial = 4 * ciclos", snap_pc - run_pc0, 4 * (snap_cycles - run_cyc0));
            check("ciclos sumados = ciclos de enable", snap_cycles - run_cyc0,
                  cpu_enable_cycles - en_before);
        end
    endtask

    // Llena toda la memoria del stub con NOP: un programa que nunca termina.
    task fill_nops;
        begin
            @(negedge clk);
            for (k = 0; k < 256; k = k + 1) begin
                dut.u_cpu.imem[k] = 32'h0000_0013;
                if (k < 32) mem_model[k] = 32'h0000_0013;
            end
        end
    endtask

    task check_dump(input [8*32-1:0] name, input [31:0] pc_v, input [31:0] cycles_v,
                    input [7:0] status_v);
        check_cmd_dump(CMD_DUMP, name, pc_v, cycles_v, status_v);
    endtask

    // Un 'S': verifica el volcado y que haya dado exactamente 1 ciclo de enable.
    task check_step(input [8*32-1:0] name, input [31:0] pc_v, input [31:0] cycles_v,
                    input [7:0] status_v);
        begin
            en_before = cpu_enable_cycles;
            check_cmd_dump(CMD_STEP, name, pc_v, cycles_v, status_v);
            check("ciclos de cpu_enable en un 'S'", cpu_enable_cycles - en_before, 32'd1);
        end
    endtask

    //------------------------------------------------ Secuencia
    initial begin
        //---------------------------------------- 1. Arranque
        #1;
        check("TX al arrancar", {31'd0, line_fpga_to_pc}, 32'd1);
        repeat (5) @(posedge clk);
        pc_reset = 1'b0;
        repeat (50) @(posedge clk); #1;     // termina el power-on reset del DUT
        check("leds en IDLE", {24'd0, leds}, 32'h00);

        //---------------------------------------- 2. 'X' -> 'K' y PC = 0
        set_stub_pc(32'h0000_0040);
        pc_send(CMD_RESET);
        expect_byte(RSP_ACK);
        check("PC tras 'X'", dut.pc, 32'd0);
        check("ciclos de cpu_reset tras 1 'X'", cpu_reset_cycles, 32'd1);

        //---------------------------------------- 3. Bytes que no son comando
        set_stub_pc(32'h0000_0080);
        pc_send("?");
        pc_send(8'h00);
        pc_send("x");                        // 'x' minuscula: NO es el comando
        pc_send("d");                        // 'd' minuscula: tampoco
        pc_send("s");                        // 's' minuscula: tampoco
        pc_send(CMD_INT);                    // 'I' fuera de RUN: se ignora
        pc_send("r");                        // 'r' minuscula: no es 'R'
        expect_silence;
        check("PC tras bytes desconocidos", dut.pc, 32'h0000_0080);
        check("ciclos de cpu_reset (sin cambios)", cpu_reset_cycles, 32'd1);
        check("leds de vuelta en IDLE", {24'd0, leds}, 32'h00);

        //---------------------------------------- 4. 'X' de nuevo
        pc_send(CMD_RESET);
        expect_byte(RSP_ACK);
        check("PC tras el 2do 'X'", dut.pc, 32'd0);
        check("ciclos de cpu_reset tras 2 'X'", cpu_reset_cycles, 32'd2);

        //---------------------------------------- 5. Boton de reset
        set_stub_pc(32'h0000_0020);
        @(negedge clk); btn_reset = 1'b1;
        repeat (10) @(negedge clk);
        btn_reset = 1'b0;
        repeat (10) @(posedge clk); #1;
        check("PC tras el boton (OR de reset)", dut.pc, 32'd0);
        pc_send(CMD_RESET);                  // y todo sigue funcionando
        expect_byte(RSP_ACK);

        //---------------------------------------- 6. 'D' recien reseteado
        check_dump("D tras reset", 32'd0, 32'd0, 8'h00);

        //---------------------------------------- 7. 'D' con valores forzados
        set_stub_pc(32'h0012_3458);
        set_stub_mem(8'd0,  32'h1111_2222);
        set_stub_mem(8'd1,  32'h3344_5566);
        set_stub_mem(8'd5,  32'hDEAD_BEEF);
        set_stub_mem(8'd31, 32'h0102_0304);
        set_stub_halted;
        fork
            check_dump("D con valores", 32'h0012_3458, 32'd0, 8'h01);
            begin                            // a mitad del volcado: estado DUMP
                #(FRAME_NS * 100);
                check("leds durante el volcado", {24'd0, leds}, 32'h18);
            end
        join
        check("leds tras el volcado (IDLE + halted)", {24'd0, leds}, 32'h10);

        //---------------------------------------- 8. 'X' y 'D' de nuevo
        pc_send(CMD_RESET);
        expect_byte(RSP_ACK);
        check_dump("D tras 'X'", 32'd0, 32'd0, 8'h00);   // memoria conservada

        check("ciclos con cpu_enable (antes de 'S')", cpu_enable_cycles, 32'd0);

        //---------------------------------------- 9. 'S' paso a paso hasta el HALT
        // Memoria: [0],[1] y [5] escritas en la prueba 7, NOPs en [2],[4],[6],[7].
        // Se pone un HALT en la palabra 3 (direccion 0x0C):
        //   S1 PC 4 | S2 PC 8 | S3 PC 0xC (llega al HALT) | S4 el HALT pasa a ID
        //   (PC congelado) | S5, S6 vaciado | S7 halted = 1 | S8 ya no cambia nada
        set_stub_mem(8'd3, 32'h0000_0000);
        check_step("S1", 32'h4, 32'd1, 8'h00);
        check_step("S2", 32'h8, 32'd2, 8'h00);
        check_step("S3", 32'hC, 32'd3, 8'h00);
        check_step("S4 (HALT en ID)", 32'hC, 32'd4, 8'h00);
        check_step("S5", 32'hC, 32'd5, 8'h00);
        check_step("S6", 32'hC, 32'd6, 8'h00);
        check_step("S7 (halted)", 32'hC, 32'd7, 8'h01);
        check_step("S8 (sin cambios)", 32'hC, 32'd7, 8'h01);

        //---------------------------------------- 10. 'X' y 'D' despues de los pasos
        pc_send(CMD_RESET);
        expect_byte(RSP_ACK);
        check_dump("D tras los pasos y 'X'", 32'd0, 32'd0, 8'h00);

        //---------------------------------------- 11. Totales parciales
        check("ciclos con cpu_enable (8 'S')", cpu_enable_cycles, 32'd8);
        check("ciclos de cpu_reset (hasta aca)", cpu_reset_cycles, 32'd5);

        //---------------------------------------- 12. 'R' hasta el HALT
        // Misma memoria que en la prueba 9 (HALT en la palabra 3): 'R' tiene que
        // llegar exactamente al mismo estado que S7, en 7 ciclos de enable.
        check_run("R hasta el HALT", 32'hC, 32'd7, 8'h01, 32'd7);

        //---------------------------------------- 13. 'R' ya detenido
        check_run("R ya detenido", 32'hC, 32'd7, 8'h01, 32'd0);

        //---------------------------------------- 14. 'I' fuera de RUN
        pc_send(CMD_INT);
        expect_silence;
        check_dump("D tras 'I' en IDLE", 32'hC, 32'd7, 8'h01);   // sin bit 1

        //---------------------------------------- 15. Programa sin HALT + 'I'
        pc_send(CMD_RESET);
        expect_byte(RSP_ACK);
        fill_nops;
        en_before = cpu_enable_cycles;
        pc_send(CMD_RUN);
        #(FRAME_NS / 2); #1;
        check("leds durante RUN", {24'd0, leds}, 32'h06);
        check("cpu_enable durante RUN", {31'd0, dut.cpu_enable}, 32'd1);
        // Otros bytes durante RUN: se leen y se descartan, la corrida sigue.
        snap_pc = dut.pc;
        pc_send(CMD_DUMP);
        pc_send(CMD_STEP);
        pc_send(CMD_RESET);
        pc_send(CMD_RUN);
        pc_send("i");                         // 'i' minuscula: no interrumpe
        expect_silence;
        check("ciclos de cpu_reset ('X' durante RUN no resetea)", cpu_reset_cycles, 32'd6);
        if (dut.pc <= snap_pc) begin
            $display("ERROR: el PC no siguio avanzando durante RUN");
            errors = errors + 1;
        end
        check("leds siguen en RUN", {24'd0, leds}, 32'h06);
        // Ahora si: 'I'
        pc_send(CMD_INT);
        check_dump_snapshot("R + I (sin HALT)", 8'h02);
        $display("  R + I (sin HALT): cortado en PC = 0x%h, ciclos = %0d", snap_pc, snap_cycles);
        check("PC = 4 * ciclos (desde 0)", snap_pc, 4 * snap_cycles);
        check("ciclos = ciclos de enable", snap_cycles, cpu_enable_cycles - en_before);
        check("leds tras la interrupcion (IDLE)", {24'd0, leds}, 32'h00);

        //---------------------------------------- 16. 'D' tras la interrupcion
        fork
            check_dump("D tras R + I", snap_pc, snap_cycles, 8'h02);
            begin                             // una 'I' a mitad del volcado
                #(FRAME_NS * 100);
                pc_send(CMD_INT);
            end
        join
        expect_silence;                       // la 'I' se consumio en IDLE, sin efecto
        check("PC sin cambios tras la 'I' en IDLE", dut.pc, snap_pc);

        //---------------------------------------- 17. Otro 'R' + 'I': continua
        check_run_int("R + I (continua)", 8'h02);
        if (run_cyc0 == 32'd0) begin
            $display("ERROR: el segundo 'R' no partia de los ciclos anteriores");
            errors = errors + 1;
        end

        //---------------------------------------- 18. 'S' borra el bit
        check_step("S tras R + I", snap_pc + 32'd4, snap_cycles + 32'd1, 8'h00);

        //---------------------------------------- 19. 'X' borra el bit
        check_run_int("R + I (antes de 'X')", 8'h02);
        pc_send(CMD_RESET);
        expect_byte(RSP_ACK);
        check_dump("D tras R + I + X", 32'd0, 32'd0, 8'h00);

        //---------------------------------------- 20. 'R' borra el bit
        check_run_int("R + I (antes del HALT)", 8'h02);
        // HALT 3 palabras despues del PC actual: corre 3 instrucciones y para.
        set_stub_mem(snap_pc[9:2] + 8'd3, 32'h0000_0000);
        check_run("R hasta el HALT (tras I)", snap_pc + 32'd12, snap_cycles + 32'd7,
                  8'h01, 32'd7);

        //---------------------------------------- 21. Empate HALT / 'I'
        pc_send(CMD_RESET);
        expect_byte(RSP_ACK);
        fill_nops;
        pc_send(CMD_RUN);
        #(FRAME_NS * 2);
        fork
            pc_send(CMD_INT);
            begin
                // Apenas la 'I' queda disponible (rx_empty baja en un flanco),
                // en el semiciclo siguiente se fuerza halted: en el proximo
                // flanco la FSM ve las dos cosas a la vez.
                wait (dut.rx_empty == 1'b0);
                @(negedge clk);
                dut.u_cpu.halting   = 1'b1;
                dut.u_cpu.drain_cnt = 2'd3;
            end
        join
        check_dump_snapshot("empate HALT / I", 8'h01);   // gana el HALT
        $display("  empate HALT / I: PC = 0x%h, ciclos = %0d", snap_pc, snap_cycles);
        check_dump("D tras el empate", snap_pc, snap_cycles, 8'h01);

        //---------------------------------------- 22. Total de cpu_reset
        check("ciclos de cpu_reset (total: 8 'X')", cpu_reset_cycles, 32'd8);

        //---------------------------------------- Resultado
        if (errors == 0) $display("PASS: comandos 'X', 'D', 'S', 'R' e 'I' correctos");
        else             $display("FAIL: %0d errores", errors);
        $finish;
    end

endmodule

`default_nettype wire
