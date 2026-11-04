`default_nettype none

// Provide the twiddle factor omega^exponent mod 17, omega=3, for N=16.
module twiddle_rom16 (
    input  wire [3:0] exponent,
    output reg  [4:0] tw
);
    always @* begin
        case (exponent)
            4'd0:  tw = 5'd1;
            4'd1:  tw = 5'd3;
            4'd2:  tw = 5'd9;
            4'd3:  tw = 5'd10;
            4'd4:  tw = 5'd13;
            4'd5:  tw = 5'd5;
            4'd6:  tw = 5'd15;
            4'd7:  tw = 5'd11;
            4'd8:  tw = 5'd16;
            4'd9:  tw = 5'd14;
            4'd10: tw = 5'd8;
            4'd11: tw = 5'd7;
            4'd12: tw = 5'd4;
            4'd13: tw = 5'd12;
            4'd14: tw = 5'd2;
            4'd15: tw = 5'd6;
            default: tw = 5'd0;
        endcase
    end
endmodule
