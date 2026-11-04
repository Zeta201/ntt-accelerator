// Verify pipelined NTT results, sequencing, timing, and control behavior.

`default_nettype none

module tb_pipelined;

    localparam STAGES = 3;
    localparam BUTTERFLIES_PER_STAGE = 4;
    localparam TOTAL_BUTTERFLIES = STAGES * BUTTERFLIES_PER_STAGE;

    reg clk;
    reg rst;
    reg start;
    reg [39:0] coef_in;
    wire busy;
    wire done;
    wire [39:0] coef_out;

    ntt_top_pipelined dut (
        .clk(clk), .rst(rst), .start(start), .coef_in(coef_in),
        .busy(busy), .done(done), .coef_out(coef_out)
    );

    always #5 clk = ~clk;

    integer cycle_count;
    always @(posedge clk) cycle_count <= cycle_count + 1;

    // Count busy cycles using the same convention as the other experiments.
    integer busy_cycle_accum;

    integer error_count;
    integer check_count;
    integer setup_error_count;
    integer vectors_checked;

    reg [4:0] rdbuf [0:7];
    reg [4:0] stage_check_expected [0:7];

    reg [4:0] mod_s1_exp [0:7];
    reg [4:0] mod_s2_exp [0:7];
    reg checkpoint1_pending, checkpoint2_pending;
    reg checkpoint1_armed, checkpoint2_armed;

    // Expected butterfly schedule, defined independently of the DUT.
    reg [2:0] exp_lo [0:11];
    reg [2:0] exp_hi [0:11];
    reg [2:0] exp_texp [0:11];

    integer butterflies_this_transform;
    integer butterflies_total;
    integer stalls_this_transform;
    integer writes_this_transform;

    // Track issued destinations to verify write order and completeness.
    reg [2:0] issue_fifo_lo [0:15];
    reg [2:0] issue_fifo_hi [0:15];
    integer fifo_push, fifo_pop;

    integer first_busy_cycles_recorded;
    integer first_busy_cycles;
    integer mon_k;

    integer i;

    initial begin
        exp_lo[0]=3'd0; exp_hi[0]=3'd4; exp_texp[0]=3'd0;
        exp_lo[1]=3'd1; exp_hi[1]=3'd5; exp_texp[1]=3'd1;
        exp_lo[2]=3'd2; exp_hi[2]=3'd6; exp_texp[2]=3'd2;
        exp_lo[3]=3'd3; exp_hi[3]=3'd7; exp_texp[3]=3'd3;
        exp_lo[4]=3'd0; exp_hi[4]=3'd2; exp_texp[4]=3'd0;
        exp_lo[5]=3'd1; exp_hi[5]=3'd3; exp_texp[5]=3'd2;
        exp_lo[6]=3'd4; exp_hi[6]=3'd6; exp_texp[6]=3'd0;
        exp_lo[7]=3'd5; exp_hi[7]=3'd7; exp_texp[7]=3'd2;
        exp_lo[8]=3'd0; exp_hi[8]=3'd1; exp_texp[8]=3'd0;
        exp_lo[9]=3'd2; exp_hi[9]=3'd3; exp_texp[9]=3'd0;
        exp_lo[10]=3'd4; exp_hi[10]=3'd5; exp_texp[10]=3'd0;
        exp_lo[11]=3'd6; exp_hi[11]=3'd7; exp_texp[11]=3'd0;
    end

    // Monitor issue and write events without modifying DUT state.
    always @(posedge clk) begin
        #1;
        // Check checkpoints one cycle after the corresponding writes are observed.
        if (checkpoint1_armed) begin
            checkpoint1_armed = 1'b0;
            for (mon_k = 0; mon_k < 8; mon_k = mon_k + 1) begin
                check_count = check_count + 1;
                if (dut.u_mem.mem[mon_k] !== mod_s1_exp[mon_k]) begin
                    error_count = error_count + 1;
                    $display("FAIL: stage 1 checkpoint: mem[%0d] expected=%0d actual=%0d",
                        mon_k, mod_s1_exp[mon_k], dut.u_mem.mem[mon_k]);
                end
            end
        end
        if (checkpoint2_armed) begin
            checkpoint2_armed = 1'b0;
            for (mon_k = 0; mon_k < 8; mon_k = mon_k + 1) begin
                check_count = check_count + 1;
                if (dut.u_mem.mem[mon_k] !== mod_s2_exp[mon_k]) begin
                    error_count = error_count + 1;
                    $display("FAIL: stage 2 checkpoint: mem[%0d] expected=%0d actual=%0d",
                        mon_k, mod_s2_exp[mon_k], dut.u_mem.mem[mon_k]);
                end
            end
        end

        if (busy) busy_cycle_accum = busy_cycle_accum + 1;

        if (dut.u_ctrl.issue_valid) begin
            check_count = check_count + 1;
            if (dut.u_ctrl.lo !== exp_lo[butterflies_this_transform] ||
                dut.u_ctrl.hi !== exp_hi[butterflies_this_transform] ||
                dut.u_ctrl.twiddle_exp !== exp_texp[butterflies_this_transform]) begin
                error_count = error_count + 1;
                $display("FAIL: issue #%0d this-transform got (lo=%0d hi=%0d texp=%0d) expected (lo=%0d hi=%0d texp=%0d)",
                    butterflies_this_transform, dut.u_ctrl.lo, dut.u_ctrl.hi, dut.u_ctrl.twiddle_exp,
                    exp_lo[butterflies_this_transform], exp_hi[butterflies_this_transform], exp_texp[butterflies_this_transform]);
            end
            issue_fifo_lo[fifo_push] = dut.u_ctrl.lo;
            issue_fifo_hi[fifo_push] = dut.u_ctrl.hi;
            fifo_push = fifo_push + 1;
            butterflies_this_transform = butterflies_this_transform + 1;
            butterflies_total = butterflies_total + 1;
        end

        if (dut.u_ctrl.write_enable) begin
            check_count = check_count + 1;
            if (!dut.u_ctrl.valid2) begin
                error_count = error_count + 1;
                $display("FAIL: write_enable asserted while valid2=0 -- an invalid pipeline entry would be written");
            end
            check_count = check_count + 1;
            if (fifo_pop >= fifo_push) begin
                error_count = error_count + 1;
                $display("FAIL: write observed with no corresponding issue in the FIFO (lost or duplicated issue tracking)");
            end else begin
                if (dut.u_ctrl.lo_reg !== issue_fifo_lo[fifo_pop] || dut.u_ctrl.hi_reg !== issue_fifo_hi[fifo_pop]) begin
                    error_count = error_count + 1;
                    $display("FAIL: write destination (lo=%0d hi=%0d) does not match the oldest outstanding issue (lo=%0d hi=%0d)",
                        dut.u_ctrl.lo_reg, dut.u_ctrl.hi_reg, issue_fifo_lo[fifo_pop], issue_fifo_hi[fifo_pop]);
                end
                fifo_pop = fifo_pop + 1;
            end
            writes_this_transform = writes_this_transform + 1;

            // Arm the checkpoint check for next cycle, once this write has
            // actually landed in memory (see the top of this block).
            if (checkpoint1_pending && writes_this_transform == 4) begin
                checkpoint1_pending = 0;
                checkpoint1_armed = 1'b1;
            end
            if (checkpoint2_pending && writes_this_transform == 8) begin
                checkpoint2_pending = 0;
                checkpoint2_armed = 1'b1;
            end
        end

        // Verify simultaneous issue and write addresses do not overlap.
        if (dut.u_ctrl.issue_valid && dut.u_ctrl.write_enable) begin
            check_count = check_count + 1;
            if (dut.u_ctrl.lo === dut.u_ctrl.lo_reg || dut.u_ctrl.lo === dut.u_ctrl.hi_reg ||
                dut.u_ctrl.hi === dut.u_ctrl.lo_reg || dut.u_ctrl.hi === dut.u_ctrl.hi_reg) begin
                error_count = error_count + 1;
                $display("FAIL: concurrent issue (lo=%0d hi=%0d) collides with concurrent write (lo_reg=%0d hi_reg=%0d)",
                    dut.u_ctrl.lo, dut.u_ctrl.hi, dut.u_ctrl.lo_reg, dut.u_ctrl.hi_reg);
            end
        end

        // Count cycles where hazard detection blocks the next issue.
        if (busy && !dut.u_ctrl.all_issued && !dut.u_ctrl.issue_valid && dut.u_ctrl.state == 2'd2) begin
            stalls_this_transform = stalls_this_transform + 1;
        end
    end

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
        integer k, cyc_start, elapsed, timeout_limit, mismatch;
        integer busy_accum_start, busy_cycles;
        begin
            $sformat(input_path, "reference/test_vectors/input_%0s.txt", name);
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
                writes_this_transform = 0;
                stalls_this_transform = 0;
                fifo_push = 0;
                fifo_pop = 0;

                for (k = 0; k < 8; k = k + 1) mod_s1_exp[k] = s1_exp[k];
                for (k = 0; k < 8; k = k + 1) mod_s2_exp[k] = s2_exp[k];
                checkpoint1_pending = 1'b1;
                checkpoint2_pending = 1'b1;

                @(posedge clk);
                start <= 1'b1;
                cyc_start = cycle_count;
                busy_accum_start = busy_cycle_accum;
                @(posedge clk);
                start <= 1'b0;

                // Allow nonblocking assignments to settle before checking done.
                @(posedge clk);
                #1;

                timeout_limit = cyc_start + 200;
                while (!done && cycle_count < timeout_limit) begin
                    @(posedge clk);
                    #1;
                end

                check_count = check_count + 1;
                if (!done) begin
                    error_count = error_count + 1;
                    $display("FAIL: vector '%0s': TIMEOUT waiting for done (no done within 200 cycles of start)", name);
                end else begin
                    busy_cycles = busy_cycle_accum - busy_accum_start;

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
                    if (butterflies_this_transform !== TOTAL_BUTTERFLIES) begin
                        error_count = error_count + 1;
                        $display("FAIL: vector '%0s': expected exactly %0d issued butterflies, observed %0d", name, TOTAL_BUTTERFLIES, butterflies_this_transform);
                    end

                    check_count = check_count + 1;
                    if (writes_this_transform !== TOTAL_BUTTERFLIES) begin
                        error_count = error_count + 1;
                        $display("FAIL: vector '%0s': expected exactly %0d writes, observed %0d", name, TOTAL_BUTTERFLIES, writes_this_transform);
                    end

                    check_count = check_count + 1;
                    if (fifo_pop !== fifo_push) begin
                        error_count = error_count + 1;
                        $display("FAIL: vector '%0s': %0d issues but only %0d writes matched (lost or stuck pipeline entry)", name, fifo_push, fifo_pop);
                    end

                    // Verify the expected single stall cycle.
                    check_count = check_count + 1;
                    if (stalls_this_transform !== 1) begin
                        error_count = error_count + 1;
                        $display("FAIL: vector '%0s': expected exactly 1 stall cycle, observed %0d", name, stalls_this_transform);
                    end

                    check_count = check_count + 1;
                    if (first_busy_cycles_recorded == 0) begin
                        first_busy_cycles = busy_cycles;
                        first_busy_cycles_recorded = 1;
                        $display("INFO: first measured busy-cycle latency = %0d cycles (vector '%0s')", busy_cycles, name);
                    end else if (busy_cycles !== first_busy_cycles) begin
                        error_count = error_count + 1;
                        $display("FAIL: vector '%0s': busy cycles %0d differs from first-measured %0d (timing should be data-independent)", name, busy_cycles, first_busy_cycles);
                    end

                    if (mismatch == 0) begin
                        $display("PASS: vector '%0s' (busy_cycles=%0d, butterflies=%0d)", name, busy_cycles, butterflies_this_transform);
                    end
                end
            end
        end
    endtask

    reg [8*32-1:0] vec_name [0:63];
    integer n_vectors;

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

    // Verify that start requests received while busy are ignored.
    task start_while_busy_test;
        integer el;
        reg [4:0] rt [0:7];
        reg bad;
        integer k;
        begin
            butterflies_this_transform = 0;
            writes_this_transform = 0;
            stalls_this_transform = 0;
            fifo_push = 0;
            fifo_pop = 0;
            coef_in = {5'd8,5'd7,5'd6,5'd5,5'd4,5'd3,5'd2,5'd1};
            start <= 1'b1;
            @(posedge clk);
            #1;
            start <= 1'b0;
            check_count = check_count + 1;
            if (busy !== 1'b1) begin
                error_count = error_count + 1;
                $display("FAIL: start-while-busy: busy must be 1 after accepted start");
            end
            start <= 1'b1;
            @(posedge clk); #1;
            start <= 1'b0;
            el = 0;
            while (!done && el < 200) begin
                @(posedge clk); #1;
                el = el + 1;
            end
            check_count = check_count + 1;
            if (!done) begin
                error_count = error_count + 1;
                $display("FAIL: start-while-busy: transform did not complete");
            end
            // x=[1..8] -> X=[2,1,12,3,13,6,14,8] (README worked example).
            rt[0]=coef_out[4:0]; rt[1]=coef_out[9:5]; rt[2]=coef_out[14:10]; rt[3]=coef_out[19:15];
            rt[4]=coef_out[24:20]; rt[5]=coef_out[29:25]; rt[6]=coef_out[34:30]; rt[7]=coef_out[39:35];
            bad = (rt[0]!==5'd2 || rt[1]!==5'd1 || rt[2]!==5'd12 || rt[3]!==5'd3 ||
                   rt[4]!==5'd13 || rt[5]!==5'd6 || rt[6]!==5'd14 || rt[7]!==5'd8);
            check_count = check_count + 1;
            if (bad) begin
                error_count = error_count + 1;
                $display("FAIL: start-while-busy: mid-pipeline start pulse corrupted the result");
            end
            @(posedge clk); #1;
        end
    endtask

    // Verify that reset during pipeline fill/drain returns to IDLE cleanly.
    task reset_mid_pipeline_test;
        integer el;
        begin
            butterflies_this_transform = 0;
            writes_this_transform = 0;
            stalls_this_transform = 0;
            fifo_push = 0;
            fifo_pop = 0;
            coef_in = {5'd8,5'd7,5'd6,5'd5,5'd4,5'd3,5'd2,5'd1};
            start <= 1'b1;
            @(posedge clk);
            #1;
            start <= 1'b0;
            for (el = 0; el < 3; el = el + 1) begin
                @(posedge clk); #1;
            end
            check_count = check_count + 1;
            if (busy !== 1'b1) begin
                error_count = error_count + 1;
                $display("FAIL: reset-mid-pipeline: must still be busy before reset");
            end
            rst <= 1'b1;
            @(posedge clk); #1;
            check_count = check_count + 1;
            if (dut.u_ctrl.state !== 2'd0) begin
                error_count = error_count + 1;
                $display("FAIL: reset-mid-pipeline: state must return to S_IDLE the cycle after reset");
            end
            check_count = check_count + 1;
            if (busy !== 1'b0 || done !== 1'b0) begin
                error_count = error_count + 1;
                $display("FAIL: reset-mid-pipeline: busy and done must both be 0 after reset");
            end
            check_count = check_count + 1;
            if (dut.u_ctrl.valid1 !== 1'b0 || dut.u_ctrl.valid2 !== 1'b0) begin
                error_count = error_count + 1;
                $display("FAIL: reset-mid-pipeline: pipeline valid bits must clear on reset (no stale writes afterward)");
            end
            rst <= 1'b0;
            @(posedge clk); #1;
        end
    endtask

    // Verify that a fresh transform after the mid-pipeline reset still completes correctly.
    task fresh_after_reset_test;
        integer el, k;
        reg [4:0] rt;
        begin
            butterflies_this_transform = 0;
            writes_this_transform = 0;
            stalls_this_transform = 0;
            fifo_push = 0;
            fifo_pop = 0;
            coef_in = 40'd0;
            start <= 1'b1;
            @(posedge clk);
            #1;
            start <= 1'b0;
            el = 0;
            while (!done && el < 200) begin
                @(posedge clk); #1;
                el = el + 1;
            end
            check_count = check_count + 1;
            if (!done) begin
                error_count = error_count + 1;
                $display("FAIL: fresh-after-reset: transform did not complete");
            end
            for (k = 0; k < 8; k = k + 1) begin
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
        coef_in = 40'd0;
        cycle_count = 0;
        busy_cycle_accum = 0;
        error_count = 0;
        check_count = 0;
        setup_error_count = 0;
        vectors_checked = 0;
        butterflies_total = 0;
        first_busy_cycles_recorded = 0;
        checkpoint1_pending = 1'b0;
        checkpoint2_pending = 1'b0;
        checkpoint1_armed = 1'b0;
        checkpoint2_armed = 1'b0;

        load_manifest;
        $display("tb_pipelined: loaded manifest with %0d vector names", n_vectors);

        repeat (3) @(posedge clk);
        rst <= 1'b0;
        @(posedge clk);

        for (i = 0; i < n_vectors; i = i + 1) begin
            run_vector(vec_name[i]);
        end

        start_while_busy_test;
        reset_mid_pipeline_test;
        fresh_after_reset_test;

        $display("");
        $display("tb_pipelined summary:");
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
