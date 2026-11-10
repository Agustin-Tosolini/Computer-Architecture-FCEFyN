`timescale 1ns / 1ps
`default_nettype none

//------------------------------------------------------------------------------
// Testbench del dump_mux (combinacional, no necesita clock).
//
// Idea: se arma en el testbench el volcado ESPERADO byte por byte, a partir
// del formato de params.vh y con codigo distinto al del modulo (bucles que
// recorren registros/latches/memoria). Despues se recorre idx = 0..325 y se
// compara la salida del dump_mux contra ese volcado esperado.
//
// Los "registros" y la "memoria" del procesador se simulan con funciones:
// devuelven un valor distinto por direccion y con los 4 bytes distintos, asi
// un error de orden (little-endian) o de direccion se nota enseguida.
//
// Pruebas:
//   1. Los 326 bytes del volcado, en orden.
//   2. Direcciones de debug correctas en los tramos de registros y memoria.
//   3. Fuera de rango (idx >= 326): byte 0 y direcciones 0.
//------------------------------------------------------------------------------
module tb_dump_mux;

    //------------------------------------------------ Entradas / salidas
    reg  [8:0]   idx      = 9'd0;
    reg  [31:0]  cycles   = 32'hC1C2_C3C4;
    reg  [7:0]   status   = 8'h01;              // halted = 1
    reg  [31:0]  pc       = 32'hA1A2_A3A4;
    reg  [479:0] latches;
    wire [4:0]   dbg_reg_addr;
    wire [31:0]  dbg_reg_data;
    wire [7:0]   dbg_mem_addr;
    wire [31:0]  dbg_mem_data;
    wire [7:0]   dbg_byte;

    //------------------------------------------------ Modelo del procesador
    // Registro n: bytes {n, 0x20+n, 0x40+n, 0x60+n} (del mas significativo al
    // menos). x0 = 0 como en RISC-V.
    function [31:0] reg_val(input [4:0] n);
        reg_val = (n == 0) ? 32'd0 : {8'h60 + n, 8'h40 + n, 8'h20 + n, 3'b000, n};
    endfunction
    // Palabra de memoria n: bytes {0xF0 ^ n, 0xD0 ^ n, 0xB0 ^ n, 0x90 ^ n}.
    function [31:0] mem_val(input [7:0] n);
        mem_val = {8'hF0 ^ n, 8'hD0 ^ n, 8'hB0 ^ n, 8'h90 ^ n};
    endfunction

    assign dbg_reg_data = reg_val(dbg_reg_addr);
    assign dbg_mem_data = mem_val(dbg_mem_addr);

    //------------------------------------------------ DUT
    dump_mux dut
    (
        .i_dump_idx     (idx),
        .i_cycles       (cycles),
        .i_status       (status),
        .i_pc           (pc),
        .i_latches      (latches),
        .o_dbg_reg_addr (dbg_reg_addr),
        .i_dbg_reg_data (dbg_reg_data),
        .o_dbg_mem_addr (dbg_mem_addr),
        .i_dbg_mem_data (dbg_mem_data),
        .o_dump_byte    (dbg_byte)
    );

    //------------------------------------------------ Volcado esperado
    reg [7:0] expected [0:325];
    integer   i, k, n;
    integer   errors = 0;

    task put_word(input integer pos, input [31:0] w);   // little-endian
        begin
            expected[pos    ] = w[ 7: 0];
            expected[pos + 1] = w[15: 8];
            expected[pos + 2] = w[23:16];
            expected[pos + 3] = w[31:24];
        end
    endtask

    initial begin
        // latches: byte k = 0x80 + k  (el byte 0 es el menos significativo)
        for (k = 0; k < 60; k = k + 1)
            latches[8*k +: 8] = 8'h80 + k;

        // armado del volcado esperado, tramo por tramo
        n = 0;
        expected[n] = 8'hA5;                 n = n + 1;    // cabecera
        put_word(n, pc);                     n = n + 4;    // PC
        put_word(n, cycles);                 n = n + 4;    // ciclos
        expected[n] = status;                n = n + 1;    // estado
        for (k = 0; k < 32; k = k + 1) begin               // registros
            put_word(n, reg_val(k[4:0]));    n = n + 4;
        end
        for (k = 0; k < 60; k = k + 1) begin               // latches
            expected[n] = latches[8*k +: 8]; n = n + 1;
        end
        for (k = 0; k < 32; k = k + 1) begin               // memoria
            put_word(n, mem_val(k[7:0]));    n = n + 4;
        end
        if (n != 326) begin
            $display("ERROR en el testbench: el volcado esperado tiene %0d bytes", n);
            errors = errors + 1;
        end

        //---------------------------------------- 1 y 2. Los 326 bytes
        for (i = 0; i < 326; i = i + 1) begin
            idx = i[8:0];
            #1;
            if (dbg_byte !== expected[i]) begin
                $display("ERROR: idx %0d: byte %h, esperado %h", i, dbg_byte, expected[i]);
                errors = errors + 1;
            end
            // direcciones de debug: solo en su tramo, 0 fuera de el
            if (i >= 10 && i < 138) begin
                if (dbg_reg_addr !== (i - 10) / 4) begin
                    $display("ERROR: idx %0d: dbg_reg_addr %0d, esperado %0d",
                             i, dbg_reg_addr, (i - 10) / 4);
                    errors = errors + 1;
                end
            end
            else if (dbg_reg_addr !== 5'd0) begin
                $display("ERROR: idx %0d: dbg_reg_addr deberia ser 0", i);
                errors = errors + 1;
            end
            if (i >= 198) begin
                if (dbg_mem_addr !== (i - 198) / 4) begin
                    $display("ERROR: idx %0d: dbg_mem_addr %0d, esperado %0d",
                             i, dbg_mem_addr, (i - 198) / 4);
                    errors = errors + 1;
                end
            end
            else if (dbg_mem_addr !== 8'd0) begin
                $display("ERROR: idx %0d: dbg_mem_addr deberia ser 0", i);
                errors = errors + 1;
            end
        end

        //---------------------------------------- 3. Fuera de rango
        for (i = 326; i < 512; i = i + 1) begin
            idx = i[8:0];
            #1;
            if (dbg_byte !== 8'h00 || dbg_reg_addr !== 5'd0 || dbg_mem_addr !== 8'd0) begin
                $display("ERROR: idx %0d fuera de rango: byte %h", i, dbg_byte);
                errors = errors + 1;
            end
        end

        if (errors == 0) $display("PASS: dump_mux arma los 326 bytes en orden");
        else             $display("FAIL: %0d errores", errors);
        $finish;
    end

endmodule

`default_nettype wire
