`timescale 1ns / 1ps
`default_nettype none

//------------------------------------------------------------------------------
// Top del Trabajo Final — PASO 4: debug_unit + cpu real (o cpu_stub).
//
// Es la frontera del chip: sus puertos son los pines de la placa y son los
// nombres que busca el archivo de constraints (top.xdc, sin cambios).
//
//   i_rx --> [ uart ] --> [ intf ] --> [ debug_unit ] <== contrato ==> [ cpu ]
//   o_tx <--          <--          <--
//
//   i_reset (boton) --> [ reset_gen ] --> reset global
//
// Reset del procesador:  cpu_rst = reset (global) OR cpu_reset (debug_unit).
//   - reset global: al encender o con el boton se resetea todo.
//   - cpu_reset:    el comando 'X' resetea SOLO el procesador; la UART y la
//                   debug_unit siguen funcionando y pueden responder 'K'.
//
// Procesador: el parametro USE_CPU_STUB elige cual se instancia (los dos
// tienen los mismos puertos, contrato de params.vh seccion 4):
//   - USE_CPU_STUB = 0 (por defecto, PLACA): el cpu real (src/cpu/cpu.v).
//   - USE_CPU_STUB = 1 (solo tb_top): el cpu_stub, que imita al cpu con valores
//     reconocibles para probar el protocolo de la debug_unit.
// Se resuelve con un generate: solo se sintetiza la rama elegida. La instancia
// se llama u_cpu en las dos ramas; su ruta jerarquica es dut.g_cpu.u_cpu o
// dut.g_stub.u_cpu.
//
// Evolucion prevista:
//   - clk_wiz; su "locked" va a reset_gen.i_locked.
//------------------------------------------------------------------------------
module top #
(
    parameter CLK_FREQ     = 100_000_000,   // reloj de la Basys 3 (sin clk_wiz)
    parameter BAUD_RATE    = 115200,
    parameter OVERSAMP     = 16,
    parameter DATA_BITS    = 8,
    parameter RX_SB_TICK   = 16,            // el Rx espera 1 bit de stop
    parameter TX_STOP_BITS = 1,             // el Tx manda 1 bit de stop
    parameter POR_CYCLES   = 16,            // ciclos de reset al encender
    parameter USE_CPU_STUB = 0,             // 0 = cpu real (placa), 1 = cpu_stub (tb_top)
    parameter STUB_INIT_NOPS = 8            // NOPs iniciales del cpu_stub (solo con
                                            // USE_CPU_STUB = 1)
)
(
    input  wire        i_clk,       // W5  - 100 MHz
    input  wire        i_reset,     // U18 - btnC
    input  wire        i_rx,        // B18 - salida del puente USB-UART
    output wire        o_tx,        // A18 - entrada del puente USB-UART
    output wire [7:0]  o_leds       // LD0..LD3 = estado de la debug_unit, LD4 = halted
);

    //------------------------------------------------ Senales internas
    wire                  reset;          // reset global, sincronico
    wire                  cpu_rst;        // reset del procesador (global OR 'X')

    // uart <-> intf
    wire                  rx_done;
    wire [DATA_BITS-1:0]  dout;
    wire                  tx_start;
    wire [DATA_BITS-1:0]  tx_din;
    wire                  tx_done;

    // intf <-> debug_unit (las seis senales del diagrama de bloques)
    wire [DATA_BITS-1:0]  r_data;
    wire                  rx_empty;
    wire                  rd;
    wire [DATA_BITS-1:0]  w_data;
    wire                  wr;
    wire                  tx_full;

    // debug_unit <-> cpu (contrato, params.vh seccion 4)
    wire                  cpu_enable;
    wire                  cpu_reset;
    wire                  imem_we;
    wire [7:0]            imem_addr;
    wire [31:0]           imem_data;
    wire [4:0]            dbg_reg_addr;
    wire [31:0]           dbg_reg_data;
    wire [7:0]            dbg_mem_addr;
    wire [31:0]           dbg_mem_data;
    wire [31:0]           pc;
    wire [479:0]          latches;        // 15 palabras (params.vh, seccion 4b)
    wire                  halted;
    wire                  fault;

    //================================================ Reset global
    reset_gen #
    (
        .POR_CYCLES (POR_CYCLES)
    )
    u_reset_gen
    (
        .i_clk    (i_clk),
        .i_btn    (i_reset),
        .i_locked (1'b1),       // sin clk_wiz todavia: clock siempre estable
        .o_reset  (reset)
    );

    //================================================ UART
    uart #
    (
        .CLK_FREQ     (CLK_FREQ),
        .BAUD_RATE    (BAUD_RATE),
        .OVERSAMP     (OVERSAMP),
        .DATA_BITS    (DATA_BITS),
        .RX_SB_TICK   (RX_SB_TICK),
        .TX_STOP_BITS (TX_STOP_BITS)
    )
    u_uart
    (
        .i_clk      (i_clk),
        .i_reset    (reset),

        .i_rx       (i_rx),
        .o_tx       (o_tx),

        .o_rx_done  (rx_done),
        .o_dout     (dout),

        .i_tx_start (tx_start),
        .i_din      (tx_din),
        .o_tx_done  (tx_done)
    );

    //================================================ Interface circuit
    intf #
    (
        .DATA_BITS (DATA_BITS)
    )
    u_intf
    (
        .i_clk      (i_clk),
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

    //================================================ Debug unit
    debug_unit u_debug_unit
    (
        .i_clk          (i_clk),
        .i_reset        (reset),

        .i_r_data       (r_data),
        .i_rx_empty     (rx_empty),
        .o_rd           (rd),

        .o_w_data       (w_data),
        .i_tx_full      (tx_full),
        .o_wr           (wr),

        .o_cpu_enable   (cpu_enable),
        .o_cpu_reset    (cpu_reset),
        .o_imem_we      (imem_we),
        .o_imem_addr    (imem_addr),
        .o_imem_data    (imem_data),

        .o_dbg_reg_addr (dbg_reg_addr),
        .i_dbg_reg_data (dbg_reg_data),
        .o_dbg_mem_addr (dbg_mem_addr),
        .i_dbg_mem_data (dbg_mem_data),

        .i_pc           (pc),
        .i_latches      (latches),
        .i_halted       (halted),
        .i_fault        (fault),

        .o_leds         (o_leds)
    );

    //================================================ Procesador
    assign cpu_rst = reset | cpu_reset;

    generate
        if (USE_CPU_STUB) begin : g_stub
            cpu_stub #
            (
                .INIT_NOPS (STUB_INIT_NOPS)
            )
            u_cpu
            (
                .i_clk          (i_clk),
                .i_cpu_reset    (cpu_rst),
                .i_enable       (cpu_enable),
                .i_imem_we      (imem_we),
                .i_imem_addr    (imem_addr),
                .i_imem_data    (imem_data),
                .i_dbg_reg_addr (dbg_reg_addr),
                .o_dbg_reg_data (dbg_reg_data),
                .i_dbg_mem_addr (dbg_mem_addr),
                .o_dbg_mem_data (dbg_mem_data),
                .o_pc           (pc),
                .o_latches      (latches),
                .o_halted       (halted),
                .o_fault        (fault)
            );
        end
        else begin : g_cpu
            cpu u_cpu
            (
                .i_clk          (i_clk),
                .i_cpu_reset    (cpu_rst),
                .i_enable       (cpu_enable),
                .i_imem_we      (imem_we),
                .i_imem_addr    (imem_addr),
                .i_imem_data    (imem_data),
                .i_dbg_reg_addr (dbg_reg_addr),
                .o_dbg_reg_data (dbg_reg_data),
                .i_dbg_mem_addr (dbg_mem_addr),
                .o_dbg_mem_data (dbg_mem_data),
                .o_pc           (pc),
                .o_latches      (latches),
                .o_halted       (halted),
                .o_fault        (fault)
            );
        end
    endgenerate

endmodule

`default_nettype wire
