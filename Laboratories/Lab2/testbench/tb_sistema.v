`timescale 1ns / 1ps

//------------------------------------------------------------------------------
// Testbench del sistema completo.
//
//   [PC simulada]  <--- dos lineas serie --->  [FPGA: uart + intf + alu_ctrl + alu]
//
// La "PC" es otra instancia del modulo uart: manda los tres bytes (A, B, opcode)
// y recibe el byte de resultado, igual que haria la terminal real.
//
// Para que la simulacion sea corta se usa un BAUD_RATE alto (N = 4). La logica
// es la misma que a 9600 baudios.
//------------------------------------------------------------------------------
module tb_sistema;

    //------------------------------------------------ Parametros de la prueba
    localparam CLK_PERIOD = 10;               // 100 MHz
    localparam CLK_FREQ   = 100_000_000;
    localparam BAUD_RATE  = 1_562_500;        // N = 4
    localparam DATA_BITS  = 8;
    localparam STOP_BITS  = 1;

    // Opcodes (los mismos que la ALU)
    localparam [7:0] ADD = 8'h20, SUB = 8'h22, AND_ = 8'h24, OR_  = 8'h25,
                     XOR_= 8'h26, NOR_= 8'h27, SRA  = 8'h03, SRL  = 8'h02;

    //------------------------------------------------ Senales
    reg clk = 1'b0;
    reg reset = 1'b1;

    always #(CLK_PERIOD/2) clk = ~clk;

    wire linea_pc_a_fpga;      // tx de la PC   -> rx de la FPGA
    wire linea_fpga_a_pc;      // tx de la FPGA -> rx de la PC

    //================================================ FPGA
    wire                  rx_done, tx_done, tx_start;
    wire [DATA_BITS-1:0]  dout, tx_din;

    uart #
    (
        .CLK_FREQ     (CLK_FREQ),
        .BAUD_RATE    (BAUD_RATE),
        .DATA_BITS    (DATA_BITS),
        .TX_STOP_BITS (STOP_BITS)
    )
    u_uart
    (
        .i_clk      (clk),
        .i_reset    (reset),
        .i_rx       (linea_pc_a_fpga),
        .o_tx       (linea_fpga_a_pc),
        .o_rx_done  (rx_done),
        .o_dout     (dout),
        .i_tx_start (tx_start),
        .i_din      (tx_din),
        .o_tx_done  (tx_done)
    );

    wire                  rd, wr, rx_empty, tx_full;
    wire [DATA_BITS-1:0]  r_data, w_data;

    intf #
    (
        .DATA_BITS (DATA_BITS)
    )
    u_intf
    (
        .i_clk      (clk),
        .i_reset    (reset),
        .i_rx_done  (rx_done),
        .i_dout     (dout),
        .o_tx_start (tx_start),
        .o_tx_din   (tx_din),
        .i_tx_done  (tx_done),
        .o_r_data   (r_data),
        .o_rx_empty (rx_empty),
        .i_rd       (rd),
        .i_w_data   (w_data),
        .i_wr       (wr),
        .o_tx_full  (tx_full)
    );

    wire zero, carry, overflow;

    alu_ctrl #
    (
        .DATA_BITS  (DATA_BITS),
        .LENGTH_OPT (6)
    )
    u_ctrl
    (
        .i_clk      (clk),
        .i_reset    (reset),
        .i_r_data   (r_data),
        .i_rx_empty (rx_empty),
        .o_rd       (rd),
        .o_w_data   (w_data),
        .i_tx_full  (tx_full),
        .o_wr       (wr),
        .o_zero     (zero),
        .o_carry    (carry),
        .o_overflow (overflow)
    );

    //================================================ PC simulada
    reg                   pc_start = 1'b0;
    reg  [DATA_BITS-1:0]  pc_din = {DATA_BITS{1'b0}};
    wire                  pc_tx_done, pc_rx_done;
    wire [DATA_BITS-1:0]  pc_dout;

    uart #
    (
        .CLK_FREQ     (CLK_FREQ),
        .BAUD_RATE    (BAUD_RATE),
        .DATA_BITS    (DATA_BITS),
        .TX_STOP_BITS (STOP_BITS)
    )
    u_pc
    (
        .i_clk      (clk),
        .i_reset    (reset),
        .i_rx       (linea_fpga_a_pc),
        .o_tx       (linea_pc_a_fpga),
        .o_rx_done  (pc_rx_done),
        .o_dout     (pc_dout),
        .i_tx_start (pc_start),
        .i_din      (pc_din),
        .o_tx_done  (pc_tx_done)
    );

    //------------------------------------------------ Captura de la respuesta
    reg  [DATA_BITS-1:0] respuesta;
    integer recibidos = 0;
    integer errores   = 0;
    integer pruebas   = 0;

    always @(posedge clk)
        if (pc_rx_done) begin
            respuesta = pc_dout;
            recibidos = recibidos + 1;
        end

    //------------------------------------------------ Mandar un byte
    task pc_enviar(input [DATA_BITS-1:0] dato);
    begin
        @(negedge clk);
        pc_din   = dato;
        pc_start = 1'b1;
        @(negedge clk);
        pc_start = 1'b0;
        pc_din   = {DATA_BITS{1'bx}};
        @(posedge pc_tx_done);
        @(negedge pc_tx_done);        // esperar a que salga de DONE
    end
    endtask

    //------------------------------------------------ Una operacion completa
    task operacion(input [DATA_BITS-1:0] a,
                   input [DATA_BITS-1:0] b,
                   input [DATA_BITS-1:0] opcode,
                   input [DATA_BITS-1:0] esperado,
                   input [80*8:1]        nombre);
    begin
        pruebas   = pruebas + 1;
        recibidos = 0;

        pc_enviar(a);
        pc_enviar(b);
        pc_enviar(opcode);

        // Esperar la respuesta (el timeout global corta si nunca llega)
        wait (recibidos == 1);
        repeat (40) @(posedge clk);

        if (respuesta !== esperado) begin
            errores = errores + 1;
            $display("ERROR %0s: %h , %h -> %h   (esperado %h)",
                     nombre, a, b, respuesta, esperado);
        end
        else if (recibidos != 1) begin
            errores = errores + 1;
            $display("ERROR %0s: llegaron %0d bytes en vez de 1", nombre, recibidos);
        end
        else
            $display("OK    %0s: %h , %h -> %h   [z=%b c=%b v=%b]",
                     nombre, a, b, respuesta, zero, carry, overflow);
    end
    endtask

    //------------------------------------------------ Secuencia principal
    initial begin
        $dumpfile("tb_sistema.vcd");
        $dumpvars(0, tb_sistema);

        repeat (8) @(negedge clk);
        reset = 1'b0;
        repeat (20) @(negedge clk);

        // --- Las ocho operaciones
        operacion(8'd5,  8'd3,  ADD,  8'd8,  "ADD  5+3");
        operacion(8'd3,  8'd5,  SUB,  8'hFE, "SUB  3-5");
        operacion(8'h0F, 8'hF0, AND_, 8'h00, "AND");
        operacion(8'h0F, 8'hF0, OR_,  8'hFF, "OR");
        operacion(8'h0F, 8'hFF, XOR_, 8'hF0, "XOR");
        operacion(8'h0F, 8'hF0, NOR_, 8'h00, "NOR");
        operacion(8'h80, 8'd1,  SRA,  8'hC0, "SRA  negativo");
        operacion(8'h80, 8'd1,  SRL,  8'h40, "SRL  negativo");

        // --- Casos borde
        operacion(8'hFF, 8'd1,  ADD,  8'h00, "ADD  carry");
        operacion(8'd127, 8'd1, ADD,  8'h80, "ADD  overflow");
        operacion(8'd7,  8'd7,  SUB,  8'h00, "SUB  zero");
        operacion(8'h00, 8'h00, ADD,  8'h00, "ADD  ceros");
        operacion(8'hAA, 8'h55, OR_,  8'hFF, "OR   patron");
        operacion(8'd9,  8'd2,  8'h3F, 8'h00, "opcode invalido");

        // --- Dos operaciones seguidas sin pausa entre tramas
        operacion(8'd10, 8'd20, ADD,  8'd30, "ADD  seguidas 1");
        operacion(8'd20, 8'd10, SUB,  8'd10, "ADD  seguidas 2");

        repeat (200) @(posedge clk);

        $display("--------------------------------------------------");
        $display("pruebas = %0d   errores = %0d", pruebas, errores);
        if (errores == 0) $display("SISTEMA OK");
        else              $display("SISTEMA CON FALLAS");
        $display("--------------------------------------------------");
        $finish;
    end

    //------------------------------------------------ Timeout de seguridad
    initial begin
        #20_000_000;
        $display("TIMEOUT: la simulacion no termino (falta alguna respuesta)");
        $finish;
    end

endmodule