`timescale 1ns / 1ps
`default_nettype none

// Registro EX/MEM: conserva el resultado de EX y los controles de MEM/WB.
// Prioridad: reset > pausa global > burbuja > captura.
// No lleva flush: un salto resuelto en EX descarta IF/ID e ID/EX, no EX/MEM.
module ex_mem
(
    input wire i_clk,    // Captura en el flanco ascendente.
    input wire i_reset,  // Reset sincronico, incluso estando pausado.
    input wire i_enable, // Habilita el avance del pipeline.

    // Entradas desde EX.
    input wire [31:0] i_result,             // Resultado de EX o direccion de memoria.
    input wire [31:0] i_store_data,         // Dato de STORE con forwarding aplicado.
    input wire [4:0] i_rd,                  // Numero del registro destino.
    input wire [2:0] i_funct3,              // Tipo de acceso a memoria.
    input wire i_reg_write,                 // Solicitud de escritura en rd.
    input wire i_mem_read,                  // Solicitud de lectura de memoria.
    input wire i_mem_write,                 // Solicitud de escritura de memoria.
    input wire i_result_src,                // Resultado para WB: 0=EX; 1=memoria.
    input wire i_halt,                      // HALT que avanza hacia WB.
    input wire i_illegal,                   // Codificacion no soportada.
    input wire i_valid,                     // 1=instruccion presente; 0=burbuja.

    // Salidas almacenadas hacia MEM.
    output reg [31:0] o_result,             // Resultado de EX o direccion de memoria.
    output reg [31:0] o_store_data,         // Dato de STORE con forwarding aplicado.
    output reg [4:0] o_rd,                  // Numero del registro destino.
    output reg [2:0] o_funct3,              // Tipo de acceso a memoria.
    output reg o_reg_write,                 // Solicitud de escritura en rd.
    output reg o_mem_read,                  // Solicitud de lectura de memoria.
    output reg o_mem_write,                 // Solicitud de escritura de memoria.
    output reg o_result_src,                // Resultado para WB: 0=EX; 1=memoria.
    output reg o_halt,                      // HALT que avanza hacia WB.
    output reg o_illegal,                   // Codificacion no soportada.
    output reg o_valid                      // 1=instruccion presente; 0=burbuja.
);

    always @(posedge i_clk) begin
        if (i_reset || (i_enable && !i_valid)) begin
            o_result <= 32'd0;
            o_store_data <= 32'd0;
            o_rd <= 5'd0;
            o_funct3 <= 3'd0;
            o_reg_write <= 1'd0;
            o_mem_read <= 1'd0;
            o_mem_write <= 1'd0;
            o_result_src <= 1'd0;
            o_halt <= 1'd0;
            o_illegal <= 1'd0;
            o_valid <= 1'd0;
        end
        else if (i_enable) begin
            o_result <= i_result;
            o_store_data <= i_store_data;
            o_rd <= i_rd;
            o_funct3 <= i_funct3;
            o_reg_write <= i_reg_write;
            o_mem_read <= i_mem_read;
            o_mem_write <= i_mem_write;
            o_result_src <= i_result_src;
            o_halt <= i_halt;
            o_illegal <= i_illegal;
            o_valid <= i_valid;
        end
        // Sin enable, conserva todos los campos.
    end

endmodule

`default_nettype wire
