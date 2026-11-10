`timescale 1ns / 1ps
`default_nettype none

// Control principal combinacional (etapa ID).
// Recibe la instruccion completa para validar tambien funct3/funct7 y HALT.
// Una burbuja o codificacion no soportada deja todas las salidas en cero.
// No implementa traps: o_illegal informa una instruccion valida no soportada.
module control_unit
(
    input  wire [31:0] i_instr,
    input  wire        i_valid,
    output reg         o_reg_write,
    output reg         o_alu_src_a, // 0: rs1 adelantado; 1: cero.
    output reg         o_alu_src_b, // 0: rs2 adelantado; 1: inmediato.
    output reg         o_mem_read,
    output reg         o_mem_write,
    output reg         o_result_src, // WB: 0 resultado EX; 1 dato de memoria.
    output reg         o_branch,
    output reg         o_jump,
    output reg         o_jalr,
    output reg [1:0]   o_alu_op,
    output reg         o_halt,
    output reg         o_uses_rs1,
    output reg         o_uses_rs2,
    output wire        o_illegal
);
    localparam [6:0] OP_REG = 7'b0110011,
                     OP_IMM = 7'b0010011,
                     LOAD   = 7'b0000011,
                     STORE  = 7'b0100011,
                     BRANCH = 7'b1100011,
                     JAL    = 7'b1101111,
                     JALR   = 7'b1100111,
                     LUI    = 7'b0110111;

    wire [6:0] opcode = i_instr[6:0];
    wire [2:0] funct3 = i_instr[14:12];
    wire [6:0] funct7 = i_instr[31:25];
    reg supported;

    // Reconocer solo las codificaciones del subconjunto implementado.
    // Por ejemplo MUL no debe confundirse con ADD por compartir funct3.
    always @(*) begin
        supported = 1'b0;
        case (opcode)
            OP_REG: supported = (funct7 == 7'b0000000) ||
                                ((funct7 == 7'b0100000) &&
                                 (funct3 == 3'b000 || funct3 == 3'b101));
            OP_IMM: begin
                case (funct3)
                    3'b001: supported = (funct7 == 7'b0000000);
                    3'b101: supported = (funct7 == 7'b0000000 ||
                                         funct7 == 7'b0100000);
                    default: supported = 1'b1;
                endcase
            end
            LOAD: supported = (funct3 == 3'b000 || funct3 == 3'b001 ||
                               funct3 == 3'b010 || funct3 == 3'b100 ||
                               funct3 == 3'b101);
            STORE: supported = (funct3 == 3'b000 || funct3 == 3'b001 ||
                                funct3 == 3'b010);
            BRANCH: supported = (funct3 == 3'b000 || funct3 == 3'b001);
            JAL, LUI: supported = 1'b1;
            JALR: supported = (funct3 == 3'b000);
            default: supported = (i_instr == 32'h0000_0000);
        endcase
    end

    assign o_illegal = i_valid && !supported;

    always @(*) begin
        o_reg_write = 1'b0;
        o_alu_src_a = 1'b0;
        o_alu_src_b = 1'b0;
        o_mem_read = 1'b0;
        o_mem_write = 1'b0;
        o_result_src = 1'b0;
        o_branch = 1'b0;
        o_jump = 1'b0;
        o_jalr = 1'b0;
        o_alu_op = 2'b00;
        o_halt = 1'b0;
        o_uses_rs1 = 1'b0;
        o_uses_rs2 = 1'b0;

        if (i_valid && supported) begin
            case (opcode)
                OP_REG: begin
                    o_reg_write = 1'b1;
                    o_uses_rs1 = 1'b1;
                    o_uses_rs2 = 1'b1;
                    o_alu_op = 2'b10;
                end
                OP_IMM: begin
                    o_reg_write = 1'b1;
                    o_alu_src_b = 1'b1;
                    o_uses_rs1 = 1'b1;
                    o_alu_op = 2'b11;
                end
                LOAD: begin
                    o_reg_write = 1'b1;
                    o_alu_src_b = 1'b1;
                    o_mem_read = 1'b1;
                    o_result_src = 1'b1;
                    o_uses_rs1 = 1'b1;
                end
                STORE: begin
                    o_alu_src_b = 1'b1;
                    o_mem_write = 1'b1;
                    o_uses_rs1 = 1'b1;
                    o_uses_rs2 = 1'b1; // rs2 es el dato a guardar, no la direccion.
                end
                BRANCH: begin
                    o_branch = 1'b1;
                    o_uses_rs1 = 1'b1;
                    o_uses_rs2 = 1'b1;
                    o_alu_op = 2'b01;
                end
                JAL: begin
                    o_reg_write = 1'b1;
                    o_jump = 1'b1;
                end
                JALR: begin
                    o_reg_write = 1'b1;
                    o_jump = 1'b1;
                    o_jalr = 1'b1;
                    o_alu_src_b = 1'b1;
                    o_uses_rs1 = 1'b1;
                end
                LUI: begin
                    o_reg_write = 1'b1;
                    o_alu_src_a = 1'b1;
                    o_alu_src_b = 1'b1;
                end
                default: o_halt = 1'b1; // Solo queda HALT exacto, ya validado.
            endcase
        end
    end
endmodule

`default_nettype wire

//------------------------------------------------------------------------------
// Referencia rapida
// i_instr      : instruccion completa de IF/ID.
// i_valid      : 0 significa burbuja; no generar efectos ni HALT.
// o_reg_write  : solicitar escritura del registro destino en WB.
// o_alu_src_a  : seleccionar rs1 (0) o cero (1) como operando A.
// o_alu_src_b  : seleccionar rs2 (0) o inmediato (1) como operando B.
// o_mem_read   : solicitar lectura de memoria de datos.
// o_mem_write  : solicitar escritura de memoria de datos.
// o_result_src : elegir resultado EX (0) o dato de memoria (1) en WB.
// o_branch     : salto condicional; EX distingue BEQ/BNE mediante funct3.
// o_jump       : salto incondicional; EX selecciona PC+4 como resultado.
// o_jalr       : destino (rs1+imm)&~1, en vez de PC+imm.
// o_alu_op     : categoria para alu_control (00 suma, 01 resta, 10 R, 11 I).
// o_halt       : instruccion HALT valida; la CPU debe drenar el pipeline.
// o_uses_rs1/2 : indica fuentes reales para evitar stalls por falsos operandos.
// o_illegal    : instruccion no soportada; politica de parada/trap pendiente.
//
// Familia   | ALUOp | Accion principal
// ----------|-------|-----------------------------------------------------------
// R         | 10    | Calcular entre registros y escribir rd.
// I aritm.  | 11    | Calcular con inmediato y escribir rd.
// LOAD      | 00    | Sumar direccion, leer memoria y escribir rd.
// STORE     | 00    | Sumar direccion y guardar rs2 en memoria.
// BRANCH    | 01    | Restar para comparar; decidir salto en EX.
// JAL       | 00*   | Saltar a PC+imm y devolver PC+4.
// JALR      | 00    | Sumar destino; devolver PC+4 como resultado de EX.
// LUI       | 00    | Sumar cero al inmediato superior.
// HALT      | 00*   | Solicitar parada con vaciado del pipeline.
// * El resultado de la ALU no se utiliza.
//------------------------------------------------------------------------------
