# Laboratorios

Esta carpeta tiene los trabajos de laboratorio de la materia, uno por carpeta,
y una carpeta de material de consulta común a todos.

```
Laboratories/
├── Lab1/        ALU de 8 bits controlada con switches y botones
├── Lab2/        UART + ALU: la ALU del Lab1 operada desde la PC por puerto serie
├── Lab3/        Trabajo final: pipeline RISC-V (RV32I) de 5 etapas + Debug Unit por UART
└── resources/   Material de referencia de la placa y de Vivado
```

| Laboratorio | Tema | Informe |
|-------------|------|---------|
| [Lab1](Lab1/) | ALU parametrizable con banderas zero, carry y overflow | [Lab1-ALU.pdf](Lab1/output/Lab1-ALU.pdf) |
| [Lab2](Lab2/) | UART con FSMD (Rx/Tx, sobremuestreo 16x) conectada a la ALU | [Lab2-UART.pdf](Lab2/output/Lab2-UART.pdf) |
| [Lab3](Lab3/) | Procesador RISC-V segmentado (forwarding, stall y flush), Debug Unit por UART y depurador gráfico en Python | [Lab3-Pipeline.pdf](Lab3/docs/informe/output/Lab3-Pipeline.pdf) |

## Estructura de cada laboratorio

Los Lab1 y Lab2 siguen la misma organización:

| Elemento | Contenido |
|----------|-----------|
| `*.tex` | Fuente LaTeX del informe |
| `output/` | Salida de la compilación del informe; solo se versiona el PDF final |
| `img/` | Figuras del informe: esquemáticos RTL, diagramas de estado y capturas de simulación |
| `logos/` | Logos de la UNC y la FCEFyN para la carátula |
| Código Verilog | Fuentes, testbenches y constraints. En el Lab1 están dentro del proyecto de Vivado (`ALU/`); en el Lab2, en `src/` y `testbench/` |
| `scripts/` | (Lab2) Interfaz en Python para probar la placa |
| `.gitignore` | Ignora los archivos auxiliares de LaTeX |

El Lab3 es más grande y se organiza distinto:

| Elemento | Contenido |
|----------|-----------|
| `src/` | Diseño en Verilog: `cpu/` (etapas IF, ID, EX, MEM, WB, latches y unidades de riesgos), `debug_unit/` (UART, protocolo y módulo `top`), `ip/` (Clocking Wizard a 62,5 MHz) y `params.vh` (contrato entre cpu y debug unit) |
| `testbench/` | Testbenches de cada módulo y de integración, más los vectores de prueba generados por el modelo de referencia |
| `constrains/` | `top.xdc` con los pines de la Basys 3 |
| `scripts/` | Ensamblador RV32I, modelo de referencia, scripts de prueba por UART, pruebas de mutación, programas de ejemplo y el depurador gráfico (`gui/`, PySide6) |
| `docs/` | Decisiones de diseño, instrucciones soportadas, manual del depurador, checklist de la placa, material de defensa e informe LaTeX (`docs/informe/`) |
| `TRABAJO-FINAL-2026.pdf` | Consigna del trabajo final |

Ni el Lab2 ni el Lab3 versionan el proyecto de Vivado, solo las fuentes: para
sintetizar hay que crear un proyecto nuevo y agregarlas. Los archivos que
genera Vivado (`*.runs/`, `*.sim/`, `*.cache/`, bitstreams, logs, etc.) no se
versionan: el [.gitignore](../.gitignore) de la raíz los excluye.

El README de cada laboratorio explica en detalle cómo está organizado y cómo
simularlo y probarlo.

## resources/

| Archivo | Descripción |
|---------|-------------|
| `Basys-3-Master.xdc` | Archivo de constraints maestro de Digilent para la Basys 3 (todos los pines de la placa) |
| `basys3-_basic_io_block_diagram.webp` | Diagrama de los periféricos básicos de E/S de la placa |
| `Diseño con FPGA VIVADO.pdf` | Material de la cátedra sobre el flujo de diseño en Vivado |
| `image.png` | Imagen de referencia |
| `videoIvo.txt` | Enlace a un video de apoyo |

## Herramientas

- **Lenguaje:** Verilog
- **Síntesis, implementación y simulación:** Xilinx Vivado
- **Simulación por línea de comandos (Lab3):** Icarus Verilog
- **Placa:** Digilent Basys 3 (Artix-7 XC7A35T-1CPG236C, reloj de 100 MHz;
  el Lab3 trabaja a 62,5 MHz con un Clocking Wizard)
- **Informes:** LaTeX
- **Pruebas desde la PC:** Python 3 con `pyserial`; interfaz en Tkinter (Lab2)
  y depurador gráfico en PySide6 con pruebas en `pytest` (Lab3)
