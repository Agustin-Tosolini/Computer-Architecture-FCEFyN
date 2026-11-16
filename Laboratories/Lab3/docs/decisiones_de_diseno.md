# Decisiones de diseño — CPU y depurador

Este documento describe el diseño actual y los motivos de sus decisiones.
Las secciones 1 a 7 explican la CPU y su interfaz; las siguientes cubren la
comunicación, las herramientas, las pruebas y la implementación en FPGA.

La CPU está en `src/cpu/cpu.v` y el top de placa en `src/debug_unit/top.v`.
`src/params.vh` documenta el contrato: los módulos RTL no lo incluyen.
Los resultados de implementación y placa están documentados en la sección 12
y en [CHECKLIST_placa.md](CHECKLIST_placa.md).

Referencia: [instrucciones con ejemplos](instrucciones_cpu.md).
Diagrama: [CPU completa](informe/img/CPU_completo.png).

## 1. Organización y alcance

Implementamos un procesador de 32 bits con cinco etapas: **IF → ID → EX → MEM → WB**.
Las instrucciones avanzan en orden. Cada etapa trabaja sobre una instrucción
distinta; los registros intermedios conservan sus datos entre flancos.

Se soportan **32 instrucciones RISC-V más HALT propio**, no toda la ISA:

| Grupo | Instrucciones |
|---|---|
| Registro a registro | ADD, SUB, SLL, SRL, SRA, SLT, SLTU, XOR, OR, AND |
| Con inmediato | ADDI, SLLI, SRLI, SRAI, SLTI, SLTIU, XORI, ORI, ANDI |
| Lectura de memoria | LB, LH, LW, LBU, LHU |
| Escritura de memoria | SB, SH, SW |
| Saltos | BEQ, BNE, JAL, JALR |
| Inmediato superior | LUI |

HALT es `0x00000000`. NOP es `0x00000013` (`addi x0,x0,0`), no una
instrucción adicional. No se implementan AUIPC, instrucciones comprimidas ni traps.

Los archivos se agrupan por función; las conexiones reales dependen de las
instancias en `cpu.v`, no de las carpetas:

| Carpeta dentro de `src/cpu/` | Módulos y función |
|---|---|
| `if/` | `pc_reg`: guarda PC. `instr_mem`: guarda el programa. |
| `id/` | `control_unit`: decodifica. `reg_file`: banco de registros. `imm_gen`: inmediato. |
| `ex/` | `alu_control`: elige la operación. `alu`: calcula. |
| `mem/` | `data_mem`: memoria de datos. |
| `pipeline/` | `if_id`, `id_ex`, `ex_mem`, `mem_wb`: almacenamiento entre etapas. |
| `hazards/` | `forwarding_unit` y `hazard_unit`: dependencias, esperas y limpieza. |
| Raíz | `cpu.v`: integración completa. `cpu_if_id_test.v`: prueba aislada de IF/ID. |

Los multiplexores, sumadores de PC, decisiones de salto y control de parada
están escritos dentro de `cpu.v`; no son módulos separados. `ALU_ctrl` del TP2
no se reutiliza: coordinaba la comunicación UART y tenía otra función.

## 2. Memorias, PC y registros

Separamos programa, datos y banco de registros para permitir accesos simultáneos.
La consigna no fija la capacidad de las memorias. El contrato de la Debug Unit
es nuestra referencia principal: toda la memoria de datos debe entrar en su volcado.

| Recurso | Tamaño | Direccionamiento y acceso |
|---|---|---|
| Programa | 256 palabras de 32 bits: 1 KiB | CPU usa PC en bytes; memoria recibe `PC[9:2]`. Lectura combinacional, escritura por flanco. |
| Datos | 32 palabras de 32 bits: 128 bytes | CPU usa bytes 0…127; índice de palabra `addr[6:2]`. Lectura combinacional, escritura por bytes en el flanco. RAM: **el reset de CPU no la borra**. |
| Banco de registros | 32 registros de 32 bits | Índices de 5 bits: x0…x31. Dos lecturas combinacionales y una escritura por flanco. |

**PC tiene 32 bits y cuenta bytes.** El avance normal es PC+4 porque cada
instrucción ocupa cuatro bytes. `pc_reg` solo almacena el próximo valor;
`cpu.v` calcula PC+4, selecciona saltos y comprueba rango y alineación.

Ambas memorias solicitan RAM distribuida con `(* ram_style = "distributed" *)`
para mantener las lecturas combinacionales. La implementación documentada en Vivado confirma RAM distribuida
para ambas memorias (sección 12). Al configurar la FPGA, programa inicia en HALT y
datos en cero. Esas inicializaciones no se repiten con el reset de CPU.

### Banco de registros y x0

- Las instrucciones leen x0 como cero y sus escrituras se descartan.
- El reset síncrono limpia los 32 registros, incluso durante pausa.
- Debug lee directamente el arreglo, sin bypass, pero **x0 se fuerza a 0**
  (contrato).
- El bypass WB → ID entrega el dato nuevo si WB escribe el registro que ID
  necesita. Usa la misma habilitación que la escritura:
  `i_enable && i_we && !i_reset && rd != 0`.
- Antes del flanco, un operando puede ver el dato adelantado mientras debug
  todavía muestra el anterior. El almacenamiento cambia recién en el flanco.

### Accesos a datos

La memoria es **little-endian**: el byte menos significativo ocupa la dirección
más baja. LB/LH extienden signo; LBU/LHU completan con ceros; LW entrega 32 bits.
SB/SH modifican solo los bytes seleccionados y SW la palabra completa.
El dato de STORE llega con forwarding aplicado.

Se exige dirección par para halfword y múltiplo de cuatro para word. Se rechazan
accesos fuera de rango, funct3 no soportado y lectura/escritura simultáneas:
`o_access_error=1`, lectura cero y escritura inhibida. No se permite que una
dirección inválida termine accediendo a otra posición por truncamiento.

Sin LOAD, `o_rdata=0`; sin solicitud de acceso, `o_access_error=0`. Las lecturas
siguen disponibles durante pausa. Las solicitudes de CPU se habilitan solo para
instrucciones válidas de EX/MEM; la escritura requiere además avance y ausencia
de reset. La respuesta de la CPU a errores se explica en la sección 6.

## 3. Decodificación, cálculo y escritura

### IF: búsqueda de la instrucción

IF usa el PC para leer la memoria de instrucciones. Como el PC indica una
dirección en bytes y cada instrucción ocupa cuatro bytes, `instr_mem` recibe
`PC[9:2]` como índice de palabra. La lectura es combinacional.

En un avance normal, el flanco ascendente guarda la instrucción y su PC en
IF/ID, y actualiza el PC a PC+4. Por ejemplo, con PC=8 se lee la palabra 2;
IF/ID conserva esa instrucción junto con el valor 8, mientras el PC pasa a 12.

`cpu.v` controla las excepciones a ese avance: un stall retiene PC e IF/ID;
un salto tomado en EX redirige el PC y descarta las instrucciones buscadas
por el camino incorrecto. También comprueba que la dirección esté alineada
a cuatro bytes y dentro de la memoria de programa. Una búsqueda inválida
se trata como se explica en la sección 6.

### ID: control e inmediato

`control_unit` recibe instrucción completa y valid. Usa opcode, funct3 y funct7
para reconocer las operaciones; solo la palabra cero completa es HALT.
Una burbuja no genera efectos. Una instrucción no soportada activa `illegal`
y deja desactivados los controles de escritura y acceso a memoria.
La alineación y el rango se comprueban durante la ejecución, no en este módulo.

| Control | Significado |
|---|---|
| `reg_write` | Solicita escritura en rd. |
| `alu_src_a` | 0: rs1 adelantado; 1: cero. |
| `alu_src_b` | 0: rs2 adelantado; 1: inmediato. |
| `mem_read`, `mem_write` | Solicitan LOAD o STORE. |
| `result_src` | 0: resultado de EX; 1: dato de memoria. |
| `branch`, `jump`, `jalr` | Identifican salto condicional, incondicional y destino basado en rs1. |
| `uses_rs1`, `uses_rs2` | Indican fuentes reales para forwarding y hazards. STORE usa rs2 aunque la ALU use inmediato. |
| `halt`, `illegal` | Identifican parada e instrucción no soportada. |

`imm_gen` reconstruye el inmediato de 32 bits según opcode:

- I para aritmética inmediata, LOAD y JALR; S para STORE; B para BEQ/BNE;
  U para LUI; J para JAL.
- I, S, B y J extienden signo; U agrega 12 ceros inferiores.
- B y J ya entregan desplazamientos en bytes, con su cero inferior incluido:
  no se desplazan nuevamente antes de sumarlos al PC.
- Los shifts usan el formato I, pero la ALU toma solo cinco bits de desplazamiento.
- Los demás opcodes entregan inmediato cero; eso no significa que sean válidos.

### EX: ALU y saltos

La ALU es combinacional, de ancho fijo de 32 bits. Reutiliza las operaciones
útiles del TP2 y elimina NOR. No guarda resultados ni expone carry u overflow.
Suma y resta conservan los 32 bits inferiores, sin excepción por desbordamiento.

| Operación | Código interno de ALU |
|---|---|
| ADD / SUB | `0000` / `1000` |
| SLL / SRL / SRA | `0001` / `0101` / `1101` |
| SLT / SLTU | `0010` / `0011` |
| XOR / OR / AND | `0100` / `0110` / `0111` |

Estos códigos no son opcodes de instrucciones. `alu_control` los obtiene de
ALUOp, funct3 y bit 30. ALUOp indica `00`: suma, `01`: resta, `10`: tipo R,
`11`: aritmética I. En R usa `{funct7[5],funct3}`; en I utiliza bit 30 solo
para distinguir SRLI/SRAI. Así un inmediato negativo no convierte ADDI en SUB.
La validación completa corresponde a `control_unit`. Un código interno de ALU
no reconocido devuelve cero, pero no sustituye esa validación.

Los desplazamientos usan `i_b[4:0]` (0…31). SLT y SRA interpretan el dato con
signo; SLTU y SRL sin signo. `zero` indica resultado cero y sirve para BEQ/BNE.

Todos los saltos se resuelven en EX con los operandos corregidos por forwarding:

| Instrucción | Decisión y destino |
|---|---|
| BEQ / BNE | Comparar por resta; si corresponde, destino = PC de la instrucción + inmediato. |
| JAL | Destino = PC de la instrucción + inmediato. |
| JALR | Destino = `(rs1 + inmediato) & ~1`. |

JAL/JALR seleccionan PC+4 como resultado de EX antes de guardarlo en EX/MEM.
Así la dirección de retorno también puede adelantarse. El destino debe estar
alineado a cuatro bytes: no se implementan instrucciones comprimidas.

### MEM y WB

MEM accede a `data_mem` solo para LOAD/STORE. Las demás instrucciones dejan
pasar su resultado de EX. WB selecciona memoria o EX mediante `result_src` y
escribe rd si la instrucción es válida, solicita escritura, no es ilegal y
la CPU avanza. Un LOAD rechazado pierde su permiso de escritura antes de WB.
STORE no escribe el banco de registros.

## 4. Registros entre etapas

Los llamados “latches” son **flip-flops de flanco ascendente**, no latches
sensibles a nivel. Cada grupo tiene campos fijos para todas las instrucciones.
Los datos y sus controles siempre avanzan juntos; valid=0 representa una burbuja.

| Módulo | Campos almacenados | Bits |
|---|---|---|
| `if_id` | PC, instrucción completa, valid. | 65 (96 en el volcado) |
| `id_ex` | PC, rs1_data, rs2_data, inmediato, rs1/rs2/rd, funct3, bit 30; reg_write, alu_src_a/b, mem_read/write, result_src, branch, jump, jalr, ALUOp, halt, uses_rs1/2, illegal, valid. | 163 (192) |
| `ex_mem` | Resultado EX, dato STORE, rd, funct3; reg_write, mem_read/write, result_src, halt, illegal, valid. | 79 (96) |
| `mem_wb` | Resultado EX, dato leído de memoria, rd; reg_write, result_src, halt, illegal (también 1 si el error fue un acceso a memoria), valid. | 74 (96) |

En el volcado cada latch ocupa palabras enteras de 32 bits: la
tabla de campos con sus bits está en `src/params.vh`, sección 4b.

ID/EX no conserva la instrucción completa: conserva su información decodificada.
EX/MEM recibe el resultado ya seleccionado y MEM/WB guarda ambas opciones para
WB. Ninguno de estos registros realiza cálculos ni escribe por sí mismo en rd.

El reset tiene prioridad sobre todo; la pausa conserva todos los campos.
Durante un avance:

- IF/ID: flush gana al permiso local de escritura; sin permiso retiene el estado.
  Reset/flush dejan PC=0, instrucción NOP y valid=0.
- ID/EX: flush o entrada inválida limpian todos los campos; en otro caso captura.
- EX/MEM y MEM/WB: entrada inválida limpia todos los campos; en otro caso capturan.
  No tienen flush de salto porque las instrucciones anteriores deben continuar.

## 5. Riesgos del pipeline

Los tres tipos están contemplados. No todos los resuelve `hazard_unit`:

| Riesgo | Ejemplo | Solución del diseño |
|---|---|---|
| **Estructural** | IF y MEM necesitan acceder a memoria en el mismo ciclo. | Memorias de programa y datos separadas. El banco tiene dos lecturas y una escritura para que ID y WB puedan trabajar simultáneamente. |
| **De datos** | Una instrucción necesita un resultado aún no escrito en rd. | Forwarding hacia EX, bypass WB → ID y un ciclo de stall ante LOAD-use inmediato. |
| **De control** | Se buscan instrucciones antes de resolver un salto. | Resolver en EX; si se toma, cambiar PC y limpiar IF/ID e ID/EX. |

### Forwarding

`forwarding_unit` compara las fuentes realmente usadas por una instrucción
válida de EX con los destinos de escritores válidos en EX/MEM y MEM/WB.
Ignora x0 y controla dos multiplexores independientes en `cpu.v`:

| Selector | Fuente del dato |
|---|---|
| `00` | Dato guardado en ID/EX. |
| `01` | Resultado final seleccionado en WB. |
| `10` | Resultado de EX/MEM. |
| `11` | No utilizado. |

EX/MEM tiene prioridad porque contiene el resultado más reciente. Un LOAD en
EX/MEM todavía no puede aportar su dato: no se adelanta su dirección ni se usa
un valor más viejo de WB para ese mismo registro.

Forwarding ocurre antes de seleccionar cero/inmediato para la ALU. También
corrige el dato de STORE y los operandos de saltos. El bypass WB → ID del banco
cubre otro momento: WB escribe mientras ID lee. No agregamos EX/MEM → ID,
porque los operandos se consumen en EX.

### Stall y flush

Ante un LOAD válido en EX cuyo rd distinto de x0 es usado en ID, `hazard_unit`:

1. Congela PC e IF/ID.
2. Inserta una burbuja en ID/EX.
3. Permite avanzar las etapas posteriores.

Al ciclo siguiente el LOAD ya salió de EX; la consumidora puede avanzar y
recibir el dato desde WB. Es **un ciclo habilitado** con nuestra memoria de
lectura combinacional; cambiar esa latencia exigiría revisar el mecanismo.
La comparación incluye rs2 de STORE y omite campos que no son operandos reales.

Para un salto tomado en EX, permite actualizar PC y activa flush de IF/ID e
ID/EX. Hasta entonces se buscaba secuencialmente. El salto tiene prioridad
sobre LOAD-use en `hazard_unit`; `cpu.v` combina sus salidas con HALT y errores.

## 6. Pausa, reset, HALT y errores

El reloj nunca se corta con lógica. `step = i_enable && !o_halted` habilita el
avance de PC, pipeline, banco y escrituras de datos. Un pulso de enable ejecuta
**un ciclo**, no necesariamente una instrucción completa. En pausa tampoco se
aplica un flush pendiente; el reset sí actúa.

El reset global y el de CPU son distintos. El top actual forma
`cpu_rst = reset_global | cpu_reset_debug`, de modo que el comando de reset
de CPU no reinicia la UART.

| Acción | Qué se limpia o conserva |
|---|---|
| Configurar la FPGA | Programa en HALT y memoria de datos en cero. La CPU requiere reset para iniciar su estado. |
| Reset de CPU | PC=0, banco en cero, pipeline inválido, halting/halted/fault en cero. Conserva programa y datos. |
| Cargar otro programa | Solo se acepta carga con i_enable=0 y reset=0. El cargador limpia el resto del programa y luego resetea la CPU. Los datos se conservan. |

El cargador de debug completa con HALT las posiciones no utilizadas y fuerza
HALT en la palabra 255. Si llegan más de 256 palabras, consume las sobrantes
sin escribirlas. La memoria por sí sola no borra restos de programas anteriores:
en la de programa lo hace el CLEAR de `'L'`; la de datos los conserva.
Cada programa debe inicializar los datos que necesite.

### HALT

Al aceptar HALT en ID se detiene la búsqueda y se descartan las instrucciones
posteriores; las anteriores terminan. `halting` indica ese drenaje.
Cuando el marcador **llega** a WB (entra a MEM/WB) se activa `o_halted`:
`o_halted = wb_valid && wb_halt`. En ese flanco la instrucción
anterior al HALT ya escribió su resultado, y IF/ID, ID/EX y EX/MEM están vacíos;
MEM/WB conserva el marcador. Con 5 NOPs + HALT, `o_halted` vale 1 después de
exactamente **9 ciclos** habilitados, como pide el contrato. Como `o_halted`
anula el avance, MEM/WB queda congelado y la CPU permanece detenida hasta
reset. IF/ID vacío contiene NOP, no HALT.

El PC mostrado es el de búsqueda: al detenerse por HALT queda en **HALT+4**. Un salto tomado
en EX tiene prioridad sobre un HALT más joven en ID y lo descarta.
Sin HALT, el programa puede seguir indefinidamente si salta en un bucle; si
termina alcanzando una búsqueda fuera de memoria, se aplica la parada por error.

### Errores: parada sin traps

- Instrucción ilegal: se desactivan sus efectos y se envía un marcador de parada.
- Fetch fuera de rango o desalineado: se congela el avance secuencial del PC y
  se entrega `0xFFFFFFFF` a ID para reconocer una instrucción ilegal. Un salto
  válido de una instrucción anterior puede redirigir PC y descartar ese error.
- Acceso inválido en MEM: no escribe RAM ni rd, descarta instrucciones más
  jóvenes y permite completar la instrucción anterior en WB. Envía un marcador
  de parada hacia WB (con `illegal = 1`) y tiene prioridad sobre un salto más
  joven en EX. El PC conserva el valor de búsqueda que tenía al detectarse el error;
  no representa la dirección de datos inválida ni identifica por sí solo la
  instrucción que falló.

Las tres paradas por error activan **`o_fault`** junto con `o_halted`:
`o_fault = o_halted && wb_illegal`. La debug_unit lo informa en
el bit 2 del byte de estado: un HALT normal da 0x01 y un error 0x05. La causa
exacta (cuál de los tres errores) no se distingue. Esto no es un sistema de
excepciones RISC-V.

## 7. Contrato de la Debug Unit

`cpu.v` conserva los puertos del contrato de `cpu_stub`, sin su parámetro de
prueba INIT_NOPS. Debug lee combinacionalmente registros, datos, PC y pipeline.
El índice de memoria de debug sigue teniendo ocho bits por compatibilidad:
0…31 devuelven palabras y los demás índices devuelven cero. La memoria de
datos tiene 32 palabras también en el contrato.

| Grupo | Señales |
|---|---|
| Control | i_clk, i_cpu_reset, i_enable. |
| Carga | i_imem_we, i_imem_addr[7:0], i_imem_data[31:0]. |
| Registros | i_dbg_reg_addr[4:0], o_dbg_reg_data[31:0]. |
| Datos | i_dbg_mem_addr[7:0], o_dbg_mem_data[31:0]. |
| Estado | o_pc[31:0], o_halted, o_fault, o_latches[479:0]. |

El volcado es de **326 bytes**: cabecera (1), PC (4), ciclos (4), estado (1),
registros (128), pipeline (60) y datos (128).

`o_latches = {IF/ID, ID/EX, EX/MEM, MEM/WB}`, cada uno en palabras enteras:

| Bits | Contenido | Ancho | Palabras del volcado |
|---|---|---|---|
| 479:384 | IF/ID (65 bits reales + relleno) | 96 | 12–14 |
| 383:192 | ID/EX (163 + relleno) | 192 | 6–11 |
| 191:96 | EX/MEM (79 + relleno) | 96 | 3–5 |
| 95:0 | MEM/WB (74 + relleno) | 96 | 0–2 |

Dentro de cada bloque, los campos siguen el orden de sus salidas declaradas,
de mayor a menor peso; los de 32 bits ocupan una palabra propia y los chicos
se juntan en una palabra de control rellena con ceros. La tabla completa
(campo por campo, con sus bits) está en `src/params.vh`, sección 4b, y
`scripts/uart_test.py` la usa para mostrar cada campo con su nombre. No se
trunca información ni se crean registros adicionales para el volcado.

## 8. Debug Unit y comunicación

La `debug_unit` se divide en `control_fsmd` y `dump_mux`. El primero administra
comandos, carga, ejecución y contador de ciclos; el segundo selecciona cada
byte del volcado y las direcciones de lectura de debug. `debug_unit.v` es el
wrapper que los conecta.

### Protocolo UART

Se usa UART a **115200 baud, 8N1**, con protocolo pedido → respuesta.
La PC espera la respuesta antes de enviar otro comando, excepto `'I'` durante
una corrida. El buffer de recepción tiene un byte; la FSM consume los datos
mucho más rápido de lo que llegan por UART.

| Comando | Acción y respuesta |
|---|---|
| `'X'` | Resetea la CPU y el contador de ciclos; responde `'K'`. No reinicia la UART. |
| `'L'` | Recibe longitud y programa, completa la memoria según la sección 6, resetea la CPU y responde `'K'`. No inicia la ejecución. |
| `'D'` | Devuelve el volcado del estado actual. |
| `'S'` | Habilita un ciclo de CPU y devuelve el volcado posterior. Si ya estaba halted, responde sin avanzar ni sumar ciclos. |
| `'R'` | Ejecuta hasta HALT, error o interrupción; devuelve un volcado. |
| `'I'` | Interrumpe RUN. Fuera de RUN se descarta. |

Durante RUN se consumen todos los bytes, pero solo `'I'` interrumpe. Si HALT e
interrupción coinciden, gana HALT y se envía una sola respuesta. Interrumpir
pausa el pipeline sin vaciarlo; se puede continuar con `'R'` o `'S'`.

El byte de estado contiene `halted` en bit 0, `interrupted` en bit 1 y `fault`
en bit 2. `control_fsmd` lo arma. El indicador de interrupción se limpia al
resetear y al comenzar `'R'` o `'S'`; `'D'` no lo modifica.

### Carga del programa

Después de `'L'` llegan dos bytes de longitud y N palabras de cuatro bytes,
en little-endian: **3 + 4N bytes** contando el comando. Durante la carga ningún
byte se interpreta como comando, aunque coincida con su código ASCII.

La FSM arma una palabra a la vez y la escribe, sin almacenar una copia completa
del programa. Consume también las palabras que exceden la capacidad, para no
confundirlas con comandos. La regla de relleno y HALT final está en la sección 6.

No hay checksum ni timeout de carga en el hardware. Una carga cortada a mitad
se recupera con el botón de reset. `'K'` confirma que terminó el reset posterior
a la carga, no una verificación de integridad del programa.

### Control y volcado

- En STEP, `cpu_enable = 1` depende solo del estado (Moore). En RUN,
  `cpu_enable = !halted` depende también de una entrada (Mealy).
- `cpu_reset` depende del estado RESET. Las señales de transferencia dependen
  además de `rx_empty` y `tx_full`.
- El volcado se arma byte por byte, sin un buffer de 326 bytes. La CPU permanece
  pausada mientras se transmite, por lo que todo corresponde al mismo estado.
- El contador de ciclos tiene 32 bits y cuenta avances habilitados, no tiempo
  de espera ni transmisión. A 62,5 MHz se desborda aproximadamente a los 69 s
  de ejecución continua.
- Un volcado tarda aproximadamente 28 ms a 115200 baud. Un byte tarda unos
  87 µs, aproximadamente 5425 ciclos del reloj de 62,5 MHz.

`reset_gen` combina encendido, botón sincronizado y estado del reloj. TX inicia
en 1 para mantener la línea UART en reposo desde la configuración.

## 9. Ensamblador y verificación

`scripts/ensamblador.py` soporta las instrucciones de la CPU, HALT, etiquetas,
comentarios y las pseudoinstrucciones `nop`, `j`, `mv`, `li`, `beqz`, `bnez`,
`call` y `ret`. Estas se expanden a instrucciones reales; `li` puede ocupar
una o dos palabras. `.word` permite introducir una palabra cruda, útil para
probar instrucciones ilegales. Se aceptan las directivas `.text`, `.globl` y
`.option` ignorándolas. Las instrucciones no soportadas producen error.

El formato `.hex` contiene una palabra hexadecimal de 32 bits por línea.
`uart_test.py` permite cargar `.asm` o `.hex`, ejecutar y consultar volcados.
Su opción `--verificar` de carga solo sirve con `cpu_stub`: el puerto de debug
de la CPU real expone datos, no la memoria de programa.

Las pruebas combinan fuentes distintas para evitar depender de una sola:

| Herramienta | Propósito |
|---|---|
| `scripts/rv32i_model.py` | Modelo independiente de ejecución y tiempos; contrasta las anotaciones manuales `# ESPERADO:` y genera vectores. |
| `testbench/tb_cpu_isa.v` | Compara la CPU con el contrato y los vectores, ciclo a ciclo. |
| `testbench/tb_top_cpu.v` | Prueba carga, ejecución, pausa, reset y volcados mediante UART con la CPU real. |
| `scripts/run_all_tests.sh` | Ejecuta el conjunto de pruebas RTL. |
| `scripts/mutaciones.py` | Introduce fallos deliberados para comprobar que los tests los detecten. |
| `scripts/gui/tests/hdl/tb_captura.v` | Captura volcados del RTL para verificar la decodificación de la GUI. |
| `scripts/gui/tests/hdl/tb_traza.v` | Genera trazas para contrastar el simulador de pipeline con el RTL. |

El modelo permite verificar qué palabras modifica cada programa y conservar
las demás. Los programas deben inicializar los datos que necesitan; el reset
no borra la RAM. Esto es una elección de implementación, no una imposibilidad
de construir un mecanismo que la recorra escribiendo ceros.

Los ejemplos de GUI están en `scripts/gui/programas/`. Las demos de defensa
están en `scripts/programas/defensa/`, con pruebas en `test_demos_defensa.py`
y un [guion de defensa](guion_defensa.md). Separar estas carpetas evita que el
generador de vectores de integración procese programas que no le corresponden.

El caso `scripts/programas/NOPx256.asm` comprueba el límite de memoria:
al cargarlo quedan 255 NOPs y HALT en la palabra 255; termina normalmente en
259 ciclos. El cargador, el modelo y `PipelineSim` aplican esa misma regla.

### Módulos auxiliares

`cpu_if_id_test` permite estudiar IF/ID por separado. Expone PC, instrucción,
operandos, inmediato y controles, pero no ejecuta operaciones, saltos ni HALT,
y no escribe registros. Ante un PC inválido entrega NOP con valid=0 y señala
`o_if_addr_error`; ese comportamiento no sustituye al de la CPU completa.

`cpu_stub` es un procesador artificial para probar el protocolo. El top lo
selecciona solo con `USE_CPU_STUB = 1`; la placa usa la CPU real por defecto.
Sus registros y latches son artificiales, y su puerto de datos lee programa
para verificar la carga. `tb_top` usa este stub; `tb_top_cpu` usa la CPU real.

## 10. Depurador gráfico

La aplicación está en `scripts/gui/` y usa **PySide6 (Qt 6)** para tablas,
editor, señales y trabajo en segundo plano. Su entorno virtual está en
`scripts/gui/.venv`, ignorado en git. En Mint, el plugin `xcb` necesita
`libxcb-cursor0`. Manual: [manual_depurador.md](manual_depurador.md).

| Componente | Responsabilidad |
|---|---|
| `app/` | Ventana, editor, tablas, latches, log y tema. |
| `hilo_serie.py` | Trabajador en un `QThread`; centraliza los pedidos al enlace. |
| `protocolo.py` | Comandos, respuestas, timeouts e interrupción. |
| `transporte.py` | Transporte por puerto serie con pyserial. |
| `fpga_simulada.py` | Transporte simulado con el mismo protocolo, basado en `PipelineSim`. |
| `decodificador.py`, `campos_latches.py` | Interpretan los 326 bytes como campos con nombre. |
| `desensamblador.py` | Convierte palabras de instrucción en texto. |

La interfaz no accede directamente al puerto serie. Los pedidos se procesan
de a uno en el trabajador, para evitar respuestas mezcladas y bloqueos de la
ventana. Interrumpir activa un `threading.Event` que el enlace consulta mientras
espera la respuesta de RUN; al cerrar durante una corrida también se envía `'I'`.

El transporte intercambiable permite usar el mismo protocolo con placa o en
modo demo. La simulación reproduce registros, memoria, PC y los 480 bits del
pipeline. Para corridas largas usa una velocidad simulada de 2000 ciclos por
segundo tras una tanda inicial, con un límite de simulación; no reproduce la
velocidad física de la FPGA.

Los errores se muestran en la ventana y el log. Los fallos inesperados también
se registran en `~/.local/state/tp_riscv/depurador.log`. Un temporizador detecta
la desconexión del puerto cuando la aplicación está en reposo.

Las constantes del protocolo están duplicadas entre Python y `params.vh`,
pero `tests/test_constantes.py` verifica su coincidencia. No se lee `params.vh`
durante la ejecución de la aplicación.

## 11. Vista del pipeline

La GUI muestra cinco etapas, cuatro registros intermedios y el programa
resaltado. `pipeline_sim.py` simula ciclo a ciclo; `pipeline_view.py` deduce
las instrucciones e indicadores; `app/vista_pipeline.py` dibuja la vista.

Los tests comparan el simulador con el RTL en cada ciclo: los 480 bits de
latches, PC, halted, fault, registros y memoria. Incluyen dependencias, saltos,
errores de acceso, memoria precargada y HALT descartado por un salto.

### Identificación de instrucciones

IF/ID e ID/EX contienen PC; EX/MEM y MEM/WB no lo conservan. Por eso:

- Con volcados consecutivos, la vista sigue el avance: MEM recibe lo que
  estaba en EX, y WB lo que estaba en MEM, comprobando los bits `valid`.
- Sin esa continuidad, intenta reconstruir desde reset mediante simulación.
  Solo utiliza el resultado si coinciden el PC y los 480 bits del volcado,
  y si la instrucción corresponde a los controles del latch.
- Si falta información o hay discrepancias, muestra `?` y explica el motivo.
  No presenta una deducción incierta como si fuera un dato leído de la placa.

Los indicadores de forwarding, stall y flush reproducen las condiciones del
hardware, incluidas sus prioridades y los errores de memoria. El bypass WB → ID
se informa en la nota de ID. Los estados tienen texto e iconos además de color.

## 12. Reloj e implementación en FPGA

Todo el diseño funciona con **un reloj de 62,5 MHz**, generado desde la entrada
de 100 MHz por `clk_wiz_0` (MMCM). Se eligió esa frecuencia para cumplir timing
con margen y divisores enteros. El camino crítico combina forwarding, ALU y
decisión de salto; en la implementación documentada termina en el flush de ID/EX.

| Parámetro | Valor |
|---|---|
| Entrada | 100 MHz, pin W5 |
| Multiplicador / divisores M, D, O | 10 / 1 / 16 |
| Frecuencia VCO | 1000 MHz |
| Salida | 62,5 MHz, período de 16 ns |
| Jitter / error de fase | 144,481 ps / 98,575 ps |
| Divisor UART, sobremuestreo ×16 | 34 |
| Baud real / error | Aproximadamente 114890 / −0,27 % |

`i_clk` entra únicamente al Clocking Wizard. CPU, UART, debug y reset usan su
salida, evitando cruces entre dominios. Mientras `locked = 0`, `reset_gen`
mantiene el sistema en reset. El MMCM arranca al configurar la FPGA y no tiene
entrada de reset habilitada.

El IP declara el clock de entrada en su XDC. El `create_clock` de `top.xdc`
permanece comentado para no duplicarlo; solo corresponde habilitarlo al
sintetizar sin el MMCM. `CLK_FREQ` debe coincidir con el reloj real, porque
se usa para calcular el divisor UART.

Para Icarus Verilog se usa `USE_CLK_WIZ = 0`: el top conecta directamente
`i_clk` y fija `locked = 1`, sin elaborar el IP de Xilinx. Los testbenches con
reloj de 10 ns pasan explícitamente `CLK_FREQ = 100_000_000`. Algunos usan
1 Mbaud para acelerar la simulación; la placa usa 115200.

### Resultados documentados de implementación

Estos valores corresponden a la implementación registrada en el proyecto;
no se recalculan al editar este documento.

| Medida | Resultado |
|---|---|
| WNS / TNS | +0,802 ns / 0 ns |
| WHS / THS | +0,051 ns / 0 ns |
| WPWS | +3,000 ns |
| Camino crítico | `u_ex_mem/o_rd_reg[0]` → `u_id_ex/o_rs1_data_reg[13]` |
| Retardo / niveles de lógica | 14,494 ns / 17 |
| LUT | 2449 (11,8 %), 208 usadas como RAM distribuida |
| Flip-flops | 1629 (3,9 %) |
| Slices / Block RAM | 1148 / 0 |
| IOB / BUFG / MMCM | 12 / 2 / 1 |

La memoria de programa usa 176 LUT como memoria y la de datos 32.
El banco de registros usa 1024 flip-flops y 864 LUT; la debug_unit, 157 LUT y
118 flip-flops. La validación en placa se registra en
[CHECKLIST_placa.md](CHECKLIST_placa.md).

## 13. Convenciones y límites actuales

- Puertos con prefijos `i_` y `o_`; cables internos sin esos prefijos. Los
  wrappers mantienen los nombres de los puertos que conectan.
- Los módulos delimitan su código con `` `default_nettype none `` y
  `` `default_nettype wire `` para detectar señales sin declarar.
- Los errores detienen la CPU sin traps. `o_fault` informa que hubo un error,
  pero no diferencia su causa concreta.
- `params.vh` documenta el contrato; centralizar allí las constantes del RTL
  sigue pendiente.
- Un programa puede correr indefinidamente en un bucle aunque exista HALT al
  final de la memoria. El comando `'I'` permite pausarlo.
