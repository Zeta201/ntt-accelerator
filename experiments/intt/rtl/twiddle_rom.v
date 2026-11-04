`default_nettype none

// Provide omega^exponent mod 17 (forward) or omega^-exponent mod 17 (inverse).
module twiddle_rom (
    input  wire [2:0] exponent,
    input  wire       inv,
    output reg  [4:0] tw
);
    always @* begin
        if (!inv) begin
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
        end else begin
            case (exponent)
                3'd0: tw = 5'd1;
                3'd1: tw = 5'd2;
                3'd2: tw = 5'd4;
                3'd3: tw = 5'd8;
                3'd4: tw = 5'd16;
                3'd5: tw = 5'd15;
                3'd6: tw = 5'd13;
                3'd7: tw = 5'd9;
                default: tw = 5'd0;
            endcase
        end
    end
endmodule
