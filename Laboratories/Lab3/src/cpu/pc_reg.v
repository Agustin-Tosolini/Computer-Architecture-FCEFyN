`timescale 1ns / 1ps
`default_nettype none

//------------------------------------------------------------------------------
// Program Counter — registro de la etapa IF.
// Guarda la direccion en BYTES de la instruccion que se esta buscando.
// El sumador PC+4 y la seleccion del destino de salto quedan fuera del modulo.
// Reset sincronico con prioridad sobre las habilitaciones.
//------------------------------------------------------------------------------
module pc_reg
(
    input  wire        i_clk,
    input  wire        i_reset,
    input  wire        i_enable,
    input  wire        i_pc_write,
    input  wire [31:0] i_pc_next,
    output reg  [31:0] o_pc
);

    always @(posedge i_clk) begin
        if (i_reset)
            o_pc <= 32'd0;
        else if (i_enable && i_pc_write)
            o_pc <= i_pc_next;
        // Sin habilitacion, conserva la direccion actual.
    end

endmodule

`default_nettype wire

//------------------------------------------------------------------------------
// Referencia rapida de entradas y salidas
// Senal       | Tipo    | Funcion
// ------------|---------|-------------------------------------------------------
// i_clk       | Entrada | Reloj: actualizacion en flanco ascendente.
// i_reset     | Entrada | Lleva el PC a cero en el flanco, con prioridad.
// i_enable    | Entrada | Habilitacion global de avance de la CPU.
// i_pc_write  | Entrada | Permiso de actualizar PC; en 0 lo congela.
// i_pc_next   | Entrada | Proxima direccion en bytes, calculada externamente.
// o_pc        | Salida  | Direccion actual en bytes (32 bits).
// Debe recibir reset antes de usarse; no tiene inicializacion independiente.
//------------------------------------------------------------------------------
