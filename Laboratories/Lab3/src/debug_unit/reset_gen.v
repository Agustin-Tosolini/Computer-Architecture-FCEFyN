`timescale 1ns / 1ps
`default_nettype none

//------------------------------------------------------------------------------
// Generador del reset GLOBAL del sistema.
//
// El reset sale en 1 en tres situaciones:
//   1. Al encender (power-on reset): durante POR_CYCLES ciclos despues de que
//      la FPGA se configura. Asi todo arranca en un estado conocido sin tener
//      que apretar el boton.
//   2. Mientras se aprieta el boton (i_btn).
//   3. Mientras el clock no es estable (i_locked = 0). Hoy i_locked se ata a 1
//      en el top; cuando se agregue el clk_wiz se conecta a su salida "locked".
//
// El boton es asincronico respecto del clock: pasa por dos flip-flops antes de
// usarse (mismo sincronizador que la linea rx de la UART). No hace falta
// antirrebote: un rebote solo alarga el reset.
//
// Este es el reset de TODO (UART incluida). El reset del procesador solo
// (cpu_reset) lo va a generar la debug_unit y es otra senal.
//------------------------------------------------------------------------------
module reset_gen #
(
    parameter POR_CYCLES = 16
)
(
    input  wire i_clk,
    input  wire i_btn,       // boton de reset (activo en 1)
    input  wire i_locked,    // 1 = clock estable
    output wire o_reset      // reset sincronico, activo en 1
);

    localparam CNT_BITS = $clog2(POR_CYCLES + 1);

    //------------------------------------------------ Sincronizador del boton
    reg btn_meta = 1'b0;
    reg btn_sync = 1'b0;

    always @(posedge i_clk) begin
        btn_meta <= i_btn;
        btn_sync <= btn_meta;
    end

    //------------------------------------------------ Power-on reset
    // El contador arranca en 0 por valor inicial (lo carga la configuracion de
    // la FPGA) y se detiene al llegar a POR_CYCLES.
    reg  [CNT_BITS-1:0] por_cnt = {CNT_BITS{1'b0}};
    wire                por_active = (por_cnt != POR_CYCLES);

    always @(posedge i_clk)
        if (por_active)
            por_cnt <= por_cnt + 1'b1;

    //------------------------------------------------ Salida registrada
    reg reset_q = 1'b1;

    always @(posedge i_clk)
        reset_q <= por_active | btn_sync | ~i_locked;

    assign o_reset = reset_q;

endmodule

`default_nettype wire
