`timescale 1ns / 1ps
`default_nettype none

//------------------------------------------------------------------------------
// tb_traza — Traza ciclo a ciclo del cpu real (sin UART), para comparar el
// simulador de Python (scripts/gui/pipeline_sim.py) bit por bit.
//
// Lo usa scripts/gui/tests/test_pipeline_sim.py (no es parte de testbench/).
//
// Carga el programa (+PROG, +N palabras; el resto HALT), precarga la memoria
// de datos con +MEM (32 palabras, opcional) por referencia jerarquica, hace un
// reset y da +CICLOS ciclos habilitados. Despues de cada ciclo (y en el ciclo
// 0) escribe una linea en +SALIDA:
//   <ciclo> <pc> <halted> <fault> <latches 480 bits> <x0..x31> <mem0..mem31>
//------------------------------------------------------------------------------
module tb_traza;

    reg clk = 1'b0;
    always #5 clk = ~clk;

    reg         rst = 1'b0, en = 1'b0, we = 1'b0;
    reg  [7:0]  wa = 8'd0;
    reg  [31:0] wd = 32'd0;
    reg  [4:0]  ra = 5'd0;
    wire [31:0] rdat, mdat, pc;
    wire [479:0] lat;
    wire        halted, fault;

    cpu dut (.i_clk(clk), .i_cpu_reset(rst), .i_enable(en), .i_imem_we(we),
             .i_imem_addr(wa), .i_imem_data(wd), .i_dbg_reg_addr(ra), .o_dbg_reg_data(rdat),
             .i_dbg_mem_addr(8'd0), .o_dbg_mem_data(mdat), .o_pc(pc), .o_latches(lat),
             .o_halted(halted), .o_fault(fault));

    reg [31:0] prog [0:255];
    reg [31:0] memi [0:31];
    integer n, ciclos, salida, i, k;
    reg [8*256-1:0] f_prog, f_mem, f_sal;

    task anotar(input integer c);
        begin
            $fwrite(salida, "%0d %h %0d %0d %h", c, pc, halted, fault, lat);
            for (k = 0; k < 32; k = k + 1) begin
                ra = k[4:0];
                #0.1;
                $fwrite(salida, " %h", rdat);
            end
            for (k = 0; k < 32; k = k + 1)
                $fwrite(salida, " %h", dut.u_dmem.mem[k]);
            $fwrite(salida, "\n");
        end
    endtask

    initial begin
        if (!$value$plusargs("PROG=%s", f_prog) || !$value$plusargs("N=%d", n) ||
            !$value$plusargs("CICLOS=%d", ciclos) || !$value$plusargs("SALIDA=%s", f_sal)) begin
            $display("FAIL: faltan +PROG, +N, +CICLOS o +SALIDA");
            $finish;
        end
        for (i = 0; i < 256; i = i + 1) prog[i] = 32'd0;
        if (n > 0) $readmemh(f_prog, prog, 0, n - 1);
        if ($value$plusargs("MEM=%s", f_mem)) begin
            $readmemh(f_mem, memi, 0, 31);
            for (i = 0; i < 32; i = i + 1) dut.u_dmem.mem[i] = memi[i];
        end
        salida = $fopen(f_sal, "w");
        for (i = 0; i < 256; i = i + 1) begin
            @(negedge clk);
            wa = i[7:0]; wd = (i == 255) ? 32'd0 : prog[i]; we = 1'b1;
        end
        @(negedge clk); we = 1'b0; rst = 1'b1;
        @(negedge clk); rst = 1'b0;
        anotar(0);
        for (i = 1; i <= ciclos; i = i + 1) begin
            @(negedge clk); en = 1'b1;
            @(posedge clk); #1;
            @(negedge clk); en = 1'b0;
            anotar(i);
        end
        $fclose(salida);
        $display("PASS: traza terminada");
        $finish;
    end
endmodule

`default_nettype wire
