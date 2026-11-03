# Programa de prueba IF/ID — seguimiento paso a paso

Cargar **un único programa** y avanzar un ciclo por vez permite ver cómo IF
busca la siguiente instrucción mientras ID decodifica la anterior.
Esta referencia complementa las [pruebas aisladas](prueba_if_id_salidas_esperadas.md).

## Archivos del programa

- [programa_if_id.S](ejemplos/programa_if_id.S): listado assembler con etiquetas y direcciones.
- [programa_if_id.hex](ejemplos/programa_if_id.hex): palabras de 32 bits ya codificadas, una por línea.

Hay **38 instrucciones de prueba**, que cubren las 32 instrucciones RISC-V del
subconjunto, HALT, inicializaciones y ejemplos adicionales. Después hay una NOP
de guarda: **39 palabras en total**, posiciones 0 a 38. La primera línea del
HEX se carga en mem[0], la segunda en mem[1], etc. El HEX contiene palabras, no
bytes UART; la separación en bytes depende del protocolo de la Debug Unit.
No es necesario ensamblar el archivo S para usar esta referencia.

El listado prepara una base y operandos, recorre operaciones aritméticas,
escribe y lee memoria y termina con saltos, LUI y HALT. Los saltos apuntan a la
instrucción siguiente para que sea fácil seguir las direcciones. Es un programa
de cobertura para estudiar las instrucciones, no una aplicación completa.

**En cpu_if_id_test se recorre y decodifica el programa, pero no se ejecuta.**
Aunque aparezca `addi x1, x0, 64`, x1 permanece en cero. Las lecturas del banco
siempre entregan cero tras reset; no hay EX, memoria de datos ni WB conectados.
JALR tampoco salta y HALT no detiene este top. No usar estas tablas como resultados
de una CPU completa: al implementar las etapas restantes cambiarán los datos leídos.

## Cómo cargar y avanzar

1. Con enable=0, aplicar reset durante un flanco y luego quitarlo.
2. Manteniendo enable=0 y reset=0, escribir cada palabra del HEX con
   `i_imem_we=1`, su índice en `i_imem_addr` y su palabra en `i_imem_data`.
   Cada escritura necesita un flanco ascendente. Después poner `i_imem_we=0`.
3. Fijar `i_dbg_reg_addr=0`. El PC sigue en cero porque la CPU estuvo pausada.
4. Para cada paso, poner enable=1 durante **un solo flanco ascendente**, volver
   a enable=0 antes del siguiente y leer una vez estabilizadas las salidas.
5. No resetear ni recargar entre pasos. Comparar con las fichas en orden.
6. Detener manualmente la prueba después del paso 38. La NOP final está para
   que la instrucción buscada por IF en ese paso también tenga un valor conocido.

La carga no cuenta como pasos de CPU. En simulación esperar las actualizaciones
secuenciales y combinacionales después de cada flanco antes de comprobar valores.

## Momento de observación

| Momento | IF | ID |
|---|---|---|
| Tras carga, antes del primer paso | PC=0, primera instrucción | PC=0, NOP, valid=0 |
| Tras paso 1 | PC=4, segunda instrucción | PC=0, primera instrucción, valid=1 |
| Tras paso 2 | PC=8, tercera instrucción | PC=4, segunda instrucción, valid=1 |
| Tras paso n | PC=4×n, palabra mem[n] | PC=4×(n−1), palabra mem[n−1], valid=1 |

Antes del primer paso, todos los controles de ID son cero porque valid=0.
En cambio, la NOP del programa se decodifica con valid=1 como ADDI a x0.
La pausa mantiene las salidas si no hay reset ni escrituras en memoria de programa.

Cada ficha muestra **las 27 salidas**. Hexadecimal para datos de 32 bits;
registros en decimal; `alu_op` en binario de dos bits. Los campos rs1/rs2/rd
se muestran incluso cuando la instrucción no los utiliza: sus bits pueden
pertenecer al inmediato. Consultar uses_rs1/uses_rs2/reg_write.

## Recorrido completo

La instrucción de cada fila es la que queda en **ID después del paso**.
IF ya está leyendo la fila siguiente. Los PC de esta tabla están en decimal.

| Paso | PC de ID | PC de IF | Instrucción en ID | Palabra de ID |
|---|---|---|---|---|
| [1](#paso-01) | 0 | 4 | `addi x1, x0, 64` | `0x04000093` |
| [2](#paso-02) | 4 | 8 | `addi x2, x0, 3` | `0x00300113` |
| [3](#paso-03) | 8 | 12 | `add x3, x1, x2` | `0x002081B3` |
| [4](#paso-04) | 12 | 16 | `sub x3, x1, x2` | `0x402081B3` |
| [5](#paso-05) | 16 | 20 | `and x3, x1, x2` | `0x0020F1B3` |
| [6](#paso-06) | 20 | 24 | `or x3, x1, x2` | `0x0020E1B3` |
| [7](#paso-07) | 24 | 28 | `xor x3, x1, x2` | `0x0020C1B3` |
| [8](#paso-08) | 28 | 32 | `sll x3, x1, x2` | `0x002091B3` |
| [9](#paso-09) | 32 | 36 | `srl x3, x1, x2` | `0x0020D1B3` |
| [10](#paso-10) | 36 | 40 | `sra x3, x1, x2` | `0x4020D1B3` |
| [11](#paso-11) | 40 | 44 | `slt x3, x1, x2` | `0x0020A1B3` |
| [12](#paso-12) | 44 | 48 | `sltu x3, x1, x2` | `0x0020B1B3` |
| [13](#paso-13) | 48 | 52 | `addi x3, x1, 5` | `0x00508193` |
| [14](#paso-14) | 52 | 56 | `andi x3, x1, 15` | `0x00F0F193` |
| [15](#paso-15) | 56 | 60 | `ori x3, x1, 1` | `0x0010E193` |
| [16](#paso-16) | 60 | 64 | `xori x3, x1, 1` | `0x0010C193` |
| [17](#paso-17) | 64 | 68 | `slli x3, x1, 2` | `0x00209193` |
| [18](#paso-18) | 68 | 72 | `srli x3, x1, 2` | `0x0020D193` |
| [19](#paso-19) | 72 | 76 | `srai x3, x1, 2` | `0x4020D193` |
| [20](#paso-20) | 76 | 80 | `slti x3, x1, 10` | `0x00A0A193` |
| [21](#paso-21) | 80 | 84 | `sltiu x3, x1, 10` | `0x00A0B193` |
| [22](#paso-22) | 84 | 88 | `sb x3, 4(x1)` | `0x00308223` |
| [23](#paso-23) | 88 | 92 | `sh x3, 4(x1)` | `0x00309223` |
| [24](#paso-24) | 92 | 96 | `sw x3, 4(x1)` | `0x0030A223` |
| [25](#paso-25) | 96 | 100 | `lb x3, 4(x1)` | `0x00408183` |
| [26](#paso-26) | 100 | 104 | `lbu x3, 4(x1)` | `0x0040C183` |
| [27](#paso-27) | 104 | 108 | `lh x3, 4(x1)` | `0x00409183` |
| [28](#paso-28) | 108 | 112 | `lhu x3, 4(x1)` | `0x0040D183` |
| [29](#paso-29) | 112 | 116 | `lw x3, 4(x1)` | `0x0040A183` |
| [30](#paso-30) | 116 | 120 | `beq x1, x2, paso_31` | `0x00208263` |
| [31](#paso-31) | 120 | 124 | `bne x1, x2, paso_32` | `0x00209263` |
| [32](#paso-32) | 124 | 128 | `jal x5, paso_33` | `0x004002EF` |
| [33](#paso-33) | 128 | 132 | `addi x4, x0, 136` | `0x08800213` |
| [34](#paso-34) | 132 | 136 | `jalr x0, 0(x4)` | `0x00020067` |
| [35](#paso-35) | 136 | 140 | `lui x3, 0x12345` | `0x123451B7` |
| [36](#paso-36) | 140 | 144 | `addi x3, x1, -5` | `0xFFB08193` |
| [37](#paso-37) | 144 | 148 | `addi x0, x0, 0` | `0x00000013` |
| [38](#paso-38) | 148 | 152 | `halt` | `0x00000000` |

<a id="paso-01"></a>

## Paso 1: addi x1, x0, 64

ID: **`addi x1, x0, 64`**, PC=0. IF: **`addi x2, x0, 3`**, PC=4.

| Salida | Valor esperado |
|---|---|
| `o_dbg_reg_data` | `0x00000000` |
| `o_if_pc` | `0x00000004` |
| `o_if_instr` | `0x00300113` |
| `o_if_addr_error` | `0` |
| `o_id_pc` | `0x00000000` |
| `o_id_instr` | `0x04000093` |
| `o_id_valid` | `1` |
| `o_id_imm` | `0x00000040` |
| `o_id_rs1` | `0` |
| `o_id_rs2` | `0` |
| `o_id_rd` | `1` |
| `o_id_rs1_data` | `0x00000000` |
| `o_id_rs2_data` | `0x00000000` |
| `o_id_reg_write` | `1` |
| `o_id_alu_src_a` | `0` |
| `o_id_alu_src_b` | `1` |
| `o_id_mem_read` | `0` |
| `o_id_mem_write` | `0` |
| `o_id_result_src` | `0` |
| `o_id_branch` | `0` |
| `o_id_jump` | `0` |
| `o_id_jalr` | `0` |
| `o_id_alu_op` | `11` |
| `o_id_halt` | `0` |
| `o_id_uses_rs1` | `1` |
| `o_id_uses_rs2` | `0` |
| `o_id_illegal` | `0` |

<a id="paso-02"></a>

## Paso 2: addi x2, x0, 3

ID: **`addi x2, x0, 3`**, PC=4. IF: **`add x3, x1, x2`**, PC=8.

| Salida | Valor esperado |
|---|---|
| `o_dbg_reg_data` | `0x00000000` |
| `o_if_pc` | `0x00000008` |
| `o_if_instr` | `0x002081B3` |
| `o_if_addr_error` | `0` |
| `o_id_pc` | `0x00000004` |
| `o_id_instr` | `0x00300113` |
| `o_id_valid` | `1` |
| `o_id_imm` | `0x00000003` |
| `o_id_rs1` | `0` |
| `o_id_rs2` | `3` |
| `o_id_rd` | `2` |
| `o_id_rs1_data` | `0x00000000` |
| `o_id_rs2_data` | `0x00000000` |
| `o_id_reg_write` | `1` |
| `o_id_alu_src_a` | `0` |
| `o_id_alu_src_b` | `1` |
| `o_id_mem_read` | `0` |
| `o_id_mem_write` | `0` |
| `o_id_result_src` | `0` |
| `o_id_branch` | `0` |
| `o_id_jump` | `0` |
| `o_id_jalr` | `0` |
| `o_id_alu_op` | `11` |
| `o_id_halt` | `0` |
| `o_id_uses_rs1` | `1` |
| `o_id_uses_rs2` | `0` |
| `o_id_illegal` | `0` |

<a id="paso-03"></a>

## Paso 3: add x3, x1, x2

ID: **`add x3, x1, x2`**, PC=8. IF: **`sub x3, x1, x2`**, PC=12.

| Salida | Valor esperado |
|---|---|
| `o_dbg_reg_data` | `0x00000000` |
| `o_if_pc` | `0x0000000C` |
| `o_if_instr` | `0x402081B3` |
| `o_if_addr_error` | `0` |
| `o_id_pc` | `0x00000008` |
| `o_id_instr` | `0x002081B3` |
| `o_id_valid` | `1` |
| `o_id_imm` | `0x00000000` |
| `o_id_rs1` | `1` |
| `o_id_rs2` | `2` |
| `o_id_rd` | `3` |
| `o_id_rs1_data` | `0x00000000` |
| `o_id_rs2_data` | `0x00000000` |
| `o_id_reg_write` | `1` |
| `o_id_alu_src_a` | `0` |
| `o_id_alu_src_b` | `0` |
| `o_id_mem_read` | `0` |
| `o_id_mem_write` | `0` |
| `o_id_result_src` | `0` |
| `o_id_branch` | `0` |
| `o_id_jump` | `0` |
| `o_id_jalr` | `0` |
| `o_id_alu_op` | `10` |
| `o_id_halt` | `0` |
| `o_id_uses_rs1` | `1` |
| `o_id_uses_rs2` | `1` |
| `o_id_illegal` | `0` |

<a id="paso-04"></a>

## Paso 4: sub x3, x1, x2

ID: **`sub x3, x1, x2`**, PC=12. IF: **`and x3, x1, x2`**, PC=16.

| Salida | Valor esperado |
|---|---|
| `o_dbg_reg_data` | `0x00000000` |
| `o_if_pc` | `0x00000010` |
| `o_if_instr` | `0x0020F1B3` |
| `o_if_addr_error` | `0` |
| `o_id_pc` | `0x0000000C` |
| `o_id_instr` | `0x402081B3` |
| `o_id_valid` | `1` |
| `o_id_imm` | `0x00000000` |
| `o_id_rs1` | `1` |
| `o_id_rs2` | `2` |
| `o_id_rd` | `3` |
| `o_id_rs1_data` | `0x00000000` |
| `o_id_rs2_data` | `0x00000000` |
| `o_id_reg_write` | `1` |
| `o_id_alu_src_a` | `0` |
| `o_id_alu_src_b` | `0` |
| `o_id_mem_read` | `0` |
| `o_id_mem_write` | `0` |
| `o_id_result_src` | `0` |
| `o_id_branch` | `0` |
| `o_id_jump` | `0` |
| `o_id_jalr` | `0` |
| `o_id_alu_op` | `10` |
| `o_id_halt` | `0` |
| `o_id_uses_rs1` | `1` |
| `o_id_uses_rs2` | `1` |
| `o_id_illegal` | `0` |

<a id="paso-05"></a>

## Paso 5: and x3, x1, x2

ID: **`and x3, x1, x2`**, PC=16. IF: **`or x3, x1, x2`**, PC=20.

| Salida | Valor esperado |
|---|---|
| `o_dbg_reg_data` | `0x00000000` |
| `o_if_pc` | `0x00000014` |
| `o_if_instr` | `0x0020E1B3` |
| `o_if_addr_error` | `0` |
| `o_id_pc` | `0x00000010` |
| `o_id_instr` | `0x0020F1B3` |
| `o_id_valid` | `1` |
| `o_id_imm` | `0x00000000` |
| `o_id_rs1` | `1` |
| `o_id_rs2` | `2` |
| `o_id_rd` | `3` |
| `o_id_rs1_data` | `0x00000000` |
| `o_id_rs2_data` | `0x00000000` |
| `o_id_reg_write` | `1` |
| `o_id_alu_src_a` | `0` |
| `o_id_alu_src_b` | `0` |
| `o_id_mem_read` | `0` |
| `o_id_mem_write` | `0` |
| `o_id_result_src` | `0` |
| `o_id_branch` | `0` |
| `o_id_jump` | `0` |
| `o_id_jalr` | `0` |
| `o_id_alu_op` | `10` |
| `o_id_halt` | `0` |
| `o_id_uses_rs1` | `1` |
| `o_id_uses_rs2` | `1` |
| `o_id_illegal` | `0` |

<a id="paso-06"></a>

## Paso 6: or x3, x1, x2

ID: **`or x3, x1, x2`**, PC=20. IF: **`xor x3, x1, x2`**, PC=24.

| Salida | Valor esperado |
|---|---|
| `o_dbg_reg_data` | `0x00000000` |
| `o_if_pc` | `0x00000018` |
| `o_if_instr` | `0x0020C1B3` |
| `o_if_addr_error` | `0` |
| `o_id_pc` | `0x00000014` |
| `o_id_instr` | `0x0020E1B3` |
| `o_id_valid` | `1` |
| `o_id_imm` | `0x00000000` |
| `o_id_rs1` | `1` |
| `o_id_rs2` | `2` |
| `o_id_rd` | `3` |
| `o_id_rs1_data` | `0x00000000` |
| `o_id_rs2_data` | `0x00000000` |
| `o_id_reg_write` | `1` |
| `o_id_alu_src_a` | `0` |
| `o_id_alu_src_b` | `0` |
| `o_id_mem_read` | `0` |
| `o_id_mem_write` | `0` |
| `o_id_result_src` | `0` |
| `o_id_branch` | `0` |
| `o_id_jump` | `0` |
| `o_id_jalr` | `0` |
| `o_id_alu_op` | `10` |
| `o_id_halt` | `0` |
| `o_id_uses_rs1` | `1` |
| `o_id_uses_rs2` | `1` |
| `o_id_illegal` | `0` |

<a id="paso-07"></a>

## Paso 7: xor x3, x1, x2

ID: **`xor x3, x1, x2`**, PC=24. IF: **`sll x3, x1, x2`**, PC=28.

| Salida | Valor esperado |
|---|---|
| `o_dbg_reg_data` | `0x00000000` |
| `o_if_pc` | `0x0000001C` |
| `o_if_instr` | `0x002091B3` |
| `o_if_addr_error` | `0` |
| `o_id_pc` | `0x00000018` |
| `o_id_instr` | `0x0020C1B3` |
| `o_id_valid` | `1` |
| `o_id_imm` | `0x00000000` |
| `o_id_rs1` | `1` |
| `o_id_rs2` | `2` |
| `o_id_rd` | `3` |
| `o_id_rs1_data` | `0x00000000` |
| `o_id_rs2_data` | `0x00000000` |
| `o_id_reg_write` | `1` |
| `o_id_alu_src_a` | `0` |
| `o_id_alu_src_b` | `0` |
| `o_id_mem_read` | `0` |
| `o_id_mem_write` | `0` |
| `o_id_result_src` | `0` |
| `o_id_branch` | `0` |
| `o_id_jump` | `0` |
| `o_id_jalr` | `0` |
| `o_id_alu_op` | `10` |
| `o_id_halt` | `0` |
| `o_id_uses_rs1` | `1` |
| `o_id_uses_rs2` | `1` |
| `o_id_illegal` | `0` |

<a id="paso-08"></a>

## Paso 8: sll x3, x1, x2

ID: **`sll x3, x1, x2`**, PC=28. IF: **`srl x3, x1, x2`**, PC=32.

| Salida | Valor esperado |
|---|---|
| `o_dbg_reg_data` | `0x00000000` |
| `o_if_pc` | `0x00000020` |
| `o_if_instr` | `0x0020D1B3` |
| `o_if_addr_error` | `0` |
| `o_id_pc` | `0x0000001C` |
| `o_id_instr` | `0x002091B3` |
| `o_id_valid` | `1` |
| `o_id_imm` | `0x00000000` |
| `o_id_rs1` | `1` |
| `o_id_rs2` | `2` |
| `o_id_rd` | `3` |
| `o_id_rs1_data` | `0x00000000` |
| `o_id_rs2_data` | `0x00000000` |
| `o_id_reg_write` | `1` |
| `o_id_alu_src_a` | `0` |
| `o_id_alu_src_b` | `0` |
| `o_id_mem_read` | `0` |
| `o_id_mem_write` | `0` |
| `o_id_result_src` | `0` |
| `o_id_branch` | `0` |
| `o_id_jump` | `0` |
| `o_id_jalr` | `0` |
| `o_id_alu_op` | `10` |
| `o_id_halt` | `0` |
| `o_id_uses_rs1` | `1` |
| `o_id_uses_rs2` | `1` |
| `o_id_illegal` | `0` |

<a id="paso-09"></a>

## Paso 9: srl x3, x1, x2

ID: **`srl x3, x1, x2`**, PC=32. IF: **`sra x3, x1, x2`**, PC=36.

| Salida | Valor esperado |
|---|---|
| `o_dbg_reg_data` | `0x00000000` |
| `o_if_pc` | `0x00000024` |
| `o_if_instr` | `0x4020D1B3` |
| `o_if_addr_error` | `0` |
| `o_id_pc` | `0x00000020` |
| `o_id_instr` | `0x0020D1B3` |
| `o_id_valid` | `1` |
| `o_id_imm` | `0x00000000` |
| `o_id_rs1` | `1` |
| `o_id_rs2` | `2` |
| `o_id_rd` | `3` |
| `o_id_rs1_data` | `0x00000000` |
| `o_id_rs2_data` | `0x00000000` |
| `o_id_reg_write` | `1` |
| `o_id_alu_src_a` | `0` |
| `o_id_alu_src_b` | `0` |
| `o_id_mem_read` | `0` |
| `o_id_mem_write` | `0` |
| `o_id_result_src` | `0` |
| `o_id_branch` | `0` |
| `o_id_jump` | `0` |
| `o_id_jalr` | `0` |
| `o_id_alu_op` | `10` |
| `o_id_halt` | `0` |
| `o_id_uses_rs1` | `1` |
| `o_id_uses_rs2` | `1` |
| `o_id_illegal` | `0` |

<a id="paso-10"></a>

## Paso 10: sra x3, x1, x2

ID: **`sra x3, x1, x2`**, PC=36. IF: **`slt x3, x1, x2`**, PC=40.

| Salida | Valor esperado |
|---|---|
| `o_dbg_reg_data` | `0x00000000` |
| `o_if_pc` | `0x00000028` |
| `o_if_instr` | `0x0020A1B3` |
| `o_if_addr_error` | `0` |
| `o_id_pc` | `0x00000024` |
| `o_id_instr` | `0x4020D1B3` |
| `o_id_valid` | `1` |
| `o_id_imm` | `0x00000000` |
| `o_id_rs1` | `1` |
| `o_id_rs2` | `2` |
| `o_id_rd` | `3` |
| `o_id_rs1_data` | `0x00000000` |
| `o_id_rs2_data` | `0x00000000` |
| `o_id_reg_write` | `1` |
| `o_id_alu_src_a` | `0` |
| `o_id_alu_src_b` | `0` |
| `o_id_mem_read` | `0` |
| `o_id_mem_write` | `0` |
| `o_id_result_src` | `0` |
| `o_id_branch` | `0` |
| `o_id_jump` | `0` |
| `o_id_jalr` | `0` |
| `o_id_alu_op` | `10` |
| `o_id_halt` | `0` |
| `o_id_uses_rs1` | `1` |
| `o_id_uses_rs2` | `1` |
| `o_id_illegal` | `0` |

<a id="paso-11"></a>

## Paso 11: slt x3, x1, x2

ID: **`slt x3, x1, x2`**, PC=40. IF: **`sltu x3, x1, x2`**, PC=44.

| Salida | Valor esperado |
|---|---|
| `o_dbg_reg_data` | `0x00000000` |
| `o_if_pc` | `0x0000002C` |
| `o_if_instr` | `0x0020B1B3` |
| `o_if_addr_error` | `0` |
| `o_id_pc` | `0x00000028` |
| `o_id_instr` | `0x0020A1B3` |
| `o_id_valid` | `1` |
| `o_id_imm` | `0x00000000` |
| `o_id_rs1` | `1` |
| `o_id_rs2` | `2` |
| `o_id_rd` | `3` |
| `o_id_rs1_data` | `0x00000000` |
| `o_id_rs2_data` | `0x00000000` |
| `o_id_reg_write` | `1` |
| `o_id_alu_src_a` | `0` |
| `o_id_alu_src_b` | `0` |
| `o_id_mem_read` | `0` |
| `o_id_mem_write` | `0` |
| `o_id_result_src` | `0` |
| `o_id_branch` | `0` |
| `o_id_jump` | `0` |
| `o_id_jalr` | `0` |
| `o_id_alu_op` | `10` |
| `o_id_halt` | `0` |
| `o_id_uses_rs1` | `1` |
| `o_id_uses_rs2` | `1` |
| `o_id_illegal` | `0` |

<a id="paso-12"></a>

## Paso 12: sltu x3, x1, x2

ID: **`sltu x3, x1, x2`**, PC=44. IF: **`addi x3, x1, 5`**, PC=48.

| Salida | Valor esperado |
|---|---|
| `o_dbg_reg_data` | `0x00000000` |
| `o_if_pc` | `0x00000030` |
| `o_if_instr` | `0x00508193` |
| `o_if_addr_error` | `0` |
| `o_id_pc` | `0x0000002C` |
| `o_id_instr` | `0x0020B1B3` |
| `o_id_valid` | `1` |
| `o_id_imm` | `0x00000000` |
| `o_id_rs1` | `1` |
| `o_id_rs2` | `2` |
| `o_id_rd` | `3` |
| `o_id_rs1_data` | `0x00000000` |
| `o_id_rs2_data` | `0x00000000` |
| `o_id_reg_write` | `1` |
| `o_id_alu_src_a` | `0` |
| `o_id_alu_src_b` | `0` |
| `o_id_mem_read` | `0` |
| `o_id_mem_write` | `0` |
| `o_id_result_src` | `0` |
| `o_id_branch` | `0` |
| `o_id_jump` | `0` |
| `o_id_jalr` | `0` |
| `o_id_alu_op` | `10` |
| `o_id_halt` | `0` |
| `o_id_uses_rs1` | `1` |
| `o_id_uses_rs2` | `1` |
| `o_id_illegal` | `0` |

<a id="paso-13"></a>

## Paso 13: addi x3, x1, 5

ID: **`addi x3, x1, 5`**, PC=48. IF: **`andi x3, x1, 15`**, PC=52.

| Salida | Valor esperado |
|---|---|
| `o_dbg_reg_data` | `0x00000000` |
| `o_if_pc` | `0x00000034` |
| `o_if_instr` | `0x00F0F193` |
| `o_if_addr_error` | `0` |
| `o_id_pc` | `0x00000030` |
| `o_id_instr` | `0x00508193` |
| `o_id_valid` | `1` |
| `o_id_imm` | `0x00000005` |
| `o_id_rs1` | `1` |
| `o_id_rs2` | `5` |
| `o_id_rd` | `3` |
| `o_id_rs1_data` | `0x00000000` |
| `o_id_rs2_data` | `0x00000000` |
| `o_id_reg_write` | `1` |
| `o_id_alu_src_a` | `0` |
| `o_id_alu_src_b` | `1` |
| `o_id_mem_read` | `0` |
| `o_id_mem_write` | `0` |
| `o_id_result_src` | `0` |
| `o_id_branch` | `0` |
| `o_id_jump` | `0` |
| `o_id_jalr` | `0` |
| `o_id_alu_op` | `11` |
| `o_id_halt` | `0` |
| `o_id_uses_rs1` | `1` |
| `o_id_uses_rs2` | `0` |
| `o_id_illegal` | `0` |

<a id="paso-14"></a>

## Paso 14: andi x3, x1, 15

ID: **`andi x3, x1, 15`**, PC=52. IF: **`ori x3, x1, 1`**, PC=56.

| Salida | Valor esperado |
|---|---|
| `o_dbg_reg_data` | `0x00000000` |
| `o_if_pc` | `0x00000038` |
| `o_if_instr` | `0x0010E193` |
| `o_if_addr_error` | `0` |
| `o_id_pc` | `0x00000034` |
| `o_id_instr` | `0x00F0F193` |
| `o_id_valid` | `1` |
| `o_id_imm` | `0x0000000F` |
| `o_id_rs1` | `1` |
| `o_id_rs2` | `15` |
| `o_id_rd` | `3` |
| `o_id_rs1_data` | `0x00000000` |
| `o_id_rs2_data` | `0x00000000` |
| `o_id_reg_write` | `1` |
| `o_id_alu_src_a` | `0` |
| `o_id_alu_src_b` | `1` |
| `o_id_mem_read` | `0` |
| `o_id_mem_write` | `0` |
| `o_id_result_src` | `0` |
| `o_id_branch` | `0` |
| `o_id_jump` | `0` |
| `o_id_jalr` | `0` |
| `o_id_alu_op` | `11` |
| `o_id_halt` | `0` |
| `o_id_uses_rs1` | `1` |
| `o_id_uses_rs2` | `0` |
| `o_id_illegal` | `0` |

<a id="paso-15"></a>

## Paso 15: ori x3, x1, 1

ID: **`ori x3, x1, 1`**, PC=56. IF: **`xori x3, x1, 1`**, PC=60.

| Salida | Valor esperado |
|---|---|
| `o_dbg_reg_data` | `0x00000000` |
| `o_if_pc` | `0x0000003C` |
| `o_if_instr` | `0x0010C193` |
| `o_if_addr_error` | `0` |
| `o_id_pc` | `0x00000038` |
| `o_id_instr` | `0x0010E193` |
| `o_id_valid` | `1` |
| `o_id_imm` | `0x00000001` |
| `o_id_rs1` | `1` |
| `o_id_rs2` | `1` |
| `o_id_rd` | `3` |
| `o_id_rs1_data` | `0x00000000` |
| `o_id_rs2_data` | `0x00000000` |
| `o_id_reg_write` | `1` |
| `o_id_alu_src_a` | `0` |
| `o_id_alu_src_b` | `1` |
| `o_id_mem_read` | `0` |
| `o_id_mem_write` | `0` |
| `o_id_result_src` | `0` |
| `o_id_branch` | `0` |
| `o_id_jump` | `0` |
| `o_id_jalr` | `0` |
| `o_id_alu_op` | `11` |
| `o_id_halt` | `0` |
| `o_id_uses_rs1` | `1` |
| `o_id_uses_rs2` | `0` |
| `o_id_illegal` | `0` |

<a id="paso-16"></a>

## Paso 16: xori x3, x1, 1

ID: **`xori x3, x1, 1`**, PC=60. IF: **`slli x3, x1, 2`**, PC=64.

| Salida | Valor esperado |
|---|---|
| `o_dbg_reg_data` | `0x00000000` |
| `o_if_pc` | `0x00000040` |
| `o_if_instr` | `0x00209193` |
| `o_if_addr_error` | `0` |
| `o_id_pc` | `0x0000003C` |
| `o_id_instr` | `0x0010C193` |
| `o_id_valid` | `1` |
| `o_id_imm` | `0x00000001` |
| `o_id_rs1` | `1` |
| `o_id_rs2` | `1` |
| `o_id_rd` | `3` |
| `o_id_rs1_data` | `0x00000000` |
| `o_id_rs2_data` | `0x00000000` |
| `o_id_reg_write` | `1` |
| `o_id_alu_src_a` | `0` |
| `o_id_alu_src_b` | `1` |
| `o_id_mem_read` | `0` |
| `o_id_mem_write` | `0` |
| `o_id_result_src` | `0` |
| `o_id_branch` | `0` |
| `o_id_jump` | `0` |
| `o_id_jalr` | `0` |
| `o_id_alu_op` | `11` |
| `o_id_halt` | `0` |
| `o_id_uses_rs1` | `1` |
| `o_id_uses_rs2` | `0` |
| `o_id_illegal` | `0` |

<a id="paso-17"></a>

## Paso 17: slli x3, x1, 2

ID: **`slli x3, x1, 2`**, PC=64. IF: **`srli x3, x1, 2`**, PC=68.

| Salida | Valor esperado |
|---|---|
| `o_dbg_reg_data` | `0x00000000` |
| `o_if_pc` | `0x00000044` |
| `o_if_instr` | `0x0020D193` |
| `o_if_addr_error` | `0` |
| `o_id_pc` | `0x00000040` |
| `o_id_instr` | `0x00209193` |
| `o_id_valid` | `1` |
| `o_id_imm` | `0x00000002` |
| `o_id_rs1` | `1` |
| `o_id_rs2` | `2` |
| `o_id_rd` | `3` |
| `o_id_rs1_data` | `0x00000000` |
| `o_id_rs2_data` | `0x00000000` |
| `o_id_reg_write` | `1` |
| `o_id_alu_src_a` | `0` |
| `o_id_alu_src_b` | `1` |
| `o_id_mem_read` | `0` |
| `o_id_mem_write` | `0` |
| `o_id_result_src` | `0` |
| `o_id_branch` | `0` |
| `o_id_jump` | `0` |
| `o_id_jalr` | `0` |
| `o_id_alu_op` | `11` |
| `o_id_halt` | `0` |
| `o_id_uses_rs1` | `1` |
| `o_id_uses_rs2` | `0` |
| `o_id_illegal` | `0` |

<a id="paso-18"></a>

## Paso 18: srli x3, x1, 2

ID: **`srli x3, x1, 2`**, PC=68. IF: **`srai x3, x1, 2`**, PC=72.

| Salida | Valor esperado |
|---|---|
| `o_dbg_reg_data` | `0x00000000` |
| `o_if_pc` | `0x00000048` |
| `o_if_instr` | `0x4020D193` |
| `o_if_addr_error` | `0` |
| `o_id_pc` | `0x00000044` |
| `o_id_instr` | `0x0020D193` |
| `o_id_valid` | `1` |
| `o_id_imm` | `0x00000002` |
| `o_id_rs1` | `1` |
| `o_id_rs2` | `2` |
| `o_id_rd` | `3` |
| `o_id_rs1_data` | `0x00000000` |
| `o_id_rs2_data` | `0x00000000` |
| `o_id_reg_write` | `1` |
| `o_id_alu_src_a` | `0` |
| `o_id_alu_src_b` | `1` |
| `o_id_mem_read` | `0` |
| `o_id_mem_write` | `0` |
| `o_id_result_src` | `0` |
| `o_id_branch` | `0` |
| `o_id_jump` | `0` |
| `o_id_jalr` | `0` |
| `o_id_alu_op` | `11` |
| `o_id_halt` | `0` |
| `o_id_uses_rs1` | `1` |
| `o_id_uses_rs2` | `0` |
| `o_id_illegal` | `0` |

<a id="paso-19"></a>

## Paso 19: srai x3, x1, 2

ID: **`srai x3, x1, 2`**, PC=72. IF: **`slti x3, x1, 10`**, PC=76.

El desplazamiento es 2, pero imm_gen entrega 0x00000402 (1026): conserva el campo I completo. La ALU usará solo los cinco bits inferiores para desplazar; alu_control distinguirá SRAI usando funct7[5].

| Salida | Valor esperado |
|---|---|
| `o_dbg_reg_data` | `0x00000000` |
| `o_if_pc` | `0x0000004C` |
| `o_if_instr` | `0x00A0A193` |
| `o_if_addr_error` | `0` |
| `o_id_pc` | `0x00000048` |
| `o_id_instr` | `0x4020D193` |
| `o_id_valid` | `1` |
| `o_id_imm` | `0x00000402` |
| `o_id_rs1` | `1` |
| `o_id_rs2` | `2` |
| `o_id_rd` | `3` |
| `o_id_rs1_data` | `0x00000000` |
| `o_id_rs2_data` | `0x00000000` |
| `o_id_reg_write` | `1` |
| `o_id_alu_src_a` | `0` |
| `o_id_alu_src_b` | `1` |
| `o_id_mem_read` | `0` |
| `o_id_mem_write` | `0` |
| `o_id_result_src` | `0` |
| `o_id_branch` | `0` |
| `o_id_jump` | `0` |
| `o_id_jalr` | `0` |
| `o_id_alu_op` | `11` |
| `o_id_halt` | `0` |
| `o_id_uses_rs1` | `1` |
| `o_id_uses_rs2` | `0` |
| `o_id_illegal` | `0` |

<a id="paso-20"></a>

## Paso 20: slti x3, x1, 10

ID: **`slti x3, x1, 10`**, PC=76. IF: **`sltiu x3, x1, 10`**, PC=80.

| Salida | Valor esperado |
|---|---|
| `o_dbg_reg_data` | `0x00000000` |
| `o_if_pc` | `0x00000050` |
| `o_if_instr` | `0x00A0B193` |
| `o_if_addr_error` | `0` |
| `o_id_pc` | `0x0000004C` |
| `o_id_instr` | `0x00A0A193` |
| `o_id_valid` | `1` |
| `o_id_imm` | `0x0000000A` |
| `o_id_rs1` | `1` |
| `o_id_rs2` | `10` |
| `o_id_rd` | `3` |
| `o_id_rs1_data` | `0x00000000` |
| `o_id_rs2_data` | `0x00000000` |
| `o_id_reg_write` | `1` |
| `o_id_alu_src_a` | `0` |
| `o_id_alu_src_b` | `1` |
| `o_id_mem_read` | `0` |
| `o_id_mem_write` | `0` |
| `o_id_result_src` | `0` |
| `o_id_branch` | `0` |
| `o_id_jump` | `0` |
| `o_id_jalr` | `0` |
| `o_id_alu_op` | `11` |
| `o_id_halt` | `0` |
| `o_id_uses_rs1` | `1` |
| `o_id_uses_rs2` | `0` |
| `o_id_illegal` | `0` |

<a id="paso-21"></a>

## Paso 21: sltiu x3, x1, 10

ID: **`sltiu x3, x1, 10`**, PC=80. IF: **`sb x3, 4(x1)`**, PC=84.

| Salida | Valor esperado |
|---|---|
| `o_dbg_reg_data` | `0x00000000` |
| `o_if_pc` | `0x00000054` |
| `o_if_instr` | `0x00308223` |
| `o_if_addr_error` | `0` |
| `o_id_pc` | `0x00000050` |
| `o_id_instr` | `0x00A0B193` |
| `o_id_valid` | `1` |
| `o_id_imm` | `0x0000000A` |
| `o_id_rs1` | `1` |
| `o_id_rs2` | `10` |
| `o_id_rd` | `3` |
| `o_id_rs1_data` | `0x00000000` |
| `o_id_rs2_data` | `0x00000000` |
| `o_id_reg_write` | `1` |
| `o_id_alu_src_a` | `0` |
| `o_id_alu_src_b` | `1` |
| `o_id_mem_read` | `0` |
| `o_id_mem_write` | `0` |
| `o_id_result_src` | `0` |
| `o_id_branch` | `0` |
| `o_id_jump` | `0` |
| `o_id_jalr` | `0` |
| `o_id_alu_op` | `11` |
| `o_id_halt` | `0` |
| `o_id_uses_rs1` | `1` |
| `o_id_uses_rs2` | `0` |
| `o_id_illegal` | `0` |

<a id="paso-22"></a>

## Paso 22: sb x3, 4(x1)

ID: **`sb x3, 4(x1)`**, PC=84. IF: **`sh x3, 4(x1)`**, PC=88.

o_id_rd vale 4 por los bits [11:7] del inmediato. No es un destino: reg_write=0.

| Salida | Valor esperado |
|---|---|
| `o_dbg_reg_data` | `0x00000000` |
| `o_if_pc` | `0x00000058` |
| `o_if_instr` | `0x00309223` |
| `o_if_addr_error` | `0` |
| `o_id_pc` | `0x00000054` |
| `o_id_instr` | `0x00308223` |
| `o_id_valid` | `1` |
| `o_id_imm` | `0x00000004` |
| `o_id_rs1` | `1` |
| `o_id_rs2` | `3` |
| `o_id_rd` | `4` |
| `o_id_rs1_data` | `0x00000000` |
| `o_id_rs2_data` | `0x00000000` |
| `o_id_reg_write` | `0` |
| `o_id_alu_src_a` | `0` |
| `o_id_alu_src_b` | `1` |
| `o_id_mem_read` | `0` |
| `o_id_mem_write` | `1` |
| `o_id_result_src` | `0` |
| `o_id_branch` | `0` |
| `o_id_jump` | `0` |
| `o_id_jalr` | `0` |
| `o_id_alu_op` | `00` |
| `o_id_halt` | `0` |
| `o_id_uses_rs1` | `1` |
| `o_id_uses_rs2` | `1` |
| `o_id_illegal` | `0` |

<a id="paso-23"></a>

## Paso 23: sh x3, 4(x1)

ID: **`sh x3, 4(x1)`**, PC=88. IF: **`sw x3, 4(x1)`**, PC=92.

o_id_rd vale 4 por los bits [11:7] del inmediato. No es un destino: reg_write=0.

| Salida | Valor esperado |
|---|---|
| `o_dbg_reg_data` | `0x00000000` |
| `o_if_pc` | `0x0000005C` |
| `o_if_instr` | `0x0030A223` |
| `o_if_addr_error` | `0` |
| `o_id_pc` | `0x00000058` |
| `o_id_instr` | `0x00309223` |
| `o_id_valid` | `1` |
| `o_id_imm` | `0x00000004` |
| `o_id_rs1` | `1` |
| `o_id_rs2` | `3` |
| `o_id_rd` | `4` |
| `o_id_rs1_data` | `0x00000000` |
| `o_id_rs2_data` | `0x00000000` |
| `o_id_reg_write` | `0` |
| `o_id_alu_src_a` | `0` |
| `o_id_alu_src_b` | `1` |
| `o_id_mem_read` | `0` |
| `o_id_mem_write` | `1` |
| `o_id_result_src` | `0` |
| `o_id_branch` | `0` |
| `o_id_jump` | `0` |
| `o_id_jalr` | `0` |
| `o_id_alu_op` | `00` |
| `o_id_halt` | `0` |
| `o_id_uses_rs1` | `1` |
| `o_id_uses_rs2` | `1` |
| `o_id_illegal` | `0` |

<a id="paso-24"></a>

## Paso 24: sw x3, 4(x1)

ID: **`sw x3, 4(x1)`**, PC=92. IF: **`lb x3, 4(x1)`**, PC=96.

o_id_rd vale 4 por los bits [11:7] del inmediato. No es un destino: reg_write=0.

| Salida | Valor esperado |
|---|---|
| `o_dbg_reg_data` | `0x00000000` |
| `o_if_pc` | `0x00000060` |
| `o_if_instr` | `0x00408183` |
| `o_if_addr_error` | `0` |
| `o_id_pc` | `0x0000005C` |
| `o_id_instr` | `0x0030A223` |
| `o_id_valid` | `1` |
| `o_id_imm` | `0x00000004` |
| `o_id_rs1` | `1` |
| `o_id_rs2` | `3` |
| `o_id_rd` | `4` |
| `o_id_rs1_data` | `0x00000000` |
| `o_id_rs2_data` | `0x00000000` |
| `o_id_reg_write` | `0` |
| `o_id_alu_src_a` | `0` |
| `o_id_alu_src_b` | `1` |
| `o_id_mem_read` | `0` |
| `o_id_mem_write` | `1` |
| `o_id_result_src` | `0` |
| `o_id_branch` | `0` |
| `o_id_jump` | `0` |
| `o_id_jalr` | `0` |
| `o_id_alu_op` | `00` |
| `o_id_halt` | `0` |
| `o_id_uses_rs1` | `1` |
| `o_id_uses_rs2` | `1` |
| `o_id_illegal` | `0` |

<a id="paso-25"></a>

## Paso 25: lb x3, 4(x1)

ID: **`lb x3, 4(x1)`**, PC=96. IF: **`lbu x3, 4(x1)`**, PC=100.

| Salida | Valor esperado |
|---|---|
| `o_dbg_reg_data` | `0x00000000` |
| `o_if_pc` | `0x00000064` |
| `o_if_instr` | `0x0040C183` |
| `o_if_addr_error` | `0` |
| `o_id_pc` | `0x00000060` |
| `o_id_instr` | `0x00408183` |
| `o_id_valid` | `1` |
| `o_id_imm` | `0x00000004` |
| `o_id_rs1` | `1` |
| `o_id_rs2` | `4` |
| `o_id_rd` | `3` |
| `o_id_rs1_data` | `0x00000000` |
| `o_id_rs2_data` | `0x00000000` |
| `o_id_reg_write` | `1` |
| `o_id_alu_src_a` | `0` |
| `o_id_alu_src_b` | `1` |
| `o_id_mem_read` | `1` |
| `o_id_mem_write` | `0` |
| `o_id_result_src` | `1` |
| `o_id_branch` | `0` |
| `o_id_jump` | `0` |
| `o_id_jalr` | `0` |
| `o_id_alu_op` | `00` |
| `o_id_halt` | `0` |
| `o_id_uses_rs1` | `1` |
| `o_id_uses_rs2` | `0` |
| `o_id_illegal` | `0` |

<a id="paso-26"></a>

## Paso 26: lbu x3, 4(x1)

ID: **`lbu x3, 4(x1)`**, PC=100. IF: **`lh x3, 4(x1)`**, PC=104.

| Salida | Valor esperado |
|---|---|
| `o_dbg_reg_data` | `0x00000000` |
| `o_if_pc` | `0x00000068` |
| `o_if_instr` | `0x00409183` |
| `o_if_addr_error` | `0` |
| `o_id_pc` | `0x00000064` |
| `o_id_instr` | `0x0040C183` |
| `o_id_valid` | `1` |
| `o_id_imm` | `0x00000004` |
| `o_id_rs1` | `1` |
| `o_id_rs2` | `4` |
| `o_id_rd` | `3` |
| `o_id_rs1_data` | `0x00000000` |
| `o_id_rs2_data` | `0x00000000` |
| `o_id_reg_write` | `1` |
| `o_id_alu_src_a` | `0` |
| `o_id_alu_src_b` | `1` |
| `o_id_mem_read` | `1` |
| `o_id_mem_write` | `0` |
| `o_id_result_src` | `1` |
| `o_id_branch` | `0` |
| `o_id_jump` | `0` |
| `o_id_jalr` | `0` |
| `o_id_alu_op` | `00` |
| `o_id_halt` | `0` |
| `o_id_uses_rs1` | `1` |
| `o_id_uses_rs2` | `0` |
| `o_id_illegal` | `0` |

<a id="paso-27"></a>

## Paso 27: lh x3, 4(x1)

ID: **`lh x3, 4(x1)`**, PC=104. IF: **`lhu x3, 4(x1)`**, PC=108.

| Salida | Valor esperado |
|---|---|
| `o_dbg_reg_data` | `0x00000000` |
| `o_if_pc` | `0x0000006C` |
| `o_if_instr` | `0x0040D183` |
| `o_if_addr_error` | `0` |
| `o_id_pc` | `0x00000068` |
| `o_id_instr` | `0x00409183` |
| `o_id_valid` | `1` |
| `o_id_imm` | `0x00000004` |
| `o_id_rs1` | `1` |
| `o_id_rs2` | `4` |
| `o_id_rd` | `3` |
| `o_id_rs1_data` | `0x00000000` |
| `o_id_rs2_data` | `0x00000000` |
| `o_id_reg_write` | `1` |
| `o_id_alu_src_a` | `0` |
| `o_id_alu_src_b` | `1` |
| `o_id_mem_read` | `1` |
| `o_id_mem_write` | `0` |
| `o_id_result_src` | `1` |
| `o_id_branch` | `0` |
| `o_id_jump` | `0` |
| `o_id_jalr` | `0` |
| `o_id_alu_op` | `00` |
| `o_id_halt` | `0` |
| `o_id_uses_rs1` | `1` |
| `o_id_uses_rs2` | `0` |
| `o_id_illegal` | `0` |

<a id="paso-28"></a>

## Paso 28: lhu x3, 4(x1)

ID: **`lhu x3, 4(x1)`**, PC=108. IF: **`lw x3, 4(x1)`**, PC=112.

| Salida | Valor esperado |
|---|---|
| `o_dbg_reg_data` | `0x00000000` |
| `o_if_pc` | `0x00000070` |
| `o_if_instr` | `0x0040A183` |
| `o_if_addr_error` | `0` |
| `o_id_pc` | `0x0000006C` |
| `o_id_instr` | `0x0040D183` |
| `o_id_valid` | `1` |
| `o_id_imm` | `0x00000004` |
| `o_id_rs1` | `1` |
| `o_id_rs2` | `4` |
| `o_id_rd` | `3` |
| `o_id_rs1_data` | `0x00000000` |
| `o_id_rs2_data` | `0x00000000` |
| `o_id_reg_write` | `1` |
| `o_id_alu_src_a` | `0` |
| `o_id_alu_src_b` | `1` |
| `o_id_mem_read` | `1` |
| `o_id_mem_write` | `0` |
| `o_id_result_src` | `1` |
| `o_id_branch` | `0` |
| `o_id_jump` | `0` |
| `o_id_jalr` | `0` |
| `o_id_alu_op` | `00` |
| `o_id_halt` | `0` |
| `o_id_uses_rs1` | `1` |
| `o_id_uses_rs2` | `0` |
| `o_id_illegal` | `0` |

<a id="paso-29"></a>

## Paso 29: lw x3, 4(x1)

ID: **`lw x3, 4(x1)`**, PC=112. IF: **`beq x1, x2, paso_31`**, PC=116.

| Salida | Valor esperado |
|---|---|
| `o_dbg_reg_data` | `0x00000000` |
| `o_if_pc` | `0x00000074` |
| `o_if_instr` | `0x00208263` |
| `o_if_addr_error` | `0` |
| `o_id_pc` | `0x00000070` |
| `o_id_instr` | `0x0040A183` |
| `o_id_valid` | `1` |
| `o_id_imm` | `0x00000004` |
| `o_id_rs1` | `1` |
| `o_id_rs2` | `4` |
| `o_id_rd` | `3` |
| `o_id_rs1_data` | `0x00000000` |
| `o_id_rs2_data` | `0x00000000` |
| `o_id_reg_write` | `1` |
| `o_id_alu_src_a` | `0` |
| `o_id_alu_src_b` | `1` |
| `o_id_mem_read` | `1` |
| `o_id_mem_write` | `0` |
| `o_id_result_src` | `1` |
| `o_id_branch` | `0` |
| `o_id_jump` | `0` |
| `o_id_jalr` | `0` |
| `o_id_alu_op` | `00` |
| `o_id_halt` | `0` |
| `o_id_uses_rs1` | `1` |
| `o_id_uses_rs2` | `0` |
| `o_id_illegal` | `0` |

<a id="paso-30"></a>

## Paso 30: beq x1, x2, paso_31

ID: **`beq x1, x2, paso_31`**, PC=116. IF: **`bne x1, x2, paso_32`**, PC=120.

El destino es la instrucción siguiente (PC+4). rd=4 son bits del desplazamiento, no un registro destino.

| Salida | Valor esperado |
|---|---|
| `o_dbg_reg_data` | `0x00000000` |
| `o_if_pc` | `0x00000078` |
| `o_if_instr` | `0x00209263` |
| `o_if_addr_error` | `0` |
| `o_id_pc` | `0x00000074` |
| `o_id_instr` | `0x00208263` |
| `o_id_valid` | `1` |
| `o_id_imm` | `0x00000004` |
| `o_id_rs1` | `1` |
| `o_id_rs2` | `2` |
| `o_id_rd` | `4` |
| `o_id_rs1_data` | `0x00000000` |
| `o_id_rs2_data` | `0x00000000` |
| `o_id_reg_write` | `0` |
| `o_id_alu_src_a` | `0` |
| `o_id_alu_src_b` | `0` |
| `o_id_mem_read` | `0` |
| `o_id_mem_write` | `0` |
| `o_id_result_src` | `0` |
| `o_id_branch` | `1` |
| `o_id_jump` | `0` |
| `o_id_jalr` | `0` |
| `o_id_alu_op` | `01` |
| `o_id_halt` | `0` |
| `o_id_uses_rs1` | `1` |
| `o_id_uses_rs2` | `1` |
| `o_id_illegal` | `0` |

<a id="paso-31"></a>

## Paso 31: bne x1, x2, paso_32

ID: **`bne x1, x2, paso_32`**, PC=120. IF: **`jal x5, paso_33`**, PC=124.

El destino es la instrucción siguiente (PC+4). rd=4 son bits del desplazamiento, no un registro destino.

| Salida | Valor esperado |
|---|---|
| `o_dbg_reg_data` | `0x00000000` |
| `o_if_pc` | `0x0000007C` |
| `o_if_instr` | `0x004002EF` |
| `o_if_addr_error` | `0` |
| `o_id_pc` | `0x00000078` |
| `o_id_instr` | `0x00209263` |
| `o_id_valid` | `1` |
| `o_id_imm` | `0x00000004` |
| `o_id_rs1` | `1` |
| `o_id_rs2` | `2` |
| `o_id_rd` | `4` |
| `o_id_rs1_data` | `0x00000000` |
| `o_id_rs2_data` | `0x00000000` |
| `o_id_reg_write` | `0` |
| `o_id_alu_src_a` | `0` |
| `o_id_alu_src_b` | `0` |
| `o_id_mem_read` | `0` |
| `o_id_mem_write` | `0` |
| `o_id_result_src` | `0` |
| `o_id_branch` | `1` |
| `o_id_jump` | `0` |
| `o_id_jalr` | `0` |
| `o_id_alu_op` | `01` |
| `o_id_halt` | `0` |
| `o_id_uses_rs1` | `1` |
| `o_id_uses_rs2` | `1` |
| `o_id_illegal` | `0` |

<a id="paso-32"></a>

## Paso 32: jal x5, paso_33

ID: **`jal x5, paso_33`**, PC=124. IF: **`addi x4, x0, 136`**, PC=128.

Salto a la instrucción siguiente; la CPU completa guardaría PC+4 en x5. Este top solo lo decodifica.

| Salida | Valor esperado |
|---|---|
| `o_dbg_reg_data` | `0x00000000` |
| `o_if_pc` | `0x00000080` |
| `o_if_instr` | `0x08800213` |
| `o_if_addr_error` | `0` |
| `o_id_pc` | `0x0000007C` |
| `o_id_instr` | `0x004002EF` |
| `o_id_valid` | `1` |
| `o_id_imm` | `0x00000004` |
| `o_id_rs1` | `0` |
| `o_id_rs2` | `4` |
| `o_id_rd` | `5` |
| `o_id_rs1_data` | `0x00000000` |
| `o_id_rs2_data` | `0x00000000` |
| `o_id_reg_write` | `1` |
| `o_id_alu_src_a` | `0` |
| `o_id_alu_src_b` | `0` |
| `o_id_mem_read` | `0` |
| `o_id_mem_write` | `0` |
| `o_id_result_src` | `0` |
| `o_id_branch` | `0` |
| `o_id_jump` | `1` |
| `o_id_jalr` | `0` |
| `o_id_alu_op` | `00` |
| `o_id_halt` | `0` |
| `o_id_uses_rs1` | `0` |
| `o_id_uses_rs2` | `0` |
| `o_id_illegal` | `0` |

<a id="paso-33"></a>

## Paso 33: addi x4, x0, 136

ID: **`addi x4, x0, 136`**, PC=128. IF: **`jalr x0, 0(x4)`**, PC=132.

| Salida | Valor esperado |
|---|---|
| `o_dbg_reg_data` | `0x00000000` |
| `o_if_pc` | `0x00000084` |
| `o_if_instr` | `0x00020067` |
| `o_if_addr_error` | `0` |
| `o_id_pc` | `0x00000080` |
| `o_id_instr` | `0x08800213` |
| `o_id_valid` | `1` |
| `o_id_imm` | `0x00000088` |
| `o_id_rs1` | `0` |
| `o_id_rs2` | `8` |
| `o_id_rd` | `4` |
| `o_id_rs1_data` | `0x00000000` |
| `o_id_rs2_data` | `0x00000000` |
| `o_id_reg_write` | `1` |
| `o_id_alu_src_a` | `0` |
| `o_id_alu_src_b` | `1` |
| `o_id_mem_read` | `0` |
| `o_id_mem_write` | `0` |
| `o_id_result_src` | `0` |
| `o_id_branch` | `0` |
| `o_id_jump` | `0` |
| `o_id_jalr` | `0` |
| `o_id_alu_op` | `11` |
| `o_id_halt` | `0` |
| `o_id_uses_rs1` | `1` |
| `o_id_uses_rs2` | `0` |
| `o_id_illegal` | `0` |

<a id="paso-34"></a>

## Paso 34: jalr x0, 0(x4)

ID: **`jalr x0, 0(x4)`**, PC=132. IF: **`lui x3, 0x12345`**, PC=136.

En una CPU completa, x4 tendría la dirección de la instrucción siguiente. Aquí x4 sigue en cero y el salto no se ejecuta. reg_write=1 y rd=0: el banco bloquearía escribir x0.

| Salida | Valor esperado |
|---|---|
| `o_dbg_reg_data` | `0x00000000` |
| `o_if_pc` | `0x00000088` |
| `o_if_instr` | `0x123451B7` |
| `o_if_addr_error` | `0` |
| `o_id_pc` | `0x00000084` |
| `o_id_instr` | `0x00020067` |
| `o_id_valid` | `1` |
| `o_id_imm` | `0x00000000` |
| `o_id_rs1` | `4` |
| `o_id_rs2` | `0` |
| `o_id_rd` | `0` |
| `o_id_rs1_data` | `0x00000000` |
| `o_id_rs2_data` | `0x00000000` |
| `o_id_reg_write` | `1` |
| `o_id_alu_src_a` | `0` |
| `o_id_alu_src_b` | `1` |
| `o_id_mem_read` | `0` |
| `o_id_mem_write` | `0` |
| `o_id_result_src` | `0` |
| `o_id_branch` | `0` |
| `o_id_jump` | `1` |
| `o_id_jalr` | `1` |
| `o_id_alu_op` | `00` |
| `o_id_halt` | `0` |
| `o_id_uses_rs1` | `1` |
| `o_id_uses_rs2` | `0` |
| `o_id_illegal` | `0` |

<a id="paso-35"></a>

## Paso 35: lui x3, 0x12345

ID: **`lui x3, 0x12345`**, PC=136. IF: **`addi x3, x1, -5`**, PC=140.

rs1=8 y rs2=3 son fragmentos del inmediato superior: uses_rs1=uses_rs2=0. A se selecciona en cero y B en inmediato.

| Salida | Valor esperado |
|---|---|
| `o_dbg_reg_data` | `0x00000000` |
| `o_if_pc` | `0x0000008C` |
| `o_if_instr` | `0xFFB08193` |
| `o_if_addr_error` | `0` |
| `o_id_pc` | `0x00000088` |
| `o_id_instr` | `0x123451B7` |
| `o_id_valid` | `1` |
| `o_id_imm` | `0x12345000` |
| `o_id_rs1` | `8` |
| `o_id_rs2` | `3` |
| `o_id_rd` | `3` |
| `o_id_rs1_data` | `0x00000000` |
| `o_id_rs2_data` | `0x00000000` |
| `o_id_reg_write` | `1` |
| `o_id_alu_src_a` | `1` |
| `o_id_alu_src_b` | `1` |
| `o_id_mem_read` | `0` |
| `o_id_mem_write` | `0` |
| `o_id_result_src` | `0` |
| `o_id_branch` | `0` |
| `o_id_jump` | `0` |
| `o_id_jalr` | `0` |
| `o_id_alu_op` | `00` |
| `o_id_halt` | `0` |
| `o_id_uses_rs1` | `0` |
| `o_id_uses_rs2` | `0` |
| `o_id_illegal` | `0` |

<a id="paso-36"></a>

## Paso 36: addi x3, x1, -5

ID: **`addi x3, x1, -5`**, PC=140. IF: **`addi x0, x0, 0`**, PC=144.

El inmediato es -5 en complemento a dos. rs2=27 son bits del inmediato; uses_rs2=0. ALUOp sigue siendo 11, no cambia por el signo.

| Salida | Valor esperado |
|---|---|
| `o_dbg_reg_data` | `0x00000000` |
| `o_if_pc` | `0x00000090` |
| `o_if_instr` | `0x00000013` |
| `o_if_addr_error` | `0` |
| `o_id_pc` | `0x0000008C` |
| `o_id_instr` | `0xFFB08193` |
| `o_id_valid` | `1` |
| `o_id_imm` | `0xFFFFFFFB` |
| `o_id_rs1` | `1` |
| `o_id_rs2` | `27` |
| `o_id_rd` | `3` |
| `o_id_rs1_data` | `0x00000000` |
| `o_id_rs2_data` | `0x00000000` |
| `o_id_reg_write` | `1` |
| `o_id_alu_src_a` | `0` |
| `o_id_alu_src_b` | `1` |
| `o_id_mem_read` | `0` |
| `o_id_mem_write` | `0` |
| `o_id_result_src` | `0` |
| `o_id_branch` | `0` |
| `o_id_jump` | `0` |
| `o_id_jalr` | `0` |
| `o_id_alu_op` | `11` |
| `o_id_halt` | `0` |
| `o_id_uses_rs1` | `1` |
| `o_id_uses_rs2` | `0` |
| `o_id_illegal` | `0` |

<a id="paso-37"></a>

## Paso 37: addi x0, x0, 0

ID: **`addi x0, x0, 0`**, PC=144. IF: **`halt`**, PC=148.

NOP es un alias de ADDI, no una operación extra. valid=1 y reg_write=1, pero rd=0. No confundir con la burbuja del reset: allí valid=0 y los controles están desactivados.

| Salida | Valor esperado |
|---|---|
| `o_dbg_reg_data` | `0x00000000` |
| `o_if_pc` | `0x00000094` |
| `o_if_instr` | `0x00000000` |
| `o_if_addr_error` | `0` |
| `o_id_pc` | `0x00000090` |
| `o_id_instr` | `0x00000013` |
| `o_id_valid` | `1` |
| `o_id_imm` | `0x00000000` |
| `o_id_rs1` | `0` |
| `o_id_rs2` | `0` |
| `o_id_rd` | `0` |
| `o_id_rs1_data` | `0x00000000` |
| `o_id_rs2_data` | `0x00000000` |
| `o_id_reg_write` | `1` |
| `o_id_alu_src_a` | `0` |
| `o_id_alu_src_b` | `1` |
| `o_id_mem_read` | `0` |
| `o_id_mem_write` | `0` |
| `o_id_result_src` | `0` |
| `o_id_branch` | `0` |
| `o_id_jump` | `0` |
| `o_id_jalr` | `0` |
| `o_id_alu_op` | `11` |
| `o_id_halt` | `0` |
| `o_id_uses_rs1` | `1` |
| `o_id_uses_rs2` | `0` |
| `o_id_illegal` | `0` |

<a id="paso-38"></a>

## Paso 38: halt

ID: **`halt`**, PC=148. IF: **`addi x0, x0, 0 (NOP de guarda)`**, PC=152.

HALT propio del proyecto: cargar la palabra 0x00000000. El nombre halt requiere soporte del ensamblador. La salida halt=1 solo indica reconocimiento; este top sigue avanzando.

| Salida | Valor esperado |
|---|---|
| `o_dbg_reg_data` | `0x00000000` |
| `o_if_pc` | `0x00000098` |
| `o_if_instr` | `0x00000013` |
| `o_if_addr_error` | `0` |
| `o_id_pc` | `0x00000094` |
| `o_id_instr` | `0x00000000` |
| `o_id_valid` | `1` |
| `o_id_imm` | `0x00000000` |
| `o_id_rs1` | `0` |
| `o_id_rs2` | `0` |
| `o_id_rd` | `0` |
| `o_id_rs1_data` | `0x00000000` |
| `o_id_rs2_data` | `0x00000000` |
| `o_id_reg_write` | `0` |
| `o_id_alu_src_a` | `0` |
| `o_id_alu_src_b` | `0` |
| `o_id_mem_read` | `0` |
| `o_id_mem_write` | `0` |
| `o_id_result_src` | `0` |
| `o_id_branch` | `0` |
| `o_id_jump` | `0` |
| `o_id_jalr` | `0` |
| `o_id_alu_op` | `00` |
| `o_id_halt` | `1` |
| `o_id_uses_rs1` | `0` |
| `o_id_uses_rs2` | `0` |
| `o_id_illegal` | `0` |

## Verificación y próximos pasos

Los valores se calcularon con las codificaciones de las instrucciones y el RTL
actual de `cpu_if_id_test`, `control_unit` e `imm_gen`. Se comprobó que cada ficha
incluye las 27 salidas y que IF observa la palabra siguiente del HEX. No se corrió
simulación HDL ni se midieron estos valores en placa; son la referencia esperada.

Con el top actual, los datos del banco no permiten comprobar operaciones ni
forwarding. Al integrar EX/MEM/WB habrá que preparar otra referencia que incluya
escrituras reales, dependencias, stalls y saltos tomados que cambien el recorrido.
