`timescale 1ns / 1ps
`default_nettype none

//------------------------------------------------------------------------------
// debug_unit — Unidad de depuracion.
//
// Wrapper sin logica propia (mismo criterio que uart.v e intf.v): agrupa los
// dos bloques que la forman y expone la interfaz definitiva hacia el top.
//
//             +---------------------- debug_unit ----------------------+
//   intf <--> |  control_fsmd  -- dump_idx, cycles, status -->         |
//             |  (protocolo)   <-------- dump_byte ----------  dump_mux| <--> cpu
//   cpu  <--> |                                              (volcado) |
//             +--------------------------------------------------------+
//
//   control_fsmd: FSM + registros. Habla con el intf (6 senales) y controla
//                 el procesador (enable, cpu_reset, carga de programa).
//   dump_mux:     combinacional. Dado dump_idx elige el byte del volcado y
//                 pone las direcciones de lectura de debug del procesador.
//
// Sus puertos no cambian al agregar comandos: el top no se toca.
//------------------------------------------------------------------------------
module debug_unit
(
    input  wire          i_clk,
    input  wire          i_reset,          // reset GLOBAL (reset_gen)

    // ---------------- Lado intf
    input  wire [7:0]    i_r_data,
    input  wire          i_rx_empty,
    output wire          o_rd,

    output wire [7:0]    o_w_data,
    input  wire          i_tx_full,
    output wire          o_wr,

    // ---------------- Lado cpu (contrato, params.vh seccion 4)
    output wire          o_cpu_enable,
    output wire          o_cpu_reset,
    output wire          o_imem_we,
    output wire [7:0]    o_imem_addr,
    output wire [31:0]   o_imem_data,

    output wire [4:0]    o_dbg_reg_addr,
    input  wire [31:0]   i_dbg_reg_data,
    output wire [7:0]    o_dbg_mem_addr,
    input  wire [31:0]   i_dbg_mem_data,

    input  wire [31:0]   i_pc,
    input  wire [383:0]  i_latches,
    input  wire          i_halted,

    // ---------------- Depuracion en la placa
    output wire [7:0]    o_leds            // {3'b000, halted, codigo de estado}
);

    //------------------------------------------------ Senales internas
    wire [8:0]  dump_idx;
    wire [31:0] cycles;
    wire [7:0]  status;
    wire [7:0]  dump_byte;
    wire [3:0]  state_code;

    //================================================ Control (protocolo)
    control_fsmd u_control_fsmd
    (
        .i_clk         (i_clk),
        .i_reset       (i_reset),

        .i_r_data      (i_r_data),
        .i_rx_empty    (i_rx_empty),
        .o_rd          (o_rd),

        .o_w_data      (o_w_data),
        .i_tx_full     (i_tx_full),
        .o_wr          (o_wr),

        .o_cpu_enable  (o_cpu_enable),
        .o_cpu_reset   (o_cpu_reset),
        .o_imem_we     (o_imem_we),
        .o_imem_addr   (o_imem_addr),
        .o_imem_data   (o_imem_data),
        .i_halted      (i_halted),

        .o_dump_idx    (dump_idx),
        .o_cycles      (cycles),
        .o_status      (status),
        .i_dump_byte   (dump_byte),

        .o_state_code  (state_code)
    );

    //================================================ Volcado
    dump_mux u_dump_mux
    (
        .i_dump_idx     (dump_idx),

        .i_cycles       (cycles),
        .i_status       (status),

        .i_pc           (i_pc),
        .i_latches      (i_latches),

        .o_dbg_reg_addr (o_dbg_reg_addr),
        .i_dbg_reg_data (i_dbg_reg_data),
        .o_dbg_mem_addr (o_dbg_mem_addr),
        .i_dbg_mem_data (i_dbg_mem_data),

        .o_dump_byte    (dump_byte)
    );

    //================================================ Leds
    assign o_leds = {3'b000, i_halted, state_code};

endmodule

`default_nettype wire
