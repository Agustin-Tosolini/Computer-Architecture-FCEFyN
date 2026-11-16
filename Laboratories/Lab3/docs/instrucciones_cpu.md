# Instrucciones de la CPU — referencia con ejemplos

Este documento explica las **32 instrucciones de RISC-V más el HALT propio**
que reconoce nuestro [decodificador](../src/cpu/id/control_unit.v).
Es el subconjunto del proyecto, no toda la ISA RISC-V.

La CPU completa está implementada en `src/cpu/cpu.v`. El módulo
`cpu_if_id_test` se conserva para estudiar búsqueda y decodificación por
separado: no ejecuta las instrucciones. Las decisiones de implementación
están en [decisiones_de_diseno.md](decisiones_de_diseno.md).

## Cómo leer los ejemplos

- `x0` a `x31` son registros de 32 bits. `x0` siempre entrega cero a las instrucciones y descarta las escrituras.
- Un número escrito directamente, como `5`, es un **inmediato**: está codificado dentro de la instrucción.
- En las operaciones aritméticas, el primer registro es el destino: `add x3, x1, x2` escribe en `x3`.
- Las direcciones y los desplazamientos de memoria se expresan en **bytes**.
- Cada ejemplo de las tablas es independiente; no forman un único programa.

## Tipos de instrucción y estructura de sus 32 bits

Una cosa es **qué hace una instrucción** (sumar, cargar, saltar) y otra es
**cómo se distribuyen sus bits**. No existe un formato L para LOAD: las cargas
usan el formato I. Tampoco todos los saltos son tipo J: JAL es J, JALR es I
y BEQ/BNE son B.

| Tipo | Nombre en inglés | Instrucciones de nuestro procesador |
|---|---|---|
| R | Register | Operaciones entre dos registros: ADD, SUB, AND, etc. |
| I | Immediate | Operaciones inmediatas, LOAD y JALR |
| S | Store | SB, SH, SW |
| B | Branch | BEQ, BNE |
| U | Upper Immediate | LUI |
| J | Jump | JAL |

Los campos tienen estas funciones:

- **rd:** registro destino. **rs1 y rs2:** registros fuente. Cada campo ocupa
  5 bits, suficientes para seleccionar uno de los 32 registros.
- **opcode:** 7 bits que identifican la familia de operación.
- **funct3 y funct7:** distinguen operaciones dentro de una familia; por
  ejemplo, ADD y SUB comparten opcode y funct3, pero cambia funct7.
- **imm:** inmediato, una constante incluida en la instrucción.

De bit 31 a bit 0, los formatos son:

```text
R: [funct7: 7][rs2: 5][rs1: 5][funct3: 3][rd: 5][opcode: 7]
I: [    imm[11:0]    ][rs1: 5][funct3: 3][rd: 5][opcode: 7]
S: [imm[11:5]][rs2: 5][rs1: 5][funct3: 3][imm[4:0]][opcode: 7]
B: [imm[12|10:5]][rs2: 5][rs1: 5][funct3: 3][imm[4:1|11]][opcode: 7]
U: [              imm[31:12]            ][rd: 5][opcode: 7]
J: [          imm[20|10:1|11|19:12]      ][rd: 5][opcode: 7]
```

En B y J, `|` separa fragmentos del inmediato, no representa una operación OR.
Su bit 0 no se almacena: se reconstruye como cero. Cuando existen, rd, rs1 y
rs2 están siempre en los bits `[11:7]`, `[19:15]` y `[24:20]`, respectivamente.

En tipo I, el inmediato ocupa los **12 bits superiores de la instrucción**,
`[31:20]`. Eso no significa que ocupe los bits superiores del resultado:
`addi x3, x0, 7` escribe **7** en x3. La CPU extrae el campo y extiende su signo
a 32 bits. Su rango es **−2048 a +2047**. En SLLI/SRLI/SRAI solo 5 bits
indican cuánto desplazar (0 a 31); los restantes identifican la operación.

**Usar un inmediato no significa ser tipo I:** S, B, U y J también tienen
inmediatos, distribuidos de otra manera.

## Tipo R: operaciones entre dos registros (10)

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

Por ejemplo, si x1 = 5 y x2 = 8, `add x3, x1, x2` escribe 13 en x3.
`SLT` (*Set Less Than*) y `SLTU` (*Set Less Than Unsigned*) también escriben
**en rd**: `slt x3, x1, x2` escribe 1 en x3 si x1 < x2, o 0 si no. No saltan.
Se reemplazan los 32 bits de x3 por `0x00000001` o `0x00000000`.

La diferencia de signo importa: `0xFFFFFFFF` es −1 con signo y 4294967295 sin
signo. Comparado con 3, SLT da 1 y SLTU da 0.

En SLL, SRL y SRA, la cantidad de desplazamientos sale de los cinco bits
inferiores de x2: entre 0 y 31. Los resultados quedan en x3.
Las sumas y restas conservan los 32 bits inferiores, sin generar una excepción
por desbordamiento aritmético.

## Tipo I: operaciones con inmediato (9)

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

## Tipo I: lecturas de memoria de datos — LOAD (5)

LOAD lleva un dato **de la memoria de datos a un registro**. Sus siglas son:

- **LB:** Load Byte. **LBU:** Load Byte Unsigned.
- **LH:** Load Halfword. **LHU:** Load Halfword Unsigned.
- **LW:** Load Word.

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
Ambos resultados tienen **32 bits**: cada dígito hexadecimal representa 4 bits;
8 dígitos son 32 bits. El prefijo `0x` no ocupa bits. Estos son los datos
cargados en rd, no las codificaciones de las instrucciones.

```text
Byte leído:           11111111
LB:  11111111 11111111 11111111 11111111  (copia el signo)
LBU: 00000000 00000000 00000000 11111111  (completa con ceros)
```

Por ejemplo, con x1 = 16 y una palabra de valor 99 en la dirección 20:
`lw x3, 4(x1)` calcula 16 + 4 = 20, lee esa palabra y escribe **99** en x3,
no la dirección 20.

## Tipo S: escrituras en memoria de datos — STORE (3)

El primer registro es **el dato que queremos guardar**, no un registro destino.
La dirección se calcula sumando el desplazamiento al registro entre paréntesis.

| Instrucción | Ejemplo | Qué hace |
|---|---|---|
| SB | `sb x3, 4(x1)` | Guarda los 8 bits inferiores de x3 en memoria. |
| SH | `sh x3, 4(x1)` | Guarda los 16 bits inferiores de x3. |
| SW | `sw x3, 4(x1)` | Guarda los 32 bits completos de x3. |

STORE hace el recorrido inverso a LOAD: **del registro a la memoria**.
SB significa *Store Byte*, SH *Store Halfword* y SW *Store Word*.
Con x1 = 16 y x3 = 99, `sw x3, 4(x1)` guarda 99 en la dirección 20.
No tiene rd: x3 es rs2 (dato) y x1 es rs1 (base de la dirección).

### Direcciones, tamaño y alineación de nuestra memoria

La memoria tiene **32 palabras de 32 bits**, es decir, 128 bytes. La CPU usa
**direcciones de byte**, no índices de palabra:

| Palabra del arreglo | Direcciones de sus bytes |
|---|---|
| mem[0] | 0, 1, 2, 3 |
| mem[1] | 4, 5, 6, 7 |
| mem[2] | 8, 9, 10, 11 |
| mem[31] | 124, 125, 126, 127 |

El índice es `dirección / 4` (división entera) y el byte dentro de la palabra
es `dirección % 4`. No siempre se accede al primer byte:

```asm
lb x3, 5(x0)     # Byte de dirección 5: byte 1 de mem[1]
lh x3, 6(x0)     # Bytes 6 y 7: mitad superior de mem[1]
lw x3, 4(x0)     # Bytes 4 a 7: mem[1] completa
```

La memoria es **little-endian**: el byte de menor dirección ocupa los bits
menos significativos de la palabra. SB modifica un byte y SH dos; los demás
conservan su valor. SW reemplaza los cuatro.

**Alineación** significa comenzar en un múltiplo del tamaño del acceso:

| Tamaño | Direcciones iniciales válidas |
|---|---|
| Byte | Cualquiera de 0 a 127 |
| Halfword (2 bytes) | Pares: 0, 2, …, 126 |
| Word (4 bytes) | Múltiplos de 4: 0, 4, …, 124 |

```asm
lw x3, 124(x0)   # Válido: última palabra
lw x3, 5(x0)     # Error: desalineado
sw x3, 128(x0)   # Error: fuera de rango
```

La comprobación se hace sobre la **dirección final = rs1 + inmediato**.
Los 12 bits del inmediato son un desplazamiento **siempre con signo**,
entre −2048 y +2047 bytes. La U de LBU/LHU se refiere al dato leído, no a la
dirección. Esos 12 bits no limitan la memoria a 4096 bytes: se extienden a
32 bits y se suman a la base de 32 bits; no forman una dirección de 44 bits.
La suma conserva los 32 bits inferiores. El espacio representable es de
4 GiB, pero nuestro hardware solo implementa 128 bytes.

### Qué ocurre ante un acceso inválido

En MEM se activa `o_access_error`. Un STORE inválido **no escribe memoria** y
un LOAD inválido **no modifica rd**. Las instrucciones anteriores terminan y
las posteriores se descartan. Al llegar el marcador de error a WB quedan
`o_halted = 1` y `o_fault = 1`.

La unidad de depuración incluye estas señales en el byte de estado del
volcado: bit 0 = detenido, bit 1 = interrumpido, bit 2 = error. Una parada por
error sin interrupción da **0x05**; un HALT normal da **0x01**. La bandera no se
manda sola: viaja dentro del volcado de 326 bytes, al terminar R, después de S
o al pedir D.

La CPU queda detenida hasta un reset. Cargar otro programa con L también la
resetea: limpia el error, registros, PC, contador de ciclos y pipeline, pero
**conserva la memoria de datos**. Responde K y espera R o S para ejecutar.

## Saltos: tipos B, J e I (4)

BEQ significa *Branch if Equal* y BNE *Branch if Not Equal*: ambos son
**tipo B**, comparan dos registros y no guardan una dirección de retorno.
JAL (*Jump And Link*) es **tipo J**. JALR (*Jump And Link Register*) es
**tipo I**. Ambos saltan siempre y guardan PC + 4 en rd; “Link” se refiere a
esa dirección de retorno.

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

Por ejemplo, `jalr x5, 8(x1)`, ejecutado en PC = 40 con x1 = 100,
salta a 108 y guarda 44 en x5. No lee memoria de datos en 108: busca allí la
próxima instrucción. Si la suma diera 109, borrar el bit 0 la convierte en
108; si diera 110, queda 110 y produce error por no ser múltiplo de 4.

### Cómo se interpreta una etiqueta

La etiqueta nombra la dirección de la instrucción siguiente; **no ocupa
memoria**. Si un BEQ o JAL está en 40 y su etiqueta en 60, el ensamblador
codifica un desplazamiento de **60 − 40 = 20 bytes**. La CPU recibe ese número,
no el nombre de la etiqueta. Si el destino está antes, el desplazamiento es negativo.

En `beq x1, x2, destino`, los registros sirven para comparar y el inmediato
para calcular adónde saltar. Si son iguales va a 40 + 20 = 60; si no, a 44.
El inmediato **ya está codificado**, no está en cero durante la decodificación:
en ID, `imm_gen` reordena sus bits y extiende el signo; ID/EX lo guarda y EX
lo usa junto con el PC de esa instrucción para calcular el destino.

Ejemplo de llamada y retorno (cargado desde la dirección 0):

```asm
    jal  x1, rutina       # PC=0: inmediato=12; salta a 12 y guarda 4 en x1
    addi x5, x0, 7        # PC=4: al volver, continúa acá
    halt                 # PC=8

rutina:                  # Nombre de la dirección 12
    addi x6, x0, 3        # PC=12
    jalr x0, 0(x1)        # PC=16: vuelve a 4; descarta el nuevo retorno en x0
```

La CPU completa resuelve los saltos en EX. El módulo auxiliar `cpu_if_id_test`
solo los reconoce y sigue buscando secuencialmente; no ejecuta este flujo.

## Tipo U: LUI (1), y la parada propia HALT

| Instrucción | Ejemplo | Qué hace |
|---|---|---|
| LUI | `lui x3, 0x12345` | Coloca el inmediato en los 20 bits superiores y deja los 12 inferiores en cero: x3 = 0x12345000. |
| HALT — propia | `halt` | Solicita detener el ingreso de instrucciones y completar las anteriores antes de indicar halted. |

**LUI significa Load Upper Immediate.** Pertenece al tipo U, aunque su nombre
incluya “Immediate”: tiene 20 bits de inmediato y no lee un registro fuente.
Coloca ese valor en los 20 bits superiores de rd y deja 12 ceros debajo:

```asm
lui x3, 0x12345    # x3 = 0x12345000
lui x3, 0x123      # x3 = 0x00123000: también desplaza 12 bits
```

Se puede combinar con ADDI para construir una constante mayor:

```asm
lui  x3, 0x12345
addi x3, x3, 0x678    # x3 = 0x12345678
```

HALT se codifica como `0x00000000` por decisión del proyecto: **no es una
instrucción estándar de RV32I**. Nuestro ensamblador (`scripts/ensamblador.py`)
reconoce el nombre `halt`. El cpu la detecta en ID, deja de buscar
instrucciones y activa `o_halted` cuando el HALT llega a WB: con 5 NOPs + HALT,
después de 9 ciclos. El PC queda en la dirección del HALT + 4. Una instrucción
no soportada (o un fetch fuera de la memoria) se detiene igual, pero además
activa `o_fault` (estado 0x05 en el volcado).

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
Las 32 instrucciones soportadas y HALT tienen pruebas en simulación: `testbench/tb_cpu_isa.v`
(cpu solo) y `testbench/tb_top_cpu.v` (por UART) ejecutan los programas de
`scripts/programas/` y comparan, ciclo a ciclo, con el modelo de referencia
`scripts/rv32i_model.py`. `alu.asm` y `memoria.asm` cubren los casos borde.
