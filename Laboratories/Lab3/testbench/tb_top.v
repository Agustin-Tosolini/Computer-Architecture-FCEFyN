`timescale 1ns / 1ps
`default_nettype none

//------------------------------------------------------------------------------
// Testbench del top (paso 1: eco por UART).
//
// Truco: en lugar de armar la trama serie bit a bit a mano, se instancia OTRA
// copia del modulo uart que hace de "PC". El testbench le pide que mande bytes
// (i_tx_start + i_din) y recibe lo que vuelve (o_rx_done + o_dout).
//
//   [ uart "PC" ] --tx--> i_rx [ top (DUT) ] o_tx --rx--> [ uart "PC" ]
//
// Este mismo esquema sirve despues para probar la debug_unit: solo cambia la
// secuencia de bytes que se manda y lo que se espera recibir.
//
// Pruebas:
//   1. La linea TX esta en 1 desde el arranque (sin apretar reset).
//   2. Un byte suelto vuelve igual.
//   3. Una rafaga de bytes seguidos (sin pausa) vuelve completa y en orden.
//   4. Los leds muestran el ultimo byte.
//
// Resultado: imprime "PASS" o la lista de errores y "FAIL".
//------------------------------------------------------------------------------
module tb_top;

    localparam CLK_FREQ  = 100_000_000;
    localparam BAUD_RATE = 115200;
    localparam CLK_HALF  = 5;                          // 100 MHz
    localparam BIT_NS    = 1_000_000_000 / BAUD_RATE;  // ~8680 ns por bit

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

    //------------------------------------------------ Bytes de prueba
    localparam N_BYTES = 10;
    reg [7:0] sent [0:N_BYTES-1];
    reg [7:0] recv [0:N_BYTES-1];
    integer   n_recv = 0;
    integer   errors = 0;
    integer   i;

    initial begin
        // un byte suelto + rafaga con casos borde (todo 0, todo 1, patrones)
        sent[0] = 8'h41;                                    // 'A'
        sent[1] = "H"; sent[2] = "o"; sent[3] = "l"; sent[4] = "a";
        sent[5] = 8'h00; sent[6] = 8'hFF; sent[7] = 8'hA5;
        sent[8] = 8'h5A; sent[9] = 8'h0D;
    end

    //------------------------------------------------ Recepcion (en paralelo)
    always @(posedge clk)
        if (pc_rx_done) begin
            if (n_recv < N_BYTES) recv[n_recv] = pc_dout;
            n_recv = n_recv + 1;
        end

    //------------------------------------------------ Tarea: la PC manda un byte
    // Pulso de un ciclo en i_tx_start y espera a que termine la trama.
    //
    // OJO: o_tx_done vale 1 mientras el tx_fsmd esta en DONE, y en DONE el
    // tx_fsmd ignora i_tx_start. Por eso se espera un ciclo mas: el proximo
    // pedido tiene que llegar con el tx_fsmd ya en IDLE. (Es el mismo problema
    // que resuelve tx_intf en el diseno real con su registro "full".)
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

    //------------------------------------------------ Secuencia
    initial begin
        // Prueba 1: TX en reposo desde el arranque, sin ningun reset externo.
        #1;
        if (line_fpga_to_pc !== 1'b1) begin
            $display("ERROR: TX no arranca en 1 (vale %b)", line_fpga_to_pc);
            errors = errors + 1;
        end

        // Solo la uart "PC" necesita reset; el DUT usa su power-on reset.
        repeat (5) @(posedge clk);
        pc_reset = 1'b0;
        repeat (50) @(posedge clk);

        // Prueba 2: un byte suelto, esperando su eco antes de seguir.
        pc_send(sent[0]);
        wait (n_recv == 1);

        // Prueba 3: rafaga, un byte detras del otro sin pausa.
        for (i = 1; i < N_BYTES; i = i + 1)
            pc_send(sent[i]);

        // Espera los ecos que faltan (con timeout).
        fork : espera
            begin
                wait (n_recv == N_BYTES);
                disable espera;
            end
            begin
                #(BIT_NS * 10 * 5);
                $display("ERROR: timeout, llegaron %0d de %0d bytes", n_recv, N_BYTES);
                errors = errors + 1;
                disable espera;
            end
        join

        // Verificacion de contenido y orden.
        for (i = 0; i < N_BYTES && i < n_recv; i = i + 1)
            if (recv[i] !== sent[i]) begin
                $display("ERROR: byte %0d: mandado %h, recibido %h", i, sent[i], recv[i]);
                errors = errors + 1;
            end

        // Prueba 4: leds con el ultimo byte.
        if (leds !== sent[N_BYTES-1]) begin
            $display("ERROR: leds = %h, esperado %h", leds, sent[N_BYTES-1]);
            errors = errors + 1;
        end

        // Que no lleguen bytes de mas.
        #(BIT_NS * 20);
        if (n_recv != N_BYTES) begin
            $display("ERROR: se recibieron %0d bytes, se esperaban %0d", n_recv, N_BYTES);
            errors = errors + 1;
        end

        if (errors == 0) $display("PASS: %0d bytes con eco correcto", N_BYTES);
        else             $display("FAIL: %0d errores", errors);
        $finish;
    end

endmodule

`default_nettype wire
