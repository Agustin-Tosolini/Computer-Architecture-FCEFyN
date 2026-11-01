`timescale 1ns / 1ps
`default_nettype none

//------------------------------------------------------------------------------
// Testbench del top — PASO 3, debug_unit version 2 (comandos 'X' y 'D').
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
// El volcado ESPERADO se arma en el testbench con un modelo propio del
// cpu_stub (mismas formulas que documenta cpu_stub.v), no leyendo al DUT.
//
// Pruebas:
//   1. Arranque: TX en reposo (1) y debug_unit en IDLE (leds = 0).
//   2. 'X' -> 'K', el PC del stub vuelve a 0, cpu_reset dura 1 ciclo.
//   3. Bytes que no son comando -> sin respuesta y sin reset.
//   4. 'X' otra vez -> sigue funcionando.
//   5. Boton de reset -> tambien resetea el procesador (OR de reset).
//   6. 'D' recien reseteado -> 314 bytes: PC = 0, estado = 0, memoria en 0.
//   7. 'D' con PC, memoria y halted forzados -> 314 bytes con esos valores;
//      durante el volcado los leds muestran el estado DUMP (8).
//   8. 'X' y 'D' -> PC = 0 y halted = 0 otra vez; la memoria se conserva.
//   9. Totales: cpu_enable no se activo nunca ('D' no ejecuta); cuenta de
//      cpu_reset.
//
// Resultado: imprime "PASS" o la lista de errores y "FAIL".
//------------------------------------------------------------------------------
module tb_top;

    localparam CLK_FREQ  = 100_000_000;
    localparam BAUD_RATE = 115200;
    localparam CLK_HALF  = 5;                                // 100 MHz
    localparam FRAME_NS  = 10 * (1_000_000_000 / BAUD_RATE); // ~86.8 us por byte

    localparam [7:0] CMD_RESET = 8'h58;   // 'X'
    localparam [7:0] CMD_DUMP  = 8'h44;   // 'D'
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
        .CLK_FREQ  (CLK_FREQ),
        .BAUD_RATE (BAUD_RATE)
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

    // Ciclos en que la debug_unit hace avanzar al procesador. Con 'X' y 'D'
    // no deberia activarse nunca.
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
            mem_model[m] = 32'h0000_0000;     // el stub arranca todo en HALT

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

    // Manda un comando que responde con volcado ('D') y verifica los 314
    // bytes contra el volcado esperado. Solo muestra los primeros errores.
    integer dump_errors;
    task check_cmd_dump(input [7:0] cmd, input [8*32-1:0] name, input [31:0] pc_v,
                        input [31:0] cycles_v, input [7:0] status_v);
        begin
            build_expected(pc_v, cycles_v, status_v);
            dump_errors = 0;
            pc_send(cmd);
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

    task check_dump(input [8*32-1:0] name, input [31:0] pc_v, input [31:0] cycles_v,
                    input [7:0] status_v);
        check_cmd_dump(CMD_DUMP, name, pc_v, cycles_v, status_v);
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

        //---------------------------------------- 9. Totales
        check("ciclos con cpu_enable (nunca)", cpu_enable_cycles, 32'd0);
        check("ciclos de cpu_reset (total)", cpu_reset_cycles, 32'd4);

        //---------------------------------------- Resultado
        if (errors == 0) $display("PASS: comandos 'X' y 'D' correctos");
        else             $display("FAIL: %0d errores", errors);
        $finish;
    end

endmodule

`default_nettype wire
