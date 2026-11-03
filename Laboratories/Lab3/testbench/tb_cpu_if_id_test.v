`timescale 1ns / 1ps
`default_nettype none

module tb_cpu_if_id_test;
    reg clk = 0;
    always #5 clk = ~clk;
    reg reset = 1, enable = 0, we = 0;
    reg [7:0] addr = 0;
    reg [31:0] data = 0;
    wire [31:0] if_pc, if_instr, id_pc, instr, imm, a, b, dbg;
    wire valid, addr_error, reg_write, src_a, src_b, mem_read, mem_write;
    wire result_src, branch, jump, jalr, halt, uses1, uses2, illegal;
    wire [1:0] alu_op;
    wire [4:0] rs1, rs2, rd;
    integer errors = 0;
    integer k;

    cpu_if_id_test dut (
        .i_clk(clk), .i_reset(reset), .i_enable(enable),
        .i_imem_we(we), .i_imem_addr(addr), .i_imem_data(data),
        .i_dbg_reg_addr(5'd1), .o_dbg_reg_data(dbg),
        .o_if_pc(if_pc), .o_if_instr(if_instr), .o_if_addr_error(addr_error),
        .o_id_pc(id_pc), .o_id_instr(instr), .o_id_valid(valid), .o_id_imm(imm),
        .o_id_rs1(rs1), .o_id_rs2(rs2), .o_id_rd(rd),
        .o_id_rs1_data(a), .o_id_rs2_data(b),
        .o_id_reg_write(reg_write), .o_id_alu_src_a(src_a),
        .o_id_alu_src_b(src_b), .o_id_mem_read(mem_read),
        .o_id_mem_write(mem_write), .o_id_result_src(result_src),
        .o_id_branch(branch), .o_id_jump(jump), .o_id_jalr(jalr),
        .o_id_alu_op(alu_op), .o_id_halt(halt),
        .o_id_uses_rs1(uses1), .o_id_uses_rs2(uses2), .o_id_illegal(illegal)
    );

    task check;
        input [8*60-1:0] label;
        input [31:0] got, expected;
        begin
            if (got !== expected) begin
                $display("ERROR %0s: %h != %h", label, got, expected);
                errors = errors + 1;
            end
        end
    endtask

    task load_word;
        input [7:0] word_addr;
        input [31:0] word_data;
        begin
            @(negedge clk); addr = word_addr; data = word_data; we = 1;
            @(negedge clk); we = 0;
        end
    endtask

    task step;
        begin
            @(negedge clk); enable = 1;
            @(negedge clk); enable = 0;
            #1;
        end
    endtask

    initial begin
        @(negedge clk); reset = 0;
        check("PC reset", if_pc, 0);
        check("burbuja reset", valid, 0);
        check("NOP reset", instr, 32'h13);
        check("sin HALT falso", halt, 0);

        load_word(0, 32'hFFF00093); // addi x1,x0,-1
        load_word(1, 32'h00C12203); // lw x4,12(x2)
        load_word(2, 32'h00412423); // sw x4,8(x2)
        load_word(3, 32'h00000463); // beq x0,x0,+8
        load_word(4, 32'h00000000); // HALT: se observa, no se ejecuta
        load_word(5, 32'hFFFFFFFF); // no soportada
        check("carga no avanza PC", if_pc, 0);
        check("carga no modifica ID", valid, 0);
        check("lectura IF", if_instr, 32'hFFF00093);

        step;
        check("primer IF PC", if_pc, 4);
        check("primer ID PC", id_pc, 0);
        check("ADDI capturado", instr, 32'hFFF00093);
        check("ID valido", valid, 1);
        check("inmediato negativo", imm, 32'hFFFFFFFF);
        check("categoria inmediata", alu_op, 3);
        check("ADDI controles", {reg_write, src_b, uses1, uses2}, 4'b1110);
        check("destino", rd, 1);
        check("sin ejecucion WB", dbg, 0);

        repeat (4) @(negedge clk);
        check("pausa PC", if_pc, 4);
        check("pausa ID", instr, 32'hFFF00093);

        // Intentar pisar la siguiente instruccion mientras se avanza: se ignora.
        @(negedge clk); enable = 1; we = 1; addr = 1; data = 0;
        @(negedge clk); enable = 0; we = 0; #1;
        check("LW capturado", instr, 32'h00C12203);
        check("LW PC", id_pc, 4);
        check("LW inmediato", imm, 12);
        check("LW controles", {reg_write, mem_read, mem_write, result_src}, 4'b1101);
        check("LW fuente", rs1, 2);
        check("operando cero", a, 0);

        step;
        check("SW inmediato", imm, 8);
        check("SW controles", {reg_write, mem_write, uses1, uses2}, 4'b0111);
        check("SW fuente dato", rs2, 4);
        check("dato store cero", b, 0);
        step;
        check("BEQ reconocido", branch, 1);
        check("BEQ desplazamiento", imm, 8);
        check("BEQ resta", alu_op, 1);
        step;
        check("no se ejecuta salto", id_pc, 16);
        check("HALT reconocido", halt, 1);
        step;
        check("HALT no detiene prueba", id_pc, 20);
        check("ilegal reconocida", illegal, 1);
        check("ilegal sin efectos", {reg_write, mem_write, mem_read, jump, branch, halt}, 0);

        // Reset conserva programa, invalida ID y limpia banco.
        @(negedge clk); reset = 1;
        @(negedge clk); reset = 0; #1;
        check("reset PC", if_pc, 0);
        check("reset ID", valid, 0);
        check("programa conservado", if_instr, 32'hFFF00093);
        step; step;
        check("escritura en marcha rechazada", instr, 32'h00C12203);

        // Recorrer hasta el limite sin ejecutar ninguna de las instrucciones.
        for (k = 2; k < 256; k = k + 1) step;
        check("ultima direccion ID", id_pc, 1020);
        check("ultimo fetch valido", valid, 1);
        check("PC fuera de memoria", if_pc, 1024);
        check("error de rango", addr_error, 1);
        step;
        check("PC no vuelve a cero", if_pc, 1024);
        check("fuera de rango es burbuja", valid, 0);
        check("burbuja sin HALT", halt, 0);

        if (errors != 0) $fatal(1, "FAIL: %0d errores", errors);
        $display("PASS: integracion IF/ID");
        $finish;
    end

    initial begin
        #100000;
        $fatal(1, "Timeout global");
    end
endmodule

`default_nettype wire
