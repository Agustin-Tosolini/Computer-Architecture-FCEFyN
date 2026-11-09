`timescale 1ns / 1ps
`default_nettype none

// CPU RV32 de cinco etapas. Puertos compatibles con el contrato de debug.
module cpu (
    input wire i_clk,                    // Reloj sin compuertas.
    input wire i_cpu_reset,              // Reinicia CPU; conserva ambas memorias.
    input wire i_enable,                 // Avanza un ciclo; cero pausa todo.
    input wire i_imem_we,                // Carga programa durante pausa.
    input wire [7:0] i_imem_addr,         // Palabra de programa 0..255.
    input wire [31:0] i_imem_data,        // Instruccion a cargar.
    input wire [4:0] i_dbg_reg_addr,      // Registro a consultar.
    output wire [31:0] o_dbg_reg_data,    // Contenido almacenado del registro.
    input wire [7:0] i_dbg_mem_addr,      // Palabra de datos 0..31.
    output wire [31:0] o_dbg_mem_data,    // Contenido de memoria de datos.
    output wire [31:0] o_pc,             // PC de busqueda, en bytes.
    output wire [383:0] o_latches,       // Estado de los cuatro registros intermedios.
    output reg o_halted                  // Parada completada; requiere reset.
);
    reg halting;
    wire step = i_enable && !o_halted;
    wire [31:0] id_pc;
    wire [31:0] id_instr;
    wire  id_valid;
    wire [31:0] ex_pc;
    wire [31:0] ex_rs1_data;
    wire [31:0] ex_rs2_data;
    wire [31:0] ex_imm;
    wire [4:0] ex_rs1;
    wire [4:0] ex_rs2;
    wire [4:0] ex_rd;
    wire [2:0] ex_funct3;
    wire  ex_funct7_b5;
    wire  ex_reg_write;
    wire  ex_alu_src_a;
    wire  ex_alu_src_b;
    wire  ex_mem_read;
    wire  ex_mem_write;
    wire  ex_result_src;
    wire  ex_branch;
    wire  ex_jump;
    wire  ex_jalr;
    wire [1:0] ex_alu_op;
    wire  ex_halt;
    wire  ex_uses_rs1;
    wire  ex_uses_rs2;
    wire  ex_illegal;
    wire  ex_valid;
    wire [31:0] mem_result;
    wire [31:0] mem_store_data;
    wire [4:0] mem_rd;
    wire [2:0] mem_funct3;
    wire  mem_reg_write;
    wire  mem_mem_read;
    wire  mem_mem_write;
    wire  mem_result_src;
    wire  mem_halt;
    wire  mem_illegal;
    wire  mem_valid;
    wire [31:0] wb_result;
    wire [31:0] wb_mem_data;
    wire [4:0] wb_rd;
    wire  wb_reg_write;
    wire  wb_result_src;
    wire  wb_halt;
    wire  wb_illegal;
    wire  wb_valid;

    // ID: controles decodificados y lectura con bypass WB -> ID.
    wire dec_reg_write;
    wire dec_alu_src_a;
    wire dec_alu_src_b;
    wire dec_mem_read;
    wire dec_mem_write;
    wire dec_result_src;
    wire dec_branch;
    wire dec_jump;
    wire dec_jalr;
    wire [1:0] dec_alu_op;
    wire dec_halt;
    wire dec_uses_rs1;
    wire dec_uses_rs2;
    wire dec_illegal;
    wire [4:0] id_rs1 = id_instr[19:15];
    wire [4:0] id_rs2 = id_instr[24:20];
    wire [4:0] id_rd = id_instr[11:7];
    wire [31:0] id_rs1_data, id_rs2_data, id_imm;
    wire [31:0] wb_data = wb_result_src ? wb_mem_data : wb_result;
    wire wb_write = wb_valid && wb_reg_write && !wb_illegal;
    wire [31:0] fetched_instr;
    wire fetch_error = (o_pc[31:10] != 0) || (o_pc[1:0] != 0);
    // Una direccion de fetch invalida entra como instruccion ilegal, sin alias.
    wire [31:0] if_instr = fetch_error ? 32'hFFFFFFFF : fetched_instr;
    wire pc_write, if_write, if_flush, ex_flush;
    wire [1:0] forward_a, forward_b;
    wire [31:0] ex_rs1_value = forward_a == 2'b10 ? mem_result :
                               forward_a == 2'b01 ? wb_data : ex_rs1_data;
    wire [31:0] ex_rs2_value = forward_b == 2'b10 ? mem_result :
                               forward_b == 2'b01 ? wb_data : ex_rs2_data;
    wire [31:0] alu_a = ex_alu_src_a ? 32'd0 : ex_rs1_value;
    wire [31:0] alu_b = ex_alu_src_b ? ex_imm : ex_rs2_value;
    wire [3:0] alu_op;
    wire [31:0] alu_result;
    wire alu_zero;
    wire branch_taken = ex_branch && ((ex_funct3 == 3'b000 && alu_zero) ||
                                       (ex_funct3 == 3'b001 && !alu_zero));
    wire redirect = ex_valid && !ex_illegal && (ex_jump || branch_taken);
    wire [31:0] jalr_target = (ex_rs1_value + ex_imm) & 32'hFFFFFFFE;
    wire [31:0] target = ex_jalr ? jalr_target : ex_pc + ex_imm;
    wire [31:0] ex_result = ex_jump ? ex_pc + 32'd4 : alu_result;
    wire [31:0] mem_data;
    wire mem_error;
    // Fallo de memoria: conservar escrituras anteriores y descartar las posteriores.
    wire mem_fault = mem_valid && mem_error;
    wire stop_id = id_valid && (dec_halt || dec_illegal) &&
                   !redirect && !mem_fault && !halting;
    wire [31:0] pc_next = redirect ? target : o_pc + 32'd4;

    always @(posedge i_clk) begin
        if (i_cpu_reset) begin
            halting <= 1'b0;
            o_halted <= 1'b0;
        end
        else if (step) begin
            if (stop_id || mem_fault) halting <= 1'b1;
            // En este flanco sale el marcador de WB y quedan todas las etapas vacias.
            if (wb_valid && wb_halt) o_halted <= 1'b1;
        end
    end

    // IF: seleccion de PC y memoria de programa.
    pc_reg u_pc (.i_clk(i_clk), .i_reset(i_cpu_reset), .i_enable(step),
        .i_pc_write(pc_write && (redirect || !fetch_error) && !halting && !stop_id && !mem_fault),
        .i_pc_next(pc_next), .o_pc(o_pc));
    instr_mem u_imem (.i_clk(i_clk),
        .i_we(i_imem_we && !i_enable && !i_cpu_reset),
        .i_waddr(i_imem_addr), .i_wdata(i_imem_data),
        .i_raddr(o_pc[9:2]), .o_rdata(fetched_instr));
    reg_file u_regs (.i_clk(i_clk), .i_reset(i_cpu_reset), .i_enable(step),
        .i_rs1(id_rs1), .i_rs2(id_rs2), .o_rs1_data(id_rs1_data), .o_rs2_data(id_rs2_data),
        .i_we(wb_write), .i_rd(wb_rd), .i_wdata(wb_data),
        .i_dbg_addr(i_dbg_reg_addr), .o_dbg_data(o_dbg_reg_data));
    imm_gen u_imm (.i_instr(id_instr), .o_imm(id_imm));
    control_unit u_control (.i_instr(id_instr), .i_valid(id_valid),
        .o_reg_write(dec_reg_write),
        .o_alu_src_a(dec_alu_src_a),
        .o_alu_src_b(dec_alu_src_b),
        .o_mem_read(dec_mem_read),
        .o_mem_write(dec_mem_write),
        .o_result_src(dec_result_src),
        .o_branch(dec_branch),
        .o_jump(dec_jump),
        .o_jalr(dec_jalr),
        .o_alu_op(dec_alu_op),
        .o_halt(dec_halt),
        .o_uses_rs1(dec_uses_rs1),
        .o_uses_rs2(dec_uses_rs2),
        .o_illegal(dec_illegal));

    if_id u_if_id (
        .i_clk(i_clk),
        .i_reset(i_cpu_reset),
        .i_enable(step),
        .i_write(if_write),
        .i_flush(if_flush || stop_id || halting || mem_fault),
        .i_pc(o_pc),
        .i_instr(if_instr),
        .i_valid(!halting),
        .o_pc(id_pc),
        .o_instr(id_instr),
        .o_valid(id_valid));

    id_ex u_id_ex (
        .i_clk(i_clk),
        .i_reset(i_cpu_reset),
        .i_enable(step),
        .i_flush(ex_flush || mem_fault),
        .i_pc(id_pc),
        .i_rs1_data(id_rs1_data),
        .i_rs2_data(id_rs2_data),
        .i_imm(id_imm),
        .i_rs1(id_rs1),
        .i_rs2(id_rs2),
        .i_rd(id_rd),
        .i_funct3(id_instr[14:12]),
        .i_funct7_b5(id_instr[30]),
        .i_reg_write(dec_reg_write),
        .i_alu_src_a(dec_alu_src_a),
        .i_alu_src_b(dec_alu_src_b),
        .i_mem_read(dec_mem_read),
        .i_mem_write(dec_mem_write),
        .i_result_src(dec_result_src),
        .i_branch(dec_branch),
        .i_jump(dec_jump),
        .i_jalr(dec_jalr),
        .i_alu_op(dec_alu_op),
        .i_halt(dec_halt || dec_illegal),
        .i_uses_rs1(dec_uses_rs1),
        .i_uses_rs2(dec_uses_rs2),
        .i_illegal(dec_illegal),
        .i_valid(id_valid && !halting),
        .o_pc(ex_pc),
        .o_rs1_data(ex_rs1_data),
        .o_rs2_data(ex_rs2_data),
        .o_imm(ex_imm),
        .o_rs1(ex_rs1),
        .o_rs2(ex_rs2),
        .o_rd(ex_rd),
        .o_funct3(ex_funct3),
        .o_funct7_b5(ex_funct7_b5),
        .o_reg_write(ex_reg_write),
        .o_alu_src_a(ex_alu_src_a),
        .o_alu_src_b(ex_alu_src_b),
        .o_mem_read(ex_mem_read),
        .o_mem_write(ex_mem_write),
        .o_result_src(ex_result_src),
        .o_branch(ex_branch),
        .o_jump(ex_jump),
        .o_jalr(ex_jalr),
        .o_alu_op(ex_alu_op),
        .o_halt(ex_halt),
        .o_uses_rs1(ex_uses_rs1),
        .o_uses_rs2(ex_uses_rs2),
        .o_illegal(ex_illegal),
        .o_valid(ex_valid));

    ex_mem u_ex_mem (
        .i_clk(i_clk),
        .i_reset(i_cpu_reset),
        .i_enable(step),
        .i_result(ex_result),
        .i_store_data(ex_rs2_value),
        .i_rd(ex_rd),
        .i_funct3(ex_funct3),
        .i_reg_write(ex_reg_write),
        .i_mem_read(ex_mem_read),
        .i_mem_write(ex_mem_write),
        .i_result_src(ex_result_src),
        .i_halt(ex_halt),
        .i_illegal(ex_illegal),
        .i_valid(ex_valid && !mem_fault),
        .o_result(mem_result),
        .o_store_data(mem_store_data),
        .o_rd(mem_rd),
        .o_funct3(mem_funct3),
        .o_reg_write(mem_reg_write),
        .o_mem_read(mem_mem_read),
        .o_mem_write(mem_mem_write),
        .o_result_src(mem_result_src),
        .o_halt(mem_halt),
        .o_illegal(mem_illegal),
        .o_valid(mem_valid));

    mem_wb u_mem_wb (
        .i_clk(i_clk),
        .i_reset(i_cpu_reset),
        .i_enable(step),
        .i_result(mem_result),
        .i_mem_data(mem_data),
        .i_rd(mem_rd),
        .i_reg_write(mem_reg_write && !mem_fault),
        .i_result_src(mem_result_src),
        .i_halt(mem_halt || mem_fault),
        .i_illegal(mem_illegal),
        .i_valid(mem_valid),
        .o_result(wb_result),
        .o_mem_data(wb_mem_data),
        .o_rd(wb_rd),
        .o_reg_write(wb_reg_write),
        .o_result_src(wb_result_src),
        .o_halt(wb_halt),
        .o_illegal(wb_illegal),
        .o_valid(wb_valid));

    // EX: forwarding antes de los mux de ALU y del dato de STORE.
    forwarding_unit u_forwarding (
        .i_ex_valid(ex_valid), .i_ex_uses_rs1(ex_uses_rs1), .i_ex_uses_rs2(ex_uses_rs2),
        .i_ex_rs1(ex_rs1), .i_ex_rs2(ex_rs2),
        .i_mem_valid(mem_valid), .i_mem_reg_write(mem_reg_write),
        .i_mem_result_src(mem_result_src), .i_mem_rd(mem_rd),
        .i_wb_valid(wb_valid), .i_wb_reg_write(wb_write), .i_wb_rd(wb_rd),
        .o_forward_a(forward_a), .o_forward_b(forward_b));
    alu_control u_alu_control (.i_alu_op(ex_alu_op), .i_funct3(ex_funct3),
        .i_funct7_b5(ex_funct7_b5), .o_alu_ctrl(alu_op));
    alu u_alu (.i_a(alu_a), .i_b(alu_b), .i_op(alu_op),
        .o_result(alu_result), .o_zero(alu_zero));
    hazard_unit u_hazard (
        .i_id_valid(id_valid), .i_id_uses_rs1(dec_uses_rs1), .i_id_uses_rs2(dec_uses_rs2),
        .i_id_rs1(id_rs1), .i_id_rs2(id_rs2), .i_ex_valid(ex_valid),
        .i_ex_mem_read(ex_mem_read), .i_ex_reg_write(ex_reg_write), .i_ex_rd(ex_rd),
        .i_ex_redirect(redirect), .o_pc_write(pc_write), .o_if_id_write(if_write),
        .o_if_id_flush(if_flush), .o_id_ex_flush(ex_flush));

    // MEM: 32 palabras; WB usa el mux wb_data y el puerto de escritura de u_regs.
    data_mem u_dmem (.i_clk(i_clk), .i_reset(i_cpu_reset), .i_enable(step),
        .i_addr(mem_result), .i_wdata(mem_store_data),
        .i_re(mem_valid && mem_mem_read), .i_we(mem_valid && mem_mem_write),
        .i_funct3(mem_funct3), .o_rdata(mem_data), .o_access_error(mem_error),
        .i_dbg_addr(i_dbg_mem_addr), .o_dbg_data(o_dbg_mem_data));

    // Contrato de 384 bits: 3 ceros + IF/ID(65) + ID/EX(163) + EX/MEM(79) + MEM/WB(74).
    // Dentro de cada bloque, campos en el orden de sus salidas declaradas.
    wire [64:0] snapshot_id = {id_pc, id_instr, id_valid};
    wire [162:0] snapshot_ex = {ex_pc, ex_rs1_data, ex_rs2_data, ex_imm, ex_rs1, ex_rs2, ex_rd, ex_funct3, ex_funct7_b5, ex_reg_write, ex_alu_src_a, ex_alu_src_b, ex_mem_read, ex_mem_write, ex_result_src, ex_branch, ex_jump, ex_jalr, ex_alu_op, ex_halt, ex_uses_rs1, ex_uses_rs2, ex_illegal, ex_valid};
    wire [78:0] snapshot_mem = {mem_result, mem_store_data, mem_rd, mem_funct3, mem_reg_write, mem_mem_read, mem_mem_write, mem_result_src, mem_halt, mem_illegal, mem_valid};
    wire [73:0] snapshot_wb = {wb_result, wb_mem_data, wb_rd, wb_reg_write, wb_result_src, wb_halt, wb_illegal, wb_valid};
    assign o_latches = {3'd0, snapshot_id, snapshot_ex, snapshot_mem, snapshot_wb};
endmodule

`default_nettype wire
