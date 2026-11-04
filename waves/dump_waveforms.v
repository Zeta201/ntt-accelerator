`default_nettype none

// Standalone VCD capture harness, outside the formal verification suite.
// Drives one full transform through ntt_top with the README's worked-example
// vector and dumps every signal in the hierarchy for waveform inspection.
module dump_waveforms;
    reg clk, rst, start;
    reg [39:0] coef_in;
    wire busy, done;
    wire [39:0] coef_out;

    ntt_top dut (
        .clk(clk), .rst(rst), .start(start), .coef_in(coef_in),
        .busy(busy), .done(done), .coef_out(coef_out)
    );

    always #5 clk = ~clk;

    // Text trace of the controller's internal state, for reference alongside
    // the VCD when no graphical waveform viewer is available.
    always @(posedge clk) begin
        #1;
        if (busy)
            $display("t=%0t state=%0d stage=%0d bidx=%0d lo=%0d hi=%0d twexp=%0d a_reg=%0d b_reg=%0d tw_reg=%0d u_reg=%0d v_reg=%0d we=%0b",
                $time, dut.u_ctrl.state, dut.u_ctrl.stage, dut.u_ctrl.bidx,
                dut.u_ctrl.lo, dut.u_ctrl.hi, dut.u_ctrl.twiddle_exp,
                dut.u_ctrl.a_reg, dut.u_ctrl.b_reg, dut.u_ctrl.tw_reg,
                dut.u_ctrl.u_reg, dut.u_ctrl.v_reg, dut.write_enable);
    end

    integer k;

    initial begin
        $dumpfile("waves/ntt_top.vcd");
        $dumpvars(0, dump_waveforms);

        clk = 0;
        rst = 1;
        start = 0;
        coef_in = 40'd0;

        repeat (3) @(posedge clk);
        #1;
        rst <= 1'b0;
        @(posedge clk);
        #1;

        // x = [1,2,3,4,5,6,7,8], the README worked-example input.
        coef_in <= {5'd8, 5'd7, 5'd6, 5'd5, 5'd4, 5'd3, 5'd2, 5'd1};
        start <= 1'b1;
        @(posedge clk);
        #1;
        start <= 1'b0;

        wait (done);
        @(posedge clk);
        #1;
        @(posedge clk);
        #1;

        $display("coef_out (natural order) = %0d %0d %0d %0d %0d %0d %0d %0d",
            coef_out[4:0], coef_out[9:5], coef_out[14:10], coef_out[19:15],
            coef_out[24:20], coef_out[29:25], coef_out[34:30], coef_out[39:35]);
        $display("expected (from README)   = 2 1 12 3 13 6 14 8");

        $finish;
    end

    initial begin
        #2000;
        $display("FAIL: dump_waveforms global timeout -- simulation did not finish");
        $finish;
    end
endmodule
