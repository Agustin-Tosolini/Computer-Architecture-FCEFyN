`timescale 1ns / 1ps
`default_nettype none

//------------------------------------------------------------------------------
// Memoria de instrucciones — etapa IF.
// 256 palabras de 32 bits (1 KiB), con lectura asincrona y escritura sincronica.
// Las direcciones de ambos puertos son NUMEROS DE PALABRA, no bytes.
// En la integracion, i_raddr se conecta a PC[9:2].
// El controlador debe cargar programas solo con la CPU detenida.
//------------------------------------------------------------------------------
module instr_mem
(
    input  wire        i_clk,
    input  wire        i_we,
    input  wire [7:0]  i_waddr,
    input  wire [31:0] i_wdata,
    input  wire [7:0]  i_raddr,
    output wire [31:0] o_rdata
);

    // Solicita RAM distribuida en Vivado para mantener lectura asincrona.
    (* ram_style = "distributed" *) reg [31:0] mem [0:255];
    integer index;

    // Inicializacion al configurar la FPGA (no es un reset de CPU).
    // Las posiciones vacias contienen nuestro HALT: 0x00000000.
    initial begin
        for (index = 0; index < 256; index = index + 1)
            mem[index] = 32'h0000_0000;
    end

    always @(posedge i_clk) begin
        if (i_we)
            mem[i_waddr] <= i_wdata;
    end

    // El dato cambia al cambiar la direccion o el contenido seleccionado.
    assign o_rdata = mem[i_raddr];

endmodule

`default_nettype wire

//------------------------------------------------------------------------------
// Referencia rapida de entradas y salidas
// Senal   | Tipo    | Funcion
// --------|---------|-----------------------------------------------------------
// i_clk   | Entrada | Reloj para escribir instrucciones.
// i_we    | Entrada | En 1, habilita la escritura en el flanco ascendente.
// i_waddr | Entrada | Palabra a escribir (0 a 255).
// i_wdata | Entrada | Instruccion de 32 bits que se quiere guardar.
// i_raddr | Entrada | Palabra a leer (0 a 255); normalmente PC[9:2].
// o_rdata | Salida  | Instruccion seleccionada, sin esperar un flanco.
// Ejemplo: PC=12 bytes corresponde a i_raddr=3, la cuarta instruccion.
// No hay reset: reiniciar la CPU conserva el programa cargado.
// La carga y las comprobaciones de rango/alineacion corresponden al exterior.
//------------------------------------------------------------------------------
