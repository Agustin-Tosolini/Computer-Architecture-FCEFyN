# Lab 1 - ALU

Diseño e implementación en Verilog de una ALU parametrizable (8 bits por
defecto) sobre la Basys 3. Los operandos A y B y el código de operación se
cargan con los switches; tres botones eligen en qué registro se guarda cada
uno. El resultado se ve en los LEDs, junto con las banderas **zero**,
**carry** y **overflow**.

Operaciones soportadas (los códigos son los del campo `funct` de MIPS):

| Operación | Código |
|-----------|--------|
| ADD | `100000` |
| SUB | `100010` |
| AND | `100100` |
| OR  | `100101` |
| XOR | `100110` |
| NOR | `100111` |
| SRA | `000011` |
| SRL | `000010` |

El informe completo está en [output/Lab1-ALU.pdf](output/Lab1-ALU.pdf).

## Estructura

```
Lab1/
├── ALU/                              Proyecto de Vivado
│   ├── ALU.xpr                       Archivo de proyecto (abrir con Vivado)
│   └── ALU.srcs/
│       ├── sources_1/new/ALU.v       Diseño: módulo ALU
│       ├── sim_1/new/ALU_dut.v       Testbench autoverificable
│       ├── sim_1/new/ALU_tb.v        Mismo testbench, con el módulo llamado ALU_tb
│       └── constrs_1/new/synth-ALU.xdc   Asignación de pines de la Basys 3
├── Lab1-ALU.tex                      Fuente LaTeX del informe
├── output/Lab1-ALU.pdf               Informe compilado
├── img/                              Figuras del informe
└── logos/                            Logos para la carátula
```

### Diseño - `ALU.v`

Un solo módulo con dos parámetros: `LENGTH_BITS` (ancho de los datos) y
`LENGTH_OPT` (ancho del código de operación). Tiene dos partes:

- **Bloque secuencial:** en cada flanco de reloj guarda el valor de los
  switches en `dato_A`, `dato_B` u `opt`, según qué botón esté presionado.
  Tiene reset síncrono.
- **Bloque combinacional:** un `case` sobre el código de operación que calcula
  el resultado, el acarreo y el desbordamiento.

### Verificación - `ALU_dut.v`

Testbench autoverificable con reloj de 100 MHz. Compara cada salida del diseño
(LEDs y las tres banderas) contra un modelo de referencia que describe la
especificación. Corre casos dirigidos para cada operación, una prueba del
reset, una prueba con el botón sostenido y 500 vectores aleatorios. El 85 % de
esos vectores usa códigos válidos; el resto prueba la rama `default`.

### Constraints - `synth-ALU.xdc`

Conecta los puertos del módulo a los switches, botones y LEDs de la Basys 3,
con estándar LVCMOS33.

### Figuras - `img/`

| Archivo | Contenido |
|---------|-----------|
| `ALU-schematic.png` | Esquemático RTL que genera Vivado |
| `TB2.png`, `TB3.png` | Formas de onda: reset inicial y carga de los registros A, B y `opt` |
| `coverage.png` | Reporte de cobertura y resumen que imprime el testbench |

## Cómo usarlo

1. Abrir `ALU/ALU.xpr` con Vivado.
2. **Simulación:** *Run Simulation → Run Behavioral Simulation* con
   `ALU_dut` (o `ALU_tb`) como top de simulación.
3. **Placa:** *Generate Bitstream* y programar la Basys 3 desde el
   *Hardware Manager*.
4. **Informe:** compilar `Lab1-ALU.tex` (por ejemplo con
   `latexmk -pdf -outdir=output Lab1-ALU.tex`).
