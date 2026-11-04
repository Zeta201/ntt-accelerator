// Exercise vector-reading and timeout handling with malformed and invalid input files.

`default_nettype none

module tb_negative;

    localparam ERR_NONE        = 0;
    localparam ERR_MISSING     = 1;
    localparam ERR_MALFORMED   = 2;
    localparam ERR_BAD_COUNT   = 3;
    localparam ERR_OUT_OF_RANGE = 4;

    reg [4:0] rdbuf [0:7];
    integer error_count;
    integer check_count;

    task check(input cond, input [8*96-1:0] msg);
        begin
            check_count = check_count + 1;
            if (!cond) begin
                $display("FAIL: %0s", msg);
                error_count = error_count + 1;
            end
        end
    endtask

    // Read eight canonical coefficients and classify file-reading errors.
    task try_read(input [8*256-1:0] path, output integer errtype);
        integer fd, i, got, extra, val;
        begin
            errtype = ERR_NONE;
            fd = $fopen(path, "r");
            if (fd == 0) begin
                errtype = ERR_MISSING;
            end else begin
                for (i = 0; i < 8; i = i + 1) begin
                    got = $fscanf(fd, "%d", val);
                    if (got != 1) begin
                        if (errtype == ERR_NONE)
                            errtype = $feof(fd) ? ERR_BAD_COUNT : ERR_MALFORMED;
                    end else begin
                        rdbuf[i] = val[4:0];
                        if ((val < 0 || val > 16) && errtype == ERR_NONE)
                            errtype = ERR_OUT_OF_RANGE;
                    end
                end
                if (errtype == ERR_NONE) begin
                    extra = $fscanf(fd, "%d", got);
                    if (extra == 1) errtype = ERR_BAD_COUNT;
                end
                $fclose(fd);
            end
        end
    endtask

    integer errtype;

    reg         clk, rst, start;
    reg  [39:0] coef_in;
    wire        busy, done;
    wire [39:0] coef_out;

    ntt_top dut (
        .clk(clk), .rst(rst), .start(start), .coef_in(coef_in),
        .busy(busy), .done(done), .coef_out(coef_out)
    );

    always #5 clk = ~clk;

    initial begin
        error_count = 0;
        check_count = 0;

        // Verify that a missing file is reported correctly.
        try_read("tb/fixtures/does_not_exist.txt", errtype);
        check(errtype == ERR_MISSING, "N1: a nonexistent file must be reported as a missing-file setup error");

        // Verify that a non-numeric token is reported as malformed.
        try_read("tb/fixtures/malformed.txt", errtype);
        check(errtype == ERR_MALFORMED, "N2: a non-numeric token must be reported as a malformed-file setup error");

        // Verify that fewer than eight coefficients trigger a count error.
        try_read("tb/fixtures/short_count.txt", errtype);
        check(errtype == ERR_BAD_COUNT, "N3: a file with fewer than 8 coefficients must be reported as a bad-count setup error");

        // Verify that more than eight coefficients trigger a count error.
        try_read("tb/fixtures/long_count.txt", errtype);
        check(errtype == ERR_BAD_COUNT, "N4: a file with more than 8 coefficients must be reported as a bad-count setup error");

        // Verify that an out-of-range coefficient is rejected.
        try_read("tb/fixtures/out_of_range.txt", errtype);
        check(errtype == ERR_OUT_OF_RANGE, "N5: a coefficient outside [0,16] must be reported as an out-of-range setup error, not fed to the DUT");

        // Verify that bounded polling reports a timeout while reset holds the FSM in IDLE.
        begin : n6
            integer n, ok;
            clk = 0; rst = 1; start = 0; coef_in = 40'd0;
            repeat (3) @(posedge clk);
            start <= 1'b1;
            @(posedge clk);
            #1;
            start <= 1'b0;
            ok = 0;
            for (n = 0; n < 60 && !ok; n = n + 1) begin
                @(posedge clk);
                #1;
                if (done === 1'b1) ok = 1;
            end
            check(ok == 0, "N6: done must never assert while reset is held asserted");
            check(dut.u_ctrl.state === 3'd0, "N6: FSM must remain in S_IDLE throughout while reset is held asserted");
            $display("N6: done-timeout mechanism correctly reported TIMEOUT after %0d cycles (as expected under held reset)", n);
        end

        $display("tb_negative: %0d checks, %0d failures", check_count, error_count);
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
        $display("FAIL: tb_negative global timeout -- simulation did not finish");
        $fatal(1);
    end
endmodule
