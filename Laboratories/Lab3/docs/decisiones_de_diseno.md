# Decisiones de diseño — CPU del TP3

Documento de trabajo para registrar qué elegimos, por qué y qué consecuencias
tiene. Se actualiza al implementar o revisar cada módulo; también servirá como
base para el informe final.

Última actualización: 2026-10-27.

**Estados:** implementado significa que existe el código; no implica que haya
pasado simulación o pruebas en placa. Acordado significa que es la dirección
elegida, pero todavía falta implementarla. Provisional requiere una definición
antes de integrar los bloques.

## 1. Organización e integración

| Decisión | Motivo y consecuencias | Estado |
|---|---|---|
| Agrupar los módulos de la CPU en `src/cpu/`. | Separa el trabajo del procesador del de comunicación y debug. Las carpetas no determinan la jerarquía del hardware: la determinan las instancias. | Implementado |
| Mantener `cpu_stub` disponible para desarrollar la Debug Unit. | Permite que ambos integrantes trabajen por separado. Sus datos artificiales y su temporización no son una referencia exacta del pipeline real. | Implementado en la infraestructura existente |
| Mantener un contrato explícito entre CPU y Debug Unit. | La CPU expone habilitación, reset, carga de instrucciones, lecturas de debug, PC, estado del pipeline y `halted`. La integración deberá respetar ese contrato. | Contrato existente en `src/params.vh`; CPU real pendiente |

## 2. ALU (`src/cpu/alu.v`)

| Decisión | Motivo y consecuencias | Estado |
|---|---|---|
| Operandos y resultado de 32 bits, con ancho fijo. | Corresponde al tamaño de datos de RV32. Sustituye el ancho parametrizable de la ALU del TP2. | Implementado |
| ALU combinacional, sin reloj ni almacenamiento propio. | Los registros del pipeline se encargan de guardar los resultados. | Implementado |
| Operaciones ADD, SUB, SLL, SRL, SRA, SLT, SLTU, XOR, OR y AND. | Cubre los cálculos necesarios para el subconjunto de instrucciones solicitado. Una misma operación puede servir a varias instrucciones. Se elimina NOR del TP2. | Implementado |
| Código interno `i_op` de cuatro bits. | No es el opcode RISC-V de siete bits. `alu_control` deberá traducir los campos de instrucción a esta selección. | ALU implementada; control pendiente |
| Usar `i_b[4:0]` como cantidad de desplazamiento. | Los desplazamientos RV32 consideran cinco bits: de 0 a 31 posiciones. | Implementado |
| Comparación explícita con signo en SLT y desplazamiento con signo en SRA. | Los mismos bits pueden tener distinta interpretación. SLTU y SRL usan la interpretación sin signo. | Implementado |
| Eliminar carry y overflow; conservar `o_zero`. | No exponemos flags aritméticos arquitectónicos. `zero` es una señal interna útil para comparar mediante resta en los saltos. Suma y resta conservan los 32 bits inferiores. | Implementado |

Codificación interna:

| Operación | Código |
|---|---|
| ADD | `0000` |
| SUB | `1000` |
| SLL | `0001` |
| SLT | `0010` |
| SLTU | `0011` |
| XOR | `0100` |
| SRL | `0101` |
| SRA | `1101` |
| OR | `0110` |
| AND | `0111` |

Un código interno no reconocido devuelve cero. Esto no sustituye la validación
de instrucciones que deberá realizar la lógica de control.

## 3. Banco de registros (`src/cpu/reg_file.v`)

| Decisión | Motivo y consecuencias | Estado |
|---|---|---|
| Arreglo de 32 registros de 32 bits. | Representa `x0` a `x31`. Los números de registro tienen cinco bits. | Implementado |
| Dos puertos de lectura combinacionales para ID. | Permiten obtener ambos operandos durante el mismo ciclo, sin esperar otro flanco. | Implementado |
| Un puerto de escritura en flanco ascendente. | WB actualiza un registro cuando la CPU está habilitada y la instrucción solicita escribir. | Implementado |
| Reset síncrono que limpia todo el banco y tiene prioridad sobre `i_enable`. | Permite reiniciar la CPU estando pausada y obtener un estado reproducible. No hay inicialización del arreglo independiente del reset. | Implementado |
| Bloquear escrituras dirigidas a `x0`. | Cumple la semántica de RISC-V. | Implementado |
| Forzar cero al leer `x0` por los puertos de operandos. | La ejecución siempre observa cero, sin depender del contenido del arreglo. | Implementado |
| Lectura de debug directa del arreglo, incluida `regs[0]`, sin bypass. | Permite inspeccionar el contenido descrito en RTL sin reemplazarlo por cero. Antes del reset puede aparecer desconocido en simulación; después del reset `regs[0]` queda en cero y sus escrituras están bloqueadas. La síntesis puede optimizar su almacenamiento constante. | Implementado por elección explícita del equipo |
| Forwarding WB → ID dentro del banco, también llamado bypass. | Si WB escribe el registro que ID lee, se entrega `i_wdata` antes del flanco. Evita que ID/EX capture el valor viejo justo cuando WB actualiza el banco. | Implementado para ambos operandos |
| Usar la misma condición para escritura y bypass. | `i_enable && i_we && !i_reset && (i_rd != 0)`. Evita adelantar una escritura que no está habilitada. | Implementado |

El forwarding del banco no cambia el almacenamiento antes del flanco. Por eso,
antes de una escritura, una lectura de operandos puede mostrar el dato nuevo
mientras debug todavía muestra el dato anterior.

## Generador de inmediatos (`src/cpu/imm_gen.v`)

| Decisión | Motivo y consecuencias | Estado |
|---|---|---|
| Módulo combinacional con instrucción de 32 bits como entrada e inmediato de 32 bits como salida. | No requiere reloj; su resultado se almacenará en ID/EX. | Implementado |
| Seleccionar el formato por opcode: I para OP-IMM, LOAD y JALR; S para STORE; B para BRANCH; U para LUI; J para JAL. | Reconstruye los campos sin decodificar la operación completa. La validación corresponde al control. AUIPC no forma parte del subconjunto elegido. | Implementado |
| Extender signo en I, S, B y J; completar U con 12 ceros inferiores. | Conserva constantes y desplazamientos negativos. | Implementado |
| Entregar los desplazamientos B y J en bytes, incluyendo su cero inferior implícito. | La lógica de destino debe sumar el inmediato al PC sin desplazarlo nuevamente. | Implementado |
| Para shifts inmediatos, conservar el formato I y usar cinco bits en la ALU. | `alu_control` distingue SRLI/SRAI usando los campos de la instrucción. | Generador implementado; control pendiente |
| Devolver cero para opcodes restantes. | Cubre instrucciones sin inmediato y valores no soportados; no constituye una señal de validez. | Implementado |

## 4. Pipeline y resolución de riesgos

Estas decisiones están acordadas conceptualmente; aún no representan módulos
de pipeline implementados.

| Decisión | Motivo y consecuencias | Estado |
|---|---|---|
| Pipeline de cinco etapas: IF, ID, EX, MEM y WB. | Separa búsqueda, decodificación, cálculo, acceso a datos y escritura de resultados. | Acordado |
| Cuatro grupos de registros: IF/ID, ID/EX, EX/MEM y MEM/WB. | Cada grupo tiene una estructura fija que incluye los datos y controles necesarios para las distintas instrucciones. No se crea un registro diferente por tipo de instrucción. | Acordado; campos y tamaños pendientes |
| Implementar los registros de pipeline con flip-flops por flanco. | La consigna los llama latches, pero no se pretende inferir latches sensibles a nivel. | Acordado |
| Forwarding hacia EX desde EX/MEM y MEM/WB. | Permite usar resultados pendientes sin esperar su escritura en el banco. Se selecciona cada operando por separado y se prioriza EX/MEM cuando hay coincidencias válidas en ambos orígenes. Nunca se adelantan escrituras a x0. | Acordado |
| Mantener también el forwarding WB → ID del banco. | Cubre el caso en que la productora está en WB mientras la consumidora está en ID: al ciclo siguiente, la productora ya no estará disponible en MEM/WB. | Implementado en el banco; integración pendiente |
| No agregar forwarding directo EX/MEM → ID. | Los operandos del diseño propuesto se utilizan en EX, donde pueden corregirse. Habría que reconsiderarlo si se resolvieran saltos en ID. | Acordado |
| Stall de un ciclo para una carga seguida inmediatamente por una instrucción que usa su resultado. | Con la memoria propuesta, el dato de load se obtiene en MEM. Se congelan PC e IF/ID, se introduce una burbuja en ID/EX y se deja avanzar la carga; luego se usa forwarding desde MEM/WB. Otra latencia de memoria exigiría revisar esta decisión. | Acordado |
| Resolver los saltos en EX y continuar buscando secuencialmente mientras tanto. | Simplifica la resolución con los operandos adelantados de EX. Si el salto se toma, se redirige el PC y se invalidan las instrucciones posteriores de IF e ID. | Acordado |
| Representar burbujas con instrucciones inválidas y controles sin efectos. | Evita escrituras de registros o memoria provenientes de instrucciones descartadas. Los registros se reutilizan al avanzar el pipeline. | Acordado |

## 5. Control de ejecución y parada

| Decisión | Motivo y consecuencias | Estado |
|---|---|---|
| Usar `enable` para detener o avanzar la CPU; no cortar el reloj con lógica. | Permite ejecutar un ciclo por comando sin detener UART ni Debug Unit. Debe controlar todos los cambios de estado relevantes de la CPU. | Implementado en el banco; integración pendiente |
| Distinguir reset global de reset de CPU. | Reiniciar el procesador no debe interrumpir la UART. | Acordado para la integración |
| HALT propio codificado como `0x00000000`; NOP como `0x00000013`. | Son valores definidos en el contrato existente. Una burbuja no debe confundirse con HALT; su validez y controles deben respetarse. | Acordado; CPU pendiente |
| Detener la admisión de instrucciones al aceptar HALT, y dejar drenar el pipeline. | Las instrucciones anteriores deben terminar antes de indicar `halted`. Se distingue entre estar terminando (`halting`) y haber terminado (`halted`). | Acordado |
| Dar prioridad a un salto tomado en EX sobre un HALT posterior en ID. | Ese HALT pertenece al camino descartado y no debe detener la ejecución. | Acordado |

## 6. Puntos pendientes de cerrar

- Definir campos, anchos y orden exacto del vector de debug de los registros del
  pipeline. Los 384 bits de `params.vh` son provisionales; actualizar también el
  formato del volcado y el software si cambian.
- Confirmar al implementar las memorias la propuesta de 256 palabras de 32 bits
  por memoria, lectura asíncrona y memorias de programa y datos separadas.
- Precisar tratamiento de direcciones fuera de rango, accesos desalineados e
  instrucciones no soportadas.
- Definir qué se conserva o limpia en memoria al resetear y reprogramar.
- Precisar el ciclo de finalización de HALT y el PC visible al detenerse; no
  adoptar automáticamente la temporización simplificada de `cpu_stub`.
- Definir si se centralizan las constantes en `params.vh`: actualmente ese
  archivo documenta el contrato, pero los módulos no lo incluyen.

## 7. Estado de verificación

- ALU: implementada; simulación pendiente.
- Generador de inmediatos: implementado; simulación pendiente.
- Banco de registros: implementado; existe `testbench/tb_reg_file.v` con casos
  de reset, escritura, x0, lecturas, bypass, pausa y debug. Simulación pendiente.
- En las revisiones realizadas no se encontraron `iverilog` ni `verilator` en
  el PATH. Las revisiones estáticas no sustituyen la simulación, síntesis ni
  comprobación de timing en Vivado.

Al actualizar este documento, registrar los resultados de pruebas efectivamente
ejecutadas y revisar las decisiones afectadas por cualquier cambio de interfaz.
