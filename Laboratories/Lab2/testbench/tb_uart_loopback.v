`timescale 1ns / 1ps

//------------------------------------------------------------------------------
// Testbench de loopback Tx -> Rx.
//
// La salida o_tx del transmisor se conecta directamente a la entrada i_rx del
// receptor, asi que todo lo que se transmite tiene que volver identico.
// Verifica la cadena entera (baud rate generator, trama, muestreo) sin
// depender de la PC ni de la placa.
//
// Para que la simulacion sea corta se usa un BAUD_RATE alto (N = 4). La logica
// es exactamente la misma que a 9600 baudios: lo unico que cambia es cada
// cuantos ciclos llega el tick.
//------------------------------------------------------------------------------
module tb_uart_loopback;

    //------------------------------------------------ Parametros de la prueba
    localparam CLK_PERIOD = 10;               // 100 MHz
    localparam CLK_FREQ   = 100_000_000;
    localparam BAUD_RATE  = 1_562_500;        // N = 4 (simulacion rapida)
    localparam DATA_BITS  = 8;
    localparam STOP_BITS  = 1;
    localparam N_BYTES    = 8;

    //------------------------------------------------ Senales
    reg                   clk = 1'b0;
    reg                   reset = 1'b1;
    reg                   tx_start = 1'b0;
    reg  [DATA_BITS-1:0]  din = {DATA_BITS{1'b0}};

    wire                  tick;
    wire                  linea;             // el "cable" entre Tx y Rx
    wire                  tx_done;
    wire                  rx_done;
    wire [DATA_BITS-1:0]  dout;

    integer i;
    integer enviados  = 0;
    integer recibidos = 0;
    integer errores   = 0;

    reg [DATA_BITS-1:0] patron [0:N_BYTES-1];

    //------------------------------------------------ Reloj
    always #(CLK_PERIOD/2) clk = ~clk;

    //------------------------------------------------ Modulos bajo prueba
    baud_rate_generator #
    (
        .CLK_FREQ  (CLK_FREQ),
        .BAUD_RATE (BAUD_RATE),
        .OVERSAMP  (16)
    )
    u_baud
    (
        .i_clk   (clk),
        .i_reset (reset),
        .o_tick  (tick)
    );

    tx_fsmd #
    (
        .DATA_BITS (DATA_BITS),
        .STOP_BITS (STOP_BITS)
    )
    u_tx
    (
        .i_clk      (clk),
        .i_reset    (reset),
        .i_s_tick   (tick),
        .i_tx_start (tx_start),
        .i_din      (din),
        .o_tx_done  (tx_done),
        .o_tx       (linea)
    );

    rx_fsmd #
    (
        .DATA_BITS (DATA_BITS),
        .SB_TICK   (16)
    )
    u_rx
    (
        .i_clk     (clk),
        .i_reset   (reset),
        .i_s_tick  (tick),
        .i_rx      (linea),          // <-- el puente
        .o_rx_done (rx_done),
        .o_dout    (dout)
    );

    //------------------------------------------------ Verificacion automatica
    always @(posedge clk) begin
        if (rx_done) begin
            if (dout === patron[recibidos])
                $display("[%0t] OK   enviado %h  recibido %h", $time, patron[recibidos], dout);
            else begin
                $display("[%0t] ERROR enviado %h  recibido %h", $time, patron[recibidos], dout);
                errores = errores + 1;
            end
            recibidos = recibidos + 1;
        end
    end

    // La linea en reposo tiene que estar en 1
    always @(posedge clk)
        if (!reset && u_tx.state == 3'b001 && linea !== 1'b1) begin
            $display("[%0t] ERROR la linea esta en 0 estando en IDLE", $time);
            errores = errores + 1;
        end

    //------------------------------------------------ Envio de un byte
    task enviar(input [DATA_BITS-1:0] dato);
    begin
        // El dato solo tiene que ser valido en el ciclo del pulso
        @(negedge clk);
        din      = dato;
        tx_start = 1'b1;
        @(negedge clk);
        tx_start = 1'b0;
        din      = {DATA_BITS{1'bx}};
        enviados = enviados + 1;

        // Esperar a que termine Y a que tx_done vuelva a 0: mientras el Tx
        // esta en DONE ignora un tx_start nuevo.
        @(posedge tx_done);
        @(negedge tx_done);
    end
    endtask

    //------------------------------------------------ Secuencia principal
    initial begin
        $dumpfile("tb_uart_loopback.vcd");
        $dumpvars(0, tb_uart_loopback);

        patron[0] = 8'h41;   // 'A'
        patron[1] = 8'h55;   // 0101_0101
        patron[2] = 8'hAA;   // 1010_1010
        patron[3] = 8'h00;   // todos ceros
        patron[4] = 8'hFF;   // todos unos
        patron[5] = 8'h01;   // solo el LSB
        patron[6] = 8'h80;   // solo el MSB
        patron[7] = 8'h3C;

        repeat (8) @(negedge clk);
        reset = 1'b0;
        repeat (20) @(negedge clk);

        for (i = 0; i < N_BYTES; i = i + 1)
            enviar(patron[i]);

        repeat (200) @(negedge clk);

        $display("--------------------------------------------------");
        $display("enviados = %0d   recibidos = %0d   errores = %0d",
                 enviados, recibidos, errores);
        if (enviados == recibidos && errores == 0)
            $display("LOOPBACK OK");
        else
            $display("LOOPBACK CON FALLAS");
        $display("--------------------------------------------------");
        $finish;
    end

    // Corta la simulacion si algo se cuelga
    initial begin
        #5_000_000;
        $display("TIMEOUT: la simulacion no termino");
        $finish;
    end

endmodule