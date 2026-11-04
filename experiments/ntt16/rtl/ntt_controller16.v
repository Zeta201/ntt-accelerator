`default_nettype none

// Control the iterative 16-point NTT execution.
module ntt_controller16 (
    input  wire       clk,
    input  wire       rst,
    input  wire       start,
    output wire       busy,
    output reg        done,

    output wire [3:0] lo,
    output wire [3:0] hi,
    input  wire [4:0] a_in,
    input  wire [4:0] b_in,

    output wire       load_enable,
    output wire       write_enable,
    output reg  [3:0] lo_reg,
    output reg  [3:0] hi_reg,
    output reg  [4:0] u_reg,
    output reg  [4:0] v_reg
);
    localparam [2:0] S_IDLE    = 3'd0;
    localparam [2:0] S_LOAD    = 3'd1;
    localparam [2:0] S_READ    = 3'd2;
    localparam [2:0] S_COMPUTE = 3'd3;
    localparam [2:0] S_WRITE   = 3'd4;

    reg [2:0] state;
    reg [1:0] stage;
    reg [2:0] bidx;
    reg       start_d;

    reg [4:0] a_reg, b_reg, tw_reg;

    wire start_pulse = start & ~start_d;

    assign busy         = (state != S_IDLE);
    assign load_enable  = (state == S_LOAD)  & ~rst;
    assign write_enable = (state == S_WRITE) & ~rst;

    // Address and twiddle-exponent generation for N=16 (4 stages, 8
    // butterflies/stage). Same shift/mask construction as the baseline
    // ntt_controller.v, generalized from log2(N/2)=2 bits to 3 bits of
    // bidx and from 3 stages to 4.
    wire [3:0] half      = 4'd8 >> stage;
    wire [1:0] shift_amt = 2'd3 - stage;
    wire [2:0] group     = bidx >> shift_amt;
    wire [3:0] half_m1   = half - 4'd1;
    wire [2:0] j         = bidx & half_m1[2:0];
    wire [4:0] two_half  = {1'b0, half} << 1;
    wire [6:0] prod      = group * two_half;
    wire [7:0] lo_full    = {1'b0, prod} + {5'b0, j};
    wire [7:0] hi_full    = lo_full + {4'b0, half};
    wire [6:0] texp_full  = ({4'b0, j} << stage);

    assign lo = lo_full[3:0];
    assign hi = hi_full[3:0];
    wire [3:0] twiddle_exp = texp_full[3:0];

    wire [4:0] tw;
    twiddle_rom16 u_rom (.exponent(twiddle_exp), .tw(tw));

    wire [4:0] u_c, v_c;
    butterfly_datapath u_bfly (.a(a_reg), .b(b_reg), .tw(tw_reg), .u(u_c), .v(v_c));

    always @(posedge clk) begin
        if (rst) begin
            state   <= S_IDLE;
            stage   <= 2'd0;
            bidx    <= 3'd0;
            done    <= 1'b0;
            start_d <= 1'b0;
        end else begin
            start_d <= start;

            case (state)
                S_IDLE: begin
                    if (start_pulse) begin
                        state <= S_LOAD;
                        done  <= 1'b0;
                    end
                end

                S_LOAD: begin
                    stage <= 2'd0;
                    bidx  <= 3'd0;
                    state <= S_READ;
                end

                S_READ: begin
                    a_reg  <= a_in;
                    b_reg  <= b_in;
                    tw_reg <= tw;
                    lo_reg <= lo;
                    hi_reg <= hi;
                    state  <= S_COMPUTE;
                end

                S_COMPUTE: begin
                    u_reg <= u_c;
                    v_reg <= v_c;
                    state <= S_WRITE;
                end

                S_WRITE: begin
                    if (bidx == 3'd7) begin
                        bidx <= 3'd0;
                        if (stage == 2'd3) begin
                            done  <= 1'b1;
                            state <= S_IDLE;
                        end else begin
                            stage <= stage + 2'd1;
                            state <= S_READ;
                        end
                    end else begin
                        bidx  <= bidx + 3'd1;
                        state <= S_READ;
                    end
                end

                default: state <= S_IDLE;
            endcase
        end
    end
endmodule
