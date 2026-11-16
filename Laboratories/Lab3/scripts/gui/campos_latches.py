"""
campos_latches.py - Campos de los 4 latches del pipeline dentro de o_latches.

Es la tabla de src/params.vh, seccion 4b (480 bits). tests/test_constantes.py
verifica que sea IGUAL a la de params.vh y a la de scripts/uart_test.py.

Cada campo: (latch, nombre, bit alto, bit bajo, descripcion). Los bits son
posiciones dentro de o_latches[479:0]; la palabra k del volcado es
o_latches[32k+31 : 32k].
"""

LATCHES_W = 480
LATCHES = ["IF/ID", "ID/EX", "EX/MEM", "MEM/WB"]

# Explicacion corta de cada latch (encabezado del arbol en la interfaz).
DESCRIPCION_LATCH = {
    "IF/ID": "Entre IF y ID: la instruccion que se acaba de buscar y su PC.",
    "ID/EX": "Entre ID y EX: la instruccion decodificada (operandos, inmediato y controles).",
    "EX/MEM": "Entre EX y MEM: resultado de la ALU (o direccion) y dato a guardar.",
    "MEM/WB": "Entre MEM y WB: lo que se va a escribir en el registro destino.",
}

CAMPOS = [
    ("IF/ID", "pc", 479, 448, "Direccion (en bytes) de la instruccion buscada."),
    ("IF/ID", "instr", 447, 416, "Instruccion de 32 bits que leyo IF. Burbuja = NOP (0x00000013)."),
    ("IF/ID", "valid", 384, 384, "1 = hay una instruccion; 0 = burbuja (reset, flush o parada)."),
    ("ID/EX", "pc", 383, 352, "PC de la instruccion que esta por ejecutarse."),
    ("ID/EX", "rs1_data", 351, 320, "Valor de rs1 leido del banco en ID (antes del forwarding)."),
    ("ID/EX", "rs2_data", 319, 288, "Valor de rs2 leido en ID; tambien es el dato de un store."),
    ("ID/EX", "imm", 287, 256, "Inmediato de 32 bits, ya extendido."),
    ("ID/EX", "rs1", 242, 238, "Numero del registro fuente 1."),
    ("ID/EX", "rs2", 237, 233, "Numero del registro fuente 2."),
    ("ID/EX", "rd", 232, 228, "Numero del registro destino."),
    ("ID/EX", "funct3", 227, 225, "funct3 de la instruccion (operacion, tipo de salto o tamano del acceso)."),
    ("ID/EX", "funct7_b5", 224, 224, "Bit 30 de la instruccion: distingue SUB/SRA/SRAI."),
    ("ID/EX", "reg_write", 207, 207, "La instruccion escribe un registro."),
    ("ID/EX", "alu_src_a", 206, 206, "1 = el operando A de la ALU es 0 (lui)."),
    ("ID/EX", "alu_src_b", 205, 205, "1 = el operando B de la ALU es el inmediato."),
    ("ID/EX", "mem_read", 204, 204, "Es un load."),
    ("ID/EX", "mem_write", 203, 203, "Es un store."),
    ("ID/EX", "result_src", 202, 202, "0 = WB escribe el resultado de EX; 1 = el dato de memoria."),
    ("ID/EX", "branch", 201, 201, "Es un salto condicional (beq/bne)."),
    ("ID/EX", "jump", 200, 200, "Es un salto incondicional (jal/jalr)."),
    ("ID/EX", "jalr", 199, 199, "El destino es rs1 + inmediato (jalr)."),
    ("ID/EX", "alu_op", 198, 197, "Categoria para la ALU: 0 suma, 1 resta, 2 tipo R, 3 tipo I."),
    ("ID/EX", "halt", 196, 196, "Marcador de parada (HALT o error) que baja hacia WB."),
    ("ID/EX", "uses_rs1", 195, 195, "La instruccion usa rs1 (para forwarding y stalls)."),
    ("ID/EX", "uses_rs2", 194, 194, "La instruccion usa rs2."),
    ("ID/EX", "illegal", 193, 193, "Instruccion no soportada: parada por error."),
    ("ID/EX", "valid", 192, 192, "1 = hay una instruccion; 0 = burbuja."),
    ("EX/MEM", "result", 191, 160, "Resultado de la ALU, direccion de memoria o PC+4 (jal/jalr)."),
    ("EX/MEM", "store_data", 159, 128, "Dato que va a escribir un store (con forwarding aplicado)."),
    ("EX/MEM", "rd", 110, 106, "Registro destino."),
    ("EX/MEM", "funct3", 105, 103, "Tamano y signo del acceso a memoria."),
    ("EX/MEM", "reg_write", 102, 102, "La instruccion escribe un registro."),
    ("EX/MEM", "mem_read", 101, 101, "Es un load."),
    ("EX/MEM", "mem_write", 100, 100, "Es un store."),
    ("EX/MEM", "result_src", 99, 99, "1 = WB va a escribir el dato leido de memoria."),
    ("EX/MEM", "halt", 98, 98, "Marcador de parada."),
    ("EX/MEM", "illegal", 97, 97, "La parada es por error."),
    ("EX/MEM", "valid", 96, 96, "1 = hay una instruccion; 0 = burbuja."),
    ("MEM/WB", "result", 95, 64, "Resultado de EX que se escribiria en rd."),
    ("MEM/WB", "mem_data", 63, 32, "Dato leido de memoria (load), ya extendido."),
    ("MEM/WB", "rd", 9, 5, "Registro destino."),
    ("MEM/WB", "reg_write", 4, 4, "Escribe rd en este ciclo."),
    ("MEM/WB", "result_src", 3, 3, "1 = escribe mem_data; 0 = escribe result."),
    ("MEM/WB", "halt", 2, 2, "Marcador de parada: si valid = 1, el procesador se detuvo."),
    ("MEM/WB", "illegal", 1, 1, "La parada fue por error (o_fault)."),
    ("MEM/WB", "valid", 0, 0, "1 = hay una instruccion; 0 = burbuja."),
]

# Campos de 32 bits (se muestran en hexadecimal) y de control (1 bit: ON/off).
def ancho(campo):
    return campo[2] - campo[3] + 1


def es_control(campo):
    return ancho(campo) == 1


def valor(lat_bits, campo):
    """Valor del campo dentro del entero de 480 bits."""
    return (lat_bits >> campo[3]) & ((1 << ancho(campo)) - 1)
