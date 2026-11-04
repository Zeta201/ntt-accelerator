`default_nettype none

// Compute one radix-2 DIF butterfly.
module butterfly_datapath (
    input  wire [4:0] a,
    input  wire [4:0] b,
    input  wire [4:0] tw,
    output wire [4:0] u,
    output wire [4:0] v
);
    wire [4:0] diff;

    mod_add u_mod_add (.a(a),    .b(b),  .sum(u));
    mod_sub u_mod_sub (.a(a),    .b(b),  .diff(diff));
    mod_mul u_mod_mul (.diff(diff), .tw(tw), .v(v));
endmodule
