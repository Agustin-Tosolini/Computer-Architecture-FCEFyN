`timescale 1ns / 1ps
`default_nettype none
module tb_cpu;
    reg clk=0;
    always #5 clk=~clk;
    reg reset=1, enable=0, imem_we=0;
    reg [7:0] imem_addr=0, mem_addr=0;
    reg [31:0] imem_data=0;
    reg [4:0] reg_addr=0;
    wire [31:0] reg_data, mem_data, pc;
    wire [479:0] latches;
    wire halted, fault;
    integer cycles, stalls, k;
    reg [511:0] saved;
    // Patrones de los latches (480 bits, params.vh seccion 4b).
    // Reset: todo en cero salvo IF/ID.instr = NOP.
    localparam [479:0] LAT_RESET = {32'd0, 32'h13, 32'd0, 384'd0};
    // Parada: igual que el reset, pero MEM/WB conserva el marcador de parada
    // (bit 0 valid, bit 2 halt; bit 1 illegal solo si fue por error).
    cpu dut (.i_clk(clk), .i_cpu_reset(reset), .i_enable(enable),
        .i_imem_we(imem_we), .i_imem_addr(imem_addr), .i_imem_data(imem_data),
        .i_dbg_reg_addr(reg_addr), .o_dbg_reg_data(reg_data),
        .i_dbg_mem_addr(mem_addr), .o_dbg_mem_data(mem_data),
        .o_pc(pc), .o_latches(latches), .o_halted(halted), .o_fault(fault));
    task check;
        input [31:0] got, expected;
        begin if (got !== expected) $fatal(1,"CPU got %h expected %h pc=%h",got,expected,pc); end
    endtask
    task put;
        input [7:0] address;
        input [31:0] word;
        begin
            @(negedge clk); imem_addr=address; imem_data=word; imem_we=1;
            @(posedge clk); #1;
            @(negedge clk); imem_we=0;
        end
    endtask
    task restart;
        begin
            @(negedge clk); enable=0; reset=1;
            @(posedge clk); #1; check(pc,0); check(halted,0); check(fault,0);
            if (latches !== LAT_RESET) $fatal(1,"reset latches");
            @(negedge clk); reset=0;
        end
    endtask
    task run_program;
        input pause_each_cycle;
        input expect_fault;
        begin
            cycles=0; stalls=0;
            while (!halted && cycles<400) begin
                @(negedge clk); enable=1;
                #1; if (!dut.pc_write) stalls=stalls+1;
                @(posedge clk); #1; cycles=cycles+1;
                if (pause_each_cycle) begin
                    @(negedge clk); enable=0; saved={pc,latches};
                    repeat(2) begin
                        @(posedge clk); #1;
                        if ({pc,latches} !== saved) $fatal(1,"pausa no conserva pipeline");
                    end
                end
            end
            if (!halted) $fatal(1,"CPU no termina");
            check(fault, expect_fault);
            // IF/ID, ID/EX y EX/MEM vacios; el marcador de parada queda en MEM/WB.
            if (latches[479:96] !== {32'd0, 32'h13, 32'd0, 288'd0}) $fatal(1,"HALT no vacia pipeline");
            if (latches[0] !== 1'b1 || latches[2] !== 1'b1 || latches[1] !== expect_fault)
                $fatal(1,"MEM/WB no tiene el marcador de parada");
            @(negedge clk); enable=0;
        end
    endtask
    task check_architecture;
        begin
            reg_addr=5'd0; #1; check(reg_data,32'h00000000);
            reg_addr=5'd1; #1; check(reg_data,32'h00000007);
            reg_addr=5'd2; #1; check(reg_data,32'h0000000e);
            reg_addr=5'd3; #1; check(reg_data,32'h0000000e);
            reg_addr=5'd4; #1; check(reg_data,32'h00000015);
            reg_addr=5'd5; #1; check(reg_data,32'h0000000e);
            reg_addr=5'd6; #1; check(reg_data,32'hfffffff8);
            reg_addr=5'd7; #1; check(reg_data,32'h00000002);
            reg_addr=5'd8; #1; check(reg_data,32'h00000000);
            reg_addr=5'd9; #1; check(reg_data,32'hfffffffe);
            reg_addr=5'd10; #1; check(reg_data,32'hfffffff8);
            reg_addr=5'd11; #1; check(reg_data,32'h000000f8);
            reg_addr=5'd12; #1; check(reg_data,32'hfffffff8);
            reg_addr=5'd13; #1; check(reg_data,32'h0000fff8);
            reg_addr=5'd14; #1; check(reg_data,32'hfff800f8);
            reg_addr=5'd15; #1; check(reg_data,32'h0000001b);
            reg_addr=5'd16; #1; check(reg_data,32'h0000001c);
            reg_addr=5'd17; #1; check(reg_data,32'h00000021);
            reg_addr=5'd18; #1; check(reg_data,32'h00000000);
            reg_addr=5'd19; #1; check(reg_data,32'h00000110);
            reg_addr=5'd20; #1; check(reg_data,32'h00000129);
            reg_addr=5'd21; #1; check(reg_data,32'h00000120);
            reg_addr=5'd22; #1; check(reg_data,32'h00000120);
            reg_addr=5'd23; #1; check(reg_data,32'h12345000);
            reg_addr=5'd24; #1; check(reg_data,32'h12345000);
            reg_addr=5'd25; #1; check(reg_data,32'h00000037);
            reg_addr=5'd26; #1; check(reg_data,32'h00000000);
            reg_addr=5'd27; #1; check(reg_data,32'h00000000);
            reg_addr=5'd28; #1; check(reg_data,32'h00000000);
            reg_addr=5'd29; #1; check(reg_data,32'h00000000);
            reg_addr=5'd30; #1; check(reg_data,32'h00000000);
            reg_addr=5'd31; #1; check(reg_data,32'h00000000);
            mem_addr=8'd0; #1; check(mem_data,32'h0000000e);
            mem_addr=8'd1; #1; check(mem_data,32'h0000000e);
            mem_addr=8'd2; #1; check(mem_data,32'hfffffffa);
            mem_addr=8'd3; #1; check(mem_data,32'hfffffff6);
            mem_addr=8'd4; #1; check(mem_data,32'hffffffe0);
            mem_addr=8'd5; #1; check(mem_data,32'h00000001);
            mem_addr=8'd6; #1; check(mem_data,32'h00000000);
            mem_addr=8'd7; #1; check(mem_data,32'hfffffffa);
            mem_addr=8'd8; #1; check(mem_data,32'h3ffffffe);
            mem_addr=8'd9; #1; check(mem_data,32'hfffffffe);
            mem_addr=8'd10; #1; check(mem_data,32'hfffffffa);
            mem_addr=8'd11; #1; check(mem_data,32'h00000000);
            mem_addr=8'd12; #1; check(mem_data,32'hfffffff5);
            mem_addr=8'd13; #1; check(mem_data,32'h00000001);
            mem_addr=8'd14; #1; check(mem_data,32'h00000001);
            mem_addr=8'd15; #1; check(mem_data,32'hfffffff7);
            mem_addr=8'd16; #1; check(mem_data,32'hffffffff);
            mem_addr=8'd17; #1; check(mem_data,32'h00000008);
            mem_addr=8'd18; #1; check(mem_data,32'hffffffe0);
            mem_addr=8'd19; #1; check(mem_data,32'h3ffffffe);
            mem_addr=8'd20; #1; check(mem_data,32'hfffffffe);
            mem_addr=8'd21; #1; check(mem_data,32'h00000000);
            mem_addr=8'd22; #1; check(mem_data,32'h00000000);
            mem_addr=8'd23; #1; check(mem_data,32'h00000000);
            mem_addr=8'd24; #1; check(mem_data,32'h00000000);
            mem_addr=8'd25; #1; check(mem_data,32'hfff800f8);
            mem_addr=8'd26; #1; check(mem_data,32'h00000000);
            mem_addr=8'd27; #1; check(mem_data,32'h00000000);
            mem_addr=8'd28; #1; check(mem_data,32'h00000000);
            mem_addr=8'd29; #1; check(mem_data,32'h00000000);
            mem_addr=8'd30; #1; check(mem_data,32'h00000000);
            mem_addr=8'd31; #1; check(mem_data,32'h12345000);
        end
    endtask
    initial begin
        restart;
        put(8'd0,32'h00500093); // x1=5
        put(8'd1,32'h00208093); // x1=7: forwarding EX/MEM
        put(8'd2,32'h00108133); // operacion R
        put(8'd3,32'h00202023); // STORE
        put(8'd4,32'h00002183); // LW x3
        put(8'd5,32'h00118233); // operacion R
        put(8'd6,32'h00002283); // LW x5
        put(8'd7,32'h00502223); // STORE
        put(8'd8,32'hff800313); // negativo
        put(8'd9,32'h00200393); // shift
        put(8'd10,32'h00730433); // operacion R
        put(8'd11,32'h00802423); // STORE
        put(8'd12,32'h40730433); // operacion R
        put(8'd13,32'h00802623); // STORE
        put(8'd14,32'h00731433); // operacion R
        put(8'd15,32'h00802823); // STORE
        put(8'd16,32'h00732433); // operacion R
        put(8'd17,32'h00802a23); // STORE
        put(8'd18,32'h00733433); // operacion R
        put(8'd19,32'h00802c23); // STORE
        put(8'd20,32'h00734433); // operacion R
        put(8'd21,32'h00802e23); // STORE
        put(8'd22,32'h00735433); // operacion R
        put(8'd23,32'h02802023); // STORE
        put(8'd24,32'h40735433); // operacion R
        put(8'd25,32'h02802223); // STORE
        put(8'd26,32'h00736433); // operacion R
        put(8'd27,32'h02802423); // STORE
        put(8'd28,32'h00737433); // operacion R
        put(8'd29,32'h02802623); // STORE
        put(8'd30,32'hffd30493); // operacion inmediata
        put(8'd31,32'h02902823); // STORE
        put(8'd32,32'h00032493); // operacion inmediata
        put(8'd33,32'h02902a23); // STORE
        put(8'd34,32'hfff33493); // operacion inmediata
        put(8'd35,32'h02902c23); // STORE
        put(8'd36,32'h00f34493); // operacion inmediata
        put(8'd37,32'h02902e23); // STORE
        put(8'd38,32'h00f36493); // operacion inmediata
        put(8'd39,32'h04902023); // STORE
        put(8'd40,32'h00f37493); // operacion inmediata
        put(8'd41,32'h04902223); // STORE
        put(8'd42,32'h00231493); // operacion inmediata
        put(8'd43,32'h04902423); // STORE
        put(8'd44,32'h00235493); // operacion inmediata
        put(8'd45,32'h04902623); // STORE
        put(8'd46,32'h40235493); // operacion inmediata
        put(8'd47,32'h04902823); // STORE
        put(8'd48,32'h06600223); // STORE
        put(8'd49,32'h06601323); // STORE
        put(8'd50,32'h06400503); // LOAD con extension
        put(8'd51,32'h06404583); // LOAD con extension
        put(8'd52,32'h06601603); // LOAD con extension
        put(8'd53,32'h06605683); // LOAD con extension
        put(8'd54,32'h06402703); // LOAD con extension
        put(8'd55,32'h01b00793); // productora
        put(8'd56,32'h00000013); // NOP
        put(8'd57,32'h00000013); // NOP
        put(8'd58,32'h00178813); // bypass WB-ID
        put(8'd59,32'h00108663); // branch
        put(8'd60,32'h00000000); // HALT camino incorrecto
        put(8'd61,32'h06102c23); // STORE
        put(8'd62,32'h00109463); // branch
        put(8'd63,32'h02100893); // branch no tomado
        put(8'd64,32'h00300913); // contador
        put(8'd65,32'hfff90913); // loop
        put(8'd66,32'hfe091ee3); // branch
        put(8'd67,32'h00c009ef); // JAL
        put(8'd68,32'h00000000); // HALT descartado por JAL
        put(8'd69,32'h06102c23); // STORE
        put(8'd70,32'h12900a13); // destino impar JALR
        put(8'd71,32'h000a0ae7); // JALR
        put(8'd72,32'h00000000); // HALT descartado
        put(8'd73,32'h06102c23); // STORE
        put(8'd74,32'h000a8b13); // usar retorno JALR
        put(8'd75,32'h12345bb7); // LUI x23
        put(8'd76,32'h07702e23); // STORE
        put(8'd77,32'h07c02c03); // LW limite superior
        put(8'd78,32'h017c0463); // branch
        put(8'd79,32'h06102c23); // STORE
        put(8'd80,32'h06300013); // escritura x0 ignorada
        put(8'd81,32'h03700c93); // ultima escritura antes HALT
        put(8'd82,32'h00000000); // HALT final
        put(8'd83,32'h06102c23); // STORE
        run_program(0,0);
        if (stalls != 3) $fatal(1,"numero de stalls %0d",stalls);
        check_architecture;
        // Enable no reinicia una CPU detenida.
        saved={pc,latches};
        @(negedge clk); enable=1;
        repeat(3) begin @(posedge clk); #1; if ({pc,latches} !== saved) $fatal(1,"halt inestable"); end
        restart;
        // Mismo programa, pausando en cada ciclo, incluso stall, STORE y salto.
        run_program(1,0); check_architecture;
        // El reset borra los registros pero NO la memoria de datos (RAM).
        restart;
        reg_addr=1; #1; check(reg_data,0);   // era 7
        mem_addr=0; #1; check(mem_data,32'h0000000e);
        mem_addr=31; #1; check(mem_data,32'h12345000);
        // LOAD invalido: no pisa destino ni permite efectos posteriores.
        put(0,32'h02a00093); // addi x1,x0,42
        put(1,32'h08002083); // lw x1,128(x0)
        put(2,32'h00102023); // sw x1,0(x0), descartado
        put(3,32'h06300113); // addi x2,x0,99, descartado
        run_program(0,1);
        reg_addr=1; #1; check(reg_data,42);
        reg_addr=2; #1; check(reg_data,0);
        mem_addr=0; #1; check(mem_data,14);  // el sw descartado no escribio
        restart;
        put(0,32'h00700093);
        put(1,32'hffffffff); // ilegal: parada sin ejecutar lo posterior
        put(2,32'h06300113);
        run_program(0,1);
        reg_addr=1; #1; check(reg_data,7);
        reg_addr=2; #1; check(reg_data,0);
        restart;
        put(0,32'h40000093); // x1=1024, fuera de memoria de programa
        put(1,32'h00008067); // jalr x0,0(x1)
        put(2,32'h06300113); // camino descartado
        run_program(0,1);
        check(pc,1024);
        reg_addr=2; #1; check(reg_data,0);
        restart;
        put(0,32'h00200093); // destino sin alineacion de palabra
        put(1,32'h00008067);
        run_program(0,1); check(pc,2);
        restart;
        put(0,32'h00900093); // x1=9
        put(1,32'h08102023); // sw x1,128(x0), fuera de rango
        put(2,32'h06300113);
        run_program(0,1);
        mem_addr=0; #1; check(mem_data,14);
        reg_addr=2; #1; check(reg_data,0);
        restart;
        put(0,32'h00000000); // HALT inmediato
        run_program(0,0);
        // Patron exacto de una parada normal: solo MEM/WB.ctrl = valid | halt.
        if (latches !== {32'd0, 32'h13, 32'd0, 384'd0} + 480'h5) $fatal(1,"patron final de HALT");
        check(pc,4); // PC = direccion del HALT + 4
        $display("PASS: cpu integrada, ejecucion continua y paso a paso");
        $finish;
    end
    initial begin #100000; $fatal(1,"Timeout CPU"); end
endmodule
`default_nettype wire
