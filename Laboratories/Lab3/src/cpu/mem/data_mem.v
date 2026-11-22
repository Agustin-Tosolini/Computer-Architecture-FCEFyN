`timescale 1ns / 1ps
`default_nettype none

// Memoria de datos: 32 palabras, little-endian, lecturas combinacionales.
// Reset bloquea escrituras; no borra la RAM. La configuracion inicializa a cero.
module data_mem
(
    input wire i_clk,                 // Reloj de escritura.
    input wire i_reset,               // Inhibe escrituras durante reset.
    input wire i_enable,              // Habilita escrituras de la CPU.

    input wire [31:0] i_addr,         // Direccion de CPU en bytes.
    input wire [31:0] i_wdata,        // Dato de STORE, ya adelantado.
    input wire i_re,                  // Solicitud de LOAD.
    input wire i_we,                  // Solicitud de STORE.
    input wire [2:0] i_funct3,        // Tamano y signo del acceso.
    output reg [31:0] o_rdata,        // Dato leido y extendido a 32 bits.
    output wire o_access_error,       // Acceso no soportado o direccion invalida.

    input wire [7:0] i_dbg_addr,      // Indice de palabra para debug: 0..31; fuera de rango devuelve cero.
    output wire [31:0] o_dbg_data     // Palabra completa, sin extension ni mascara.
);
    (* ram_style = "distributed" *) reg [31:0] mem [0:31];
    integer index;
    initial begin
        for (index = 0; index < 32; index = index + 1)
            mem[index] = 32'd0;
    end

    wire [4:0] word_addr = i_addr[6:2];
    wire [1:0] byte_offset = i_addr[1:0];
    wire in_range = (i_addr[31:7] == 25'd0);
    wire load_supported = (i_funct3 == 3'b000 || i_funct3 == 3'b001 ||
                           i_funct3 == 3'b010 || i_funct3 == 3'b100 ||
                           i_funct3 == 3'b101);
    wire store_supported = (i_funct3 == 3'b000 || i_funct3 == 3'b001 ||
                            i_funct3 == 3'b010);
    wire aligned = (i_funct3[1:0] == 2'b00) ||
                   ((i_funct3[1:0] == 2'b01) && !i_addr[0]) ||
                   ((i_funct3[1:0] == 2'b10) && byte_offset == 2'b00);

    // Sin solicitud no hay error. No se permite LOAD y STORE simultaneos.
    assign o_access_error = (i_re || i_we) &&
                            (!in_range || !aligned || (i_re && i_we) ||
                             (i_re && !load_supported) || (i_we && !store_supported));

    wire [31:0] read_word = mem[word_addr];
    wire [31:0] shifted_word = read_word >> {byte_offset, 3'b000};
    always @(*) begin
        o_rdata = 32'd0;
        if (i_re && !o_access_error) begin
            case (i_funct3)
                3'b000: o_rdata = {{24{shifted_word[7]}}, shifted_word[7:0]}; // LB
                3'b001: o_rdata = {{16{shifted_word[15]}}, shifted_word[15:0]}; // LH
                3'b010: o_rdata = read_word;                                // LW
                3'b100: o_rdata = {24'd0, shifted_word[7:0]};                // LBU
                3'b101: o_rdata = {16'd0, shifted_word[15:0]};               // LHU
                default: o_rdata = 32'd0;
            endcase
        end
    end

    reg [3:0] byte_mask;
    reg [31:0] write_word;
    always @(*) begin
        byte_mask = 4'b0000;
        write_word = i_wdata;
        case (i_funct3)
            3'b000: begin // SB: solo el byte seleccionado.
                byte_mask = 4'b0001 << byte_offset;
                write_word = {4{i_wdata[7:0]}};
            end
            3'b001: begin // SH: dos bytes, alineados.
                byte_mask = 4'b0011 << byte_offset;
                write_word = {2{i_wdata[15:0]}};
            end
            3'b010: byte_mask = 4'b1111; // SW
            default: byte_mask = 4'b0000;
        endcase
    end

    wire write_en = i_enable && !i_reset && i_we && !o_access_error;
    always @(posedge i_clk) begin
        if (write_en) begin
            if (byte_mask[0]) mem[word_addr][7:0]   <= write_word[7:0];
            if (byte_mask[1]) mem[word_addr][15:8]  <= write_word[15:8];
            if (byte_mask[2]) mem[word_addr][23:16] <= write_word[23:16];
            if (byte_mask[3]) mem[word_addr][31:24] <= write_word[31:24];
        end
    end

    assign o_dbg_data = (i_dbg_addr[7:5] == 3'd0) ? mem[i_dbg_addr[4:0]] : 32'd0;
endmodule

`default_nettype wire
