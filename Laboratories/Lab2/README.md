# Lab 2 - UART + ALU

Diseño en Verilog de una UART (*Universal Asynchronous Receiver and
Transmitter*) que permite operar desde una PC la ALU del [Lab 1](../Lab1/).
El intercambio es de pregunta y respuesta:

```
PC   -> FPGA : 3 bytes en orden [A, B, OPCODE]
FPGA -> PC   : 1 byte con el resultado
```

Las banderas zero, carry y overflow se muestran en los LEDs de la placa. La
UART trabaja a 9600 baudios, con 8 bits de datos, sin paridad y 1 bit de stop,
y muestrea cada bit 16 veces (sobremuestreo 16x).

El informe completo está en [output/Lab2-UART.pdf](output/Lab2-UART.pdf).

## Estructura

```
Lab2/
├── src/                     Diseño en Verilog
├── testbench/               Bancos de prueba
├── scripts/uart_script.py   Interfaz gráfica en Python para probar en la placa
├── Lab2-UART.tex            Fuente LaTeX del informe
├── output/Lab2-UART.pdf     Informe compilado
├── img/                     Figuras del informe
└── logos/                   Logos para la carátula
```

A diferencia del Lab 1, acá no se versiona el proyecto de Vivado, solo las
fuentes. Para sintetizar hay que crear un proyecto nuevo y agregar los
archivos de `src/` y `testbench/`.

### Diseño - `src/`

El sistema tiene tres bloques en cadena, cada uno con un wrapper que no tiene
lógica propia:

```
i_rx --> [ uart ] --> [ intf ] --> [ ALU_ctrl + ALU ]
o_tx <--          <--          <--
```

| Archivo | Descripción |
|---------|-------------|
| `uart_alu_top.v` | Top del sistema. Sus puertos son los pines de la placa e instancia los tres bloques |
| `uart.v` | Wrapper de la UART: generador de baud rate + receptor + transmisor |
| `baud_rate_generator.v` | Contador módulo N que genera un tick 16 veces por bit (N = 651 para 100 MHz y 9600 baudios) |
| `rx_fsmd.v` | Receptor (FSMD con estados one-hot). Sincroniza la entrada, muestrea en el centro de cada bit y avisa con `rx_done` |
| `tx_fsmd.v` | Transmisor (FSMD). Arma la trama `{stop, dato, start}` en un registro de desplazamiento y la envía |
| `intf.v` | Wrapper de la interfaz: agrupa `rx_intf` y `tx_intf` |
| `rx_intf.v` | Buffer de un byte entre el receptor y el control (`r_data`, `rd`, `rx_empty`) |
| `tx_intf.v` | Indica si hay una transmisión en curso (`w_data`, `wr`, `tx_full`) |
| `ALU_ctrl.v` | Máquina de estados del protocolo: recibe A, B y el opcode, y envía el resultado. Es el único módulo que conoce el protocolo |
| `ALU.v` | ALU combinacional; las mismas operaciones que en el Lab 1 |
| `rx_fsmd_diagram.puml` | Diagrama de estados del receptor en PlantUML |

### Verificación - `testbench/`

Los dos testbenches usan un baud rate alto (N = 4) para que la simulación
termine rápido. La lógica es la misma que a 9600 baudios.

| Archivo | Descripción |
|---------|-------------|
| `tb_uart_loopback.v` | Conecta la salida del transmisor a la entrada del receptor y verifica que vuelvan los mismos bytes |
| `tb_sistema.v` | Sistema completo: otra instancia de `uart` hace de PC, envía A, B y el opcode, y revisa el resultado |

### Prueba en la placa - `scripts/`

`uart_script.py` es una interfaz gráfica hecha con Tkinter y `pyserial`. Permite
elegir el puerto serie, enviar los operandos y el opcode como bytes crudos, y
muestra el resultado en hexadecimal, decimal y binario. Además compara la
respuesta de la FPGA con un modelo de la ALU escrito en Python.

```bash
cd scripts
python3 -m venv .venv && source .venv/bin/activate
pip install pyserial
python3 uart_script.py
```

### Asignación de pines

| Puerto | Pin | Función |
|--------|-----|---------|
| `i_clk` | W5 | Oscilador de 100 MHz |
| `i_reset` | U18 | Pulsador central (btnC) |
| `i_rx` | B18 | Línea serie desde el puente USB-UART |
| `o_tx` | A18 | Línea serie hacia el puente USB-UART |
| `o_leds[0]` | U16 | Bandera zero |
| `o_leds[1]` | E19 | Bandera carry |
| `o_leds[2]` | U19 | Bandera overflow |

Todos los pines usan LVCMOS33. Se puede partir del
[Basys-3-Master.xdc](../resources/Basys-3-Master.xdc). Ojo: en ese archivo los
nombres de los pines de la UART están puestos desde el lado del chip puente.

### Figuras - `img/`

| Archivo | Contenido |
|---------|-----------|
| `schematic-full.png`, `schematic-uart.png`, `schematic-inft-alu-ctrl.png` | Esquemáticos RTL |
| `diagrama_estados_rx_fsmd.png`, `diagrama_estados_tx_fsmd.png`, `diagrama_estados_alu_ctrl.png` | Diagramas de estado |
| `signal-loopback.png`, `log-loopback.png` | Resultados del testbench de loopback |
| `systemsignal.png`, `log-fullsystem.png` | Resultados del testbench del sistema completo |
| `python-script-uart.png` | Captura de la interfaz de Python |
