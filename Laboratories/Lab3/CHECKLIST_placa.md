# Checklist de pruebas en la placa (Basys 3) — cpu real

Prueba en la FPGA física del sistema completo con el **cpu real**: carga
(`'L'`), corrida (`'R'`), paso a paso (`'S'`), volcado (`'D'`), interrupción
(`'I'`), reset (`'X'`) y paradas por error.

Los valores esperados salen del modelo de referencia
(`scripts/rv32i_model.py`), los mismos que verifican `tb_cpu_isa` y
`tb_top_cpu` en simulación. **Los valores del cpu_stub ya no valen**: con el
cpu real el PC queda en HALT + 4, los registros y la memoria son reales, y
los ciclos incluyen stalls y saltos.

---

## 0. Preparación de la PC (una sola vez)

Todo se corre **parado en `Laboratories/Lab3`** (las rutas de los programas
son relativas). Cambiá la ruta por la tuya; no puede tener espacios.

```bash
cd ~/ruta/al/repo/Laboratories/Lab3
python3 -m venv scripts/.venv                  # si el .venv del repo no anda en tu PC
scripts/.venv/bin/pip install pyserial
```

Permiso para el puerto serie (si `groups | grep dialout` no muestra nada):

```bash
sudo usermod -aG dialout $USER      # después cerrar sesión y volver a entrar
```

Atajo `T` (usa el Python del entorno virtual, no hace falta activarlo):

```bash
LAB="$HOME/ruta/al/repo/Laboratories/Lab3"
echo "T=\"$LAB/scripts/.venv/bin/python $LAB/scripts/uart_test.py /dev/ttyUSB1\"" >> ~/.bashrc
source ~/.bashrc
```

Si la placa aparece en otro puerto:

```bash
sed -i 's|/dev/ttyUSB1"|/dev/ttyUSB0"|' ~/.bashrc && source ~/.bashrc
```

Antes de empezar, en la PC: `bash scripts/run_all_tests.sh --rapido` tiene
que terminar con `PASS: todas las pruebas` (los `.hex` quedan regenerados).

### Leer los LEDs

LD0–LD3 = código de estado de la FSM, LD4 = `halted` (HALT o error).

| Estado | LEDs prendidos |
|---|---|
| IDLE | ninguno |
| LOAD_LEN | LD0 |
| LOAD_WORD | LD1 |
| RUN | LD1 + LD2 |
| procesador detenido (`halted`) | LD4 |

DUMP (LD3) y CLEAR (LD0 + LD3) duran milisegundos o microsegundos: no se llegan a ver.

---

## A. Bitstream, timing y recursos

- [ ] Proyecto de Vivado con todos los `src/debug_unit/*.v` y `src/cpu/**/*.v`
      en *Design Sources* (incluido `cpu_stub.v`), los `testbench/*.v` solo en
      *Simulation Sources*. **No** agregar `src/params.vh`. Sin `echo_ctrl.v`.
- [ ] Módulo superior: `top` (`USE_CPU_STUB = 0`, el valor por defecto).
      Constraints: `constrains/top.xdc`.
- [ ] En *Hierarchy* aparece `top → g_cpu.u_cpu (cpu)`, no `cpu_stub`.
- [ ] *Generate Bitstream* sin errores.
- [ ] **Timing** con el cpu real: en *Design Runs* (fila `impl_1`), o en
      *Open Implemented Design → Report Timing Summary*:
  - [ ] **WNS ≥ 0** y TNS = 0 (setup)
  - [ ] **WHS ≥ 0** y THS = 0 (hold)
  - [ ] Mensaje "All user specified timing constraints are met."
  - Usar los números de **implementación**, no los de síntesis.
  - Los avisos `no_input_delay` / `no_output_delay` sobre `i_rx`, `i_reset`,
    `o_tx`, `o_leds` son normales (señales asincrónicas).
  - Si el WNS da negativo: anotar el camino crítico (*Timing → Intra-Clock
    Paths → sys_clk_pin → Setup*, doble clic en el primero). El sospechoso es
    EX: forwarding → ALU (resta) → decisión del salto → PC / flush. Se
    resuelve bajando la frecuencia con el `clk_wiz` o comparando `rs1 == rs2`
    sin pasar por la ALU.
- [ ] **Recursos** (*Report Utilization*, después de la implementación):
  - [ ] Memoria de programa (`instr_mem`, 256 × 32): **LUT as Distributed RAM**
        (del orden de 100–150 LUTs), no flip-flops.
  - [ ] Memoria de datos (`data_mem`, 32 × 32, escritura por bytes): también
        **LUT as Distributed RAM**, no ~1024 flip-flops. Es la que más riesgo
        tiene, por las escrituras de byte: revisar en el *Synthesis Log* que no
        diga "RAM ... implemented as registers" / "dissolved into registers".
        Si sale como flip-flops, la solución es escribirla como 4 memorias de
        32 × 8 (una por byte). El banco de registros sí es de flip-flops (~1024:
        tiene reset).
  - Anotar: LUTs, FFs, LUTRAM y BRAM totales (para el informe).
- [ ] FPGA programada: todos los LEDs apagados.
- [ ] picocom cerrado. `$T --list` muestra el puerto de la placa.

## B. Regresión

- [ ] `$T x` → `'X' -> 4B 'K'` y `'?' -> (nada)`

## C. Volcado `'D'` recién reseteado

- [ ] `$T x` y `$T d`:
  - [ ] PC = 0x00000000, ciclos = 0, estado = 0x00 (halted / interrumpido / error = 0 / 0 / 0)
  - [ ] Registros: todos 0x00000000 (x0 también)
  - [ ] Latches: los cuatro con `(burbuja: valid = 0)`; todos los campos en 0
        salvo `IF/ID instr=0x00000013` (NOP)
  - [ ] Memoria: con la FPGA recién programada, las 32 palabras en
        0x00000000. Después de correr programas NO vuelve a 0: el reset no
        borra la memoria de datos (es RAM)
  - [ ] "OK: volcado de 326 bytes con cabecera correcta"
- [ ] `$T d --raw` → empieza con `A5 00 00 00 00 00 00 00 00 00`

## D. Carga `'L'` + corrida `'R'` (cada programa)

Para cada fila: `$T l scripts/programas/<programa>.hex` (→ "OK: N palabras
cargadas" y `'K'`) y después `$T r`.

| Programa | Mensaje de `r` | Estado | Ciclos | PC | Para mirar en el volcado |
|---|---|---|---|---|---|
| `ejemplo_3` | Termino (HALT) | 0x01 | 6 | 0x0000000C | x1 = 5, x2 = 8 |
| `nops_5` | Termino (HALT) | 0x01 | 9 | 0x00000018 | todo en 0 |
| `sumas_encadenadas` | Termino (HALT) | 0x01 | 18 | 0x0000003C | x6 = 0xD, x7 = 0xD, x8 = 0xFFFFFFF4, x10 = 0xFFFFFFEC |
| `alu` | Termino (HALT) | 0x01 | 36 | 0x00000084 | x9 = 0xFFFFFFFF, x10 = 0xF0000000, x14 = 0, x22 = 0xFFFFF803, x31 = 0x7FFFFFFD |
| `memoria` | Termino (HALT) | 0x01 | 34 | 0x00000074 | x5 = 0xFFFFFFEF, x8 = 0xFFFF89AB, mem[0] = 0x01237AFF, mem[2] = 0xEF0000EF, mem[31] = 0xC7EEFFEF |
| `saltos` | Termino (HALT) | 0x01 | 28 | 0x00000058 | x4 = 0x38, x6 = 0x39, x7 = 0x4C, x8 = 0x4C, x10…x14 = 0 |
| `loop_bne` | Termino (HALT) | 0x01 | 63 | 0x00000030 | x2 = 0x37 (55), x4 = 0x38, mem[0] = 0x37, x6 = 0 |
| `error_ilegal` | Detenido por ERROR | **0x05** | 5 | 0x00000008 | x1 = 7, x2 = 0 |
| `error_lw` | Detenido por ERROR | **0x05** | 6 | 0x00000014 | x1 = 0x2A, x2 = 0, mem[31] = 0x2A |

La lista completa de registros distintos de 0 y de las palabras de memoria
que escribe cada programa está en la cabecera de su `.hex`. Las palabras que
el programa no escribe muestran lo que dejó el programa anterior (la memoria
de datos no se borra). Además, en cada programa:

- [ ] LD4 prendido al terminar (también con error).
- [ ] En un HALT normal, el volcado tiene `MEM/WB valid=1 halt=1 illegal=0`
      y los otros tres latches como burbujas (pipeline vacío).
- [ ] En un error, `MEM/WB illegal=1` y el estado dice `error = 1`.
- [ ] `$T r` otra vez (ya detenido) → mismo volcado, mismos ciclos.

## E. Paso a paso `'S'`

- [ ] `$T l scripts/programas/ejemplo_3.hex`, después `$T step`, y 7 veces Enter:

| Paso | PC | ciclos | Qué cambia | halted |
|---|---|---|---|---|
| 1 | 0x4 | 1 | IF/ID tiene `addi x1` (pc 0) | 0 |
| 2 | 0x8 | 2 | ID/EX tiene `addi x1` (rd = 1, imm = 5) | 0 |
| 3 | 0xC | 3 | EX/MEM.result = 5 (x1 todavía 0 en el banco: se va a adelantar), ID/EX tiene `addi x2` (rs1 = 1) | 0 |
| 4 | 0xC (se congela: HALT en ID) | 4 | EX/MEM.result = 8 | 0 |
| 5 | 0xC | 5 | **x1 = 5** (WB) | 0 |
| 6 | 0xC | 6 | **x2 = 8**, MEM/WB halt = 1 | **1** (se prende LD4) |
| 7 | — | 6 | "sin cambios" | 1 |

  - [ ] La secuencia coincide con la tabla. Salir con `q`.
- [ ] `$T l scripts/programas/nops_5.hex` y `$T step`: PC 0x4, 0x8, …, 0x18
      en los pasos 1 a 6; 0x18 fijo en los pasos 7, 8 y 9; `halted = 1`
      exactamente en el **paso 9**.
- [ ] `$T x` y `$T r` con `nops_5` ya cargado → PC = 0x18, ciclos = 9 (el
      programa sigue en memoria después del reset).

## F. Interrupción `'I'` (ya no hace falta otro bitstream)

- [ ] `$T l scripts/programas/loop_infinito.hex` y `$T r` → LD1 + LD2
      prendidos (RUN). Esperar ~2 s y Enter →
      `Interrumpido en PC = 0x00000008` (o 0x0C o 0x10) `después de N ciclos`,
      estado 0x02, **x1 = 3, mem[2] = 3**. N ≈ 100 millones por segundo.
- [ ] `$T d` → estado sigue en 0x02
- [ ] `$T s` → estado 0x00, ciclos + 1
- [ ] `$T r` + Enter otra vez → los ciclos siguen subiendo desde donde quedaron
- [ ] Otros bytes durante RUN: en picocom escribir `R` (LD1 + LD2), después
      `D`, `S`, `X` → no pasa nada; escribir `I` → llegan caracteres raros
      (el volcado) y los LEDs se apagan
- [ ] `$T r` y Ctrl+C → "Cancelado: se mando 'I'…", LEDs apagados

## G. Reprogramación (se borran los registros; la memoria de datos se conserva)

- [ ] `$T l scripts/programas/memoria.hex`, `$T r` → mem[0] = 0x01237AFF, etc.
- [ ] `$T x` y `$T d` → **registros en 0**, PC = 0, estado 0x00, y la
      **memoria igual que antes** (mem[0] = 0x01237AFF…): el reset no borra la RAM
- [ ] `$T r` → otra vez el mismo resultado que la primera corrida (ciclos = 34):
      el programa inicializa los datos que usa
- [ ] `$T l scripts/programas/nops_5.hex` y `$T d` → registros en 0 y la
      memoria **todavía** con los datos de `memoria`; `$T r` → PC = 0x18,
      ciclos = 9, memoria sin cambios

## H. Casos borde de `'L'`

- [ ] Programa vacío (N = 0):
  ```bash
  echo "# vacio" > /tmp/vacio.hex
  $T l /tmp/vacio.hex
  $T r
  ```
  → estado 0x01, PC = **0x4**, ciclos = **4** (HALT en la palabra 0)
- [ ] Datos que parecen comandos:
  ```bash
  printf '58525349\n4C444B49\n00000000\n' > /tmp/comandos.hex
  $T l /tmp/comandos.hex
  $T r
  ```
  → una sola 'K'; después **estado 0x05** (0x58525349 no es una instrucción
  válida: error), PC = 0x4, ciclos = 4
- [ ] Más de 256 palabras:
  ```bash
  python3 -c "print('\n'.join(['00000013']*300))" > /tmp/grande.hex
  $T l /tmp/grande.hex
  $T r
  ```
  → los dos AVISOS (recorta a 256; la 255 pasa a HALT); después estado 0x01,
  PC = **0x400**, ciclos = **259** (255 NOPs + 4)
- [ ] `--verificar` ya **no** sirve (era un truco del stub): con el cpu real
      el `'D'` muestra la memoria de datos.

## I. Botón de reset (btnC)

- [ ] `$T l scripts/programas/ejemplo_3.hex`, `$T r`, apretar btnC, `$T d` →
      PC, ciclos, estado y registros en 0 (el reset global también resetea el
      cpu), memoria de datos sin cambios; `$T r` → otra vez x1 = 5, x2 = 8,
      ciclos = 6 (el botón no borra la memoria de programa)
- [ ] Recuperar una carga trabada:
  1. `picocom -b 115200 /dev/ttyUSB1` y escribir solo `L` → se prende LD0 (esperando N)
  2. Apretar btnC → LEDs apagados
  3. Salir de picocom (Ctrl+A, Ctrl+X) y `$T x` → 'K'

---

## Si algo no coincide

Anotar el ítem, copiar la salida completa del script (con `--raw` si es un
volcado) y el estado de los LEDs. Para comparar con la simulación:
`python3 scripts/rv32i_model.py scripts/programas/<programa>.asm`.

## Notas para interpretar los resultados

1. **PC al terminar = dirección del HALT + 4**: el HALT se detecta en ID,
   cuando IF ya buscó la siguiente. En un error de memoria el PC queda en la
   dirección del load/store + 12.
2. **Ciclos = instrucciones ejecutadas + 4 + stalls + 2 × saltos tomados.**
   Un stall aparece cuando una instrucción usa el registro que cargó el load
   inmediatamente anterior.
3. **`halted` sube cuando el HALT llega a WB**: en ese momento IF/ID, ID/EX y
   EX/MEM ya están vacíos y MEM/WB tiene el marcador del HALT.
4. **La memoria de datos tiene 128 bytes** (32 palabras, toda visible en el
   volcado). Un acceso fuera de 0..127 o desalineado detiene con error.
5. El reset (`'X'`, `'L'` o btnC) borra registros y pipeline; **no** borra
   las memorias (son RAM). La de programa la limpia el CLEAR de `'L'`; la de
   datos conserva lo del programa anterior: cada programa inicializa lo que usa.
6. `cycles` es de 32 bits: da la vuelta a los ~43 s de corrida continua.
   El PC no cuenta ciclos con el cpu real (no vale "PC = 4 · N").
7. Sin timeout en `'L'`: una carga cortada se recupera con el botón (bloque I).
