// Verify NTT outputs, intermediate stages, butterfly sequencing, and execution timing.

`default_nettype none

module tb_ntt_top;

    reg         clk;
    reg         rst;
    reg         start;
    reg  [39:0] coef_in;
    wire        busy;
    wire        done;
    wire [39:0] coef_out;

    ntt_top dut (
        .clk(clk), .rst(rst), .start(start), .coef_in(coef_in),
        .busy(busy), .done(done), .coef_out(coef_out)
    );

    always #5 clk = ~clk;

    integer cycle_count;
    // Track clock cycles using a nonblocking assignment to avoid testbench races.
    always @(posedge clk) cycle_count <= cycle_count + 1;

    integer error_count;
    integer check_count;
    integer setup_error_count;
    integer vectors_checked;

    // Share scratch buffers across tasks.
    reg [4:0] rdbuf [0:7];
    reg [4:0] stage_check_expected [0:7];

    // Define the expected butterfly schedule independently of the DUT.
    reg [2:0] exp_lo   [0:11];
    reg [2:0] exp_hi   [0:11];
    reg [2:0] exp_texp [0:11];

    integer butterflies_this_transform;
    integer butterflies_total;

    integer first_elapsed_recorded;
    integer first_elapsed_cycles;

    integer i;

    initial begin
        // Initialize stage 1: butterfly distance 4.
        exp_lo[0]=3'd0; exp_hi[0]=3'd4; exp_texp[0]=3'd0;
        exp_lo[1]=3'd1; exp_hi[1]=3'd5; exp_texp[1]=3'd1;
        exp_lo[2]=3'd2; exp_hi[2]=3'd6; exp_texp[2]=3'd2;
        exp_lo[3]=3'd3; exp_hi[3]=3'd7; exp_texp[3]=3'd3;
        // Initialize stage 2: butterfly distance 2.
        exp_lo[4]=3'd0; exp_hi[4]=3'd2; exp_texp[4]=3'd0;
        exp_lo[5]=3'd1; exp_hi[5]=3'd3; exp_texp[5]=3'd2;
        exp_lo[6]=3'd4; exp_hi[6]=3'd6; exp_texp[6]=3'd0;
        exp_lo[7]=3'd5; exp_hi[7]=3'd7; exp_texp[7]=3'd2;
        // Initialize stage 3: butterfly distance 1.
        exp_lo[8]=3'd0; exp_hi[8]=3'd1; exp_texp[8]=3'd0;
        exp_lo[9]=3'd2; exp_hi[9]=3'd3; exp_texp[9]=3'd0;
        exp_lo[10]=3'd4; exp_hi[10]=3'd5; exp_texp[10]=3'd0;
        exp_lo[11]=3'd6; exp_hi[11]=3'd7; exp_texp[11]=3'd0;
    end

    // Monitor internal signals without modifying DUT state.
    // Monitor butterfly sequencing and verify state-dependent control signals.
    always @(posedge clk) begin
        #1;
        if (dut.u_ctrl.state == 3'd2) begin // S_READ: issue one butterfly.
            check_count = check_count + 1;
            if (dut.u_ctrl.lo !== exp_lo[butterflies_this_transform] ||
                dut.u_ctrl.hi !== exp_hi[butterflies_this_transform] ||
                dut.u_ctrl.twiddle_exp !== exp_texp[butterflies_this_transform]) begin
                error_count = error_count + 1;
                $display("FAIL: butterfly #%0d this-transform got (lo=%0d hi=%0d texp=%0d) expected (lo=%0d hi=%0d texp=%0d)",
                    butterflies_this_transform, dut.u_ctrl.lo, dut.u_ctrl.hi, dut.u_ctrl.twiddle_exp,
                    exp_lo[butterflies_this_transform], exp_hi[butterflies_this_transform], exp_texp[butterflies_this_transform]);
            end
            butterflies_this_transform = butterflies_this_transform + 1;
            butterflies_total = butterflies_total + 1;
        end

        check_count = check_count + 1;
        if (dut.u_ctrl.write_enable && dut.u_ctrl.state !== 3'd4) begin
            error_count = error_count + 1;
            $display("FAIL: write_enable asserted outside WRITE state (state=%0d)", dut.u_ctrl.state);
        end

        check_count = check_count + 1;
        if (dut.u_ctrl.load_enable && dut.u_ctrl.state !== 3'd1) begin
            error_count = error_count + 1;
            $display("FAIL: load_enable asserted outside LOAD state (state=%0d)", dut.u_ctrl.state);
        end
    end

    // Read eight decimal coefficients and report invalid vector files.
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
                        $display("SETUP-ERROR: '%0s': failed to read a valid integer at line %0d (only %0d value(s) read)", path, li+1, li);
                        ok = 0;
                        val = 0;
                    end else if (val < 0 || val > 16) begin
                        $display("SETUP-ERROR: '%0s' line %0d: coefficient %0d outside canonical range 0..16", path, li+1, val);
                        ok = 0;
                    end
                    rdbuf[li] = val[4:0];
                end
                extra_rc = $fscanf(fd, "%d", extra_val);
                if (extra_rc == 1) begin
                    $display("SETUP-ERROR: '%0s': contains more than 8 numeric values", path);
                    ok = 0;
                end
                $fclose(fd);
            end
        end
    endtask

    // Verify all eight memory coefficients against the expected stage checkpoint.
    task check_stage_mem;
        input [8*32-1:0] vecname;
        input integer stage_num;
        integer m;
        begin
            check_count = check_count + 1;
            for (m = 0; m < 8; m = m + 1) begin
                if (dut.u_mem.mem[m] !== stage_check_expected[m]) begin
                    error_count = error_count + 1;
                    $display("FAIL: vector '%0s' stage %0d checkpoint: mem[%0d] expected=%0d actual=%0d",
                        vecname, stage_num, m, stage_check_expected[m], dut.u_mem.mem[m]);
                end
            end
        end
    endtask

    // Load vector data, execute the transform, and verify outputs and execution behavior.
    task run_vector;
        input [8*32-1:0] name;
        reg [8*256-1:0] input_path, expected_path, s1_path, s2_path, s3_path;
        reg ok_in, ok_exp, ok_s1, ok_s2, ok_s3;
        reg [4:0] in_vec [0:7];
        reg [4:0] exp_out [0:7];
        reg [4:0] s1_exp [0:7];
        reg [4:0] s2_exp [0:7];
        reg [4:0] s3_exp [0:7];
        reg [4:0] actual_out;
        integer k, cyc_start, cyc_done, elapsed, timeout_limit, mismatch;
        reg checkpoint1_done, checkpoint2_done;
        begin
            $sformat(input_path,    "reference/test_vectors/input_%0s.txt", name);
            $sformat(expected_path, "reference/test_vectors/expected_%0s.txt", name);
            $sformat(s1_path, "reference/stage_checkpoints/stage1_%0s.txt", name);
            $sformat(s2_path, "reference/stage_checkpoints/stage2_%0s.txt", name);
            $sformat(s3_path, "reference/stage_checkpoints/stage3_%0s.txt", name);

            read_8_vector(input_path, ok_in);
            for (k = 0; k < 8; k = k + 1) in_vec[k] = rdbuf[k];
            read_8_vector(expected_path, ok_exp);
            for (k = 0; k < 8; k = k + 1) exp_out[k] = rdbuf[k];
            read_8_vector(s1_path, ok_s1);
            for (k = 0; k < 8; k = k + 1) s1_exp[k] = rdbuf[k];
            read_8_vector(s2_path, ok_s2);
            for (k = 0; k < 8; k = k + 1) s2_exp[k] = rdbuf[k];
            read_8_vector(s3_path, ok_s3);
            for (k = 0; k < 8; k = k + 1) s3_exp[k] = rdbuf[k];

            check_count = check_count + 1;
            if (!(ok_in && ok_exp && ok_s1 && ok_s2 && ok_s3)) begin
                setup_error_count = setup_error_count + 1;
                $display("SETUP-ERROR: vector '%0s': one or more files failed to load; skipping DUT run for this vector", name);
            end else begin
                vectors_checked = vectors_checked + 1;
                coef_in = {in_vec[7], in_vec[6], in_vec[5], in_vec[4],
                           in_vec[3], in_vec[2], in_vec[1], in_vec[0]};

                butterflies_this_transform = 0;
                checkpoint1_done = 0;
                checkpoint2_done = 0;

                @(posedge clk);
                start <= 1'b1;
                cyc_start = cycle_count;
                @(posedge clk);
                start <= 1'b0;

                // Allow the start-edge updates to settle before checking completion.
                @(posedge clk);
                #1;
                if (!checkpoint1_done && dut.u_ctrl.state === 3'd2 && dut.u_ctrl.stage === 2'd1) begin
                    checkpoint1_done = 1;
                    for (k = 0; k < 8; k = k + 1) stage_check_expected[k] = s1_exp[k];
                    check_stage_mem(name, 1);
                end

                timeout_limit = cyc_start + 200;
                while (!done && cycle_count < timeout_limit) begin
                    @(posedge clk);
                    #1;
                    if (!checkpoint1_done && dut.u_ctrl.state === 3'd2 && dut.u_ctrl.stage === 2'd1) begin
                        checkpoint1_done = 1;
                        for (k = 0; k < 8; k = k + 1) stage_check_expected[k] = s1_exp[k];
                        check_stage_mem(name, 1);
                    end
                    if (!checkpoint2_done && dut.u_ctrl.state === 3'd2 && dut.u_ctrl.stage === 2'd2) begin
                        checkpoint2_done = 1;
                        for (k = 0; k < 8; k = k + 1) stage_check_expected[k] = s2_exp[k];
                        check_stage_mem(name, 2);
                    end
                end

                check_count = check_count + 1;
                if (!done) begin
                    error_count = error_count + 1;
                    $display("FAIL: vector '%0s': TIMEOUT waiting for done (no done within 200 cycles of start)", name);
                end else begin
                    cyc_done = cycle_count;
                    elapsed = cyc_done - cyc_start;

                    for (k = 0; k < 8; k = k + 1) stage_check_expected[k] = s3_exp[k];
                    check_stage_mem(name, 3);

                    #1;
                    mismatch = 0;
                    for (k = 0; k < 8; k = k + 1) begin
                        actual_out = coef_out[5*k +: 5];
                        check_count = check_count + 1;
                        if (actual_out > 16) begin
                            error_count = error_count + 1;
                            $display("FAIL: vector '%0s': output coefficient %0d = %0d outside canonical range 0..16", name, k, actual_out);
                        end
                        check_count = check_count + 1;
                        if (actual_out !== exp_out[k]) begin
                            mismatch = mismatch + 1;
                            error_count = error_count + 1;
                            $display("FAIL: vector '%0s': coefficient %0d mismatch: expected=%0d actual=%0d", name, k, exp_out[k], actual_out);
                        end
                    end

                    check_count = check_count + 1;
                    if (butterflies_this_transform !== 12) begin
                        error_count = error_count + 1;
                        $display("FAIL: vector '%0s': expected exactly 12 butterflies, observed %0d", name, butterflies_this_transform);
                    end

                    check_count = check_count + 1;
                    if (first_elapsed_recorded == 0) begin
                        first_elapsed_cycles = elapsed;
                        first_elapsed_recorded = 1;
                        $display("INFO: first measured start-to-done latency = %0d cycles (vector '%0s')", elapsed, name);
                    end else if (elapsed !== first_elapsed_cycles) begin
                        error_count = error_count + 1;
                        $display("FAIL: vector '%0s': elapsed cycles %0d differs from first-measured %0d (timing should be data-independent)", name, elapsed, first_elapsed_cycles);
                    end

                    if (mismatch == 0) begin
                        $display("PASS: vector '%0s' (cycles=%0d, butterflies=%0d)", name, elapsed, butterflies_this_transform);
                    end
                end
            end
        end
    endtask

    reg [8*32-1:0] vec_name [0:63];
    integer n_vectors;

    // Load vector names from the generated manifest.
    task load_manifest;
        integer mf, rc;
        reg [8*32-1:0] one_name;
        begin
            n_vectors = 0;
            mf = $fopen("tb/vector_names.txt", "r");
            if (mf == 0) begin
                $display("FATAL: cannot open tb/vector_names.txt manifest");
                $fatal(1);
            end
            while (!$feof(mf) && n_vectors < 64) begin
                rc = $fscanf(mf, "%s", one_name);
                if (rc == 1) begin
                    vec_name[n_vectors] = one_name;
                    n_vectors = n_vectors + 1;
                end
            end
            $fclose(mf);
        end
    endtask

    initial begin
        clk = 0;
        rst = 1;
        start = 0;
        coef_in = 40'd0;
        cycle_count = 0;
        error_count = 0;
        check_count = 0;
        setup_error_count = 0;
        vectors_checked = 0;
        butterflies_total = 0;
        first_elapsed_recorded = 0;

        load_manifest;
        $display("tb_ntt_top: loaded manifest with %0d vector names", n_vectors);

        repeat (3) @(posedge clk);
        rst <= 1'b0;
        @(posedge clk);

        for (i = 0; i < n_vectors; i = i + 1) begin
            run_vector(vec_name[i]);
        end

        $display("");
        $display("tb_ntt_top summary:");
        $display("  vectors in manifest        : %0d", n_vectors);
        $display("  vectors actually DUT-tested: %0d", vectors_checked);
        $display("  setup errors               : %0d", setup_error_count);
        $display("  total butterflies observed : %0d (expected %0d)", butterflies_total, vectors_checked * 12);
        $display("  total individual checks    : %0d", check_count);
        $display("  failures                   : %0d", error_count);

        if (vectors_checked != n_vectors) begin
            error_count = error_count + 1;
            $display("FAIL: not all manifest vectors were DUT-tested (%0d/%0d) -- see SETUP-ERROR lines above", vectors_checked, n_vectors);
        end

        if (error_count != 0) begin
            $display("RESULT: FAIL (%0d failures)", error_count);
            $fatal(1);
        end else begin
            $display("RESULT: PASS (0 failures)");
            $finish;
        end
    end

endmodule
