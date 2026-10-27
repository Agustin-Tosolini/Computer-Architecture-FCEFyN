`timescale 1ns / 1ps
`default_nettype none

//------------------------------------------------------------------------------
// Generador combinacional de inmediatos RV32.
// El opcode selecciona como reconstruir el inmediato de 32 bits.
// No valida la instruccion completa: esa tarea corresponde al control.
//------------------------------------------------------------------------------
module imm_gen
(
    input  wire [31:0] i_instr,
    output reg  [31:0] o_imm
);
    localparam [6:0] OP_IMM = 7'b0010011,
                     LOAD   = 7'b0000011,
                     JALR   = 7'b1100111,
                     STORE  = 7'b0100011,
                     BRANCH = 7'b1100011,
                     LUI    = 7'b0110111,
                     JAL    = 7'b1101111;

    always @(*) begin
        o_imm = 32'd0;
        case (i_instr[6:0])
            // I: inmediato de 12 bits con extension de signo.
            // En shifts inmediatos, la ALU usa solo o_imm[4:0].
            OP_IMM, LOAD, JALR:
                o_imm = {{20{i_instr[31]}}, i_instr[31:20]};

            // S: el inmediato esta dividido alrededor de rs1/rs2/funct3.
            STORE:
                o_imm = {{20{i_instr[31]}}, i_instr[31:25], i_instr[11:7]};

            // B: desplazamiento en bytes; el bit 0 es implicitamente cero.
            BRANCH:
                o_imm = {{19{i_instr[31]}}, i_instr[31], i_instr[7],
                         i_instr[30:25], i_instr[11:8], 1'b0};

            // U: inmediato en los 20 bits superiores y 12 ceros inferiores.
            LUI:
                o_imm = {i_instr[31:12], 12'b0};

            // J: reordena los campos y agrega el bit 0 implicito.
            JAL:
                o_imm = {{11{i_instr[31]}}, i_instr[31], i_instr[19:12],
                         i_instr[20], i_instr[30:21], 1'b0};

            // Tipo R, HALT y opcodes no soportados no aportan inmediato.
            default: o_imm = 32'd0;
        endcase
    end
endmodule

`default_nettype wire

//------------------------------------------------------------------------------
// Referencia rapida
// Senal / formato | Funcion
// ----------------|------------------------------------------------------------
// i_instr         | Entrada: instruccion completa de 32 bits.
// o_imm           | Salida: inmediato reconstruido de 32 bits.
// I               | Aritmetica inmediata, loads y JALR: extiende 12 bits.
// S               | Stores: une dos campos y extiende el signo.
// B               | Branches: reconstruye el desplazamiento con signo.
// U               | LUI: coloca 20 bits arriba y completa abajo con ceros.
// J               | JAL: reconstruye el desplazamiento con signo.
// Otros           | Devuelve cero; no indica si la instruccion es valida.
// B/J ya salen en bytes: no desplazar otra vez antes de sumarlos al PC.
//------------------------------------------------------------------------------
