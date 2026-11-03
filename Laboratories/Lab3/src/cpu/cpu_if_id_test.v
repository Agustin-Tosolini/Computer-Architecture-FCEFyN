`timescale 1ns / 1ps
`default_nettype none

module cpu_if_id_test
(
    input wire i_clk,
    input wire i_reset,
    input wire i_enable,
    input wire i_imem_we,
    input wire [7:0] i_imem_addr,
    input wire [31:0] i_imem_data,
    input wire [4:0] i_dbg_reg_addr,

    // Debug: lectura del banco de registros.
    output wire [31:0] o_dbg_reg_data,        // Dato del registro elegido por debug.

    // IF: busqueda de instrucciones.
    output wire [31:0] o_if_pc,               // PC actual de IF, en bytes.
    output wire [31:0] o_if_instr,            // Instruccion buscada en IF.
    output wire o_if_addr_error,              // PC fuera de rango o desalineado.

    // Registro de pipeline IF/ID (latch): valores almacenados que recibe ID.
    output wire [31:0] o_id_pc,               // PC de la instruccion en ID.
    output wire [31:0] o_id_instr,            // Instruccion a decodificar.
    output wire o_id_valid,                   // 1=instruccion presente; 0=burbuja.

    // ID: datos y operandos decodificados (sin registro ID/EX todavia).
    output wire [31:0] o_id_imm,              // Inmediato reconstruido de 32 bits.
    output wire [4:0] o_id_rs1,               // Numero del registro fuente rs1.
    output wire [4:0] o_id_rs2,               // Numero del registro fuente rs2.
    output wire [4:0] o_id_rd,                // Numero del registro destino rd.
    output wire [31:0] o_id_rs1_data,         // Valor leido de rs1.
    output wire [31:0] o_id_rs2_data,         // Valor leido de rs2.

    // ID: controles combinacionales de la instruccion.
    output wire o_id_reg_write,               // Solicita escribir rd.
    output wire o_id_alu_src_a,               // Operando A: 0=rs1; 1=cero.
    output wire o_id_alu_src_b,               // Operando B: 0=rs2; 1=inmediato.
    output wire o_id_mem_read,                // Solicita leer memoria de datos.
    output wire o_id_mem_write,               // Solicita escribir memoria de datos.
    output wire o_id_result_src,              // Resultado: 0=EX; 1=memoria.
    output wire o_id_branch,                  // Reconoce BEQ/BNE.
    output wire o_id_jump,                    // Reconoce JAL/JALR.
    output wire o_id_jalr,                    // Reconoce JALR.
    output wire [1:0] o_id_alu_op,            // 00=suma; 01=resta; 10=R; 11=aritmetica I.
    output wire o_id_halt,                    // Reconoce HALT; aun no detiene la CPU.
    output wire o_id_uses_rs1,                // La instruccion utiliza rs1.
    output wire o_id_uses_rs2,                // La instruccion utiliza rs2.
    output wire o_id_illegal                  // Instruccion presente no soportada.
);
    wire [31:0] pc_next = o_if_pc + 32'd4;
    wire [31:0] mem_instr;
    assign o_if_addr_error = (o_if_pc[31:10] != 22'd0) ||
                             (o_if_pc[1:0] != 2'b00);
    assign o_if_instr = o_if_addr_error ? 32'h0000_0013 : mem_instr;

    pc_reg u_pc (
        .i_clk(i_clk), .i_reset(i_reset), .i_enable(i_enable),
        .i_pc_write(!o_if_addr_error), .i_pc_next(pc_next), .o_pc(o_if_pc)
    );

    instr_mem u_imem (
        .i_clk(i_clk), .i_we(i_imem_we && !i_enable && !i_reset),
        .i_waddr(i_imem_addr), .i_wdata(i_imem_data),
        .i_raddr(o_if_pc[9:2]), .o_rdata(mem_instr)
    );

    if_id u_if_id (
        .i_clk(i_clk), .i_reset(i_reset), .i_enable(i_enable),
        .i_write(1'b1), .i_flush(1'b0), .i_pc(o_if_pc),
        .i_instr(o_if_instr), .i_valid(!o_if_addr_error),
        .o_pc(o_id_pc), .o_instr(o_id_instr), .o_valid(o_id_valid)
    );

    assign o_id_rs1 = o_id_instr[19:15];
    assign o_id_rs2 = o_id_instr[24:20];
    assign o_id_rd  = o_id_instr[11:7];

    reg_file u_regs (
        .i_clk(i_clk), .i_reset(i_reset), .i_enable(i_enable),
        .i_rs1(o_id_rs1), .i_rs2(o_id_rs2),
        .o_rs1_data(o_id_rs1_data), .o_rs2_data(o_id_rs2_data),
        .i_we(1'b0), .i_rd(5'd0), .i_wdata(32'd0),
        .i_dbg_addr(i_dbg_reg_addr), .o_dbg_data(o_dbg_reg_data)
    );

    imm_gen u_imm (.i_instr(o_id_instr), .o_imm(o_id_imm));

    control_unit u_control (
        .i_instr(o_id_instr), .i_valid(o_id_valid),
        .o_reg_write(o_id_reg_write), .o_alu_src_a(o_id_alu_src_a),
        .o_alu_src_b(o_id_alu_src_b), .o_mem_read(o_id_mem_read),
        .o_mem_write(o_id_mem_write), .o_result_src(o_id_result_src),
        .o_branch(o_id_branch), .o_jump(o_id_jump), .o_jalr(o_id_jalr),
        .o_alu_op(o_id_alu_op), .o_halt(o_id_halt),
        .o_uses_rs1(o_id_uses_rs1), .o_uses_rs2(o_id_uses_rs2),
        .o_illegal(o_id_illegal)
    );
endmodule

`default_nettype wire
