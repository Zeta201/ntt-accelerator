# Experiment 2: Larger Transform Size (N=16)

[← Back to main README](../../README.md) · [Experiments and evaluation](../../docs/experiments.md)

> Commands below assume the repository root (`ntt_accelerator/`) as the working directory unless otherwise noted.

## Objective

Evaluate how doubling the transform size from $N=8$ to $N=16$ affects the architecture, execution latency, and hardware resource requirements while retaining the existing design approach.

## Design changes

The N=16 implementation extends the baseline's radix-2 DIF scheduling and shared-datapath approach to a specific 16-point configuration, using four stages of eight butterflies each.

For $q=17$ and $N=16$:

- Primitive root: $\omega=3$, since $3^{16}\equiv1\pmod{17}$ and $3^8\not\equiv1\pmod{17}$, confirming that its order is exactly 16.
- Twiddle table: `[1, 3, 9, 10, 13, 5, 15, 11, 16, 14, 8, 7, 4, 12, 2, 6]`.

The implementation, kept entirely under `experiments/ntt16/` with the baseline and INTT experiment untouched, adds:

- `coefficient_memory16.v` — a 16-entry coefficient memory, doubling the storage and widening the read/write addresses from 3 to 4 bits.
- `twiddle_rom16.v` — a 16-entry twiddle ROM addressed by a 4-bit exponent, compared with the baseline's 8-entry ROM and 3-bit address.
- `ntt_controller16.v` — generalizes the baseline's shift-and-mask address generation to four stages and eight butterflies per stage, using a 3-bit butterfly index.
- `ntt_top16.v` — follows the same assembly pattern as `ntt_top.v`, with an 80-bit coefficient bus and 4-bit output bit reversal, compared with 40 bits and 3-bit reversal in the baseline.

`butterfly_datapath.v` and `modular_arithmetic.v` are reused unchanged directly from `rtl/`. Both operate on operands in the canonical range 0–16, regardless of transform size, so increasing $N$ does not require changes to the arithmetic datapath.

## Verification

The implementation was checked using an independent Python reference model and RTL simulation, following the same verification structure as the baseline and Experiment 1.

| Verification | Result |
|---|---:|
| Python mathematical validation | 5,014 checks, 0 failures |
| RTL verification | 11,135 checks, 0 failures |
| Test vectors | 39/39 passed |
| Intermediate-stage checkpoints | All 4 stages verified per vector |
| Butterfly schedule | All 32 butterflies per transform verified per vector |

Test vectors cover all-zero, all-one, an impulse at each of the 16 positions, all-maximum, alternating, increasing, decreasing, and boundary inputs, plus 16 seeded-random vectors. The RTL testbench also covers start requests while busy and reset mid-transform, following the baseline's `tb_ntt_top.v` conventions.

## Results

Both implementations were synthesized using the same generic Yosys flow (`synth -top <top>; stat`).

| Metric | N=8 baseline | N=16 implementation |
|---|---:|---:|
| Transform size | 8 | 16 |
| Number of stages | 3 | 4 |
| Butterfly operations | 12 | 32 |
| Transform latency | 37 cycles | 97 cycles |
| Coefficient memory entries | 8 | 16 |
| Coefficient memory bits | 40 | 80 |
| Generic synthesis cells | 603 | 952 |
| Combinational logic cells (excluding multiplexers) | 364 | 536 |
| Multiplexers | 159 | 293 |
| Flip-flops | 80 | 123 |

Latency is measured in busy cycles, from the accepted-start edge through the final `WRITE` cycle. A dedicated counter in `tb_ntt16.v` confirms exactly 97 cycles for each of the 39 test vectors. Both designs follow the same execution pattern: one `LOAD` cycle and three cycles (`READ`, `COMPUTE`, `WRITE`) per butterfly. Therefore, latency is $1+3B$, where $B$ is the number of butterfly operations: 37 cycles for $N=8$ and 97 cycles for $N=16$.

Doubling the transform size increases the butterfly count by 2.67× and latency by 2.62×, while generic synthesis cells increase by 57.9% and flip-flops by 53.8%. The hardware increase is smaller than the increase in butterfly operations because the implementation reuses a single butterfly datapath sequentially. Most of the additional hardware is associated with coefficient storage, read-port logic, addressing, and control.

### Module-level synthesis analysis

The module-level cell counts show how this overhead is distributed:

| Module | N=8 baseline | N=16 implementation |
|---|---:|---:|
| Controller | 117 | 151 |
| Twiddle ROM | 7 | 16 |
| Coefficient memory | 242 | 548 |
| Modular arithmetic (combined) | 237 | 237 |
| Total | 603 | 952 |

Unlike Experiment 1, these module counts add up exactly to the reported design totals in both cases, with no synthesis-context-dependent drift.

The largest increase occurs in the coefficient memory module. Its storage doubles from 40 to 80 bits, while its read ports (`mem[lo]` and `mem[hi]`) require larger 16-to-1 multiplexers instead of the baseline's 8-to-1 multiplexers.

The 43 additional flip-flops are accounted for by two sources, confirmed directly in the synthesized netlist. The coefficient memory's flip-flop count increases from 40 to 80, accounting for 40 additional flip-flops. The controller's flip-flop count increases from 40 to 43 because `bidx`, `lo_reg`, and `hi_reg` each require one additional address bit.

The controller and twiddle ROM also grow modestly due to wider addresses and twiddle exponents. The shared butterfly datapath and modular arithmetic are reused unchanged, as reflected in their identical combined synthesis cell counts.

The N=16 implementation retains the baseline's sequential butterfly execution model. Consequently, the larger transform increases execution time, while the shared datapath avoids the hardware cost of instantiating additional butterfly units.

## Run commands

```bash
# Python mathematical validation
cd experiments/ntt16/reference
python3 ntt16_reference_model.py
python3 ntt16_math_validation.py

# RTL verification
cd ../../..
bash scripts/run_ntt16.sh

# Full regression
bash scripts/run_all_experiments.sh

# Synthesis comparison
bash scripts/run_synthesis.sh
```

---

[← Back to main README](../../README.md) · [Experiments and evaluation](../../docs/experiments.md)
