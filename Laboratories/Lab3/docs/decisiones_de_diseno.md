# Decisiones de diseño — Trabajo Final (CPU + Debug Unit)

Actualizado: **10 de noviembre de 2026** (paso 4: integración del cpu real).

Este documento explica el diseño actual y sus motivos. Tiene tres partes:

- **Secciones 1 a 8 — CPU** (apartado A): `src/cpu/`.
- **Sección 9 — Debug Unit y comunicación** (apartado B): `src/debug_unit/`,
  con su historial y las decisiones 1 a 27 (antes en `CAMBIOS.md`).
- **Secciones 10 y 11 — Integración** (paso 4): el top usa el cpu real;
  decisiones 28 en adelante y respuestas a las preguntas de la consigna.

El contrato entre cpu y debug_unit está en `src/params.vh` (solo
documentación: ningún módulo lo incluye). La CPU completa está implementada en
`src/cpu/cpu.v` y conectada al top de placa (`src/debug_unit/top.v`). Falta
validarla en Vivado (timing y recursos) y en la FPGA (`CHECKLIST_placa.md`).

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
| Datos | 32 palabras de 32 bits: 128 bytes | CPU usa bytes 0…127; índice de palabra `addr[6:2]`. Lectura combinacional, escritura por bytes en el flanco. RAM: **el reset de CPU no la borra** (decisión 32). |
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
- Debug lee directamente el arreglo, sin bypass, pero **x0 se fuerza a 0**
  (contrato; decisión 30). Antes de la integración se mostraba `regs[0]`, que
  en simulación es desconocido hasta el primer reset.
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
| `if_id` | PC, instrucción completa, valid. | 65 (96 en el volcado) |
| `id_ex` | PC, rs1_data, rs2_data, inmediato, rs1/rs2/rd, funct3, bit 30; reg_write, alu_src_a/b, mem_read/write, result_src, branch, jump, jalr, ALUOp, halt, uses_rs1/2, illegal, valid. | 163 (192) |
| `ex_mem` | Resultado EX, dato STORE, rd, funct3; reg_write, mem_read/write, result_src, halt, illegal, valid. | 79 (96) |
| `mem_wb` | Resultado EX, dato leído de memoria, rd; reg_write, result_src, halt, illegal (también 1 si el error fue un acceso a memoria), valid. | 74 (96) |

En el volcado cada latch ocupa palabras enteras de 32 bits (decisión 34): la
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
`o_halted = wb_valid && wb_halt` (decisión 28). En ese flanco la instrucción
anterior al HALT ya escribió su resultado, y IF/ID, ID/EX y EX/MEM están vacíos;
MEM/WB conserva el marcador. Con 5 NOPs + HALT, `o_halted` vale 1 después de
exactamente **9 ciclos** habilitados, como pide el contrato. Como `o_halted`
anula el avance, MEM/WB queda congelado y la CPU permanece detenida hasta
reset. IF/ID vacío contiene NOP, no HALT.

El PC mostrado es el de búsqueda: al detenerse por HALT queda en **HALT+4**
(decisión 29). Un salto tomado
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
  joven en EX. El PC queda en la dirección del acceso + 12 (ya se habían
  buscado tres instrucciones más).

Las tres paradas por error activan **`o_fault`** junto con `o_halted`
(decisión 33): `o_fault = o_halted && wb_illegal`. La debug_unit lo informa en
el bit 2 del byte de estado: un HALT normal da 0x01 y un error 0x05. La causa
exacta (cuál de los tres errores) no se distingue. Esto no es un sistema de
excepciones RISC-V.

## 7. Contrato de la Debug Unit

`cpu.v` conserva los puertos del contrato de `cpu_stub`, sin su parámetro de
prueba INIT_NOPS. Debug lee combinacionalmente registros, datos, PC y pipeline.
El índice de memoria de debug sigue teniendo ocho bits por compatibilidad:
0…31 devuelven palabras y los demás índices devuelven cero. La memoria de
datos tiene 32 palabras también en el contrato (decisión 31).

| Grupo | Señales |
|---|---|
| Control | i_clk, i_cpu_reset, i_enable. |
| Carga | i_imem_we, i_imem_addr[7:0], i_imem_data[31:0]. |
| Registros | i_dbg_reg_addr[4:0], o_dbg_reg_data[31:0]. |
| Datos | i_dbg_mem_addr[7:0], o_dbg_mem_data[31:0]. |
| Estado | o_pc[31:0], o_halted, o_fault, o_latches[479:0]. |

El volcado es de **326 bytes**: cabecera (1), PC (4), ciclos (4), estado (1),
registros (128), pipeline (60) y datos (128). Hasta la integración era de 314
bytes con 48 de pipeline (decisión 34).

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

## 8. Pruebas auxiliares y trabajo pendiente

`cpu_if_id_test` se conserva para estudiar IF/ID por separado. Expone PC,
instrucción, operandos, inmediato y controles. No ejecuta operaciones, saltos
ni HALT, y no escribe el banco. Cada avance captura el PC anterior y suma 4.
Carga solo durante pausa y sin reset; reset conserva el programa. Ante PC
inválido congela PC, indica `o_if_addr_error` y entrega NOP con valid=0.
Ese comportamiento de prueba no reemplaza el de `cpu.v`.

`cpu_stub` ya no va en la placa: el top lo instancia solo con
`USE_CPU_STUB = 1`, que usa `tb_top` para probar el protocolo (decisión 35).
Sus registros y latches son artificiales y su puerto de datos lee programa
para comprobar la carga. La CPU real devuelve memoria de datos por ese puerto.

Estado de lo que quedaba pendiente:

1. ~~Reemplazar cpu_stub por cpu en el top~~: hecho; verificado en simulación
   con `tb_top_cpu` (carga, ejecución, pausa, interrupción, reset y volcado por
   UART) y `tb_cpu_isa`.
2. ~~Adaptar Python al mapa real de los latches~~: hecho, con 480 bits (se
   amplió el contrato, decisión 34). `--verificar` solo sirve con el stub.
3. Sintetizar y probar en placa: inferencia de memorias, recursos, timing y
   finalización de HALT (`CHECKLIST_placa.md`). **Pendiente.**
4. Revisar frecuencia y clk_wiz al final, como acordó el equipo. **Pendiente.**
5. Diagnóstico de errores: resuelto en parte con `o_fault` (decisión 33); la
   causa exacta no se distingue. Centralizar las constantes en params.vh sigue
   sin hacerse: hoy documenta el contrato, pero ningún módulo lo incluye.

Los archivos del proyecto final se agregarán manualmente en Vivado.

## 9. Debug Unit y comunicación (apartado B)

Esta sección reúne el historial y las decisiones del apartado B (antes en
`CAMBIOS.md`). Las rutas son las del repo: `src/debug_unit/` (antes `rtl/`),
`testbench/` (antes `sim/`), `scripts/` (antes `sw/`), `src/params.vh` (antes
`docs/params.vh`) y `docs/img/` (antes `docs/diagramas/`). Donde un número
cambió con la integración (314 → 326 bytes, etc.) se aclara entre corchetes.

### Historial

**Paso 1 — UART del TP2 adaptada + eco**

| Archivo | Origen | Cambios |
|---|---|---|
| `baud_rate_generator.v` | TP2 | Se agregó el `timescale` que faltaba. Baud por defecto 115200. **El divisor ahora se redondea** en lugar de truncarse |
| `rx_fsmd.v` | TP2 | Ninguno en la lógica |
| `tx_fsmd.v` | TP2 | **Valores iniciales** en los registros: la línea TX arranca en 1 sin apretar reset |
| `uart.v` | TP2 | Baud por defecto 115200 |
| `rx_intf.v`, `tx_intf.v`, `intf.v` | TP2 | Solo comentarios |
| `reset_gen.v` | Nuevo | Reset global: power-on, botón sincronizado y `locked` del clock |
| `echo_ctrl.v` | Nuevo, basado en `ALU_ctrl` | Controlador temporal de eco. **Reemplazado en el paso 3** (ya no está en el repo) |
| `top.v`, `constrains/top.xdc`, `tb_top.v` | Nuevos | `top` con eco y testbench con una segunda `uart` que hace de PC |

Además, todos los archivos llevan `` `default_nettype none `` al principio y
`` `default_nettype wire `` al final. Así, una señal sin declarar es un error
en lugar de un cable implícito de 1 bit.

**Paso 2 — `cpu_stub`**

| Archivo | Contenido |
|---|---|
| `cpu_stub.v` | Procesador falso con exactamente los puertos del contrato (`params.vh`, sección 4) |
| `tb_cpu_stub.v` | Maneja el contrato a mano, como lo hará la `debug_unit` |

**Paso 3 — `debug_unit`, comando `'X'`**

| Archivo | Contenido |
|---|---|
| `debug_unit.v` | **Wrapper** sin lógica propia (mismo criterio que `uart.v` e `intf.v`). Sus puertos son los definitivos: el `top` no cambia al agregar comandos |
| `control_fsmd.v` | FSM + registros: IDLE → RESET (1 ciclo con `o_cpu_reset`) → ACK (`'K'`). Ya incluye los registros `cycles` y `dump_idx` y arma el byte `status` |
| `dump_mux.v` | Combinacional y **completo**: dado `i_dump_idx` (0…313 [hoy 0…325]) devuelve `o_dump_byte` y pone las direcciones de lectura de debug |
| `top.v` | `echo_ctrl` reemplazado por `debug_unit` + `cpu_stub`. Reset del cpu: `cpu_rst = reset \| cpu_reset` |
| `tb_top.v` | Reescrito para probar `'X'` |
| `tb_dump_mux.v` | Arma el volcado esperado con código propio y lo compara byte por byte |
| `scripts/uart_test.py` | Prueba desde la PC con `pyserial` |

**Paso 3b — comando `'D'` (volcado)**

| Archivo | Cambio |
|---|---|
| `control_fsmd.v` | Estado **DUMP**. En IDLE, `'D'` pone `dump_idx = 0` y pasa a DUMP. En DUMP: `o_w_data = i_dump_byte` (Moore) y `o_wr = !i_tx_full` (Mealy). Con cada byte entregado, `dump_idx` avanza; después del último vuelve a IDLE |
| `tb_top.v` | Tres volcados verificados byte por byte contra un modelo propio del `cpu_stub`: recién reseteado, con PC/memoria/halted forzados, y después de `'X'`. Además verifica los LEDs durante el volcado y que `cpu_enable` no se active nunca |
| `scripts/uart_test.py` | Modo `d`: manda `'D'`, recibe el volcado, verifica la cabecera y muestra PC, ciclos, estado, registros, latches y memoria |

**Paso 3c — comando `'S'` (paso)**

| Archivo | Cambio |
|---|---|
| `control_fsmd.v` | Estado **STEP**. En IDLE, `'S'` → STEP. STEP dura 1 ciclo con `o_cpu_enable = 1` (Moore) y pasa siempre a DUMP con `dump_idx = 0`: el volcado muestra el estado **después** del paso |
| `cpu_stub.v` | Parámetro `INIT_NOPS` (por defecto 0): cantidad de NOPs con que arranca la memoria. Solo para pruebas |
| `top.v` | Parámetro `STUB_INIT_NOPS = 8`, pasado al `cpu_stub`: en la placa el PC avanzaba con `'S'` aunque todavía no existiera `'L'` |
| `tb_top.v` | Corre a **1 Mbaud solo en simulación** (parámetro del testbench). Ocho `'S'` hasta el HALT, verificando el volcado completo y exactamente 1 ciclo de `cpu_enable` por paso; después `'X'` y `'D'` |
| `scripts/uart_test.py` | Modos `s` (un paso + volcado) y `step` (interactivo: muestra solo lo que cambió entre pasos) |

**Paso 3d — comandos `'R'` (correr) e `'I'` (interrumpir)**

| Archivo | Cambio |
|---|---|
| `control_fsmd.v` | Estado **RUN**. En IDLE, `'R'` → RUN. En RUN, `o_cpu_enable = !i_halted` (**Mealy**) y `o_rd = !i_rx_empty` (todo byte se consume). Sale a DUMP con `dump_idx = 0` cuando `i_halted = 1` o cuando llega `'I'` (0x49). Nuevo registro **`interrupted`**: 1 si la corrida se cortó con `'I'`; vuelve a 0 con el reset global, con `'X'` y al empezar `'R'` o `'S'`. `o_status = {6'd0, interrupted, halted}` [hoy `{5'd0, fault, interrupted, halted}`, decisión 33] |
| `tb_top.v` | Pruebas 12 a 22: `'R'` hasta el HALT (mismo volcado que S7, exactamente 7 ciclos de enable), `'R'` ya detenido (0 ciclos), `'I'` fuera de RUN, programa sin HALT cortado con `'I'` (status 0x02, PC = 4 × ciclos, ciclos = ciclos de enable), otros bytes durante RUN ignorados, `'I'` en medio de un volcado, continuar con otro `'R'`, `'S'`/`'X'`/`'R'` borran el bit, y empate HALT/`'I'` (gana el HALT) |
| `scripts/uart_test.py` | Modo `r`: manda `'R'` y espera el volcado; Enter manda `'I'`. Ctrl+C también manda `'I'` para no dejar la placa en RUN. El decodificador muestra el bit `interrumpido` |
| `docs/img/debug_unit_fsm` | RUN con `cpu_enable = !halted`, flecha `'I'` → DUMP, lazo "otro byte" en RUN y borrado del bit en `'R'`, `'S'` y RESET |

**Paso 3e — comando `'L'` (cargar programa)**

| Archivo | Cambio |
|---|---|
| `control_fsmd.v` | Estados **LOAD_LEN**, **LOAD_WORD**, **WRITE** y el nuevo **CLEAR** (one-hot de 10 bits, código 9). Registros `n_words`, `idx`, `word` y `byte_cnt`. La palabra se arma con un desplazamiento a derecha (`word = {byte, word[31:8]}`: little-endian). WRITE escribe 1 ciclo con `imem_we`; CLEAR pone HALT en las palabras N..255; la 255 siempre es HALT; las palabras 256+ se consumen sin escribirse. Termina en RESET → ACK (`'K'`) |
| `tb_top.v` | Pruebas 22 a 29: carga de 3 palabras (memoria completa verificada, 1 reset, 0 enable, 256 escrituras), bytes de datos iguales a comandos, 5 NOPs + `'R'`, N = 0, N = 256 (palabra 255 forzada), N = 300 (sin vuelta a la palabra 0) y `imem_we` solo durante `'L'` |
| `scripts/uart_test.py` | Modo `l archivo.hex` (una palabra hex por línea, `#` = comentario): recorta a 256 palabras y avisa; espera `'K'`. `--verificar` compara con un `'D'` (solo con el stub) |
| `scripts/programas/` | Nuevo: `ejemplo_3.hex` y `nops_5.hex` |
| `src/params.vh` | Comportamiento de `'L'` y significado de `'K'` |
| `docs/img/debug_unit_fsm` | Estado CLEAR, flecha N = 0 y `idx` en lugar de `addr` |

### Decisiones del apartado B

1. **Baud rate 115200.** Un volcado de 314 bytes [hoy 326] tarda unos 27 ms [hoy 28 ms]; a 9600 baud tardaría 0,33 s. Con 100 MHz el divisor es 54, con un error de +0,47 % (el límite es de alrededor del 2 %).
2. **Redondeo del divisor.** Con truncamiento, algunos clocks dan un error de baud innecesariamente grande. Este cambio importa cuando se cambie la frecuencia con el `clk_wiz`.
3. **Valores iniciales en `tx_fsmd`.** Antes la línea TX quedaba en 0 hasta el primer reset. Eso es una condición de *break*, y la PC lee basura.
4. **`reset_gen`.** El sistema arranca en un estado conocido sin tocar el botón. Además ya tiene la entrada `i_locked`, preparada para el `clk_wiz`.
5. **Reset global vs. reset del procesador.** `reset` resetea todo, incluida la UART. `cpu_reset` (comando `'X'`) resetea solo el procesador, así la comunicación no se corta y la `debug_unit` puede responder `'K'`. En el `top` se combinan: `cpu_rst = reset | cpu_reset`.
6. **`cpu_stub` con la misma latencia de HALT que el pipeline real.** El PC se congela al ver el HALT y `o_halted` sube 3 ciclos habilitados después. Así la `debug_unit` no queda dependiendo de que `halted` llegue al instante. [Con la integración el cpu real se ajustó a esa misma cuenta: decisión 28.]
7. **Truco del stub: el puerto de debug de la memoria de datos lee la memoria de programa.** El contrato no permite leer la memoria de programa, y sin este truco no habría forma de verificar `'L'` hasta tener el `cpu` real. [Sigue valiendo para `tb_top`; con el cpu real `--verificar` no sirve.]
8. **`debug_unit` dividida en `control_fsmd` (secuencial) + `dump_mux` (combinacional).** Son dos cosas de naturaleza distinta, cada una se prueba por separado, y el código coincide con el diagrama.
9. **Protocolo pedido → respuesta.** El buffer de recepción es de un byte, así que la PC no manda un comando nuevo hasta recibir la respuesta del anterior. Los bytes que no son comando se consumen y se descartan sin respuesta.
10. **Salidas Moore para el control del cpu, Mealy para el handshake.** `cpu_reset` y `cpu_enable` dependen solo del estado y duran exactamente lo que dura el estado: por ejemplo, STEP dura 1 ciclo. `rd` y `wr` dependen de `rx_empty` y `tx_full` en el mismo ciclo, igual que en `ALU_ctrl`.
11. **`status` lo arma `control_fsmd`**, y no el `dump_mux` leyendo `halted` directo. Así, si se agregan banderas al byte de estado, se toca un solo módulo. [Así se agregó el bit de error: decisión 33.]
12. **El volcado se arma "al vuelo".** No hay un buffer de 314 bytes [hoy 326]: el `dump_mux` calcula cada byte en el momento en que se lo pide. Esto ahorra memoria, y como el procesador está congelado (`cpu_enable = 0`) durante el volcado, todos los bytes corresponden al mismo instante.
13. **`'S'` siempre responde con el volcado**, aunque el procesador esté detenido (en ese caso, sin cambios y sin sumar ciclos). Es la forma de ver cómo terminan las últimas instrucciones antes del HALT.
14. **`cpu_stub` con NOPs iniciales (`INIT_NOPS`)**: permitió probar `'S'` en la placa antes de tener `'L'`. Por defecto vale 0, así que `tb_cpu_stub` no cambia. [Con la integración el stub ya no va en la placa: `STUB_INIT_NOPS` solo se usa con `USE_CPU_STUB = 1`, en `tb_top`.]
15. **Testbench a 1 Mbaud.** Solo el testbench pasa `BAUD_RATE = 1_000_000`; el valor por defecto de todos los módulos sigue siendo 115200, validado en la placa. Los dos extremos de la simulación usan los mismos parámetros, así que la lógica probada es la misma, y cada volcado tarda ~3 ms simulados en lugar de 28 ms. [`tb_top_cpu` usa el mismo criterio.]
16. **`cpu_enable` en RUN es Mealy (`= !halted`).** Con una salida Moore, el ciclo en que `halted` sube el enable seguiría en 1, y el procesador tendría que ignorarlo. Con Mealy, la `debug_unit` no depende de ese comportamiento del cpu. El contador de ciclos queda exacto: un `'R'` hasta el HALT suma los mismos ciclos que los `'S'` equivalentes.
17. **Interrupción con un byte específico (`'I'`), no con cualquier byte.** Un byte de ruido o un comando mandado por error no corta la corrida. Durante RUN todo byte se lee (`rd`), así el buffer de 1 byte nunca queda ocupado y la `'I'` siempre puede entrar. Fuera de RUN, `'I'` no es comando y se descarta.
18. **Si `'I'` y `halted` llegan en el mismo ciclo, gana el HALT.** El programa terminó solo, y el volcado lo dice (status 0x01). En cualquier caso la PC recibe **un solo** volcado por cada `'R'`. Una `'I'` que llega tarde se ignora.
19. **Bit `interrupted` en el byte de estado (bit 1).** Distingue "terminó" (0x01) de "lo corté" (0x02) sin que la PC tenga que adivinar. `'D'` no lo cambia (muestra cómo quedó la última ejecución). `'R'`, `'S'` y `'X'` lo borran.
20. **`cycles` es de 32 bits.** A 100 MHz da la vuelta a los ~43 s de corrida continua. Para los programas del TP alcanza de sobra.
21. **En la `debug_unit` vive una sola palabra a la vez.** No hay buffer del programa: la palabra se arma en el registro `word` y se escribe apenas está completa. La PC manda todo seguido y el buffer de 1 byte alcanza, porque la FSM consume cada byte al ciclo siguiente y el próximo tarda ~8680 ciclos en llegar.
22. **Durante `'L'` ningún byte es comando.** La FSM consume siempre exactamente 3 + 4N bytes; un 0x58 dentro de una palabra es un dato. Por eso, aun con N > 256, se consumen todas las palabras: cortar antes haría que el resto se interprete como comandos.
23. **CLEAR: después de un `'L'` la memoria tiene exactamente el programa y el resto es HALT.** No quedan restos de programas anteriores, y un salto a memoria "vacía" se detiene. Cuesta como mucho 256 ciclos (2,6 µs). Con N = 0 la memoria queda toda en HALT (sirve como "borrar programa").
24. **La palabra 255 siempre es HALT.** Un programa que se pasa del final de la memoria termina. Si alguien manda 256 palabras o más, la que cae en la 255 se reemplaza por HALT y las siguientes se descartan: el error se atribuye al usuario, no rompe el sistema. El script además recorta a 256 y avisa. Esto no detiene un loop infinito (`j .`): para eso está `'I'`.
25. **Sin timeout en la carga.** Se asume que la PC y la UART funcionan; si una carga se cortara a la mitad, se recupera con el botón de reset.
26. **`'K'` confirma un reset terminado**, sea por `'X'` o al final de un `'L'` (los dos pasan por RESET → ACK). Sin checksum por ahora.
27. **Formato de programa: texto, una palabra hex de 32 bits por línea.** Es lo que lee `$readmemh` y lo que exporta RARS (*Dump Memory → Hexadecimal Text*); también es lo que genera el ensamblador (`scripts/ensamblador.py`, decisión 36).

### Convención de nombres

- **Puertos:** prefijo `i_` / `o_`.
- **Cables (`wire`):** sin prefijo. Ejemplo: `o_dump_idx` (control_fsmd) → cable `dump_idx` (debug_unit) → `i_dump_idx` (dump_mux).
- **Wrappers:** cada puerto se llama igual que el puerto interno al que se conecta.

### Nombres que cambiaron respecto del diseño de referencia del apartado B

(`02_modulos.md` del apartado B, que no está en este repo.)

- La "FSM de control" pasó a ser el módulo **`control_fsmd`**. La `debug_unit` es ahora un wrapper.
- Puertos de `dump_mux`: **`i_dump_idx`** y **`o_dump_byte`**.

## 10. Integración del cpu real (paso 4)

### Qué se hizo

| Archivo | Cambio |
|---|---|
| `src/debug_unit/top.v` | Parámetro **`USE_CPU_STUB`** (0 por defecto = cpu real en la placa) y un `generate` que instancia `cpu` o `cpu_stub` como `u_cpu`. Cables de 480 bits para los latches y `fault` |
| `src/cpu/cpu.v` | `o_halted = wb_valid && wb_halt` (9 ciclos), salida nueva `o_fault`, el fallo de memoria marca `illegal` en MEM/WB, latches de 480 bits alineados a palabras |
| `src/cpu/id/reg_file.v` | x0 forzado a 0 en el puerto de debug |
| `src/debug_unit/control_fsmd.v` | Entrada `i_fault`; `o_status = {5'd0, i_fault, interrupted, i_halted}`; `DUMP_LAST = 325` |
| `src/debug_unit/dump_mux.v` | Latches de 480 bits, `OFF_MEM = 198`, `DUMP_LEN = 326` |
| `src/debug_unit/debug_unit.v` | Puertos `i_latches[479:0]` e `i_fault` |
| `src/debug_unit/cpu_stub.v` | 15 palabras de latches, `o_fault = 0` |
| `src/params.vh` | Contrato: memoria de datos de 32 palabras (RAM, el reset no la borra), `o_fault`, PC = HALT + 4, x0, latencia del HALT, tabla de campos (4b), volcado de 326 bytes, bit 2 del estado |
| `scripts/ensamblador.py` | Nuevo: ensamblador mínimo (para reutilizar en la parte C) |
| `scripts/rv32i_model.py` | Nuevo: modelo de referencia; genera los `.hex` y los vectores de prueba |
| `scripts/programas/*.asm` | Nuevos: programas de ejemplo con el resultado esperado anotado (`# ESPERADO:`); los `.hex` se generan |
| `scripts/uart_test.py` | Volcado de 326 bytes, campos de los latches con nombre, estado con error, `l` acepta `.asm`, `--autoprueba` |
| `testbench/tb_cpu_isa.v` | Nuevo: cpu solo contra el contrato y contra el modelo, ciclo a ciclo |
| `testbench/tb_top_cpu.v` | Nuevo: top con el cpu real, por UART, contra el modelo |
| `testbench/vectores/` | Generado por `rv32i_model.py --generar` |
| `scripts/run_all_tests.sh`, `scripts/mutaciones.py` | Nuevos: todas las pruebas; pruebas de mutación |
| `tb_top.v`, `tb_dump_mux.v`, `tb_cpu_stub.v`, `tb_cpu.v` | Tamaños nuevos, `USE_CPU_STUB = 1` en `tb_top`, patrón final del HALT y `o_fault` en `tb_cpu` |

### Decisiones de la integración

28. **`o_halted` cuando el HALT llega a WB: 9 ciclos.** El cpu original esperaba a que el marcador *saliera* de WB (10 ciclos con 5 NOPs + HALT); el contrato y el stub cuentan 9. Se corrigió el cpu, no el contrato: `assign o_halted = wb_valid && wb_halt`. En ese flanco la última instrucción real ya escribió, y las etapas anteriores están vacías; MEM/WB conserva el marcador (`valid = halt = 1`), que es lo que muestra el volcado. Además se ahorra un flip-flop: como `o_halted` anula `step`, MEM/WB queda congelado y la salida se mantiene sola.
29. **PC al detenerse = dirección del HALT + 4.** El HALT se reconoce en ID, cuando IF ya buscó la instrucción siguiente. Mostrar la dirección del HALT obligaría a guardar otro valor solo para el volcado. Con el stub el PC quedaba en la dirección del HALT: los valores esperados de la placa cambiaron (`CHECKLIST_placa.md`).
30. **x0 por el puerto de debug vale siempre 0.** Lo pide el contrato. Antes el debug mostraba `regs[0]`, que en simulación es desconocido hasta el primer reset (en la placa el reset de encendido lo pone en 0).
31. **Memoria de datos de 32 palabras: se cambió el contrato, no el cpu.** El contrato decía 256 palabras, pero el volcado solo muestra 32, y la consigna pide enviar "la memoria de datos usada". Con 32 palabras toda la memoria es visible; un acceso fuera de ella detiene el cpu con error en lugar de escribir donde nadie lo ve. Además cuesta menos hardware y ya coincidía con el cpu y sus pruebas.
32. **El reset de CPU NO borra la memoria de datos: es RAM.** Se evaluó borrarla con `'X'` y `'L'` (igual que los registros) para que un mismo programa diera siempre el mismo resultado, y se descartó: la memoria de datos tiene que ser una RAM (distribuida, como la de programa), y una RAM no se borra con un reset. Si fuera un banco de flip-flops con reset, lo que muestra la debug_unit dejaría de corresponder teóricamente a una memoria. Consecuencias: la memoria conserva lo que dejó el programa anterior (y lo muestra el volcado); arranca en 0 solo al configurar la FPGA; **cada programa tiene que inicializar los datos que usa**. `rv32i_model.py --generar` lo verifica en los programas de ejemplo: si uno lee una palabra (o escribe solo una parte) sin haberla escrito antes con `sw`, da error. Los tests leen la memoria antes de correr y esperan que las palabras que el programa no escribe queden intactas.
33. **Salida `o_fault` y bit 2 del estado.** Antes un error terminaba con `o_halted = 1`, sin distinguirse de un HALT normal. Ahora `o_fault = 1` (junto con `o_halted`) cuando la parada fue por instrucción ilegal, fetch fuera de rango o desalineado, o acceso inválido a memoria; queda en 1 hasta el reset. `control_fsmd` lo pone en el bit 2 del estado: HALT = 0x01, error = 0x05, interrumpido = 0x02. Para un error de memoria, MEM/WB guarda `illegal = 1`, así `o_fault = o_halted && wb_illegal` cubre los tres casos sin registros nuevos. El stub siempre da 0.
34. **Latches de 480 bits (15 palabras), cada uno en palabras enteras.** 381 bits reales entraban en 384, pero los campos de 32 bits quedaban cortados entre palabras y el volcado era ilegible en hexadecimal. Con relleno, cada PC, dato o resultado ocupa una palabra propia y los controles se juntan en una palabra de control. El volcado pasa de 314 a 326 bytes (~1 ms más a 115200). La tabla de campos está en `params.vh` (4b) y en `uart_test.py`; `uart_test.py --autoprueba` verifica que sean iguales y `tb_cpu_isa` (A11) que el RTL las respete.
35. **`USE_CPU_STUB` con `generate`.** Es la forma más simple de que la placa use el cpu real y `tb_top` siga probando el protocolo con el stub, sin duplicar el top. Solo se sintetiza la rama elegida. Costo: en `tb_top` las rutas jerárquicas al stub pasan a ser `dut.g_stub.u_cpu.*`.
36. **Ensamblador propio** (`scripts/ensamblador.py`). Cubre las instrucciones de la consigna, `halt`, etiquetas, comentarios con `#` y solo dos pseudo-instrucciones (`nop`, `j`). Tiene además la directiva `.word` (para poder escribir una instrucción ilegal en las pruebas) e ignora `.text`, `.globl` y `.option`, para aceptar archivos del ensamblador de GNU. Se verifica contra codificaciones conocidas y contra el `.hex` de `programa_if_id.S`, generado con GNU as: las 39 palabras coinciden.
37. **Valores esperados de un modelo independiente** (`scripts/rv32i_model.py`). El modelo decodifica y ejecuta por su cuenta (sin usar el RTL) y calcula los tiempos del pipeline a partir de las reglas del diseño: ciclos = instrucciones + 4 + stalls + 2 por salto tomado; en qué ciclo escribe cada instrucción; PC después de cada ciclo; qué palabras de memoria escribe el programa (las demás conservan su valor, decisión 32). Además verifica las anotaciones `# ESPERADO:` escritas a mano en cada `.asm`. Así se cruzan tres fuentes: la cuenta a mano, el modelo y el RTL.
38. **Pruebas de mutación** (`scripts/mutaciones.py`). Se rompe el diseño a propósito, por ejemplo sin forwarding, sin stall, sin flush, enable ignorado, HALT tarde o signo mal extendido, y se verifica que algún test falle. Si una mutación sobrevive, falta un test.

## 11. Preguntas de la consigna

**Al reprogramar (comando `'L'`):**

| Pregunta | Respuesta | Por qué |
|---|---|---|
| ¿Es necesario vaciar la memoria (de datos)? | **No**: es RAM y el reset no la borra; conserva lo que dejó el programa anterior (se ve en el volcado). | Tiene que seguir siendo una RAM (decisión 32). Basta con que **cada programa inicialice los datos que usa**: así el resultado no depende de lo que había. El modelo lo verifica en los programas de ejemplo. |
| ¿Y los registros? | **Sí**: el reset de CPU que hace `'L'` (y `'X'`) los pone en 0. | El banco de registros es parte del estado del procesador (como el PC), no una memoria: el programa nuevo arranca con x1…x31 en 0 y no depende de valores del anterior. |
| ¿Se necesita vaciar el pipeline? | **Sí**: el reset deja los cuatro latches como burbujas (`valid = 0`, IF/ID con NOP) y el PC en 0. | Si no, instrucciones del programa viejo que estaban en IF/ID…MEM/WB terminarían de ejecutarse (escribirían registros o memoria) después de cargar el nuevo. |
| ¿Y la memoria de programa? | **No con el reset; sí con la carga**: el CLEAR de `'L'` escribe HALT en todas las palabras que el programa nuevo no usa (y la 255 siempre es HALT). | El reset no la borra para poder volver a correr el mismo programa con `'X'` (decisión 23). El CLEAR evita restos del programa anterior. |

**¿Qué sucede si en la memoria no hay una instrucción de parada?**

No puede pasar del todo: después de un `'L'` las palabras no usadas son HALT y
la 255 siempre es HALT (decisiones 23 y 24). Un programa que "se cae" del final
termina en el primer HALT de relleno. Lo que sí puede pasar:

- Un **loop sin fin** (por ejemplo `j .`): `'R'` corre para siempre; `'I'`
  lo corta y el volcado trae estado 0x02 (`scripts/programas/loop_infinito.asm`).
- Un salto **fuera de la memoria** de programa (≥ 1024) o a una dirección
  desalineada: el fetch entrega una instrucción ilegal y el cpu se detiene por
  error (estado 0x05).

En los dos modos (`'R'` y `'S'`) el pipeline queda vacío al terminar: cuando
`o_halted` sube, todas las instrucciones anteriores al HALT ya escribieron y
solo queda el marcador del HALT en MEM/WB.
