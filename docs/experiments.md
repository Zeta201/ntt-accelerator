# Experiments and Evaluation

[← Back to main README](../README.md)

After completing the initial 8-point forward NTT implementation, three experiments were conducted to investigate possible extensions and architectural improvements: inverse transform support, a larger transform size, and pipelined execution.

Each experiment builds on the original implementation's design approach while evaluating a separate architectural variant. The original RTL under `rtl/` remains unchanged, and each experimental implementation is maintained independently under `experiments/`. The experiments evaluate functional correctness, execution latency, and generic synthesis resource counts, and their results are compared against the initial implementation to assess the impact of each extension. Each experiment is implemented, verified, evaluated, and committed separately.

## The experiments

| Experiment | Objective | Details |
|---|---|---|
| **1. Inverse NTT (INTT)** | Extend the accelerator to support inverse NTT while preserving forward-transform behavior and minimizing additional hardware through reuse of the existing butterfly datapath and coefficient memory. | [experiments/intt/README.md](../experiments/intt/README.md) |
| **2. Larger Transform Size (N=16)** | Evaluate how doubling the transform size from $N=8$ to $N=16$ affects the architecture, execution latency, and hardware resource requirements while retaining the existing design approach. | [experiments/ntt16/README.md](../experiments/ntt16/README.md) |
| **3. Pipelined NTT Accelerator** | Investigate whether pipelining the $N=8$ forward butterfly datapath reduces execution latency by overlapping independent butterflies within a DIF stage, while preserving the exact baseline mathematics. | [experiments/pipelined/README.md](../experiments/pipelined/README.md) |

## Synthesis methodology

All designs use the same generic Yosys synthesis flow: load the design's source files with `read_verilog -sv`, then run `hierarchy -top <top>; synth -top <top>; stat`. For example, the baseline (`reports/baseline/synth.ys`):

```text
read_verilog -sv rtl/modular_arithmetic.v
read_verilog -sv rtl/twiddle_rom.v
read_verilog -sv rtl/butterfly_datapath.v
read_verilog -sv rtl/coefficient_memory.v
read_verilog -sv rtl/ntt_controller.v
read_verilog -sv rtl/ntt_top.v
hierarchy -top ntt_top
synth -top ntt_top
stat
```

Each experiment's `reports/<name>/synth.ys` follows the same flow, loading that experiment's own RTL files (plus the unmodified baseline files it reuses) and selecting its own top module (`ntt_top`, `ntt_top16`, or `ntt_top_pipelined`). Running `bash scripts/run_synthesis.sh` executes all four `synth.ys` scripts and regenerates their `synth_report.txt` files.

No FPGA or ASIC target, timing constraints, or technology library is specified. The reported results are therefore generic synthesis cell counts, not device-specific LUT, BRAM, or DSP utilization, ASIC physical area, critical-path delay, maximum operating frequency, or power consumption — none of these were measured.

Raw reports are stored under `reports/`. The same synthesis settings are used for baseline and experimental comparisons.

## Overall comparison

| Metric | Baseline | Experiment 1 (INTT) | Experiment 2 (N=16) | Experiment 3 (Pipelined) |
|---|---:|---:|---:|---:|
| Transform size | 8 | 8 | 16 | 8 |
| Transform direction | Forward only | Forward + inverse | Forward only | Forward only |
| Butterfly operations | 12 | 12 | 32 | 12 |
| Normalization operations | N/A | 8 | N/A | N/A |
| Forward execution latency (busy cycles) | 37 | 37 | 97 | 16 |
| Inverse execution latency (busy cycles) | N/A | 61 | N/A | N/A |
| Hardware pipeline stages | N/A | N/A | N/A | 3 |
| Initiation interval (within a DIF stage) | N/A | N/A | N/A | 1 cycle |
| Stall cycles | N/A | N/A | N/A | 1 |
| Generic synthesis cells | 603 | 673 | 952 | 661 |
| Combinational logic cells (excluding multiplexers) | 364 | 417 | 536 | 413 |
| Multiplexers | 159 | 171 | 293 | 158 |
| Flip-flops | 80 | 85 | 123 | 90 |

All synthesis-cell figures are generic Yosys statistics obtained using the same synthesis flow and settings. They are not FPGA- or ASIC-specific resource estimates. Critical-path delay, maximum operating frequency, and power consumption were not measured. The N=16 implementation uses a different transform size, so its resource counts are included for completeness and are analyzed separately in its experiment README.

## Main findings

- **INTT** adds inverse-transform support for a modest hardware cost (+70 generic cells, +11.6%) by reusing the existing butterfly datapath and coefficient memory; the extra hardware is almost entirely in the controller's normalization-phase logic and the ROM's added inverse-twiddle table, not a separate arithmetic path. Forward-transform latency and correctness are unaffected.
- **N=16** roughly doubles butterfly operations (12 → 32) and latency (37 → 97 cycles), but generic synthesis cells grow by only 57.9% and flip-flops by 53.8% — sub-linear growth, because the single shared butterfly datapath is reused regardless of transform size. Nearly all of the extra hardware is coefficient storage and its wider read-port multiplexers.
- **Pipelining** is the only experiment that changes execution latency without changing the mathematics: overlapping issue/compute/write across butterflies cuts latency from 37 to 16 cycles (2.31×) for a 9.6% increase in generic synthesis cells, at the cost of explicit hazard-detection logic to keep the single in-place memory safe across DIF stage boundaries.
- Across all three, the baseline's shared-datapath, in-place-memory architecture extends cleanly: none of the experiments required a second arithmetic unit or a second memory bank, confirming the baseline's core resource-sharing trade-off (see [Design decisions and trade-offs](architecture.md#design-decisions-and-trade-offs)) holds up under extension.

## Limitations and Future Work

The three experiments above demonstrate several possible extensions to the initial 8-point forward NTT implementation, but each is implemented and evaluated independently rather than combined into a single design. There are still several areas that could be explored further:

- **Configurable transform sizes:** The larger-transform experiment extends the implementation to N=16. Supporting arbitrary transform sizes would require further generalization of the address generation, twiddle-factor storage, and controller.
- **Combined architectural extensions:** The inverse NTT, N=16, and pipelined implementations are separate experimental variants. Combining these capabilities into a unified, configurable accelerator remains future work.
- **Target-specific hardware evaluation:** The synthesis experiments use generic Yosys statistics to compare the relative hardware complexity of the implementations. FPGA- or ASIC-specific resource utilization, critical-path delay, maximum operating frequency, and power consumption have not been evaluated. These would require a target device or technology library and an appropriate implementation flow.
- **Further architectural optimization:** Additional work could investigate alternative butterfly architectures, memory organizations, and pipeline configurations to improve throughput and resource efficiency, particularly for larger transform sizes.

These extensions provide opportunities to develop the accelerator beyond the initial task requirements while retaining the original implementation as a reference for evaluating subsequent designs.

---

[← Back to main README](../README.md) · [Architecture and design](architecture.md) · [Verification and reproducibility](verification.md)
