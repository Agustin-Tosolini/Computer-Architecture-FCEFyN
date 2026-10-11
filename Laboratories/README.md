# Laboratorios

Esta carpeta tiene los trabajos de laboratorio de la materia, uno por carpeta,
y una carpeta de material de consulta común a todos.

```
Laboratories/
├── Lab1/        ALU de 8 bits controlada con switches y botones
├── Lab2/        UART + ALU: la ALU del Lab1 operada desde la PC por puerto serie
└── resources/   Material de referencia de la placa y de Vivado
```

| Laboratorio | Tema | Informe |
|-------------|------|---------|
| [Lab1](Lab1/) | ALU parametrizable con banderas zero, carry y overflow | [Lab1-ALU.pdf](Lab1/output/Lab1-ALU.pdf) |
| [Lab2](Lab2/) | UART con FSMD (Rx/Tx, sobremuestreo 16x) conectada a la ALU | [Lab2-UART.pdf](Lab2/output/Lab2-UART.pdf) |

## Estructura de cada laboratorio

Todos los laboratorios siguen más o menos la misma organización:

| Elemento | Contenido |
|----------|-----------|
| `*.tex` | Fuente LaTeX del informe |
| `output/` | Salida de la compilación del informe; solo se versiona el PDF final |
| `img/` | Figuras del informe: esquemáticos RTL, diagramas de estado y capturas de simulación |
| `logos/` | Logos de la UNC y la FCEFyN para la carátula |
| Código Verilog | Fuentes, testbenches y constraints. En el Lab1 están dentro del proyecto de Vivado (`ALU/`); en el Lab2, en `src/` y `testbench/` |
| `.gitignore` | Ignora los archivos auxiliares de LaTeX |

Los archivos que genera Vivado (`*.runs/`, `*.sim/`, `*.cache/`, bitstreams,
logs, etc.) no se versionan: el [.gitignore](../.gitignore) de la raíz los
excluye.

El README de cada laboratorio explica en detalle cómo está organizado.

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
- **Placa:** Digilent Basys 3 (Artix-7 XC7A35T-1CPG236C, reloj de 100 MHz)
- **Informes:** LaTeX
- **Pruebas desde la PC (Lab2):** Python 3 con `pyserial` y Tkinter
