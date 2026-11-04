// Test forward and inverse transforms, round-trips, normalization,
// and inverse-mode control behavior.

`default_nettype none

module tb_intt;

    localparam [2:0] S_IDLE = 3'd0;

    reg         clk, rst, start, inv;
    reg  [39:0] coef_in;
    wire        busy, done;
    wire [39:0] coef_out;

    ntt_top dut (
        .clk(clk), .rst(rst), .start(start), .inv(inv), .coef_in(coef_in),
        .busy(busy), .done(done), .coef_out(coef_out)
    );

    always #5 clk = ~clk;

    integer cycle_count;
    always @(posedge clk) cycle_count <= cycle_count + 1;

    integer error_count;
    integer check_count;
    integer setup_error_count;

    task check(input cond, input [8*128-1:0] msg);
        begin
            check_count = check_count + 1;
            if (!cond) begin
                $display("FAIL: %0s", msg);
                error_count = error_count + 1;
            end
        end
    endtask

    reg [4:0] rdbuf [0:7];

    task read_8_vector;
        input [8*256-1:0] path;
        output ok;
        integer fd, li, rc, val, extra_rc, extra_val;
        begin
            ok = 1;
            fd = $fopen(path, "r");
            if (fd == 0) begin
                $display("SETUP-ERROR: cannot open file '%0s'", path);
                ok = 0;
            end else begin
                for (li = 0; li < 8; li = li + 1) begin
                    rc = $fscanf(fd, "%d", val);
                    if (rc != 1) begin
                        ok = 0;
                        val = 0;
                    end
                    rdbuf[li] = val[4:0];
                end
                extra_rc = $fscanf(fd, "%d", extra_val);
                if (extra_rc == 1) ok = 0;
                $fclose(fd);
            end
        end
    endtask

    // Run a transform and return its outputs, latency, and completion status.
    task run_transform;
        input mode_inv;
        input [4:0] in0, in1, in2, in3, in4, in5, in6, in7;
        output [4:0] out0, out1, out2, out3, out4, out5, out6, out7;
        output integer elapsed;
        output ok;
        integer cyc_start, cyc_done, timeout_limit;
        begin
            coef_in = {in7, in6, in5, in4, in3, in2, in1, in0};
            inv     = mode_inv;
            start   <= 1'b1;
            @(posedge clk);
            #1;
            cyc_start = cycle_count;
            start <= 1'b0;

            timeout_limit = cyc_start + 200;
            while (!done && cycle_count < timeout_limit) begin
                @(posedge clk);
                #1;
            end

            if (!done) begin
                ok = 0;
                elapsed = -1;
                {out0,out1,out2,out3,out4,out5,out6,out7} = 0;
            end else begin
                ok = 1;
                cyc_done = cycle_count;
                elapsed = cyc_done - cyc_start;
                out0 = coef_out[4:0];   out1 = coef_out[9:5];
                out2 = coef_out[14:10]; out3 = coef_out[19:15];
                out4 = coef_out[24:20]; out5 = coef_out[29:25];
                out6 = coef_out[34:30]; out7 = coef_out[39:35];
                @(posedge clk); #1;
            end
        end
    endtask

    integer i, k;
    integer n_names;
    reg [8*32-1:0] names [0:63];

    task load_manifest;
        integer mf, rc;
        reg [8*32-1:0] one_name;
        begin
            n_names = 0;
            mf = $fopen("tb/vector_names.txt", "r");
            if (mf == 0) begin
                $display("FATAL: cannot open tb/vector_names.txt manifest");
                $fatal(1);
            end
            rc = $fscanf(mf, "%s", one_name);
            while (rc == 1) begin
                names[n_names] = one_name;
                n_names = n_names + 1;
                rc = $fscanf(mf, "%s", one_name);
            end
            $fclose(mf);
        end
    endtask

    reg [4:0] in_vec [0:7];
    reg [4:0] exp_vec [0:7];
    reg [4:0] o0,o1,o2,o3,o4,o5,o6,o7;
    integer elapsed;
    reg ok_in, ok_exp, ok_run;
    reg [8*256-1:0] input_path, expected_path;

    integer fwd_checked, inv_checked, roundtrip_checked;

    initial begin
        clk=0; rst=1; start=0; inv=0; coef_in=0; cycle_count=0;
        error_count=0; check_count=0; setup_error_count=0;
        fwd_checked=0; inv_checked=0; roundtrip_checked=0;

        load_manifest;

        repeat (3) @(posedge clk);
        #1;
        rst <= 1'b0;
        @(posedge clk); #1;

        // Check that the INTT-enabled design preserves baseline forward results
        // and latency.
        for (i = 0; i < n_names; i = i + 1) begin
            $sformat(input_path,    "reference/test_vectors/input_%0s.txt", names[i]);
            $sformat(expected_path, "reference/test_vectors/expected_%0s.txt", names[i]);
            read_8_vector(input_path, ok_in);
            for (k = 0; k < 8; k = k + 1) in_vec[k] = rdbuf[k];
            read_8_vector(expected_path, ok_exp);
            for (k = 0; k < 8; k = k + 1) exp_vec[k] = rdbuf[k];

            check_count = check_count + 1;
            if (!(ok_in && ok_exp)) begin
                setup_error_count = setup_error_count + 1;
                $display("SETUP-ERROR: forward vector '%0s': file load failed", names[i]);
            end else begin
                fwd_checked = fwd_checked + 1;
                run_transform(1'b0, in_vec[0],in_vec[1],in_vec[2],in_vec[3],
                                     in_vec[4],in_vec[5],in_vec[6],in_vec[7],
                              o0,o1,o2,o3,o4,o5,o6,o7, elapsed, ok_run);
                check(ok_run, "forward: done did not assert within timeout");
                if (ok_run) begin
                    check(elapsed == 37, "forward: busy-cycle latency != 37");
                    check(o0===exp_vec[0] && o1===exp_vec[1] && o2===exp_vec[2] && o3===exp_vec[3] &&
                          o4===exp_vec[4] && o5===exp_vec[5] && o6===exp_vec[6] && o7===exp_vec[7],
                          "forward: output mismatch");
                end
            end
        end
        $display("forward-mode regression: %0d/%0d vectors checked", fwd_checked, n_names);

        // Check inverse-transform outputs against the independent reference.
        for (i = 0; i < n_names; i = i + 1) begin
            $sformat(input_path,    "experiments/intt/reference/test_vectors/input_%0s.txt", names[i]);
            $sformat(expected_path, "experiments/intt/reference/test_vectors/expected_%0s.txt", names[i]);
            read_8_vector(input_path, ok_in);
            for (k = 0; k < 8; k = k + 1) in_vec[k] = rdbuf[k];
            read_8_vector(expected_path, ok_exp);
            for (k = 0; k < 8; k = k + 1) exp_vec[k] = rdbuf[k];

            check_count = check_count + 1;
            if (!(ok_in && ok_exp)) begin
                setup_error_count = setup_error_count + 1;
                $display("SETUP-ERROR: inverse vector '%0s': file load failed", names[i]);
            end else begin
                inv_checked = inv_checked + 1;
                run_transform(1'b1, in_vec[0],in_vec[1],in_vec[2],in_vec[3],
                                     in_vec[4],in_vec[5],in_vec[6],in_vec[7],
                              o0,o1,o2,o3,o4,o5,o6,o7, elapsed, ok_run);
                check(ok_run, "inverse: done did not assert within timeout");
                if (ok_run) begin
                    check(elapsed == 61, "inverse: busy-cycle latency != 61");
                    check(o0===exp_vec[0] && o1===exp_vec[1] && o2===exp_vec[2] && o3===exp_vec[3] &&
                          o4===exp_vec[4] && o5===exp_vec[5] && o6===exp_vec[6] && o7===exp_vec[7],
                          "inverse: output mismatch");
                end
            end
        end
        $display("inverse vectors: %0d/%0d vectors checked", inv_checked, n_names);

        // Verify that applying NTT followed by INTT recovers the input.
        for (i = 0; i < n_names; i = i + 2) begin
            $sformat(input_path, "reference/test_vectors/input_%0s.txt", names[i]);
            read_8_vector(input_path, ok_in);
            for (k = 0; k < 8; k = k + 1) in_vec[k] = rdbuf[k];
            check_count = check_count + 1;
            if (!ok_in) begin
                setup_error_count = setup_error_count + 1;
            end else begin : roundtrip_body
                reg [4:0] m0,m1,m2,m3,m4,m5,m6,m7;
                roundtrip_checked = roundtrip_checked + 1;
                run_transform(1'b0, in_vec[0],in_vec[1],in_vec[2],in_vec[3],
                                     in_vec[4],in_vec[5],in_vec[6],in_vec[7],
                              m0,m1,m2,m3,m4,m5,m6,m7, elapsed, ok_run);
                check(ok_run, "round-trip: forward leg did not complete");
                run_transform(1'b1, m0,m1,m2,m3,m4,m5,m6,m7,
                              o0,o1,o2,o3,o4,o5,o6,o7, elapsed, ok_run);
                check(ok_run, "round-trip: inverse leg did not complete");
                check(o0===in_vec[0] && o1===in_vec[1] && o2===in_vec[2] && o3===in_vec[3] &&
                      o4===in_vec[4] && o5===in_vec[5] && o6===in_vec[6] && o7===in_vec[7],
                      "round-trip: INTT(NTT(x)) != x");
            end
        end
        $display("round-trip (NTT then INTT): %0d vectors checked", roundtrip_checked);

        // Verify that the selected transform mode remains unchanged while busy.
        begin : stability_test
            reg [4:0] rt0,rt1,rt2,rt3,rt4,rt5,rt6,rt7;
            integer el; reg okr;
            coef_in = {5'd8,5'd7,5'd6,5'd5,5'd4,5'd3,5'd2,5'd1}; // x=[1..8]
            inv = 1'b1;
            start <= 1'b1;
            @(posedge clk);
            #1;
            start <= 1'b0;
            inv = 1'b0; // toggled while busy; must not affect this transform
            el = 0;
            while (!done && el < 200) begin
                @(posedge clk); #1;
                el = el + 1;
            end
            check(done, "mode stability: transform did not complete");
            rt0=coef_out[4:0]; rt1=coef_out[9:5]; rt2=coef_out[14:10]; rt3=coef_out[19:15];
            rt4=coef_out[24:20]; rt5=coef_out[29:25]; rt6=coef_out[34:30]; rt7=coef_out[39:35];
            check(el == 61,
                  "mode stability: latency changed after inv toggled while busy, mode_reg was not captured correctly");
            // Expected: INTT([1..8]) = [13,1,6,5,8,11,10,15] (INTT(x) != x in general).
            check(rt0===5'd13 && rt1===5'd1 && rt2===5'd6 && rt3===5'd5 &&
                  rt4===5'd8 && rt5===5'd11 && rt6===5'd10 && rt7===5'd15,
                  "mode stability: result changed after inv toggled while busy");
            @(posedge clk); #1;
        end

        // Verify that start requests received while busy are ignored.
        begin : start_while_busy
            integer el; reg okr;
            reg [4:0] rt0,rt1,rt2,rt3,rt4,rt5,rt6,rt7;
            coef_in = {5'd8,5'd7,5'd6,5'd5,5'd4,5'd3,5'd2,5'd1};
            inv = 1'b1;
            start <= 1'b1;
            @(posedge clk);
            #1;
            start <= 1'b0;
            check(busy === 1'b1, "start-while-busy: busy must be 1 after accepted start");
            // Issue a spurious start pulse mid-transform.
            start <= 1'b1;
            @(posedge clk); #1;
            start <= 1'b0;
            el = 0;
            while (!done && el < 200) begin
                @(posedge clk); #1;
                el = el + 1;
            end
            check(done, "start-while-busy: transform did not complete");
            // 60, not 61: the spurious start<=1 pulse consumes one extra edge
            // before this count starts.
            check(el == 60, "start-while-busy: mid-flight start pulse altered the latency");
            rt0=coef_out[4:0]; rt1=coef_out[9:5]; rt2=coef_out[14:10]; rt3=coef_out[19:15];
            rt4=coef_out[24:20]; rt5=coef_out[29:25]; rt6=coef_out[34:30]; rt7=coef_out[39:35];
            check(rt0===5'd13 && rt1===5'd1 && rt2===5'd6 && rt3===5'd5 &&
                  rt4===5'd8 && rt5===5'd11 && rt6===5'd10 && rt7===5'd15,
                  "start-while-busy: mid-flight start pulse corrupted the result");
            @(posedge clk); #1;
        end

        // Verify that reset during normalization returns the controller to IDLE.
        begin : reset_during_norm
            integer el;
            coef_in = {5'd8,5'd7,5'd6,5'd5,5'd4,5'd3,5'd2,5'd1};
            inv = 1'b1;
            start <= 1'b1;
            @(posedge clk);
            #1;
            start <= 1'b0;
            // The 12 butterflies finish at cycle 37, so 40 cycles lands inside
            // the normalization phase.
            for (el = 0; el < 40; el = el + 1) begin
                @(posedge clk); #1;
            end
            check(busy === 1'b1, "reset-during-norm: must still be busy before reset (normalization in progress)");
            check(dut.u_ctrl.phase === 1'b1, "reset-during-norm: controller must be in the normalization phase at this point");
            rst <= 1'b1;
            @(posedge clk); #1;
            check(dut.u_ctrl.state === S_IDLE, "reset-during-norm: state must return to S_IDLE the cycle after reset");
            check(busy === 1'b0, "reset-during-norm: busy must be 0 after reset");
            check(done === 1'b0, "reset-during-norm: done must be 0 after reset");
            rst <= 1'b0;
            @(posedge clk); #1;
        end

        // Verify that a new inverse transform completes correctly after reset.
        begin : fresh_after_reset
            reg [4:0] rt0,rt1,rt2,rt3,rt4,rt5,rt6,rt7;
            run_transform(1'b1, 5'd1,5'd2,5'd3,5'd4,5'd5,5'd6,5'd7,5'd8,
                          rt0,rt1,rt2,rt3,rt4,rt5,rt6,rt7, elapsed, ok_run);
            check(ok_run, "fresh-after-reset: transform did not complete");
            check(elapsed == 61, "fresh-after-reset: latency incorrect");
        end

        // Verify normalization of every coefficient in the memory.
        begin : normalization_per_location
            reg [4:0] rt0,rt1,rt2,rt3,rt4,rt5,rt6,rt7;
            reg [4:0] exp_mem [0:7];
            integer m;
            exp_mem[0]=5'd14; exp_mem[1]=5'd6;  exp_mem[2]=5'd1;  exp_mem[3]=5'd16;
            exp_mem[4]=5'd16; exp_mem[5]=5'd10; exp_mem[6]=5'd8;  exp_mem[7]=5'd3;

            run_transform(1'b1, 5'd6,5'd10,5'd11,5'd15,5'd0,5'd7,5'd12,5'd0,
                          rt0,rt1,rt2,rt3,rt4,rt5,rt6,rt7, elapsed, ok_run);
            check(ok_run, "normalization-per-location: transform did not complete");
            for (m = 0; m < 8; m = m + 1) begin
                check(dut.u_mem.mem[m] === exp_mem[m],
                      "normalization-per-location: mem[m] != coefficient * 15 mod 17 for some m");
            end
        end

        $display("tb_intt: %0d checks, %0d failures, %0d setup errors", check_count, error_count, setup_error_count);
        if (error_count != 0 || setup_error_count != 0) begin
            $display("RESULT: FAIL (%0d failures, %0d setup errors)", error_count, setup_error_count);
            $fatal(1);
        end else begin
            $display("RESULT: PASS (0 failures)");
            $finish;
        end
    end

    initial begin
        #200000;
        $display("FAIL: tb_intt global timeout -- simulation did not finish");
        $fatal(1);
    end
endmodule
