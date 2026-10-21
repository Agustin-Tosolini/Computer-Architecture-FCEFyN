//==============================================================================
// params.vh — Contrato del Trabajo Final (Pipeline RISC-V + Debug Unit)
//==============================================================================
//
// USO: archivo de DOCUMENTACIÓN. Los módulos NO lo incluyen; cada uno declara
// sus anchos con números, pero esos números TIENEN que coincidir con los de
// este archivo. Si un valor cambia, se cambia primero acá y después en todos
// los módulos que lo usan.
//
// Igual es Verilog válido (tiene guarda de inclusión): si más adelante se
// decide usarlo, alcanza con poner `include "params.vh" al inicio de cada
// archivo y reemplazar los números por las macros (`DATA_W, etc.).
//
// Referencia teórica: Patterson & Hennessy, "Computer Organization and Design,
// RISC-V Edition", 2.ª edición (RV32: registros y palabras de 32 bits).
//
//==============================================================================

`ifndef PARAMS_VH
`define PARAMS_VH

//------------------------------------------------------------------------------
// 1. Arquitectura (fijado por RV32I, no se discute)
//------------------------------------------------------------------------------

// Ancho de datos, registros e instrucciones: 32 bits.
//   P&H 2.3 "Operands of the Computer Hardware" (registros de 32 bits, word)
//   P&H 2.5 "Representing Instructions in the Computer" (instrucciones de 32 bits)
`define DATA_W          32

// Cantidad de registros: 32 (x0..x31) → 5 bits para numerarlos.
//   P&H 2.3. Coincide con el ancho de los campos rs1, rs2 y rd (P&H 2.5).
`define NUM_REGS        32
`define REG_ADDR_W      5

// Ancho del PC: dirección en BYTES, 32 bits. Avanza de a 4 (P&H 2.3: una
// palabra ocupa 4 bytes; memoria direccionada por bytes).
`define PC_W            32

//------------------------------------------------------------------------------
// 2. Memorias (decisión de diseño: RAM distribuida, lectura asíncrona)
//------------------------------------------------------------------------------

// Memoria de programa: 256 palabras de 32 bits (1 KiB).
// La dirección es el NÚMERO DE PALABRA (0, 1, 2...), no la dirección en bytes.
// Relación con el PC:  palabra = PC[9:2]
`define IMEM_DEPTH      256
`define IMEM_ADDR_W     8

// Memoria de datos: 256 palabras de 32 bits (1 KiB).
// Puerto del procesador: dirección en BYTES (resultado de la ALU); internamente
//   palabra = addr[9:2] y byte dentro de la palabra = addr[1:0].
// Puerto de debug (i_dbg_mem_addr): NÚMERO DE PALABRA.
`define DMEM_DEPTH      256
`define DMEM_ADDR_W     8

//------------------------------------------------------------------------------
// 3. Codificaciones especiales (decisión de diseño)
//------------------------------------------------------------------------------

// HALT = 0x00000000 (instrucción ilegal en RISC-V): una memoria vacía
// funciona como parada.
`define INSTR_HALT      32'h0000_0000

// NOP oficial de RISC-V: addi x0, x0, 0.
// OJO: el reset y el flush de los latches deben cargar NOP, NUNCA 0x00000000,
// porque eso es HALT.
`define INSTR_NOP       32'h0000_0013

//------------------------------------------------------------------------------
// 4. Interfaz de debug del cpu (contrato cpu <-> debug_unit)
//------------------------------------------------------------------------------
//
//  Señal              Dir   Ancho           Semántica
//  -----------------  ----  --------------  -----------------------------------
//  i_clk              in    1               Clock del sistema (nunca se toca)
//  i_enable           in    1               NIVEL, activo en 1: mientras valga 1
//                                           el procesador avanza un ciclo por
//                                           flanco. En 0 queda congelado.
//  i_cpu_reset        in    1               PULSO síncrono, activo en 1. Resetea
//                                           PC, latches, registros, halted.
//                                           NO resetea la UART.
//  i_imem_we          in    1               PULSO de 1 ciclo por palabra.
//                                           Solo con i_enable = 0.
//  i_imem_addr        in    IMEM_ADDR_W     Número de palabra a escribir
//  i_imem_data        in    DATA_W          Instrucción a escribir
//  i_dbg_reg_addr     in    REG_ADDR_W      Registro a leer (0..31)
//  o_dbg_reg_data     out   DATA_W          Valor del registro. ASÍNCRONO:
//                                           válido en el mismo ciclo.
//  i_dbg_mem_addr     in    DMEM_ADDR_W     Palabra de memoria de datos a leer
//  o_dbg_mem_data     out   DATA_W          Valor de esa palabra. ASÍNCRONO.
//  o_pc               out   PC_W            PC actual (dirección en bytes)
//  o_latches          out   LATCHES_W       Los 4 latches concatenados
//                                           {IF/ID, ID/EX, EX/MEM, MEM/WB}
//  o_halted           out   1               NIVEL: 1 cuando el HALT llegó a WB
//                                           (pipeline vacío). Queda en 1 hasta
//                                           i_cpu_reset.
//
//  Todas las señales de 1 bit son activas en 1.

// Ancho total de los latches concatenados. PROVISORIO: se ajusta cuando se
// definan los campos de cada latch (P&H 4.7 "Pipelined Datapath and Control").
// Mantenerlo múltiplo de 8 (se envía por UART byte a byte): 384 = 48 bytes.
`define LATCHES_W       384

//------------------------------------------------------------------------------
// 5. Comunicación UART
//------------------------------------------------------------------------------

`define CLK_FREQ        100_000_000   // Debe coincidir con el clock REAL (clk_wiz)
`define BAUD_RATE       115200

//------------------------------------------------------------------------------
// 6. Protocolo (contrato debug_unit <-> software en la PC)
//------------------------------------------------------------------------------

// Comandos (PC -> FPGA), un byte ASCII
`define CMD_LOAD        8'h4C   // 'L' + N (2 bytes, LSB primero) + N palabras
                                //       (4 bytes c/u, little-endian)
`define CMD_RUN         8'h52   // 'R'  corre hasta halted, responde volcado
`define CMD_STEP        8'h53   // 'S'  avanza 1 ciclo, responde volcado
`define CMD_DUMP        8'h44   // 'D'  no ejecuta, responde volcado
`define CMD_RESET       8'h58   // 'X'  resetea el cpu, responde ACK

// Respuestas (FPGA -> PC)
`define RSP_ACK         8'h4B   // 'K'
`define DUMP_HEADER     8'hA5   // primer byte de todo volcado

// Formato del volcado (todos los valores de 32 bits en little-endian)
//
//   Offset  Bytes  Contenido
//   ------  -----  -------------------------------------------
//   0       1      DUMP_HEADER (0xA5)
//   1       4      PC
//   5       4      Contador de ciclos
//   9       1      Estado: bit 0 = halted, resto en 0
//   10      128    Registros x0..x31 (4 bytes c/u)
//   138     48     Latches (LATCHES_W / 8 bytes)
//   186     128    Memoria de datos, palabras 0..31 (4 bytes c/u)
//   ------  -----
//   Total   314
`define DUMP_MEM_WORDS  32
`define DUMP_BYTES      (1 + 4 + 4 + 1 + 4*`NUM_REGS + `LATCHES_W/8 + 4*`DUMP_MEM_WORDS)

`endif // PARAMS_VH
