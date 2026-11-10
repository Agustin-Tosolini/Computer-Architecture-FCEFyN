# Checklist de pruebas en la placa (Basys 3)

Prueba en la FPGA física de todo lo que hasta ahora solo se validó en
simulación: `'D'`, `'S'`, `'R'`, `'I'` y `'L'`. En la placa solo estaban
probados el eco y `'X'`.

Los valores esperados salen del modelo del `cpu_stub` (los mismos que verifica
`tb_top`). **Solo valen con el stub**: con el cpu real cambian (ver
"Limitaciones del stub" al final).

---

## 0. Preparación de la PC (una sola vez)

Desde la raíz del proyecto (la carpeta que tiene `rtl/`, `sim/`, `sw/`). Cambiá
la ruta por la tuya; no puede tener espacios.

```bash
cd ~/Documentos/TP_final_apartado_B
sudo apt install python3-venv
python3 -m venv .venv
.venv/bin/pip install pyserial
echo "pyserial>=3.5" > sw/requirements.txt
printf '.venv/\n__pycache__/\n' >> .gitignore
```

Permiso para el puerto serie (si `groups | grep dialout` no muestra nada):

```bash
sudo usermod -aG dialout $USER      # después cerrar sesión y volver a entrar
```

Atajo `T`, fijo en todas las terminales (usa el Python del entorno virtual,
no hace falta activarlo):

```bash
echo 'T="$HOME/Documentos/TP_final_apartado_B/.venv/bin/python $HOME/Documentos/TP_final_apartado_B/sw/uart_test.py /dev/ttyUSB1"' >> ~/.bashrc
source ~/.bashrc
```

Si la placa aparece en otro puerto:

```bash
sed -i 's|/dev/ttyUSB1"|/dev/ttyUSB0"|' ~/.bashrc && source ~/.bashrc
```

Correr la checklist **parado en la raíz del proyecto**: las rutas de los `.hex`
son relativas.

### Leer los LEDs

LD0–LD3 = código de estado de la FSM, LD4 = `halted`.

| Estado | LEDs prendidos |
|---|---|
| IDLE | ninguno |
| LOAD_LEN | LD0 |
| LOAD_WORD | LD1 |
| RUN | LD1 + LD2 |
| procesador detenido (`halted`) | LD4 |

DUMP (LD3) y CLEAR (LD0 + LD3) duran milisegundos o microsegundos: no se llegan a ver.

---

## A. Bitstream y timing

- [ ] Proyecto de Vivado con todos los `rtl/*.v` en *Design Sources* y los
      `sim/*.v` solo en *Simulation Sources*. Sin `echo_ctrl.v`.
- [ ] Módulo superior: `top`. Constraints: `constraints/top.xdc`.
- [ ] *Generate Bitstream* sin errores.
- [ ] **Timing**: en la pestaña *Design Runs* (fila `impl_1`), o en *Project
      Summary → Timing*, o en *Flow Navigator → IMPLEMENTATION → Open
      Implemented Design → Report Timing Summary*:
  - [ ] **WNS ≥ 0** y TNS = 0 (setup)
  - [ ] **WHS ≥ 0** y THS = 0 (hold)
  - [ ] Mensaje "All user specified timing constraints are met."
  - Usar los números de **implementación**, no los de síntesis.
  - Los avisos `no_input_delay` / `no_output_delay` en *Check Timing* sobre
    `i_rx`, `i_reset`, `o_tx`, `o_leds` son normales (señales asincrónicas).
  - Si el WNS da negativo: anotar el camino crítico (*Timing → Intra-Clock
    Paths → sys_clk_pin → Setup*, doble clic en el primero).
- [ ] FPGA programada: todos los LEDs apagados.
- [ ] picocom cerrado. `$T --list` muestra el puerto de la placa.

## B. Regresión: lo que ya estaba probado

- [ ] `$T x` → `'X' -> 4B 'K'` y `'?' -> (nada)`

## C. Volcado `'D'`

- [ ] `$T x` y después `$T d`:
  - [ ] PC = 0x00000000, ciclos = 0, estado = 0x00
  - [ ] Registros: x0 = 0, xN = 0x0000000N (x1 = 0x00000001 … x31 = 0x0000001F)
  - [ ] Latches: 0xA0000000, 0xA1000000, … 0xAB000000
  - [ ] Memoria: palabras 0–7 = 0x00000013 (NOPs iniciales), 8–31 = 0x00000000
  - [ ] "OK: volcado de 314 bytes con cabecera correcta"
- [ ] `$T d --raw` → empieza con `A5 00 00 00 00 00 00 00 00 00`

## D. Paso a paso `'S'`

- [ ] `$T x` y `$T s` → PC = 0x4, ciclos = 1, estado 0x00,
      x1 = 0x00040001, latch [0] = 0xA0000004
- [ ] `$T step`: escribir `x` + Enter (reset) y después 13 veces Enter:

| Paso | PC | ciclos | halted |
|---|---|---|---|
| 1 … 8 | 0x4 … 0x20 | 1 … 8 | 0 |
| 9 | 0x20 (se congela) | 9 | 0 |
| 10, 11 | 0x20 | 10, 11 | 0 |
| 12 | 0x20 | 12 | **1** (se prende LD4) |
| 13 | "sin cambios" | 12 | 1 |

  - [ ] La secuencia coincide con la tabla. Salir con `q`.

## E. Corrida `'R'` (termina sola)

- [ ] `$T x` y `$T r` → `Termino (HALT) en PC = 0x00000020, ciclos = 12`,
      estado 0x01, LD4 prendido
- [ ] `$T r` otra vez (ya detenido) → mismo resultado, ciclos = 12
- [ ] `$T s` (ya detenido) → sin cambios, estado 0x01
- [ ] `$T terminal`, escribir `I` + Enter → `(nada)` (fuera de RUN se ignora);
      escribir `X` → `4B 'K'`; salir con Ctrl+C

## F. Carga `'L'`

- [ ] `$T l sw/programas/ejemplo_3.hex --verificar` → "3 palabras cargadas" y
      "las primeras 32 palabras coinciden" (los 8 NOPs viejos desaparecieron: CLEAR)
- [ ] `$T d` → PC = 0, ciclos = 0, estado 0x00, LD4 apagado (hubo reset después de la carga)
- [ ] `$T r` → PC = **0x8**, ciclos = **6** (HALT en la palabra 2)
- [ ] `$T l sw/programas/nops_5.hex` y `$T r` → PC = **0x14**, ciclos = **9**
- [ ] Programa vacío (N = 0):
  ```bash
  echo "# vacio" > /tmp/vacio.hex
  $T l /tmp/vacio.hex
  $T r
  ```
  → PC = **0x0**, ciclos = **4**
- [ ] Datos que parecen comandos:
  ```bash
  printf '58525349\n4C444B49\n00000000\n' > /tmp/comandos.hex
  $T l /tmp/comandos.hex --verificar
  $T r
  ```
  → una sola 'K', verificación OK; después PC = 0x8, ciclos = 6
- [ ] Más de 256 palabras:
  ```bash
  python3 -c "print('\n'.join(['00000013']*300))" > /tmp/grande.hex
  $T l /tmp/grande.hex --verificar
  $T r
  ```
  → los dos AVISOS (recorta a 256; la 255 pasa a HALT), verificación OK;
  después PC = **0x3FC**, ciclos = **259**

## G. Botón de reset (btnC)

- [ ] `$T l sw/programas/nops_5.hex`, apretar btnC, `$T r` → otra vez
      PC = 0x14, ciclos = 9 (el reset no borra la memoria de programa)
- [ ] Recuperar una carga trabada:
  1. `picocom -b 115200 /dev/ttyUSB1` y escribir solo `L` → se prende LD0 (esperando N)
  2. Apretar btnC → LEDs apagados
  3. Salir de picocom (Ctrl+A, Ctrl+X) y `$T x` → 'K'

## H. Interrupción `'I'` (segundo bitstream)

Bitstream aparte con **`STUB_INIT_NOPS = 256`** en `rtl/top.v` (toda la memoria
con NOP). Con este bitstream **no hacer ningún `l`**: después de un `'L'`
siempre hay un HALT y el programa termina solo.

- [ ] `$T x` y `$T r` → LD1 + LD2 prendidos (RUN), no responde. Esperar ~3 s y
      Enter → `Interrumpido en PC = …, después de N ciclos`, estado 0x02,
      con **PC = 4 · N** (N ≈ 100 millones por segundo de espera)
- [ ] `$T d` → estado sigue en 0x02
- [ ] `$T s` → estado 0x00, PC + 4, ciclos + 1
- [ ] `$T r` + Enter otra vez → los ciclos siguen subiendo desde donde quedaron
- [ ] Otros bytes durante RUN: en picocom escribir `R` (LD1 + LD2), después
      `D`, `S`, `X` → no pasa nada y los LEDs siguen igual; escribir `I` →
      llegan caracteres raros (el volcado) y los LEDs se apagan
- [ ] `$T r` y Ctrl+C → "Cancelado: se mando 'I'…", LEDs apagados (la placa no quedó en RUN)
- [ ] Volver a `STUB_INIT_NOPS = 8` en `rtl/top.v`

Si se interrumpe después de más de ~10 s, el PC (32 bits) ya dio la vuelta y
PC = 4 · N solo vale módulo 2³²: conviene cortar antes.

---

## Si algo no coincide

Anotar el ítem, copiar la salida completa del script (con `--raw` si es un
volcado) y el estado de los LEDs.

---

## Limitaciones del stub (para interpretar los resultados)

1. **No ejecuta instrucciones**: el PC suma 4 por ciclo; no hay saltos ni
   branches y `addi` no cambia ningún registro. Solo reconoce el HALT (0x00000000).
2. **Registros falsos**: xN = {PC[15:0], 0x00, N}.
3. **Latches falsos**: palabra k = {A, k, PC}. El ancho de 384 bits es provisorio.
4. **Ciclos = instrucciones + 4** siempre; con el pipeline real habrá stalls y flushes.
5. **`'D'` muestra la memoria de programa** en lugar de la de datos (truco para
   verificar `'L'`). Con el cpu real, `--verificar` deja de servir.
6. **Solo se ven las palabras 0–31** en el volcado; la 255 se comprueba
   indirectamente con el `r` del programa de 300 NOPs (PC = 0x3FC).
7. **`'I'` no se puede probar después de un `'L'`** (sin saltos, todo programa
   termina); por eso el bloque H usa otro bitstream.
8. **Los NOPs iniciales no vuelven** después del primer `'L'`: ni el botón ni
   `'X'` los restauran; hay que reprogramar la FPGA.
9. **El timing con el stub no dice nada del pipeline real**: el camino crítico
   va a estar en el cpu (se resuelve con el `clk_wiz`).

Del sistema en general:

- El caso N > 256 del hardware no se prueba desde el script (el script recorta);
  quedó probado en simulación (prueba 27 de `tb_top`).
- Sin timeout en `'L'`: una carga cortada se recupera con el botón (bloque G).
- `cycles` es de 32 bits: da la vuelta a los ~43 s de corrida continua.
