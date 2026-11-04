// Verify N=16 NTT outputs, intermediate stages, butterfly sequencing, and execution timing.

`default_nettype none

module tb_ntt16;

    localparam N = 16;
    localparam STAGES = 4;
    localparam BUTTERFLIES_PER_STAGE = 8;
    localparam TOTAL_BUTTERFLIES = STAGES * BUTTERFLIES_PER_STAGE;

    reg         clk;
    reg         rst;
    reg         start;
    reg  [79:0] coef_in;
    wire        busy;
    wire        done;
    wire [79:0] coef_out;

    ntt_top16 dut (
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
    reg [4:0] rdbuf [0:15];
    reg [4:0] stage_check_expected [0:15];

    // Define the expected butterfly schedule independently of the DUT
    // (from experiments/ntt16/reference/ntt16_math_validation.py's
    // dif_schedule_pairs, verified there against an independent recursive
    // DIF implementation and the direct NTT definition).
    reg [3:0] exp_lo   [0:31];
    reg [3:0] exp_hi   [0:31];
    reg [3:0] exp_texp [0:31];

    integer butterflies_this_transform;
    integer butterflies_total;

    integer first_elapsed_recorded;
    integer first_elapsed_cycles;

    integer i;

    initial begin
        // Stage 0: distance 8.
        exp_lo[0]=0;  exp_hi[0]=8;   exp_texp[0]=0;
        exp_lo[1]=1;  exp_hi[1]=9;   exp_texp[1]=1;
        exp_lo[2]=2;  exp_hi[2]=10;  exp_texp[2]=2;
        exp_lo[3]=3;  exp_hi[3]=11;  exp_texp[3]=3;
        exp_lo[4]=4;  exp_hi[4]=12;  exp_texp[4]=4;
        exp_lo[5]=5;  exp_hi[5]=13;  exp_texp[5]=5;
        exp_lo[6]=6;  exp_hi[6]=14;  exp_texp[6]=6;
        exp_lo[7]=7;  exp_hi[7]=15;  exp_texp[7]=7;
        // Stage 1: distance 4.
        exp_lo[8]=0;  exp_hi[8]=4;   exp_texp[8]=0;
        exp_lo[9]=1;  exp_hi[9]=5;   exp_texp[9]=2;
        exp_lo[10]=2; exp_hi[10]=6;  exp_texp[10]=4;
        exp_lo[11]=3; exp_hi[11]=7;  exp_texp[11]=6;
        exp_lo[12]=8; exp_hi[12]=12; exp_texp[12]=0;
        exp_lo[13]=9; exp_hi[13]=13; exp_texp[13]=2;
        exp_lo[14]=10; exp_hi[14]=14; exp_texp[14]=4;
        exp_lo[15]=11; exp_hi[15]=15; exp_texp[15]=6;
        // Stage 2: distance 2.
        exp_lo[16]=0;  exp_hi[16]=2;  exp_texp[16]=0;
        exp_lo[17]=1;  exp_hi[17]=3;  exp_texp[17]=4;
        exp_lo[18]=4;  exp_hi[18]=6;  exp_texp[18]=0;
        exp_lo[19]=5;  exp_hi[19]=7;  exp_texp[19]=4;
        exp_lo[20]=8;  exp_hi[20]=10; exp_texp[20]=0;
        exp_lo[21]=9;  exp_hi[21]=11; exp_texp[21]=4;
        exp_lo[22]=12; exp_hi[22]=14; exp_texp[22]=0;
        exp_lo[23]=13; exp_hi[23]=15; exp_texp[23]=4;
        // Stage 3: distance 1.
        exp_lo[24]=0;  exp_hi[24]=1;  exp_texp[24]=0;
        exp_lo[25]=2;  exp_hi[25]=3;  exp_texp[25]=0;
        exp_lo[26]=4;  exp_hi[26]=5;  exp_texp[26]=0;
        exp_lo[27]=6;  exp_hi[27]=7;  exp_texp[27]=0;
        exp_lo[28]=8;  exp_hi[28]=9;  exp_texp[28]=0;
        exp_lo[29]=10; exp_hi[29]=11; exp_texp[29]=0;
        exp_lo[30]=12; exp_hi[30]=13; exp_texp[30]=0;
        exp_lo[31]=14; exp_hi[31]=15; exp_texp[31]=0;
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

    // Read sixteen decimal coefficients and report invalid vector files.
    task read_16_vector;
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
                for (li = 0; li < 16; li = li + 1) begin
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
                    $display("SETUP-ERROR: '%0s': contains more than 16 numeric values", path);
                    ok = 0;
                end
                $fclose(fd);
            end
        end
    endtask

    // Verify all sixteen memory coefficients against the expected stage checkpoint.
    task check_stage_mem;
        input [8*32-1:0] vecname;
        input integer stage_num;
        integer m;
        begin
            check_count = check_count + 1;
            for (m = 0; m < 16; m = m + 1) begin
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
        reg [8*256-1:0] input_path, expected_path, s1_path, s2_path, s3_path, s4_path;
        reg ok_in, ok_exp, ok_s1, ok_s2, ok_s3, ok_s4;
        reg [4:0] in_vec [0:15];
        reg [4:0] exp_out [0:15];
        reg [4:0] s1_exp [0:15];
        reg [4:0] s2_exp [0:15];
        reg [4:0] s3_exp [0:15];
        reg [4:0] s4_exp [0:15];
        reg [4:0] actual_out;
        integer k, cyc_start, cyc_done, elapsed, timeout_limit, mismatch;
        reg checkpoint1_done, checkpoint2_done, checkpoint3_done;
        begin
            $sformat(input_path,    "experiments/ntt16/reference/test_vectors/input_%0s.txt", name);
            $sformat(expected_path, "experiments/ntt16/reference/test_vectors/expected_%0s.txt", name);
            $sformat(s1_path, "experiments/ntt16/reference/stage_checkpoints/stage1_%0s.txt", name);
            $sformat(s2_path, "experiments/ntt16/reference/stage_checkpoints/stage2_%0s.txt", name);
            $sformat(s3_path, "experiments/ntt16/reference/stage_checkpoints/stage3_%0s.txt", name);
            $sformat(s4_path, "experiments/ntt16/reference/stage_checkpoints/stage4_%0s.txt", name);

            read_16_vector(input_path, ok_in);
            for (k = 0; k < 16; k = k + 1) in_vec[k] = rdbuf[k];
            read_16_vector(expected_path, ok_exp);
            for (k = 0; k < 16; k = k + 1) exp_out[k] = rdbuf[k];
            read_16_vector(s1_path, ok_s1);
            for (k = 0; k < 16; k = k + 1) s1_exp[k] = rdbuf[k];
            read_16_vector(s2_path, ok_s2);
            for (k = 0; k < 16; k = k + 1) s2_exp[k] = rdbuf[k];
            read_16_vector(s3_path, ok_s3);
            for (k = 0; k < 16; k = k + 1) s3_exp[k] = rdbuf[k];
            read_16_vector(s4_path, ok_s4);
            for (k = 0; k < 16; k = k + 1) s4_exp[k] = rdbuf[k];

            check_count = check_count + 1;
            if (!(ok_in && ok_exp && ok_s1 && ok_s2 && ok_s3 && ok_s4)) begin
                setup_error_count = setup_error_count + 1;
                $display("SETUP-ERROR: vector '%0s': one or more files failed to load; skipping DUT run for this vector", name);
            end else begin
                vectors_checked = vectors_checked + 1;
                coef_in = {in_vec[15], in_vec[14], in_vec[13], in_vec[12],
                           in_vec[11], in_vec[10], in_vec[9],  in_vec[8],
                           in_vec[7],  in_vec[6],  in_vec[5],  in_vec[4],
                           in_vec[3],  in_vec[2],  in_vec[1],  in_vec[0]};

                butterflies_this_transform = 0;
                checkpoint1_done = 0;
                checkpoint2_done = 0;
                checkpoint3_done = 0;

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
                    for (k = 0; k < 16; k = k + 1) stage_check_expected[k] = s1_exp[k];
                    check_stage_mem(name, 1);
                end

                timeout_limit = cyc_start + 400;
                while (!done && cycle_count < timeout_limit) begin
                    @(posedge clk);
                    #1;
                    if (!checkpoint1_done && dut.u_ctrl.state === 3'd2 && dut.u_ctrl.stage === 2'd1) begin
                        checkpoint1_done = 1;
                        for (k = 0; k < 16; k = k + 1) stage_check_expected[k] = s1_exp[k];
                        check_stage_mem(name, 1);
                    end
                    if (!checkpoint2_done && dut.u_ctrl.state === 3'd2 && dut.u_ctrl.stage === 2'd2) begin
                        checkpoint2_done = 1;
                        for (k = 0; k < 16; k = k + 1) stage_check_expected[k] = s2_exp[k];
                        check_stage_mem(name, 2);
                    end
                    if (!checkpoint3_done && dut.u_ctrl.state === 3'd2 && dut.u_ctrl.stage === 2'd3) begin
                        checkpoint3_done = 1;
                        for (k = 0; k < 16; k = k + 1) stage_check_expected[k] = s3_exp[k];
                        check_stage_mem(name, 3);
                    end
                end

                check_count = check_count + 1;
                if (!done) begin
                    error_count = error_count + 1;
                    $display("FAIL: vector '%0s': TIMEOUT waiting for done (no done within 400 cycles of start)", name);
                end else begin
                    cyc_done = cycle_count;
                    elapsed = cyc_done - cyc_start;

                    for (k = 0; k < 16; k = k + 1) stage_check_expected[k] = s4_exp[k];
                    check_stage_mem(name, 4);

                    #1;
                    mismatch = 0;
                    for (k = 0; k < 16; k = k + 1) begin
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
                    if (butterflies_this_transform !== TOTAL_BUTTERFLIES) begin
                        error_count = error_count + 1;
                        $display("FAIL: vector '%0s': expected exactly %0d butterflies, observed %0d", name, TOTAL_BUTTERFLIES, butterflies_this_transform);
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
            mf = $fopen("experiments/ntt16/tb/vector_names16.txt", "r");
            if (mf == 0) begin
                $display("FATAL: cannot open experiments/ntt16/tb/vector_names16.txt manifest");
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

    // Verify that start requests received while busy are ignored.
    task start_while_busy_test;
        integer el;
        reg [4:0] rt [0:15];
        reg [4:0] expected_ones_dft [0:15];
        integer k;
        integer mm;
        reg bad;
        begin
            // x=[1]*16 -> X = direct_dft([1]*16) = [16,0,0,...,0] (see reference model).
            expected_ones_dft[0] = 5'd16;
            for (k = 1; k < 16; k = k + 1) expected_ones_dft[k] = 5'd0;

            butterflies_this_transform = 0;
            coef_in = {16{5'd1}};
            start <= 1'b1;
            @(posedge clk);
            #1;
            start <= 1'b0;
            check_count = check_count + 1;
            if (busy !== 1'b1) begin
                error_count = error_count + 1;
                $display("FAIL: start-while-busy: busy must be 1 after accepted start");
            end
            // Issue a spurious start pulse mid-transform; it must be ignored.
            start <= 1'b1;
            @(posedge clk); #1;
            start <= 1'b0;
            el = 0;
            while (!done && el < 400) begin
                @(posedge clk); #1;
                el = el + 1;
            end
            check_count = check_count + 1;
            if (!done) begin
                error_count = error_count + 1;
                $display("FAIL: start-while-busy: transform did not complete");
            end
            for (k = 0; k < 16; k = k + 1) rt[k] = coef_out[5*k +: 5];
            check_count = check_count + 1;
            bad = 0;
            for (mm = 0; mm < 16; mm = mm + 1)
                if (rt[mm] !== expected_ones_dft[mm]) bad = 1;
            if (bad) begin
                error_count = error_count + 1;
                $display("FAIL: start-while-busy: mid-flight start pulse corrupted the result");
            end
            @(posedge clk); #1;
        end
    endtask

    // Verify that reset during the transform returns the controller to IDLE.
    task reset_mid_transform_test;
        integer el;
        begin
            butterflies_this_transform = 0;
            coef_in = {16{5'd1}};
            start <= 1'b1;
            @(posedge clk);
            #1;
            start <= 1'b0;
            // Run partway through the transform, well before completion.
            for (el = 0; el < 30; el = el + 1) begin
                @(posedge clk); #1;
            end
            check_count = check_count + 1;
            if (busy !== 1'b1) begin
                error_count = error_count + 1;
                $display("FAIL: reset-mid-transform: must still be busy before reset");
            end
            rst <= 1'b1;
            @(posedge clk); #1;
            check_count = check_count + 1;
            if (dut.u_ctrl.state !== 3'd0) begin
                error_count = error_count + 1;
                $display("FAIL: reset-mid-transform: state must return to S_IDLE the cycle after reset");
            end
            check_count = check_count + 1;
            if (busy !== 1'b0) begin
                error_count = error_count + 1;
                $display("FAIL: reset-mid-transform: busy must be 0 after reset");
            end
            check_count = check_count + 1;
            if (done !== 1'b0) begin
                error_count = error_count + 1;
                $display("FAIL: reset-mid-transform: done must be 0 after reset");
            end
            rst <= 1'b0;
            @(posedge clk); #1;
        end
    endtask

    // Verify that a new transform after the mid-transform reset still completes correctly.
    task fresh_after_reset_test;
        integer el, k;
        reg [4:0] rt;
        begin
            butterflies_this_transform = 0;
            coef_in = 80'd0;
            start <= 1'b1;
            @(posedge clk);
            #1;
            start <= 1'b0;
            el = 0;
            while (!done && el < 400) begin
                @(posedge clk); #1;
                el = el + 1;
            end
            check_count = check_count + 1;
            if (!done) begin
                error_count = error_count + 1;
                $display("FAIL: fresh-after-reset: transform did not complete");
            end
            for (k = 0; k < 16; k = k + 1) begin
                rt = coef_out[5*k +: 5];
                check_count = check_count + 1;
                if (rt !== 5'd0) begin
                    error_count = error_count + 1;
                    $display("FAIL: fresh-after-reset: coefficient %0d expected 0, got %0d", k, rt);
                end
            end
        end
    endtask

    initial begin
        clk = 0;
        rst = 1;
        start = 0;
        coef_in = 80'd0;
        cycle_count = 0;
        error_count = 0;
        check_count = 0;
        setup_error_count = 0;
        vectors_checked = 0;
        butterflies_total = 0;
        first_elapsed_recorded = 0;

        load_manifest;
        $display("tb_ntt16: loaded manifest with %0d vector names", n_vectors);

        repeat (3) @(posedge clk);
        rst <= 1'b0;
        @(posedge clk);

        for (i = 0; i < n_vectors; i = i + 1) begin
            run_vector(vec_name[i]);
        end

        start_while_busy_test;
        reset_mid_transform_test;
        fresh_after_reset_test;

        $display("");
        $display("tb_ntt16 summary:");
        $display("  vectors in manifest        : %0d", n_vectors);
        $display("  vectors actually DUT-tested: %0d", vectors_checked);
        $display("  setup errors               : %0d", setup_error_count);
        $display("  total butterflies observed : %0d (expected %0d)", butterflies_total, vectors_checked * TOTAL_BUTTERFLIES);
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
