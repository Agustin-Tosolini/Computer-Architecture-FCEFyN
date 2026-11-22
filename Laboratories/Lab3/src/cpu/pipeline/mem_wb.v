`timescale 1ns / 1ps
`default_nettype none

// Registro MEM/WB: conserva los resultados y controles para escribir en registros.
// Prioridad: reset > pausa global > burbuja > captura.
// La seleccion del resultado y la escritura se realizan fuera de este registro.
module mem_wb
(
    input wire i_clk,    // Captura en el flanco ascendente.
    input wire i_reset,  // Reset sincronico, incluso estando pausado.
    input wire i_enable, // Habilita el avance del pipeline.

    // Entradas desde MEM.
    input wire [31:0] i_result,             // Resultado de EX (ALU o PC+4).
    input wire [31:0] i_mem_data,         // Dato de LOAD, ya extendido a 32 bits.
    input wire [4:0] i_rd,                  // Numero del registro destino.
    input wire i_reg_write,                 // Solicitud de escritura en rd.
    input wire i_result_src,                // Resultado para WB: 0=EX; 1=memoria.
    input wire i_halt,                      // HALT que avanza hacia WB.
    input wire i_illegal,                   // Codificacion no soportada.
    input wire i_valid,                     // 1=instruccion presente; 0=burbuja.

    // Salidas almacenadas hacia WB.
    output reg [31:0] o_result,             // Resultado de EX (ALU o PC+4).
    output reg [31:0] o_mem_data,         // Dato de LOAD, ya extendido a 32 bits.
    output reg [4:0] o_rd,                  // Numero del registro destino.
    output reg o_reg_write,                 // Solicitud de escritura en rd.
    output reg o_result_src,                // Resultado para WB: 0=EX; 1=memoria.
    output reg o_halt,                      // HALT que avanza hacia WB.
    output reg o_illegal,                   // Codificacion no soportada.
    output reg o_valid                      // 1=instruccion presente; 0=burbuja.
);

    always @(posedge i_clk) begin
        if (i_reset || (i_enable && !i_valid)) begin
            o_result <= 32'd0;
            o_mem_data <= 32'd0;
            o_rd <= 5'd0;
            o_reg_write <= 1'd0;
            o_result_src <= 1'd0;
            o_halt <= 1'd0;
            o_illegal <= 1'd0;
            o_valid <= 1'd0;
        end
        else if (i_enable) begin
            o_result <= i_result;
            o_mem_data <= i_mem_data;
            o_rd <= i_rd;
            o_reg_write <= i_reg_write;
            o_result_src <= i_result_src;
            o_halt <= i_halt;
            o_illegal <= i_illegal;
            o_valid <= i_valid;
        end
        // Sin enable, conserva todos los campos.
    end

endmodule

`default_nettype wire
