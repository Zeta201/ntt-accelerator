# 8-Point NTT Accelerator

This project implements an 8-point Number Theoretic Transform (NTT) accelerator in Verilog-2001 for the [ARCH Lab hardware task](https://archlabs.us/apply/task26fhe/). The design is simulated using Icarus Verilog.

The initial implementation uses a single reusable butterfly datapath for all three stages of the transform, rather than separate hardware for each stage. A ROM stores the twiddle factors, while a finite-state machine (FSM) controls the transform sequence. In addition to this implementation, the project includes three experiments investigating inverse NTT support, larger transform sizes, and pipelined execution.

The NTT is the finite-field counterpart of the Fast Fourier Transform (FFT). It is widely used in polynomial multiplication, where two polynomials are transformed, multiplied coefficient-wise in the transform domain, and then inverse-transformed, reducing complexity from $O(n^2)$ to $O(n\log n)$. Unlike FFT implementations that use floating-point arithmetic, an NTT operates over a finite field using integer arithmetic and modular reduction, which avoids floating-point rounding errors and makes NTTs particularly useful in lattice-based cryptography and Fully Homomorphic Encryption (FHE). See the task's *Why NTT Matters in Hardware* section for further motivation.

## Key implementation features

- Verilog-2001, simulated with Icarus Verilog.
- Single reusable butterfly datapath shared across all stages and butterflies.
- In-place coefficient memory (one 8×5-bit bank for input, intermediate, and output data).
- ROM-based, precomputed twiddle factors.
- FSM-based control (`IDLE → LOAD → READ → COMPUTE → WRITE`).
- Natural-order output via a fixed bit-reversal mapping at the output port.

## Results overview

| Metric | Baseline | Exp. 1: INTT | Exp. 2: N=16 | Exp. 3: Pipelined |
|---|---:|---:|---:|---:|
| Transform size | 8 | 8 | 16 | 8 |
| Transform direction | Forward only | Forward + inverse | Forward only | Forward only |
| Execution latency (busy cycles) | 37 | 37 (fwd) / 61 (inv) | 97 | 16 |
| Generic synthesis cells | 603 | 673 | 952 | 661 |
| Flip-flops | 80 | 85 | 123 | 90 |

Generic synthesis cell counts are technology-independent Yosys statistics, not FPGA/ASIC resource, timing, or power measurements. Full results, methodology, and per-module breakdowns are in [docs/experiments.md](docs/experiments.md).

## Quick start

**Prerequisites:** Icarus Verilog (`iverilog`/`vvp`) and Python 3. Tested with Icarus Verilog 13.0 and Python 3.11.13.

```bash
# Run the baseline RTL test suite (5,363 checks)
bash scripts/run_all_tests.sh

# Run the baseline suite plus all three experiments
bash scripts/run_all_experiments.sh
```

See [docs/verification.md](docs/verification.md) for the full verification methodology, test counts, and waveform-inspection instructions.

## Repository structure

```text
ntt_accelerator/
├── rtl/            # Baseline Verilog implementation
├── tb/             # Baseline testbenches and fixtures
├── reference/      # Baseline independent Python reference/validation code
├── experiments/    # Independent extensions (intt/, ntt16/, pipelined/) -- baseline is never modified
├── scripts/        # Test, regression, and synthesis scripts
├── reports/        # Raw Yosys synthesis scripts and output
├── waves/          # Waveform capture harness, recorded VCD, and trace log
└── docs/           # Detailed documentation (this README links to all of it)
```

Each experiment directory (`experiments/intt/`, `experiments/ntt16/`, `experiments/pipelined/`) mirrors the baseline's own `rtl/`, `tb/`, and `reference/` layout and has its own `README.md`.

## Assignment coverage

The table below describes the **initial baseline implementation** only (`rtl/`); it does not cover the experimental extensions, which are evaluated separately in [docs/experiments.md](docs/experiments.md).

| Requirement | Implemented as |
|---|---|
| 8-point transform, 8 in / 8 out | `coef_in[39:0]` / `coef_out[39:0]`, 8×5-bit packed |
| N=8, q=17, ω=9 | Fixed by memory depth, ROM contents, and address-generation width |
| Single iterative butterfly | One `butterfly_datapath` instance, reused for all 12 butterflies |
| ROM-based precomputed twiddles | `twiddle_rom.v`, 8 literal constants |
| FSM-based control | `ntt_controller.v`, 5-state FSM |
| Correct address/twiddle generation | Shift/mask formula, independently re-derived and matched in `ntt_math_validation.py` |
| Modular arithmetic | `modular_arithmetic.v`, exhaustively checked over all 289 canonical operand pairs; additional mathematical validation performed by `ntt_math_validation.py` |
| Working testbench | `tb/tb_ntt_top.v` + 3 supporting testbenches, `scripts/run_all_tests.sh` |
| Text-file input loading | `$fscanf`-based readers in `tb_ntt_top.v`, against `reference/test_vectors/` |
| Correct output verification | 31/31 test vectors match, independently cross-checked against the direct NTT definition |
| Open-source simulation | Icarus Verilog 13.0 |

## Documentation

| Document | Covers |
|---|---|
| [docs/architecture.md](docs/architecture.md) | Mathematical foundation, NTT algorithm, top-level interface, architecture diagrams, transform execution, implementation details, design trade-offs |
| [docs/verification.md](docs/verification.md) | Verification strategy, test counts and coverage, measured latency, test-vector/checkpoint generation, waveform inspection, reproduction commands |
| [docs/experiments.md](docs/experiments.md) | Why the experiments exist, shared synthesis methodology, overall comparison, main findings, future work |
| [experiments/intt/README.md](experiments/intt/README.md) | Experiment 1: inverse NTT — design, verification, synthesis results |
| [experiments/ntt16/README.md](experiments/ntt16/README.md) | Experiment 2: N=16 transform — design, verification, synthesis results |
| [experiments/pipelined/README.md](experiments/pipelined/README.md) | Experiment 3: pipelined execution — design, hazard detection, verification, synthesis results |
