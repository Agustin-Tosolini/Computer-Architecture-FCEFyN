`timescale 1ns / 1ps
`default_nettype none

//------------------------------------------------------------------------------
// dump_mux — Selector del byte del volcado.  Puramente COMBINACIONAL.
//
// Dado un indice (i_dump_idx = 0..313) devuelve el byte del volcado que va en esa
// posicion. Para los tramos de registros y de memoria, ademas pone la
// direccion de lectura de debug del procesador (o_dbg_reg_addr /
// o_dbg_mem_addr); como esas lecturas son asincronicas, el dato vuelve en el
// mismo ciclo y se elige el byte que corresponde.
//
// Formato del volcado (params.vh seccion 6). Valores de 32 bits en
// little-endian: primero el byte menos significativo.
//
//   idx        bytes  contenido
//   ---------  -----  ------------------------------------------
//   0            1    cabecera 0xA5
//   1 ..   4     4    PC
//   5 ..   8     4    contador de ciclos
//   9            1    estado (bit 0 = halted)
//   10 .. 137  128    registros x0..x31   (4 bytes c/u)
//   138 .. 185  48    latches             (byte k = i_latches[8k+7 : 8k])
//   186 .. 313 128    memoria de datos, palabras 0..31 (4 bytes c/u)
//   314 ..       -    fuera de rango: devuelve 0
//
// Ejemplo: idx = 10 + 4*5 + 2 = 32  ->  registro x5, byte 2 (bits 23:16).
//------------------------------------------------------------------------------
module dump_mux
(
    input  wire [8:0]    i_dump_idx,       // byte del volcado pedido (0..313)

    // Valores que vienen de control_fsmd
    input  wire [31:0]   i_cycles,
    input  wire [7:0]    i_status,

    // Valores que vienen del procesador
    input  wire [31:0]   i_pc,
    input  wire [383:0]  i_latches,

    output reg  [4:0]    o_dbg_reg_addr,   // registro a leer
    input  wire [31:0]   i_dbg_reg_data,
    output reg  [7:0]    o_dbg_mem_addr,   // palabra de memoria a leer
    input  wire [31:0]   i_dbg_mem_data,

    output reg  [7:0]    o_dump_byte       // byte del volcado en la posicion i_dump_idx
);

    //------------------------------------------------ Mapa del volcado
    localparam [8:0] HEADER    = 9'd0,
                     OFF_PC    = 9'd1,
                     OFF_CYC   = 9'd5,
                     OFF_ST    = 9'd9,
                     OFF_REG   = 9'd10,
                     OFF_LAT   = 9'd138,
                     OFF_MEM   = 9'd186,
                     DUMP_LEN  = 9'd314;

    localparam [7:0] DUMP_HEADER = 8'hA5;

    //------------------------------------------------ Desplazamientos por tramo
    // Posicion dentro de cada tramo (solo tiene sentido si idx cae en el).
    wire [8:0] off_pc  = i_dump_idx - OFF_PC;
    wire [8:0] off_cyc = i_dump_idx - OFF_CYC;
    wire [8:0] off_reg = i_dump_idx - OFF_REG;     // 0..127: [6:2] registro, [1:0] byte
    wire [8:0] off_lat = i_dump_idx - OFF_LAT;     // 0..47
    wire [8:0] off_mem = i_dump_idx - OFF_MEM;     // 0..127: [6:2] palabra,  [1:0] byte

    // Byte n (0 = menos significativo) de una palabra de 32 bits.
    function [7:0] byte_of(input [31:0] w, input [1:0] n);
        case (n)
            2'd0: byte_of = w[ 7: 0];
            2'd1: byte_of = w[15: 8];
            2'd2: byte_of = w[23:16];
            2'd3: byte_of = w[31:24];
        endcase
    endfunction

    //------------------------------------------------ Seleccion
    always @(*) begin
        o_dump_byte    = 8'h00;
        o_dbg_reg_addr = 5'd0;
        o_dbg_mem_addr = 8'd0;

        if (i_dump_idx == HEADER)
            o_dump_byte = DUMP_HEADER;

        else if (i_dump_idx < OFF_CYC)                  // 1..4
            o_dump_byte = byte_of(i_pc, off_pc[1:0]);

        else if (i_dump_idx < OFF_ST)                   // 5..8
            o_dump_byte = byte_of(i_cycles, off_cyc[1:0]);

        else if (i_dump_idx == OFF_ST)                  // 9
            o_dump_byte = i_status;

        else if (i_dump_idx < OFF_LAT) begin            // 10..137
            o_dbg_reg_addr = off_reg[6:2];
            o_dump_byte    = byte_of(i_dbg_reg_data, off_reg[1:0]);
        end

        else if (i_dump_idx < OFF_MEM)                  // 138..185
            o_dump_byte = i_latches[8*off_lat[5:0] +: 8];

        else if (i_dump_idx < DUMP_LEN) begin           // 186..313
            o_dbg_mem_addr = {3'b000, off_mem[6:2]};
            o_dump_byte    = byte_of(i_dbg_mem_data, off_mem[1:0]);
        end
    end

endmodule

`default_nettype wire
