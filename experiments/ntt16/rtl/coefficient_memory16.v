`default_nettype none

// Store and provide the sixteen NTT coefficients.
module coefficient_memory16 (
    input wire clk,
    input wire load_enable,
    input wire write_enable,
    input wire [79:0] coef_in,

    input wire [3:0] lo,
    input wire [3:0] hi,
    output wire [4:0] a_out,
    output wire [4:0] b_out,

    input wire [3:0] lo_reg,
    input wire [3:0] hi_reg,
    input wire [4:0] u_in,
    input wire [4:0] v_in,

    output wire [79:0] mem_flat
);
    reg [4:0] mem [0:15];
    integer li;

    assign a_out = mem[lo];
    assign b_out = mem[hi];

    always @(posedge clk) begin
        if (load_enable) begin
            for (li = 0; li < 16; li = li + 1)
                mem[li] <= coef_in[5*li +: 5];
        end
        if (write_enable) begin
            mem[lo_reg] <= u_in;
            mem[hi_reg] <= v_in;
        end
    end

    genvar gi;
    generate
        for (gi = 0; gi < 16; gi = gi + 1) begin : FLATTEN
            assign mem_flat[5*gi +: 5] = mem[gi];
        end
    endgenerate
endmodule
