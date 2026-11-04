`default_nettype none

// Control the pipelined 8-point NTT execution.
module ntt_controller_pipelined (
    input wire clk,
    input wire rst,
    input wire start,
    output wire busy,
    output reg done,

    output wire [2:0] lo,
    output wire [2:0] hi,
    input wire [4:0] a_in,
    input wire [4:0] b_in,

    output wire load_enable,
    output wire write_enable,
    output reg [2:0] lo_reg,
    output reg [2:0] hi_reg,
    output reg [4:0] u_reg,
    output reg [4:0] v_reg
);
    localparam [1:0] S_IDLE = 2'd0;
    localparam [1:0] S_LOAD = 2'd1;
    localparam [1:0] S_RUN = 2'd2;

    reg [1:0] state;
    reg [1:0] stage;
    reg [1:0] bidx;
    reg all_issued;
    reg start_d;

    wire start_pulse = start & ~start_d;

    assign busy = (state != S_IDLE);
    assign load_enable = (state == S_LOAD) & ~rst;

    // Generate addresses and twiddle exponent for the next butterfly.
    wire [2:0] half = 3'd4 >> stage;
    wire [1:0] shift_amt = 2'd2 - stage;
    wire [1:0] group = bidx >> shift_amt;
    wire [2:0] half_m1 = half - 3'd1;
    wire [1:0] j = bidx & half_m1[1:0];
    wire [3:0] two_half = {1'b0, half} << 1;
    wire [5:0] prod = group * two_half;
    wire [6:0] lo_full = {1'b0, prod} + {5'b0, j};
    wire [6:0] hi_full = lo_full + {4'b0, half};
    wire [6:0] texp_full = ({4'b0, j} << stage);

    assign lo = lo_full[2:0];
    assign hi = hi_full[2:0];
    wire [2:0] twiddle_exp = texp_full[2:0];

    wire [4:0] tw;
    twiddle_rom u_rom (.exponent(twiddle_exp), .tw(tw));

    reg [4:0] a1, b1, tw1;
    reg [2:0] lo1, hi1;
    reg valid1;

    wire [4:0] u_c, v_c;
    butterfly_datapath u_bfly (.a(a1), .b(b1), .tw(tw1), .u(u_c), .v(v_c));

    reg valid2;
    assign write_enable = valid2 & ~rst;

    // Prevent reads from addresses with pending writes.
    wire hazard_v1 = valid1 && (lo == lo1 || lo == hi1 || hi == lo1 || hi == hi1);
    wire hazard_v2 = valid2 && (lo == lo_reg || lo == hi_reg || hi == lo_reg || hi == hi_reg);
    wire issue_valid = (state == S_RUN) && !all_issued && !hazard_v1 && !hazard_v2;

    // Track the final butterfly through the pipeline to align done with its write.
    wire is_last_issue = issue_valid && (stage == 2'd2) && (bidx == 2'd3);
    reg last1, last2;

    always @(posedge clk) begin
        if (rst) begin
            state <= S_IDLE;
            stage <= 2'd0;
            bidx <= 2'd0;
            all_issued <= 1'b0;
            done <= 1'b0;
            start_d <= 1'b0;
            valid1 <= 1'b0;
            valid2 <= 1'b0;
            last1 <= 1'b0;
            last2 <= 1'b0;
        end else begin
            start_d <= start;

            valid1 <= issue_valid;
            last1 <= is_last_issue;
            if (issue_valid) begin
                a1 <= a_in;
                b1 <= b_in;
                tw1 <= tw;
                lo1 <= lo;
                hi1 <= hi;
            end

            valid2 <= valid1;
            last2 <= last1;
            if (valid1) begin
                u_reg <= u_c;
                v_reg <= v_c;
                lo_reg <= lo1;
                hi_reg <= hi1;
            end

            case (state)
                S_IDLE: begin
                    if (start_pulse) begin
                        state <= S_LOAD;
                        done <= 1'b0;
                    end
                end

                S_LOAD: begin
                    stage <= 2'd0;
                    bidx <= 2'd0;
                    all_issued <= 1'b0;
                    state <= S_RUN;
                end

                S_RUN: begin
                    if (issue_valid) begin
                        if (bidx == 2'd3) begin
                            bidx <= 2'd0;
                            if (stage == 2'd2) begin
                                all_issued <= 1'b1;
                            end else begin
                                stage <= stage + 2'd1;
                            end
                        end else begin
                            bidx <= bidx + 2'd1;
                        end
                    end
                    if (last2) begin
                        done <= 1'b1;
                        state <= S_IDLE;
                    end
                end

                default: state <= S_IDLE;
            endcase
        end
    end
endmodule
