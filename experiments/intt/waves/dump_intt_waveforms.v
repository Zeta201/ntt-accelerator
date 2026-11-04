`default_nettype none

// Standalone VCD capture harness for the INTT experiment, outside the
// formal verification suite. Drives a forward transform followed by an
// inverse transform of its own output (a round trip), using the README's
// worked-example input, and dumps every signal in the hierarchy.
module dump_intt_waveforms;
    reg         clk, rst, start, inv;
    reg  [39:0] coef_in;
    wire        busy, done;
    wire [39:0] coef_out;

    ntt_top dut (
        .clk(clk), .rst(rst), .start(start), .inv(inv), .coef_in(coef_in),
        .busy(busy), .done(done), .coef_out(coef_out)
    );

    always #5 clk = ~clk;

    reg [39:0] fwd_result;

    initial begin
        $dumpfile("experiments/intt/waves/intt_top.vcd");
        $dumpvars(0, dump_intt_waveforms);

        clk = 0; rst = 1; start = 0; inv = 0; coef_in = 0;
        repeat (3) @(posedge clk);
        #1;
        rst <= 1'b0;
        @(posedge clk);
        #1;

        // Forward: x = [1,2,3,4,5,6,7,8] (same worked-example vector as the baseline waveforms).
        coef_in <= {5'd8, 5'd7, 5'd6, 5'd5, 5'd4, 5'd3, 5'd2, 5'd1};
        inv     <= 1'b0;
        start   <= 1'b1;
        @(posedge clk);
        #1;
        start <= 1'b0;

        wait (done);
        @(posedge clk); #1;
        fwd_result = coef_out;
        $display("forward result = %0d %0d %0d %0d %0d %0d %0d %0d",
            coef_out[4:0], coef_out[9:5], coef_out[14:10], coef_out[19:15],
            coef_out[24:20], coef_out[29:25], coef_out[34:30], coef_out[39:35]);

        @(posedge clk); #1;

        // Inverse: feed the forward result back in, recovering the original input.
        coef_in <= fwd_result;
        inv     <= 1'b1;
        start   <= 1'b1;
        @(posedge clk);
        #1;
        start <= 1'b0;

        wait (done);
        @(posedge clk); #1;
        $display("inverse result = %0d %0d %0d %0d %0d %0d %0d %0d (expect 1 2 3 4 5 6 7 8)",
            coef_out[4:0], coef_out[9:5], coef_out[14:10], coef_out[19:15],
            coef_out[24:20], coef_out[29:25], coef_out[34:30], coef_out[39:35]);

        @(posedge clk); @(posedge clk);
        $finish;
    end

    initial begin
        #2000;
        $display("FAIL: dump_intt_waveforms global timeout -- simulation did not finish");
        $finish;
    end
endmodule
