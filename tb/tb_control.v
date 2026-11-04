`default_nettype none

// Verify reset, start detection, busy-time requests, and consecutive NTT executions.
module tb_control;

    localparam [2:0] S_IDLE = 3'd0;
    localparam [2:0] S_LOAD = 3'd1;
    localparam [2:0] S_READ = 3'd2;
    localparam [2:0] S_COMPUTE = 3'd3;
    localparam [2:0] S_WRITE = 3'd4;

    reg clk, rst, start;
    reg [39:0] coef_in;
    wire busy, done;
    wire [39:0] coef_out;

    ntt_top dut (
        .clk(clk), .rst(rst), .start(start), .coef_in(coef_in),
        .busy(busy), .done(done), .coef_out(coef_out)
    );

    always #5 clk = ~clk;

    integer error_count;

    // Pack eight coefficients in natural order, with coefficient k in bits [5*k+:5].
    reg [39:0] IN_ZEROS, EXP_ZEROS, IN_INC, EXP_INC;

    integer check_count;

    // Check a condition and record any validation failure.
    task check(input cond, input [8*96-1:0] msg);
        begin
            check_count = check_count + 1;
            if (!cond) begin
                $display("FAIL: %0s", msg);
                error_count = error_count + 1;
            end
        end
    endtask

    // Wait for the specified controller state, checking the current state first.
    task wait_for_state(input [2:0] target, input integer limit, output integer found);
        integer n;
        begin
            found = (dut.u_ctrl.state === target) ? 1 : 0;
            for (n = 0; n < limit && !found; n = n + 1) begin
                @(posedge clk);
                #1;
                if (dut.u_ctrl.state === target) found = 1;
            end
        end
    endtask

    // Wait for the completion signal or timeout.
    task wait_done(input integer limit, output integer ok);
        integer n;
        begin
            ok = 0;
            for (n = 0; n < limit && !ok; n = n + 1) begin
                @(posedge clk);
                #1;
                if (done === 1'b1) ok = 1;
            end
        end
    endtask

    integer found, ok;
    integer k;

    initial begin
        error_count = 0;
        check_count = 0;
        clk = 0;
        rst = 1;
        start = 0;
        coef_in = 40'd0;

        IN_ZEROS  = 40'd0;
        EXP_ZEROS = 40'd0;
        IN_INC  = {5'd7,5'd6,5'd5,5'd4,5'd3,5'd2,5'd1,5'd0};
        EXP_INC = {5'd8,5'd14,5'd6,5'd13,5'd3,5'd12,5'd1,5'd11};

        repeat (3) @(posedge clk);
        #1;
        check(busy === 1'b0, "T1: busy must be 0 immediately after reset");
        check(done === 1'b0, "T1: done must be 0 immediately after reset");
        rst <= 1'b0;
        @(posedge clk);
        #1;

        coef_in <= IN_ZEROS;
        start   <= 1'b1;
        @(posedge clk);
        #1;
        start <= 1'b0;
        @(posedge clk);
        #1;
        check(busy === 1'b1, "T2: busy must be 1 the cycle after a start pulse is accepted");
        wait_done(200, ok);
        check(ok == 1, "T2: done must assert within timeout after a single-cycle start pulse");
        check(busy === 1'b0, "T2: busy must be 0 in the same cycle done is first observed");
        for (k = 0; k < 8; k = k + 1)
            check(coef_out[5*k+:5] === EXP_ZEROS[5*k+:5], "T2: zeros-vector output mismatch");

        coef_in <= IN_INC;
        start   <= 1'b1;
        @(posedge clk);
        #1;
        check(busy === 1'b1, "T3: busy must be 1 the cycle after the held-high start is first accepted");
        wait_done(200, ok);
        check(ok == 1, "T3: done must assert within timeout while start is held high");
        for (k = 0; k < 8; k = k + 1)
            check(coef_out[5*k+:5] === EXP_INC[5*k+:5], "T3: increasing-vector output mismatch under held-high start");
        begin : t3_hold
            integer n;
            for (n = 0; n < 20; n = n + 1) begin
                @(posedge clk);
                #1;
                check(busy === 1'b0, "T3: held-high start must not retrigger busy after completion");
                check(done === 1'b1, "T3: done must remain asserted while start is held high and idle");
            end
        end
        start <= 1'b0;
        @(posedge clk);
        #1;

        coef_in <= IN_INC;
        start   <= 1'b1;
        @(posedge clk);
        #1;
        start <= 1'b0;
        @(posedge clk);
        #1;
        check(busy === 1'b1, "T4: busy must be 1 after starting the transform under test");
        begin : t4_wait_stage1
            integer n;
            integer reached;
            reached = 0;
            for (n = 0; n < 60 && !reached; n = n + 1) begin
                @(posedge clk);
                #1;
                if (dut.u_ctrl.state === S_READ && dut.u_ctrl.stage === 2'd1) reached = 1;
            end
            check(reached == 1, "T4: transform must reach stage 1 within timeout before the mid-flight pulse");
        end
        start <= 1'b1;
        @(posedge clk);
        #1;
        start <= 1'b0;
        check(busy === 1'b1, "T4: busy must remain 1 -- a start pulse while busy must not abort the transform");
        wait_done(200, ok);
        check(ok == 1, "T4: the in-flight transform must still reach done despite the mid-flight start pulse");
        for (k = 0; k < 8; k = k + 1)
            check(coef_out[5*k+:5] === EXP_INC[5*k+:5], "T4: output must be unaffected by a start pulse issued while busy");

        coef_in <= IN_INC;
        start   <= 1'b1;
        @(posedge clk);
        #1;
        start <= 1'b0;
        wait_for_state(S_LOAD, 10, found);
        check(found == 1, "T5: transform must reach S_LOAD within timeout before the reset is applied");
        rst <= 1'b1;
        @(posedge clk);
        #1;
        check(dut.u_ctrl.state === S_IDLE, "T5: state must return to S_IDLE the cycle after reset is asserted");
        check(busy === 1'b0, "T5: busy must be 0 after reset asserted mid-LOAD");
        check(done === 1'b0, "T5: done must be 0 after reset asserted mid-LOAD");
        rst <= 1'b0;
        @(posedge clk);
        #1;
        coef_in <= IN_INC;
        start   <= 1'b1;
        @(posedge clk);
        #1;
        start <= 1'b0;
        @(posedge clk);
        #1;
        wait_done(200, ok);
        check(ok == 1, "T5: a fresh transform after mid-LOAD reset must still reach done");
        for (k = 0; k < 8; k = k + 1)
            check(coef_out[5*k+:5] === EXP_INC[5*k+:5], "T5: a fresh transform after mid-LOAD reset must still produce correct output");

        coef_in <= IN_INC;
        start   <= 1'b1;
        @(posedge clk);
        #1;
        start <= 1'b0;
        wait_for_state(S_WRITE, 20, found);
        check(found == 1, "T6: transform must reach S_WRITE within timeout before the reset is applied");
        rst <= 1'b1;
        @(posedge clk);
        #1;
        check(dut.u_ctrl.state === S_IDLE, "T6: state must return to S_IDLE the cycle after reset is asserted");
        check(busy === 1'b0, "T6: busy must be 0 after reset asserted mid-WRITE");
        check(done === 1'b0, "T6: done must be 0 after reset asserted mid-WRITE");
        rst <= 1'b0;
        @(posedge clk);
        #1;
        coef_in <= IN_INC;
        start   <= 1'b1;
        @(posedge clk);
        #1;
        start <= 1'b0;
        @(posedge clk);
        #1;
        wait_done(200, ok);
        check(ok == 1, "T6: a fresh transform after mid-WRITE reset must still reach done");
        for (k = 0; k < 8; k = k + 1)
            check(coef_out[5*k+:5] === EXP_INC[5*k+:5], "T6: a fresh transform after mid-WRITE reset must still produce correct output");

        coef_in <= IN_ZEROS;
        start   <= 1'b1;
        @(posedge clk);
        #1;
        start <= 1'b0;
        @(posedge clk);
        #1;
        check(busy === 1'b1, "T7: back-to-back start immediately after a prior done must be accepted");
        wait_done(200, ok);
        check(ok == 1, "T7: back-to-back transform must reach done within timeout");
        for (k = 0; k < 8; k = k + 1)
            check(coef_out[5*k+:5] === EXP_ZEROS[5*k+:5], "T7: back-to-back transform output mismatch");

        $display("tb_control: %0d checks, %0d failures", check_count, error_count);
        if (error_count != 0) begin
            $display("RESULT: FAIL (%0d failures)", error_count);
            $fatal(1);
        end else begin
            $display("RESULT: PASS (0 failures)");
            $finish;
        end
    end

    initial begin
        #20000;
        $display("FAIL: tb_control global timeout -- simulation did not finish");
        $fatal(1);
    end
endmodule
