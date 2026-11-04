`default_nettype none

// Provide the twiddle factor omega^exponent mod 17.
module twiddle_rom (
    input wire [2:0] exponent,
    output reg [4:0] tw
);
    always @* begin
        case (exponent)
            3'd0: tw = 5'd1;
            3'd1: tw = 5'd9;
            3'd2: tw = 5'd13;
            3'd3: tw = 5'd15;
            3'd4: tw = 5'd16;
            3'd5: tw = 5'd8;
            3'd6: tw = 5'd4;
            3'd7: tw = 5'd2;
            default: tw = 5'd0;
        endcase
    end
endmodule
