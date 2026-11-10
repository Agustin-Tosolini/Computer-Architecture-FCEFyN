# Trabajo Final — Apartado B (comunicación y Debug Unit)

**Estado: paso 3, protocolo completo: comandos `'L'`, `'X'`, `'D'`, `'S'`, `'R'` e `'I'`.**

`top` = `reset_gen` + `uart` + `intf` + `debug_unit` (`control_fsmd` + `dump_mux`) + `cpu_stub`.

Los tres testbenches dan `PASS` en simulación.

---

## Estructura

```
rtl/                    fuentes de diseño (Design Sources en Vivado)
  top.v                 módulo superior: pines de la Basys 3
  reset_gen.v           reset global: encendido + botón + locked
  uart.v                wrapper: baud_rate_generator + rx_fsmd + tx_fsmd
    baud_rate_generator.v
    rx_fsmd.v
    tx_fsmd.v
  intf.v                wrapper: rx_intf + tx_intf
    rx_intf.v
    tx_intf.v
  debug_unit.v          wrapper: control_fsmd + dump_mux
    control_fsmd.v      FSM + registros (protocolo): 'L', 'X', 'D', 'S', 'R' e 'I'
    dump_mux.v          combinacional: índice del volcado → byte (completo)
  cpu_stub.v            procesador falso con los puertos del contrato
                        (el top le pone 8 NOPs iniciales: STUB_INIT_NOPS)

sim/                    testbenches (Simulation Sources en Vivado)
  tb_top.v              sistema completo con una UART que hace de PC: prueba 'L', 'X', 'D', 'S', 'R' e 'I'
                        (corre a 1 Mbaud SOLO en simulacion; el diseño sigue en 115200)
  tb_cpu_stub.v         cpu_stub solo
  tb_dump_mux.v         dump_mux solo: los 314 bytes del volcado

constraints/
  top.xdc               pines de la Basys 3 (clock, botón, UART, 8 LEDs)

sw/
  uart_test.py          prueba desde la PC (pyserial): modos echo, x, l, d, s, r, step, terminal
  programas/            programas de ejemplo para el modo l (.hex: una palabra por línea)
    ejemplo_3.hex       addi, addi, HALT
    nops_5.hex          5 NOPs

docs/
  params.vh             CONTRATO: anchos, interfaz cpu <-> debug_unit, protocolo
                        (solo documentación: ningún módulo lo incluye)
  01_guia_de_estudio.md
  02_modulos.md         diseño de referencia (algunos nombres cambiaron, ver CAMBIOS.md)
  diagramas/
    B_completo.png/.svg      apartado B al terminar (nombres actuales)
    B_paso1_eco.png/.svg     versión anterior del top (eco)
    debug_unit_fsm.png/.svg  máquina de estados de la debug_unit

CAMBIOS.md              historial de cambios y decisiones de diseño (para el informe)
```

## Al copiar al proyecto

- **`echo_ctrl.v` ya no se usa** y no viene en este zip. Si lo tenés en el proyecto, **borralo** o deshabilitalo (clic derecho → *Disable File*). Si no, Vivado puede tomarlo como otro módulo raíz.
- **`top.v` y `tb_top.v` reemplazan** a los del eco.
- En Vivado:
  - módulo superior de síntesis: **`top`**;
  - módulo superior de simulación: el testbench que quieras correr. Clic derecho → **Set as Top** dentro de *Simulation Sources*.

## Simular

**En Vivado:**

1. Elegí el testbench en *Simulation Sources* → **Run Simulation**.
2. Escribí `run all` en la consola Tcl. `tb_top` simula unos 117 ms (31 volcados y 6 cargas a 1 Mbaud); puede tardar varios minutos.
3. Buscá la línea `PASS` en la consola.

**Con Icarus Verilog** (opcional, desde esta carpeta):

```
iverilog -Wall -g2005 -o tb.vvp rtl/*.v sim/tb_top.v        && vvp tb.vvp
iverilog -Wall -g2005 -o dm.vvp rtl/dump_mux.v sim/tb_dump_mux.v && vvp dm.vvp
iverilog -Wall -g2005 -o st.vvp rtl/cpu_stub.v sim/tb_cpu_stub.v && vvp st.vvp
```

Resultados esperados:

```
PASS: comandos 'L', 'X', 'D', 'S', 'R' e 'I' correctos
PASS: dump_mux arma los 314 bytes en orden
PASS: cpu_stub cumple el contrato
```

## Probar en la placa (Linux)

**Abrir la conexión:**

```
picocom -b 115200 /dev/ttyUSB1          # salir: Ctrl+A, Ctrl+X
```

**Qué debería pasar:**

- `X` (mayúscula) → la FPGA responde `K`.
- `L` se prueba con el script (hay que mandar bytes que no se pueden tipear).
- `D` (mayúscula) → la FPGA responde los 314 bytes del volcado. En picocom se ven como caracteres raros: usá el script.
- `S` (mayúscula) → un ciclo de clock y el volcado. Con el stub: el PC avanza 0, 4, …, 0x20 (8 NOPs); en el HALT se congela y 4 pasos después `halted = 1`.
- `R` (mayúscula) → corre hasta el HALT y manda el volcado. Con el stub (8 NOPs) termina al instante: PC = 0x20, 12 ciclos (8 NOPs + 1 al ver el HALT + 3 de vaciado), `halted = 1`.
- `I` (mayúscula) fuera de una corrida → no responde nada (se ignora).
- Cualquier otra tecla → no responde nada. Es correcto: ya no hay eco.
- LEDs: LD0–LD3 muestran el código de estado de la FSM (0 = IDLE, 1/2/3 = carga, 6 = RUN, 8 = DUMP, 9 = CLEAR) y LD4 muestra `halted`. Normalmente se ven todos apagados (o solo LD4).

**Probar la interrupción `'I'` en la placa.** Con 8 NOPs el programa del stub siempre llega al HALT en 120 ns, así que no da tiempo a interrumpirlo. Para probar `'I'` hace falta un programa sin fin. Con `'L'` no se puede armar uno para el stub: después de cualquier carga la palabra 255 es HALT, y el stub no ejecuta saltos, así que siempre termina (con el cpu real alcanza con un `j .`, un salto a sí mismo). La forma es generar un bitstream aparte con **`STUB_INIT_NOPS = 256`** en `top.v` (toda la memoria con NOP) y **no hacer ningún `L`**. Con ese bitstream:

- `R` → no responde: está corriendo. **LD1 y LD2 se prenden** (estado 6 = RUN).
- Otras teclas (`D`, `S`, `X`...) → nada, y sigue corriendo.
- `I` → llega el volcado con `estado = 0x02` (interrumpido). Si antes mandaste `X`, el PC vale 4 × ciclos.
- Ojo: `cycles` es de 32 bits. A 100 MHz da la vuelta a los ~43 s de corrida.

Después volvé a `STUB_INIT_NOPS = 8`.

**Con el script** (necesita `pip install pyserial`):

```
python3 sw/uart_test.py --list
python3 sw/uart_test.py /dev/ttyUSB1 x
python3 sw/uart_test.py /dev/ttyUSB1 l sw/programas/ejemplo_3.hex --verificar
                                               # carga + compara con un 'D' (solo con el stub)
python3 sw/uart_test.py /dev/ttyUSB1 d          # agregá --raw para ver los bytes en hex
python3 sw/uart_test.py /dev/ttyUSB1 s          # un paso + volcado completo
python3 sw/uart_test.py /dev/ttyUSB1 step       # interactivo: Enter = paso, d, x, q
python3 sw/uart_test.py /dev/ttyUSB1 r          # corre; Enter = interrumpir ('I')
```

Si aparece "Permission denied", agregá tu usuario al grupo `dialout` y volvé a iniciar sesión:

```
sudo usermod -aG dialout $USER
```

## Próximo paso

**Probar `'L'` en la placa** y después la secuencia completa con un programa: `l` → `step` / `r`. Por ejemplo, con `nops_5.hex`, `r` tiene que terminar en PC = 0x14 con 9 ciclos.

Pendientes ya charlados: panel de LEDs/7 segmentos, `clk_wiz` y timing, integración con el cpu real (revisar el contrato) y la versión final del script/GUI.
