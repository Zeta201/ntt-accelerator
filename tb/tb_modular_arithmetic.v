// Verify modular arithmetic operations against independent results for all 289 canonical-residue pairs.

`default_nettype none

module tb_modular_arithmetic;

    reg  [4:0] a, b;
    wire [4:0] sum, diff, v;

    mod_add u_add (.a(a), .b(b), .sum(sum));
    mod_sub u_sub (.a(a), .b(b), .diff(diff));
    mod_mul u_mul (.diff(a), .tw(b), .v(v));

    integer ai, bi;
    integer exp_add, exp_sub, exp_mul;
    integer error_count;
    integer check_count;

    initial begin
        error_count = 0;
        check_count = 0;

        for (ai = 0; ai <= 16; ai = ai + 1) begin
            for (bi = 0; bi <= 16; bi = bi + 1) begin
                a = ai[4:0];
                b = bi[4:0];
                #1;

                exp_add = (ai + bi) % 17;
                // Normalize negative remainders to match canonical modulo-17 results.
                exp_sub = (((ai - bi) % 17) + 17) % 17;
                exp_mul = (ai * bi) % 17;

                check_count = check_count + 1;
                if (sum !== exp_add[4:0]) begin
                    error_count = error_count + 1;
                    $display("FAIL: mod_add a=%0d b=%0d: got %0d expected %0d", ai, bi, sum, exp_add);
                end

                check_count = check_count + 1;
                if (diff !== exp_sub[4:0]) begin
                    error_count = error_count + 1;
                    $display("FAIL: mod_sub a=%0d b=%0d: got %0d expected %0d", ai, bi, diff, exp_sub);
                end

                check_count = check_count + 1;
                if (v !== exp_mul[4:0]) begin
                    error_count = error_count + 1;
                    $display("FAIL: mod_mul diff=%0d tw=%0d: got %0d expected %0d (p=%0d)", ai, bi, v, exp_mul, ai*bi);
                end

                check_count = check_count + 1;
                if (sum > 16) begin
                    error_count = error_count + 1;
                    $display("FAIL: mod_add result %0d outside canonical range (a=%0d,b=%0d)", sum, ai, bi);
                end

                check_count = check_count + 1;
                if (diff > 16) begin
                    error_count = error_count + 1;
                    $display("FAIL: mod_sub result %0d outside canonical range (a=%0d,b=%0d)", diff, ai, bi);
                end

                check_count = check_count + 1;
                if (v > 16) begin
                    error_count = error_count + 1;
                    $display("FAIL: mod_mul result %0d outside canonical range (diff=%0d,tw=%0d)", v, ai, bi);
                end
            end
        end

        $display("tb_modular_arithmetic: checked %0d pairs, %0d total checks, %0d failures", 17*17, check_count, error_count);
        if (error_count != 0) begin
            $display("RESULT: FAIL (%0d failures)", error_count);
            $fatal(1);
        end else begin
            $display("RESULT: PASS (0 failures)");
            $finish;
        end
    end
endmodule
