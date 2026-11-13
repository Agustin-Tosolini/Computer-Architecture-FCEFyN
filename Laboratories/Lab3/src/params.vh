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

// Memoria de programa: 256 palabras de 32 bits (1 KiB), RAM distribuida.
// La dirección es el NÚMERO DE PALABRA (0, 1, 2...), no la dirección en bytes.
// Relación con el PC:  palabra = PC[9:2]
// NO se borra con i_cpu_reset: la limpia el CLEAR del comando 'L'.
`define IMEM_DEPTH      256
`define IMEM_ADDR_W     8

// Memoria de datos: 32 palabras de 32 bits (128 bytes). Es exactamente lo que
// muestra el volcado: toda la memoria de datos se ve (la consigna pide enviar
// "la memoria de datos usada").
// Puerto del procesador: dirección en BYTES (resultado de la ALU), 0..127;
//   internamente palabra = addr[6:2] y byte dentro de la palabra = addr[1:0].
//   Un acceso fuera de 0..127, desalineado (lh/sh impar, lw/sw no múltiplo de
//   4) detiene el cpu por error (o_halted = o_fault = 1).
// Puerto de debug (i_dbg_mem_addr): NÚMERO DE PALABRA. Sigue teniendo 8 bits
//   (DMEM_ADDR_W) por compatibilidad; las palabras 32..255 devuelven 0.
// Es RAM distribuida y NO se borra con i_cpu_reset ('X', 'L' ni el botón):
//   conserva lo que dejó el programa anterior (arranca en 0 solo al configurar
//   la FPGA). Cada programa tiene que inicializar los datos que usa.
`define DMEM_DEPTH      32
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
//                                           PC, latches, registros, halted y
//                                           fault. NO borra las memorias (ni la
//                                           de programa ni la de datos: son
//                                           RAM) ni resetea la UART.
//  i_imem_we          in    1               PULSO de 1 ciclo por palabra.
//                                           Solo con i_enable = 0.
//  i_imem_addr        in    IMEM_ADDR_W     Número de palabra a escribir
//  i_imem_data        in    DATA_W          Instrucción a escribir
//  i_dbg_reg_addr     in    REG_ADDR_W      Registro a leer (0..31)
//  o_dbg_reg_data     out   DATA_W          Valor del registro. ASÍNCRONO:
//                                           válido en el mismo ciclo. x0 = 0
//                                           siempre (aun antes del primer reset).
//  i_dbg_mem_addr     in    DMEM_ADDR_W     Palabra de memoria de datos a leer
//  o_dbg_mem_data     out   DATA_W          Valor de esa palabra. ASÍNCRONO.
//  o_pc               out   PC_W            PC de búsqueda (dirección en bytes).
//                                           Al detenerse por HALT queda en la
//                                           dirección del HALT + 4 (el HALT se
//                                           detecta en ID, cuando IF ya buscó la
//                                           siguiente). Con el cpu_stub quedaba
//                                           en la dirección del HALT.
//  o_latches          out   LATCHES_W       Los 4 latches concatenados
//                                           {IF/ID, ID/EX, EX/MEM, MEM/WB}
//                                           (campos en la sección 4b)
//  o_halted           out   1               NIVEL: 1 cuando el HALT llegó a WB
//                                           (las etapas anteriores ya están
//                                           vacías). Queda en 1 hasta
//                                           i_cpu_reset; mientras vale 1,
//                                           i_enable se ignora.
//                                           5 NOPs + HALT -> 1 después de
//                                           exactamente 9 ciclos habilitados.
//  o_fault            out   1               NIVEL: 1 cuando el cpu se detuvo por
//                                           ERROR: instrucción ilegal, fetch
//                                           fuera de rango o desalineado, o
//                                           acceso inválido a la memoria de
//                                           datos. Siempre junto con
//                                           o_halted = 1; queda en 1 hasta
//                                           i_cpu_reset.
//
//  Todas las señales de 1 bit son activas en 1.

// Ancho total de los latches concatenados: cada latch ocupa un número entero
// de palabras de 32 bits (relleno con 0). 480 = 15 palabras = 60 bytes.
// (P&H 4.7 "Pipelined Datapath and Control".)
`define LATCHES_W       480

//------------------------------------------------------------------------------
// 4b. Campos de los latches (o_latches[479:0])
//------------------------------------------------------------------------------
//
// Bits dentro de o_latches. Palabra k del volcado = o_latches[32k+31 : 32k].
// Dentro de cada latch: campos de 32 bits en su propia palabra y los chicos
// juntos en una palabra de control. "relleno" vale siempre 0.
// Burbuja (reset, flush o stall): valid = 0 y todos los campos en 0, salvo
// IF/ID.instr = NOP (0x00000013), nunca HALT.
// scripts/uart_test.py --autoprueba compara esta tabla con la suya.
//
//   Latch   Campo        Bits      Palabra
//   ------  -----------  --------  -------
//   IF/ID   pc           479:448   14
//   IF/ID   instr        447:416   13
//   IF/ID   relleno      415:385   12
//   IF/ID   valid        384       12
//   ID/EX   pc           383:352   11
//   ID/EX   rs1_data     351:320   10
//   ID/EX   rs2_data     319:288   9
//   ID/EX   imm          287:256   8
//   ID/EX   relleno      255:243   7
//   ID/EX   rs1          242:238   7
//   ID/EX   rs2          237:233   7
//   ID/EX   rd           232:228   7
//   ID/EX   funct3       227:225   7
//   ID/EX   funct7_b5    224       7
//   ID/EX   relleno      223:208   6
//   ID/EX   reg_write    207       6
//   ID/EX   alu_src_a    206       6
//   ID/EX   alu_src_b    205       6
//   ID/EX   mem_read     204       6
//   ID/EX   mem_write    203       6
//   ID/EX   result_src   202       6
//   ID/EX   branch       201       6
//   ID/EX   jump         200       6
//   ID/EX   jalr         199       6
//   ID/EX   alu_op       198:197   6
//   ID/EX   halt         196       6
//   ID/EX   uses_rs1     195       6
//   ID/EX   uses_rs2     194       6
//   ID/EX   illegal      193       6
//   ID/EX   valid        192       6
//   EX/MEM  result       191:160   5
//   EX/MEM  store_data   159:128   4
//   EX/MEM  relleno      127:111   3
//   EX/MEM  rd           110:106   3
//   EX/MEM  funct3       105:103   3
//   EX/MEM  reg_write    102       3
//   EX/MEM  mem_read     101       3
//   EX/MEM  mem_write    100       3
//   EX/MEM  result_src   99        3
//   EX/MEM  halt         98        3
//   EX/MEM  illegal      97        3
//   EX/MEM  valid        96        3
//   MEM/WB  result       95:64     2
//   MEM/WB  mem_data     63:32     1
//   MEM/WB  relleno      31:10     0
//   MEM/WB  rd           9:5       0
//   MEM/WB  reg_write    4         0
//   MEM/WB  result_src   3         0
//   MEM/WB  halt         2         0
//   MEM/WB  illegal      1         0
//   MEM/WB  valid        0         0
//
// Significado de los campos menos obvios:
//   halt       marcador de parada que baja hacia WB (HALT o error).
//   illegal    la parada es por error. En MEM/WB también vale 1 cuando el
//              error fue un acceso inválido a la memoria (o_fault = halted &&
//              MEM/WB.illegal).
//   result     EX/MEM: resultado de la ALU, dirección de memoria o PC+4 (jal/jalr).
//   result_src 0 = WB escribe result; 1 = WB escribe mem_data (load).
//   alu_op     00 suma, 01 resta (branch), 10 tipo R, 11 tipo I.
//   alu_src_a  1 = el operando A es 0 (lui).   alu_src_b  1 = inmediato.
//
// Al detenerse por HALT el patrón es fijo: todo en 0 salvo IF/ID.instr = NOP
// y MEM/WB.halt = MEM/WB.valid = 1 (palabra 0 = 0x00000005).

//------------------------------------------------------------------------------
// 5. Comunicación UART
//------------------------------------------------------------------------------

// CLK_FREQ es la frecuencia de clk, la salida clk_out1 del clk_wiz_0 (MMCM),
// NO la del pin i_clk (100 MHz). Tiene que coincidir SIEMPRE con el clk_wiz y
// con el default de CLK_FREQ en top.v, o la UART calcula mal el divisor.
//   70 MHz, 115200 baud, x16 -> divisor 38 (baud real 115132, error -0,06 %)
`define CLK_FREQ        70_000_000    // = clk_out1 del clk_wiz_0
`define BAUD_RATE       115200

//------------------------------------------------------------------------------
// 6. Protocolo (contrato debug_unit <-> software en la PC)
//------------------------------------------------------------------------------

// Comandos (PC -> FPGA), un byte ASCII
`define CMD_LOAD        8'h4C   // 'L' + N (2 bytes, LSB primero) + N palabras
                                //       (4 bytes c/u, little-endian), todo
                                //       seguido. Las palabras N..255 quedan
                                //       en HALT y la 255 siempre es HALT; si
                                //       N > 256 las sobrantes se descartan.
                                //       Resetea el cpu (registros en 0; la
                                //       memoria de datos se conserva) y
                                //       responde ACK.
`define CMD_RUN         8'h52   // 'R'  corre hasta halted (o hasta 'I'), responde volcado
`define CMD_INT         8'h49   // 'I'  interrumpe un 'R' en curso (la respuesta es
                                //      el volcado del 'R'). Fuera de RUN se ignora.
`define CMD_STEP        8'h53   // 'S'  avanza 1 ciclo, responde volcado
`define CMD_DUMP        8'h44   // 'D'  no ejecuta, responde volcado
`define CMD_RESET       8'h58   // 'X'  resetea el cpu (registros en 0; las
                                //      memorias se conservan), responde ACK

// Respuestas (FPGA -> PC)
`define RSP_ACK         8'h4B   // 'K'  reset ('X') o carga ('L') terminados
`define DUMP_HEADER     8'hA5   // primer byte de todo volcado

// Formato del volcado (todos los valores de 32 bits en little-endian)
//
//   Offset  Bytes  Contenido
//   ------  -----  -------------------------------------------
//   0       1      DUMP_HEADER (0xA5)
//   1       4      PC
//   5       4      Contador de ciclos
//   9       1      Estado: bit 0 = halted, bit 1 = interrumpido ('R' cortado
//                    con 'I'), bit 2 = error (o_fault, siempre con halted),
//                    resto en 0.  HALT -> 0x01, error -> 0x05, 'I' -> 0x02
//   10      128    Registros x0..x31 (4 bytes c/u)
//   138     60     Latches (LATCHES_W / 8 bytes; campos en la sección 4b)
//   198     128    Memoria de datos, palabras 0..31 (4 bytes c/u): toda la
//                    memoria de datos
//   ------  -----
//   Total   326
`define DUMP_MEM_WORDS  32
`define DUMP_BYTES      (1 + 4 + 4 + 1 + 4*`NUM_REGS + `LATCHES_W/8 + 4*`DUMP_MEM_WORDS)

`endif // PARAMS_VH
