`timescale 1ns / 1ps
`default_nettype none

//------------------------------------------------------------------------------
// Banco de registros RV32: 32 registros de 32 bits.
// Dos lecturas combinacionales para ID y una escritura sincronica desde WB.
// Las lecturas de operandos de x0 siempre devuelven cero; no acepta escrituras.
// El reset de CPU es sincronico y tiene prioridad sobre i_enable.
//------------------------------------------------------------------------------
module reg_file
(
    input  wire        i_clk,
    input  wire        i_reset,
    input  wire        i_enable,

    // Lecturas de operandos (etapa ID): numeros de registro y sus valores.
    input  wire [4:0]  i_rs1,
    input  wire [4:0]  i_rs2,
    output wire [31:0] o_rs1_data,
    output wire [31:0] o_rs2_data,

    // Escritura de resultado (etapa WB).
    input  wire        i_we,
    input  wire [4:0]  i_rd,
    input  wire [31:0] i_wdata,

    // Debug: lee el contenido almacenado, sin bypass ni efectos laterales.
    input  wire [4:0]  i_dbg_addr,
    output wire [31:0] o_dbg_data
);

    reg [31:0] regs [0:31];
    integer index;

    // La misma condicion habilita la escritura y el bypass. Durante pausa
    // o reset no se adelanta un dato que no se va a escribir.
    wire write_en = i_enable && i_we && !i_reset && (i_rd != 5'd0);

    always @(posedge i_clk) begin
        if (i_reset) begin
            for (index = 0; index < 32; index = index + 1)
                regs[index] <= 32'd0;
        end
        else if (write_en)
            regs[i_rd] <= i_wdata;
    end

    // Bypass WB -> ID: si WB escribe el registro que ID necesita, entregar
    // el dato nuevo antes del flanco que lo guarda en el banco y en ID/EX.
    // Se resuelve cada puerto por separado; ambos pueden leer el mismo rd.
    assign o_rs1_data = (i_rs1 == 5'd0) ? 32'd0 :
                       (write_en && i_rd == i_rs1) ? i_wdata : regs[i_rs1];

    assign o_rs2_data = (i_rs2 == 5'd0) ? 32'd0 :
                       (write_en && i_rd == i_rs2) ? i_wdata : regs[i_rs2];

    // Debug inspecciona todas las posiciones, incluida regs[0], sin forzar cero.
    // regs[0] queda en cero tras el reset; antes puede ser desconocida en simulacion.
    assign o_dbg_data = regs[i_dbg_addr];

endmodule

`default_nettype wire

//------------------------------------------------------------------------------
// Referencia rapida de entradas y salidas
// Senal       | Tipo   | Funcion
// ------------|--------|--------------------------------------------------------
// i_clk       | Entrada| Reloj: escritura en flanco ascendente.
// i_reset     | Entrada| Pone los registros en cero en el flanco; tiene prioridad.
// i_enable    | Entrada| Habilita la escritura y el bypass.
// i_rs1       | Entrada| Numero del primer registro a leer.
// i_rs2       | Entrada| Numero del segundo registro a leer.
// o_rs1_data  | Salida | Valor del primer operando, con bypass.
// o_rs2_data  | Salida | Valor del segundo operando, con bypass.
// i_we        | Entrada| Solicita escribir un registro.
// i_rd        | Entrada| Numero del registro destino (x0 no se modifica).
// i_wdata     | Entrada| Dato que se quiere guardar.
// i_dbg_addr  | Entrada| Numero del registro a consultar desde debug.
// o_dbg_data  | Salida | Contenido directo de regs[0..31], sin bypass.
//------------------------------------------------------------------------------
