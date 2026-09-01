`timescale 1ns / 1ps

module ALU#
(
    parameter LENGTH_BITS = 16,
    parameter LENGTH_OPT = 6
)
(
    output wire [LENGTH_BITS-1 : 0] o_leds,
    
    input wire [LENGTH_BITS-1:0] i_switch,
    (* clock_buffer_type = "none" *) input wire i_button_1,
    (* clock_buffer_type = "none" *) input wire i_button_2,
    (* clock_buffer_type = "none" *) input wire i_button_3
    );
    
    reg [LENGTH_BITS-1 : 0] result;
    reg [LENGTH_BITS-1 : 0] dato_A = 16'b0;
    reg [LENGTH_BITS-1 : 0] dato_B = 16'b0;
    reg [LENGTH_OPT-1 : 0] opt = 6'b0;
    reg error_signal = 1'b0;
    //----------------------------------------------Parametros locales
    localparam [5:0] ADD  = 6'b100000,
                     SUB  = 6'b100010,
                     AND_ = 6'b100100,
                     OR_  = 6'b100101,
                     XOR_ = 6'b100110,
                     NOR_ = 6'b100111,
                     SRA  = 6'b000011,
                     SRL  = 6'b000010;
                     
    localparam SHAMT_BITS = $clog2(LENGTH_BITS);
                     
    always @(*) begin
        if(i_button_1) dato_A = i_switch;
        else if (i_button_2) dato_B = i_switch;
        else if (i_button_3) opt = i_switch;
    end
    
    always @(*) begin
        case (opt)
            ADD:  result = dato_A + dato_B;
            SUB:  result = dato_A - dato_B;
            AND_: result = dato_A & dato_B;
            OR_:  result = dato_A | dato_B;
            XOR_: result = dato_A ^ dato_B;
            NOR_: result = ~(dato_A | dato_B);
            SRA:  result = $signed(dato_A) >>> dato_B[SHAMT_BITS-1:0];
            SRL:  result = dato_A >> dato_B[SHAMT_BITS-1:0];
            default: result = 16'd0;
        endcase
    end
    
    assign o_leds = result;
    
endmodule
