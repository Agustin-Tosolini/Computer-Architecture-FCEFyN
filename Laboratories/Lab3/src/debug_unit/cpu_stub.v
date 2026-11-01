`timescale 1ns / 1ps
`default_nettype none

//------------------------------------------------------------------------------
// cpu_stub — Procesador FALSO para desarrollar y probar la debug_unit.
//
// Tiene EXACTAMENTE los mismos puertos que el cpu real (contrato de params.vh,
// seccion 4). Cuando el cpu real este listo, se cambia cpu_stub por cpu en el
// top y no deberia hacer falta tocar nada mas.
//
// No ejecuta instrucciones. Imita solo lo que la debug_unit puede observar:
//
//   * Memoria de programa REAL (256 x 32), escrita con i_imem_we.
//     Arranca toda en 0x00000000 (= HALT): memoria vacia = parada.
//
//   * PC: avanza de a 4 por cada ciclo con i_enable = 1.
//
//   * HALT con la misma latencia que el pipeline real:
//       - cuando la instruccion apuntada por el PC es 0x00000000, el PC se
//         congela (en el cpu real: el HALT llego a ID y se deja de buscar);
//       - 3 ciclos habilitados despues, o_halted pasa a 1 (en el cpu real: el
//         HALT recorrio ID -> EX -> MEM -> WB y el pipeline quedo vacio);
//       - o_halted queda en 1 hasta i_cpu_reset. Mientras vale 1, i_enable se
//         ignora (igual que el "enable efectivo" del cpu real).
//
//   * Registros: valores reconocibles que cambian con el PC, para ver en el
//     volcado que un paso realmente avanzo.
//         x0 = 0
//         xN = {PC[15:0], 8'h00, 3'b000, N}      ej: PC=8, x5 -> 0x0008_0005
//
//   * TRUCO SOLO DEL STUB: el puerto de debug de "memoria de datos" devuelve
//     la MEMORIA DE PROGRAMA. El contrato no tiene forma de leer la memoria de
//     programa, y asi se puede verificar el comando 'L' con un volcado 'D'.
//     En el cpu real este puerto lee la memoria de datos.
//
//   * Latches: 12 palabras de 32 bits; la palabra k ocupa los bits
//     [32k+31 : 32k] y vale {4'hA, k, PC[23:0]}  ej: PC=8, palabra 3 -> 0xA300_0008.
//     El byte alto (A0..AB) identifica la palabra en el volcado.
//
//   * i_cpu_reset: PC = 0, halted = 0. NO borra la memoria de programa
//     (asi se puede volver a correr el mismo programa).
//------------------------------------------------------------------------------
module cpu_stub
(
    input  wire          i_clk,
    input  wire          i_cpu_reset,      // pulso sincronico, activo en 1

    // Control de ejecucion
    input  wire          i_enable,         // nivel: 1 = avanza un ciclo por flanco

    // Carga de programa (solo con i_enable = 0)
    input  wire          i_imem_we,        // pulso de 1 ciclo por palabra
    input  wire [7:0]    i_imem_addr,      // numero de palabra (0..255)
    input  wire [31:0]   i_imem_data,

    // Lectura de registros (asincronica)
    input  wire [4:0]    i_dbg_reg_addr,
    output wire [31:0]   o_dbg_reg_data,

    // Lectura de memoria (asincronica) — en el stub: memoria de PROGRAMA
    input  wire [7:0]    i_dbg_mem_addr,
    output wire [31:0]   o_dbg_mem_data,

    // Estado
    output wire [31:0]   o_pc,
    output wire [383:0]  o_latches,
    output wire          o_halted
);

    //------------------------------------------------ Parametros locales
    localparam [31:0] INSTR_HALT   = 32'h0000_0000;
    localparam        IMEM_DEPTH   = 256;
    localparam        LATCH_WORDS  = 12;          // 384 / 32
    localparam [1:0]  DRAIN_CYCLES = 2'd3;        // ID->EX, EX->MEM, MEM->WB

    //------------------------------------------------ Memoria de programa
    // Escritura sincronica, lectura asincronica: Vivado la implementa como
    // RAM distribuida (mismo tipo de memoria que se decidio para el cpu real).
    reg [31:0] imem [0:IMEM_DEPTH-1];

    integer k;
    initial
        for (k = 0; k < IMEM_DEPTH; k = k + 1)
            imem[k] = INSTR_HALT;

    always @(posedge i_clk)
        if (i_imem_we)
            imem[i_imem_addr] <= i_imem_data;

    //------------------------------------------------ PC y HALT
    reg [31:0] pc        = 32'd0;
    reg        halting   = 1'b0;   // 1 = se vio el HALT, el PC ya no avanza
    reg [1:0]  drain_cnt = 2'd0;   // ciclos de "vaciado" despues del HALT

    wire [31:0] instr   = imem[pc[9:2]];   // PC en bytes -> numero de palabra
    wire        is_halt = (instr == INSTR_HALT);
    wire        halted  = (drain_cnt == DRAIN_CYCLES);
    wire        step    = i_enable && !halted;   // enable efectivo

    always @(posedge i_clk) begin
        if (i_cpu_reset) begin
            pc        <= 32'd0;
            halting   <= 1'b0;
            drain_cnt <= 2'd0;
        end
        else if (step) begin
            if (!halting) begin
                if (is_halt)
                    halting <= 1'b1;          // el HALT pasa a "ID": PC congelado
                else
                    pc <= pc + 32'd4;         // instruccion normal: sigue
            end
            else
                drain_cnt <= drain_cnt + 1'b1; // el HALT baja hacia WB
        end
    end

    //------------------------------------------------ Registros (falsos)
    assign o_dbg_reg_data = (i_dbg_reg_addr == 5'd0)
                          ? 32'd0
                          : {pc[15:0], 8'h00, 3'b000, i_dbg_reg_addr};

    //------------------------------------------------ "Memoria de datos" (truco)
    assign o_dbg_mem_data = imem[i_dbg_mem_addr];

    //------------------------------------------------ Latches (falsos)
    genvar w;
    generate
        for (w = 0; w < LATCH_WORDS; w = w + 1) begin : g_latch
            assign o_latches[32*w +: 32] = {4'hA, w[3:0], pc[23:0]};
        end
    endgenerate

    //------------------------------------------------ Estado
    assign o_pc     = pc;
    assign o_halted = halted;

endmodule

`default_nettype wire
