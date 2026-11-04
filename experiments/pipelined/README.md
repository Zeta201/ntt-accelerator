# Experiment 3: Pipelined NTT Accelerator

[← Back to main README](../../README.md) · [Experiments and evaluation](../../docs/experiments.md)

> Commands below assume the repository root (`ntt_accelerator/`) as the working directory unless otherwise noted.

## Objective

Investigate whether pipelining the $N=8$ forward butterfly datapath reduces execution latency by overlapping independent butterflies within a DIF stage, while preserving the exact baseline mathematics. The experiment also determines the initiation interval permitted by the existing memory architecture rather than assuming that a new butterfly can be issued every cycle throughout the entire transform.

## Pipeline architecture

Within each DIF stage, the four butterflies access disjoint coefficient-address pairs. This allows a new butterfly to be issued every cycle while earlier butterflies are still in flight. The pipeline has three stages, corresponding to the baseline's `READ`, `COMPUTE`, and `WRITE` phases, but overlaps their execution:

1. **Issue** — generates the address and twiddle exponent for the next butterfly using the same combinational formulas as the baseline's `ntt_controller.v`. The operands, twiddle factor, and destination addresses are registered.
2. **Compute** — the reused `butterfly_datapath.v` combinationally computes `u` and `v` from the registered operands and twiddle factor.
3. **Write** — writes `u` and `v` to their destination addresses, with writes enabled only for valid pipeline entries.

A valid bit is carried at each register boundary (`valid1` after issue and `valid2` after compute) and advances with the corresponding data. `write_enable` is driven directly by `valid2`, preventing invalid pipeline entries from modifying coefficient memory.

The existing `coefficient_memory.v` is reused without modification. It provides independent combinational read ports (`lo`/`hi`) and registered write ports (`lo_reg`/`hi_reg`), allowing an issue operation to overlap with an older write. Within each DIF stage, the four butterflies access disjoint address pairs. At stage boundaries, however, a new issue may conflict with a write from the preceding stage, so the controller performs explicit hazard checks before issuing the next butterfly.

## Stage-boundary hazard detection

A fully conservative approach would drain the pipeline completely before advancing to the next stage. However, the dependency only requires delaying a new issue when its read addresses conflict with destinations that have not yet been written. A full pipeline drain is therefore unnecessary.

The controller checks the candidate butterfly's two read addresses (`lo` and `hi`) against the destination addresses of both in-flight entries (`lo1`/`hi1` for the compute-stage entry and `lo_reg`/`hi_reg` for the writing-stage entry). Issuing is stalled only when one of these addresses matches an outstanding write destination.

Tracing the N=8 schedule reveals that only one of the two stage boundaries contains an actual address conflict. Consequently, the controller introduces exactly one stall cycle per transform. The other stage boundary permits the next stage to begin issuing without a stall.

This behavior is verified independently by `pipelined_schedule_model.py` and directly by `tb_pipelined.v`. The Python model reproduces the issue policy and checks the resulting issue/write schedule. The RTL testbench verifies that concurrent issue and write operations never target the same address and that exactly one stall occurs for every tested vector.

Completion is tracked using a second tag (`last1`/`last2`) that advances through the same pipeline stages as the data and identifies the final butterfly. `done` is asserted on the same clock edge as the final memory write, ensuring that completion is aligned with the final writeback rather than requiring an additional confirmation cycle.

## Verification

| Verification | Result |
|---|---:|
| Python schedule-model validation | 192 checks, 0 failures |
| RTL verification | 2,747 checks, 0 failures |
| Test vectors | 31/31 passed |
| Intermediate-stage checkpoints | All 3 stages verified per vector |
| Issue/write destination tracking | Every write matched to its issuing butterfly using an issue-order FIFO |
| Concurrent access safety | All simultaneous issue/write operations verified to use disjoint addresses |
| Stall count | Exactly 1 stall cycle per transform |

`experiments/pipelined/reference/pipelined_schedule_model.py` independently models the controller's issue policy. It issues the next butterfly in fixed schedule order as soon as neither of its read addresses conflicts with an outstanding write in either pipeline slot. It computes the issue and write cycle for all 12 butterflies and verifies that no butterfly is lost, duplicated, or written out of order.

The model also checks that the resulting NTT values match the direct-NTT reference and the on-disk stage checkpoints for all 31 test vectors.

The RTL testbench (`tb_pipelined.v`) reuses the baseline's schedule-expectation tables and stage-checkpoint files because the mathematical operation is unchanged. It adds pipeline-specific checks, including an issue-order FIFO that matches every write to its originating butterfly, verification that `write_enable` only asserts for valid entries, concurrent-access checks, and stall-count verification. Directed tests also cover start requests while busy, reset during pipeline execution, and starting a new transform after reset.

Stage-checkpoint verification uses the number of committed writes to determine when each stage has completed. This ensures that a stage is checked only after all its writes have reached coefficient memory, even when the controller has already advanced to the next stage.

## Performance

Latency is measured in busy cycles using the same convention as the baseline and Experiment 2. A dedicated counter confirms that the execution latency is data-independent across all 31 test vectors.

| Metric | Baseline N=8 | Pipelined N=8 |
|---|---:|---:|
| Transform size | 8 | 8 |
| Butterfly operations | 12 | 12 |
| Pipeline stages | N/A | 3 (issue, compute, write) |
| Per-butterfly pipeline latency | N/A | 3 cycles |
| Initiation interval (within a DIF stage) | N/A | 1 cycle |
| Stall cycles | N/A | 1 |
| Execution latency (busy cycles) | 37 | 16 |
| Average cycles per butterfly (whole transform) | 3.08 (37/12) | 1.33 (16/12) |
| Average throughput | 0.324 butterflies/cycle | 0.750 butterflies/cycle |

Per-butterfly pipeline latency is the time taken for one butterfly to pass through issue, compute, and writeback. The initiation interval (II) describes how frequently a new butterfly can be accepted. These are different measurements: the pipeline latency is three cycles, while the initiation interval is one cycle within a DIF stage.

The initiation interval of one cycle is maintained throughout the issue window of each stage, except where an actual memory dependency requires a stall. For this schedule, exactly one stall occurs at the boundary between stage 0 and stage 1. The stage 1-to-stage 2 boundary has no address conflict and requires no stall.

The total execution latency is:

$$
1\;(\text{LOAD})+12\;(\text{issues})+1\;(\text{stall})+2\;(\text{final pipeline drain})=16\text{ cycles}
$$

The measured improvement reduces execution latency from 37 to 16 cycles, giving a **2.31× speedup**. This approaches the 3× asymptotic throughput improvement expected from overlapping the three baseline operations, although pipeline fill and drain overhead and the single required stall limit the improvement for this 12-butterfly transform.

## Synthesis and hardware-resource evaluation

Both implementations were synthesized using the same generic Yosys flow (`synth -top <top>; stat`).

| Metric | Baseline N=8 | Pipelined N=8 |
|---|---:|---:|
| Generic synthesis cells | 603 | 661 |
| Combinational logic cells (excluding multiplexers) | 364 | 413 |
| Multiplexers | 159 | 158 |
| Flip-flops | 80 | 90 |

Pipelining increases the generic synthesis cell count by 58 (9.6%) and the flip-flop count by 10 (12.5%). The multiplexer count remains essentially unchanged, decreasing by one cell.

The coefficient memory and twiddle ROM are reused unchanged, with identical per-module cell counts of 242 and 7, respectively. The change occurs in the controller, whose total cell count increases from 117 to 175 and whose flip-flop count increases from 40 to 50.

The net increase of 10 flip-flops is accounted for by the controller's register changes. Five additional valid and control bits are introduced (`valid1`, `valid2`, `all_issued`, `last1`, and `last2`), while six additional destination-address bits are required for the second in-flight entry (`lo1` and `hi1`). The state register becomes one bit narrower because the pipelined controller uses three states instead of the baseline's five. Together, these changes account for the net increase of 10 flip-flops.

### Hazard-logic synthesis evaluation

The hazard-detection logic is also evaluated separately. It performs eight 3-bit equality comparisons, checking the next butterfly's two read addresses against the four destination addresses held by the two in-flight entries. To isolate its synthesis cost, `hazard_v1` and `hazard_v2` are tied to constant zero and the design is synthesized again. The generic cell count decreases from 661 to 609, with the entire difference of 52 cells occurring in combinational logic; the flip-flop and multiplexer counts remain unchanged at 90 and 158, respectively.

Therefore, the isolated hazard-detection logic accounts for 52 generic combinational cells under this synthesis flow. These cells implement the address-conflict checks required to safely overlap issue and write operations across stage boundaries.

## Run commands

```bash
# Python schedule-model validation
cd experiments/pipelined/reference
python3 pipelined_schedule_model.py

# RTL verification
cd ../../..
bash scripts/run_pipelined.sh

# Full regression
bash scripts/run_all_experiments.sh

# Synthesis comparison
bash scripts/run_synthesis.sh
```

---

[← Back to main README](../../README.md) · [Experiments and evaluation](../../docs/experiments.md)
