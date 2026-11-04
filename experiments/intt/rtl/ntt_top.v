`default_nettype none

// Assemble the forward/inverse NTT accelerator from the controller and coefficient memory.
// Forward behavior (inv=0) is bit-for-bit identical to the baseline rtl/ntt_top.v.
module ntt_top (
    input  wire        clk,
    input  wire        rst,
    input  wire        start,
    input  wire        inv,
    input  wire [39:0] coef_in,
    output wire        busy,
    output wire        done,
    output wire [39:0] coef_out
);
    wire [2:0]  lo, hi, lo_reg, hi_reg;
    wire [4:0]  a_in, b_in, u_reg, v_reg;
    wire        load_enable, write_enable;
    wire [39:0] mem_flat;

    ntt_controller u_ctrl (
        .clk(clk), .rst(rst), .start(start), .inv(inv), .busy(busy), .done(done),
        .lo(lo), .hi(hi), .a_in(a_in), .b_in(b_in),
        .load_enable(load_enable), .write_enable(write_enable),
        .lo_reg(lo_reg), .hi_reg(hi_reg), .u_reg(u_reg), .v_reg(v_reg)
    );

    coefficient_memory u_mem (
        .clk(clk),
        .load_enable(load_enable), .write_enable(write_enable),
        .coef_in(coef_in),
        .lo(lo), .hi(hi), .a_out(a_in), .b_out(b_in),
        .lo_reg(lo_reg), .hi_reg(hi_reg), .u_in(u_reg), .v_in(v_reg),
        .mem_flat(mem_flat)
    );

    genvar k;
    generate
        for (k = 0; k < 8; k = k + 1) begin : OUT_PACK
            assign coef_out[5*k +: 5] = mem_flat[5*({k[0], k[1], k[2]}) +: 5];
        end
    endgenerate
endmodule
