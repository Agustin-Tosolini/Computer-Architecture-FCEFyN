# Decisiones de diseño — CPU del TP3

Actualizado: **9 de noviembre de 2026**.

Este documento explica el diseño actual y sus motivos. La CPU completa está
implementada en `src/cpu/cpu.v`. Falta conectarla al top de placa, que todavía
usa `cpu_stub`, y validar esa integración en Vivado y en la FPGA.

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
| Datos | 32 palabras de 32 bits: 128 bytes | CPU usa bytes 0…127; índice de palabra `addr[6:2]`. Lectura combinacional, escritura por bytes en el flanco. |
| Banco de registros | 32 registros de 32 bits | Índices de 5 bits: x0…x31. Dos lecturas combinacionales y una escritura por flanco. |

**PC tiene 32 bits y cuenta bytes.** El avance normal es PC+4 porque cada
instrucción ocupa cuatro bytes. `pc_reg` solo almacena el próximo valor;
`cpu.v` calcula PC+4, selecciona saltos y comprueba rango y alineación.

Ambas memorias solicitan RAM distribuida con `(* ram_style = "distributed" *)`
para mantener las lecturas combinacionales. Su inferencia y uso de recursos
se comprobarán en Vivado. Al configurar la FPGA, programa inicia en HALT y
datos en cero. Esas inicializaciones no se repiten con el reset de CPU.

### Banco de registros y x0

- Las instrucciones leen x0 como cero y sus escrituras se descartan.
- El reset síncrono limpia los 32 registros, incluso durante pausa.
- Debug lee directamente el arreglo, incluido `regs[0]`, sin bypass. Fue una
  elección del equipo para inspeccionar el valor almacenado descrito en RTL.
  Antes del reset puede ser desconocido en simulación; la síntesis puede
  optimizar el almacenamiento de x0 por ser constante.
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
| `if_id` | PC, instrucción completa, valid. | 65 |
| `id_ex` | PC, rs1_data, rs2_data, inmediato, rs1/rs2/rd, funct3, bit 30; reg_write, alu_src_a/b, mem_read/write, result_src, branch, jump, jalr, ALUOp, halt, uses_rs1/2, illegal, valid. | 163 |
| `ex_mem` | Resultado EX, dato STORE, rd, funct3; reg_write, mem_read/write, result_src, halt, illegal, valid. | 79 |
| `mem_wb` | Resultado EX, dato leído de memoria, rd; reg_write, result_src, halt, illegal, valid. | 74 |

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
| Reset de CPU | PC=0, banco en cero, pipeline inválido, halting/halted en cero. Conserva programa y datos. |
| Cargar otro programa | Solo se acepta carga con i_enable=0 y reset=0. El cargador limpia el resto del programa y luego resetea la CPU. Los datos se conservan. |

El cargador de debug completa con HALT las posiciones no utilizadas y fuerza
HALT en la palabra 255. Si llegan más de 256 palabras, consume las sobrantes
sin escribirlas. La memoria por sí sola no borra restos de programas anteriores.
Cada programa debe inicializar los datos que necesite.

### HALT

Al aceptar HALT en ID se detiene la búsqueda y se descartan las instrucciones
posteriores; las anteriores terminan. `halting` indica ese drenaje.
Al retirar el marcador en WB se activa `o_halted`, con todo el pipeline inválido.
La CPU permanece detenida hasta reset. IF/ID vacío contiene NOP, no HALT.

El PC mostrado es el de búsqueda, habitualmente PC de HALT+4. Un salto tomado
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
  de parada hacia WB y tiene prioridad sobre un salto más joven en EX.

No se agrega un bit de error al protocolo: `o_halted` no distingue HALT normal
de parada por error. El diagnóstico persistente de la causa queda pendiente.
Esto no es un sistema de excepciones RISC-V.

## 7. Contrato de la Debug Unit

`cpu.v` conserva los puertos del contrato de `cpu_stub`, sin su parámetro de
prueba INIT_NOPS. Debug lee combinacionalmente registros, datos, PC y pipeline.
El índice de memoria de debug sigue teniendo ocho bits por compatibilidad:
0…31 devuelven palabras y los demás índices devuelven cero.

| Grupo | Señales |
|---|---|
| Control | i_clk, i_cpu_reset, i_enable. |
| Carga | i_imem_we, i_imem_addr[7:0], i_imem_data[31:0]. |
| Registros | i_dbg_reg_addr[4:0], o_dbg_reg_data[31:0]. |
| Datos | i_dbg_mem_addr[7:0], o_dbg_mem_data[31:0]. |
| Estado | o_pc[31:0], o_halted, o_latches[383:0]. |

El volcado sigue siendo de **314 bytes**: cabecera (1), PC (4), ciclos (4),
estado (1), registros (128), pipeline (48) y datos (128). No cambiamos su tamaño.

`o_latches = {3'b000, IF/ID, ID/EX, EX/MEM, MEM/WB}`:

| Bits | Contenido | Ancho |
|---|---|---|
| 383:381 | Relleno cero | 3 |
| 380:316 | IF/ID | 65 |
| 315:153 | ID/EX | 163 |
| 152:74 | EX/MEM | 79 |
| 73:0 | MEM/WB | 74 |

Son 381 bits reales más tres de relleno. Dentro de cada bloque, los campos
siguen el orden de sus salidas declaradas, de mayor a menor peso. No se
trunca información ni se crean registros adicionales para el volcado.
Se transmite primero el byte menos significativo; las 12 palabras mostradas
por el software son fragmentos del vector, no 12 registros independientes.

## 8. Pruebas auxiliares y trabajo pendiente

`cpu_if_id_test` se conserva para estudiar IF/ID por separado. Expone PC,
instrucción, operandos, inmediato y controles. No ejecuta operaciones, saltos
ni HALT, y no escribe el banco. Cada avance captura el PC anterior y suma 4.
Carga solo durante pausa y sin reset; reset conserva el programa. Ante PC
inválido congela PC, indica `o_if_addr_error` y entrega NOP con valid=0.
Ese comportamiento de prueba no reemplaza el de `cpu.v`.

`cpu_stub` sigue en el top de placa. Sus registros y latches son artificiales,
su temporización de HALT es aproximada y su puerto de datos lee programa para
comprobar la carga. La CPU real devuelve memoria de datos por ese puerto.

La implementación de los módulos y su conexión interna está completa.
Queda lo siguiente:

1. Reemplazar cpu_stub por cpu en el top y verificar carga, ejecución, pausa,
   interrupción, reset y volcado con UART/debug.
2. Adaptar la presentación de Python al mapa real de los 384 bits, sin ampliar
   el contrato. La verificación de carga basada en leer programa por el puerto
   de datos del stub no se puede trasladar directamente a la CPU real.
3. Sintetizar y probar en placa: inferencia de memorias, recursos, timing y
   finalización de HALT. Tener código implementado no reemplaza esas comprobaciones.
4. Revisar frecuencia y clk_wiz al final, como acordó el equipo.
5. Evaluar diagnóstico persistente de errores y si conviene centralizar las
   constantes en params.vh; hoy documenta el contrato, pero la CPU no lo incluye.

Los archivos del proyecto final se agregarán manualmente en Vivado.
