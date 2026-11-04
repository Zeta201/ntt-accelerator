`default_nettype none

// Add two coefficients modulo 17.
module mod_add (
    input wire [4:0] a,
    input wire [4:0] b,
    output wire [4:0] sum
);
    wire [5:0] sum_ext = {1'b0, a} + {1'b0, b};
    wire [5:0] sum_corrected = sum_ext - 6'd17;
    assign sum = (sum_ext >= 6'd17) ? sum_corrected[4:0] : sum_ext[4:0];
endmodule

// Subtract two coefficients modulo 17.
module mod_sub (
    input wire [4:0] a,
    input wire [4:0] b,
    output wire [4:0] diff
);
    wire [5:0] a_ext = {1'b0, a} + 6'd17;
    wire [5:0] sub_result = a_ext - {1'b0, b};
    assign diff = (a >= b) ? (a - b) : sub_result[4:0];
endmodule

// Multiply two coefficients modulo 17.
module mod_mul (
    input wire [4:0] diff,
    input wire [4:0] tw,
    output wire [4:0] v
);
    wire [8:0] p = diff * tw;
    wire [3:0] l = p[3:0];
    wire [4:0] h = p[8:4];

    wire [5:0] l_ext = {1'b0, l} + 6'd17;
    wire [5:0] ge_result = {1'b0, l} - {1'b0, h};
    wire [5:0] lt_result = l_ext - {1'b0, h};
    assign v = ({1'b0, l} >= {1'b0, h}) ? ge_result[4:0] : lt_result[4:0];
endmodule
