`timescale 1ns / 1ps
`default_nettype none

//------------------------------------------------------------------------------
// Registro de pipeline IF/ID: conserva la instruccion buscada y su propio PC.
// Prioridad: reset > pausa global > flush > stall local > carga.
// El flush solo se aplica cuando la CPU avanza: una pausa de debug debe
// conservar todo el estado aunque la logica combinacional mantenga flush en 1.
//------------------------------------------------------------------------------
module if_id
(
    input  wire        i_clk,    // Reloj: captura en el flanco ascendente.
    input  wire        i_reset,  // 1: carga una burbuja, incluso si la CPU esta pausada.
    input  wire        i_enable, // 1: permite avanzar; 0: conserva todo salvo reset.
    input  wire        i_write,  // 1: permite cargar; 0: retiene por stall (salvo flush).
    input  wire        i_flush,  // 1: descarta el contenido si i_enable=1; gana al stall.

    input  wire [31:0] i_pc,     // Direccion en bytes de la instruccion buscada en IF.
    input  wire [31:0] i_instr,  // Instruccion de 32 bits entregada por instr_mem.
    input  wire        i_valid,  // 1: entrada valida; 0: entrada sin efectos (burbuja).

    output reg  [31:0] o_pc,     // PC guardado para ID; puede diferir del PC actual de IF.
    output reg  [31:0] o_instr,  // Instruccion guardada para decodificar en ID.
    output reg         o_valid  // 1: instruccion valida en ID; 0: burbuja.
);
    localparam [31:0] INSTR_NOP = 32'h0000_0013;

    always @(posedge i_clk) begin
        if (i_reset) begin
            o_pc    <= 32'd0;
            o_instr <= INSTR_NOP;
            o_valid <= 1'b0;
        end
        else if (i_enable) begin
            if (i_flush) begin
                o_pc    <= 32'd0;
                o_instr <= INSTR_NOP;
                o_valid <= 1'b0;
            end
            else if (i_write) begin
                o_pc    <= i_pc;
                o_instr <= i_instr;
                o_valid <= i_valid;
            end
            // i_write=0: stall local, conservar los tres campos.
        end
        // i_enable=0: pausa global, conservar los tres campos.
    end

endmodule

`default_nettype wire

// Reset/flush usan NOP (0x00000013), no HALT (0x00000000).
// En la prueba inicial: i_write=1, i_flush=0 e i_valid=1 para cada fetch valido.
