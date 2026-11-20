`timescale 1ns / 1ps
`default_nettype none

// Registro ID/EX: captura datos y controles de ID para la etapa EX.
// Prioridad: reset > pausa global > flush/burbuja > captura.
module id_ex
(
    input wire i_clk,    // Captura en el flanco ascendente.
    input wire i_reset,  // Reset sincronico, incluso estando pausado.
    input wire i_enable, // Habilita el avance del pipeline.
    input wire i_flush,  // Inserta una burbuja cuando enable=1.

    // Entradas desde ID.
    input wire [31:0] i_pc,                  // PC de la instruccion, en bytes.
    input wire [31:0] i_rs1_data,            // Valor leido de rs1.
    input wire [31:0] i_rs2_data,            // Valor leido de rs2; tambien dato de STORE.
    input wire [31:0] i_imm,                 // Inmediato reconstruido.
    input wire [4:0] i_rs1,                  // Numero del registro fuente rs1.
    input wire [4:0] i_rs2,                  // Numero del registro fuente rs2.
    input wire [4:0] i_rd,                   // Numero del registro destino.
    input wire [2:0] i_funct3,               // Funcion: ALU, salto o acceso a memoria.
    input wire i_funct7_b5,                  // Bit 30: distingue SUB y SRA/SRAI.
    input wire i_reg_write,                  // Solicitud de escritura en rd.
    input wire i_alu_src_a,                  // Operando A: 0=rs1; 1=cero.
    input wire i_alu_src_b,                  // Operando B: 0=rs2; 1=inmediato.
    input wire i_mem_read,                   // Solicitud de lectura de memoria.
    input wire i_mem_write,                  // Solicitud de escritura de memoria.
    input wire i_result_src,                 // Resultado para WB: 0=EX; 1=memoria.
    input wire i_branch,                     // Salto condicional BEQ/BNE.
    input wire i_jump,                       // Salto incondicional JAL/JALR.
    input wire i_jalr,                       // Destino basado en rs1.
    input wire [1:0] i_alu_op,               // Categoria de operacion de ALU.
    input wire i_halt,                       // Solicitud de parada.
    input wire i_uses_rs1,                   // La instruccion utiliza rs1.
    input wire i_uses_rs2,                   // La instruccion utiliza rs2.
    input wire i_illegal,                    // Codificacion no soportada.
    input wire i_valid,                      // 1=instruccion presente; 0=burbuja.

    // Salidas almacenadas hacia EX.
    output reg [31:0] o_pc,                  // PC de la instruccion, en bytes.
    output reg [31:0] o_rs1_data,            // Valor leido de rs1.
    output reg [31:0] o_rs2_data,            // Valor leido de rs2; tambien dato de STORE.
    output reg [31:0] o_imm,                 // Inmediato reconstruido.
    output reg [4:0] o_rs1,                  // Numero del registro fuente rs1.
    output reg [4:0] o_rs2,                  // Numero del registro fuente rs2.
    output reg [4:0] o_rd,                   // Numero del registro destino.
    output reg [2:0] o_funct3,               // Funcion: ALU, salto o acceso a memoria.
    output reg o_funct7_b5,                  // Bit 30: distingue SUB y SRA/SRAI.
    output reg o_reg_write,                  // Solicitud de escritura en rd.
    output reg o_alu_src_a,                  // Operando A: 0=rs1; 1=cero.
    output reg o_alu_src_b,                  // Operando B: 0=rs2; 1=inmediato.
    output reg o_mem_read,                   // Solicitud de lectura de memoria.
    output reg o_mem_write,                  // Solicitud de escritura de memoria.
    output reg o_result_src,                 // Resultado para WB: 0=EX; 1=memoria.
    output reg o_branch,                     // Salto condicional BEQ/BNE.
    output reg o_jump,                       // Salto incondicional JAL/JALR.
    output reg o_jalr,                       // Destino basado en rs1.
    output reg [1:0] o_alu_op,               // Categoria de operacion de ALU.
    output reg o_halt,                       // Solicitud de parada.
    output reg o_uses_rs1,                   // La instruccion utiliza rs1.
    output reg o_uses_rs2,                   // La instruccion utiliza rs2.
    output reg o_illegal,                    // Codificacion no soportada.
    output reg o_valid                       // 1=instruccion presente; 0=burbuja.
);

    always @(posedge i_clk) begin
        // Reset siempre limpia; flush o valid=0 solo al avanzar.
        if (i_reset || (i_enable && (i_flush || !i_valid))) begin
            o_pc <= 32'd0;
            o_rs1_data <= 32'd0;
            o_rs2_data <= 32'd0;
            o_imm <= 32'd0;
            o_rs1 <= 5'd0;
            o_rs2 <= 5'd0;
            o_rd <= 5'd0;
            o_funct3 <= 3'd0;
            o_funct7_b5 <= 1'd0;
            o_reg_write <= 1'd0;
            o_alu_src_a <= 1'd0;
            o_alu_src_b <= 1'd0;
            o_mem_read <= 1'd0;
            o_mem_write <= 1'd0;
            o_result_src <= 1'd0;
            o_branch <= 1'd0;
            o_jump <= 1'd0;
            o_jalr <= 1'd0;
            o_alu_op <= 2'd0;
            o_halt <= 1'd0;
            o_uses_rs1 <= 1'd0;
            o_uses_rs2 <= 1'd0;
            o_illegal <= 1'd0;
            o_valid <= 1'd0;
        end
        else if (i_enable) begin
            o_pc <= i_pc;
            o_rs1_data <= i_rs1_data;
            o_rs2_data <= i_rs2_data;
            o_imm <= i_imm;
            o_rs1 <= i_rs1;
            o_rs2 <= i_rs2;
            o_rd <= i_rd;
            o_funct3 <= i_funct3;
            o_funct7_b5 <= i_funct7_b5;
            o_reg_write <= i_reg_write;
            o_alu_src_a <= i_alu_src_a;
            o_alu_src_b <= i_alu_src_b;
            o_mem_read <= i_mem_read;
            o_mem_write <= i_mem_write;
            o_result_src <= i_result_src;
            o_branch <= i_branch;
            o_jump <= i_jump;
            o_jalr <= i_jalr;
            o_alu_op <= i_alu_op;
            o_halt <= i_halt;
            o_uses_rs1 <= i_uses_rs1;
            o_uses_rs2 <= i_uses_rs2;
            o_illegal <= i_illegal;
            o_valid <= i_valid;
        end
        // Sin enable, conserva todos los campos.
    end

endmodule

`default_nettype wire
