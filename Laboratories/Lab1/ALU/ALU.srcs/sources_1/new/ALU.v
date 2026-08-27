`timescale 1ns / 1ps

module ALU#
(
    parameter LENGTH_BITS = 16,
    parameter LENGTH_OPT = 6
)
(
    //input wire [4:0] i_dato_A,
    //input wire [4:0] i_dato_B,
    //input wire [5:0] i_opt,
    output wire [LENGTH_BITS-1 : 0] o_leds,
    
    input wire [LENGTH_BITS-1:0] i_switch,
    input wire i_button_1,
    input wire i_button_2,
    input wire i_button_3
    );
    
    reg [LENGTH_BITS-1 : 0] result;
    reg [LENGTH_BITS-1 : 0] dato_A;
    reg [LENGTH_BITS-1 : 0] dato_B;
    reg [LENGTH_OPT-1 : 0] opt;
    //----------------------------------------------Parametros locales
    localparam [5:0] ADD  = 6'b100000,
                     SUB  = 6'b100010,
                     AND_ = 6'b100100,
                     OR_  = 6'b100101,
                     XOR_ = 6'b100110,
                     NOR_ = 6'b100111,
                     SRA  = 6'b000011,
                     SRL  = 6'b000010,
                     SLT  = 6'b101010;
                     
     /*
     always @(*) begin
        case (i_opt)
            ADD:  result = i_dato_A + i_dato_B;
            SUB:  result = i_dato_A - i_dato_B;
            AND_: result = i_dato_A & i_dato_B;
            OR_:  result = i_dato_A | i_dato_B;
            XOR_: result = i_dato_A ^ i_dato_B;
            NOR_: result = ~(i_dato_A | i_dato_B);
            SLT:  result = ($signed(i_dato_A) < $signed(i_dato_B)) ? 7'd1 : 7'd0;
            default: result = 7'd0;
        endcase
    end
    */
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
            SLT:  result = ($signed(dato_A) < $signed(dato_B)) ? 16'd1 : 16'd0;
            default: result = 16'd0;
        endcase
    end
    
    assign o_leds = result;
    
endmodule
