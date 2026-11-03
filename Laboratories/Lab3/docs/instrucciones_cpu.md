# Instrucciones de la CPU — referencia con ejemplos

Este documento resume las **32 instrucciones de RISC-V más el HALT propio**
que reconoce nuestro [decodificador](../src/cpu/control_unit.v).
Es el subconjunto del proyecto, no toda la ISA RISC-V.

El top `cpu_if_id_test` busca y decodifica estas instrucciones, pero todavía
no las ejecuta. Las acciones descritas aquí corresponden a la CPU completa
planificada. Las decisiones de implementación están en
[decisiones_de_diseno.md](decisiones_de_diseno.md).

## Cómo leer los ejemplos

- `x0` a `x31` son registros de 32 bits. `x0` siempre entrega cero a las instrucciones y descarta las escrituras.
- Un número escrito directamente, como `5`, es un **inmediato**: está codificado dentro de la instrucción.
- En las operaciones aritméticas, el primer registro es el destino: `add x3, x1, x2` escribe en `x3`.
- Las direcciones y los desplazamientos de memoria se expresan en **bytes**.
- Cada ejemplo de las tablas es independiente; no forman un único programa.

## Operaciones entre dos registros (10)

Formato habitual: `operación destino, fuente1, fuente2`.

| Instrucción | Ejemplo | Qué hace |
|---|---|---|
| ADD | `add x3, x1, x2` | Guarda en x3 la suma x1 + x2. |
| SUB | `sub x3, x1, x2` | Guarda en x3 la resta x1 − x2. |
| AND | `and x3, x1, x2` | Hace AND bit a bit. |
| OR | `or x3, x1, x2` | Hace OR bit a bit. |
| XOR | `xor x3, x1, x2` | Hace XOR bit a bit. |
| SLL | `sll x3, x1, x2` | Desplaza x1 a la izquierda, rellenando con ceros. |
| SRL | `srl x3, x1, x2` | Desplaza x1 a la derecha, rellenando con ceros. |
| SRA | `sra x3, x1, x2` | Desplaza x1 a la derecha, copiando el bit de signo. |
| SLT | `slt x3, x1, x2` | Guarda 1 si x1 < x2, interpretados con signo; si no, 0. |
| SLTU | `sltu x3, x1, x2` | Guarda 1 si x1 < x2, interpretados sin signo; si no, 0. |

En SLL, SRL y SRA, la cantidad de desplazamientos sale de los cinco bits
inferiores de x2: entre 0 y 31. Los resultados quedan en x3.
Las sumas y restas conservan los 32 bits inferiores, sin generar una excepción
por desbordamiento aritmético.

## Operaciones con inmediato (9)

| Instrucción | Ejemplo | Qué hace |
|---|---|---|
| ADDI | `addi x3, x1, 5` | Guarda x1 + 5 en x3. |
| ANDI | `andi x3, x1, 15` | Hace AND con 15; conserva los cuatro bits inferiores. |
| ORI | `ori x3, x1, 1` | Hace OR con 1; pone el bit inferior en uno. |
| XORI | `xori x3, x1, 1` | Hace XOR con 1; invierte el bit inferior. |
| SLLI | `slli x3, x1, 2` | Desplaza x1 dos posiciones a la izquierda. |
| SRLI | `srli x3, x1, 2` | Desplaza dos posiciones a la derecha, rellenando con ceros. |
| SRAI | `srai x3, x1, 2` | Desplaza dos posiciones a la derecha, copiando el signo. |
| SLTI | `slti x3, x1, 10` | Guarda 1 si x1 < 10, con signo; si no, 0. |
| SLTIU | `sltiu x3, x1, 10` | Guarda 1 si x1 < 10, sin signo; si no, 0. |

Los resultados quedan en x3. No necesitamos SUBI: para restar una constante,
podemos escribir `addi x3, x1, -5`.

Salvo los desplazamientos, estas instrucciones usan un inmediato de 12 bits
extendido con signo a 32 bits. Esto también ocurre en SLTIU: primero se extiende
el inmediato con signo y luego se comparan ambos operandos como valores sin signo.
Los desplazamientos inmediatos permiten cantidades de 0 a 31.

## Lecturas de memoria de datos — LOAD (5)

`4(x1)` significa «dirección almacenada en x1, más 4 bytes».
Si x1 = 100, accedemos a la dirección 104. El dato leído se guarda en x3.

| Instrucción | Ejemplo | Qué hace |
|---|---|---|
| LB | `lb x3, 4(x1)` | Lee 8 bits y los extiende a 32 copiando el signo. |
| LBU | `lbu x3, 4(x1)` | Lee 8 bits y completa los bits superiores con ceros. |
| LH | `lh x3, 4(x1)` | Lee 16 bits y los extiende a 32 copiando el signo. |
| LHU | `lhu x3, 4(x1)` | Lee 16 bits y completa los bits superiores con ceros. |
| LW | `lw x3, 4(x1)` | Lee una palabra completa de 32 bits. |

Si el byte leído es `11111111`, LB devuelve `0xFFFFFFFF` (−1 con signo),
mientras que LBU devuelve `0x000000FF` (255).

## Escrituras en memoria de datos — STORE (3)

El primer registro es **el dato que queremos guardar**, no un registro destino.
La dirección se calcula sumando el desplazamiento al registro entre paréntesis.

| Instrucción | Ejemplo | Qué hace |
|---|---|---|
| SB | `sb x3, 4(x1)` | Guarda los 8 bits inferiores de x3 en memoria. |
| SH | `sh x3, 4(x1)` | Guarda los 16 bits inferiores de x3. |
| SW | `sw x3, 4(x1)` | Guarda los 32 bits completos de x3. |

Para las pruebas del proyecto, usar direcciones dentro de la memoria y alineadas:
múltiplos de 2 para medias palabras y de 4 para palabras. La política final
para accesos incorrectos está pendiente en las decisiones de diseño.

## Saltos (4)

`destino` es una **etiqueta del programa**. El ensamblador calcula el desplazamiento
desde la instrucción de salto hasta esa etiqueta. En estas fórmulas, PC es la
dirección de la propia instrucción de salto.

| Instrucción | Ejemplo | Qué hace |
|---|---|---|
| BEQ | `beq x1, x2, destino` | Salta a destino si x1 == x2; si no, continúa en PC + 4. |
| BNE | `bne x1, x2, destino` | Salta a destino si x1 != x2; si no, continúa en PC + 4. |
| JAL | `jal x1, destino` | Salta siempre a destino y guarda PC + 4 en x1. |
| JALR | `jalr x0, 0(x1)` | Salta a la dirección de x1, poniendo su bit inferior en cero. Descarta el retorno al dirigirlo a x0. |

**JAL sí es una instrucción.** Su nombre significa *Jump And Link*: salta y
guarda una dirección de retorno. BEQ, BNE y JAL calculan el destino como
`PC + inmediato`.

JALR calcula el destino como `(rs1 + inmediato) & ~1` y también guarda `PC + 4`
en su registro destino. En el ejemplo elegimos x0 porque al volver no necesitamos
guardar otra dirección de retorno. En nuestro diseño sin instrucciones comprimidas,
el destino debe quedar alineado a cuatro bytes; borrar el bit 0 no garantiza eso.

Ejemplo conceptual de llamada y retorno:

```asm
    jal  x1, rutina       # Guarda en x1 la dirección de la siguiente instrucción
    addi x5, x0, 7        # Al volver, continúa acá
    halt

rutina:
    addi x6, x0, 3
    jalr x0, 0(x1)        # Vuelve a la dirección guardada en x1
```

Resolveremos los saltos en EX. El top actual IF/ID solo los reconoce y sigue
buscando secuencialmente; todavía no ejecuta este flujo de programa.

## Constante superior (1) y parada propia

| Instrucción | Ejemplo | Qué hace |
|---|---|---|
| LUI | `lui x3, 0x12345` | Coloca el inmediato en los 20 bits superiores y deja los 12 inferiores en cero: x3 = 0x12345000. |
| HALT — propia | `halt` | Solicita detener el ingreso de instrucciones y completar las anteriores antes de indicar halted. |

HALT se codifica como `0x00000000` por decisión del proyecto: **no es una
instrucción estándar de RV32I**. La escritura `halt` en assembler requiere que
nuestro ensamblador reconozca ese nombre. Su parada está planificada; el top
actual solamente activa la salida de reconocimiento `o_id_halt`.

## NOP: no hacer nada

NOP no agrega otra operación al decodificador. Es una pseudoinstrucción que se
representa con una instrucción ya incluida:

```asm
addi x0, x0, 0           # NOP, codificación 0x00000013
```

Como x0 entrega cero y descarta las escrituras, no modifica ningún registro.
Una NOP válida y una burbuja no son exactamente lo mismo: en nuestro pipeline,
una burbuja se marca con `valid = 0`, aunque el campo de instrucción contenga NOP.

## Alcance

El total es 10 operaciones entre registros + 9 con inmediato + 5 cargas +
3 escrituras + 4 saltos + 1 LUI = **32 instrucciones RISC-V**.
Con el HALT propio son **33 entradas**; NOP es un alias de ADDI.

No incluimos, por ejemplo, MUL, DIV, AUIPC ni los saltos BLT/BGE/BLTU/BGEU.
Reconocer una instrucción en ID no significa que toda su ejecución ya esté
implementada o probada.
