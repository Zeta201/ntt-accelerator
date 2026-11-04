# Experiment 1: Inverse NTT (INTT)

[← Back to main README](../../README.md) · [Experiments and evaluation](../../docs/experiments.md)

> Commands below assume the repository root (`ntt_accelerator/`) as the working directory unless otherwise noted.

## Objective

Extend the accelerator to support inverse NTT while preserving forward-transform behavior and minimizing additional hardware through reuse of the existing butterfly datapath and coefficient memory.

## Design changes

The inverse transform uses the same DIF butterfly schedule and address generation as the forward transform, with inverse twiddle factors and a final normalization pass.

For $q=17$ and $N=8$:

- Inverse primitive root: $\omega^{-1}=2$.
- Normalization factor: $N^{-1}=15 \pmod{17}$.
- Inverse twiddle table: `[1, 2, 4, 8, 16, 15, 13, 9]`.

The implementation adds:

- An inverse-mode input captured when a transform starts.
- An inverse twiddle table in the twiddle ROM.
- A normalization phase that scales all eight output coefficients by 15.

During normalization, the controller selects the butterfly's `v` output for both memory write ports. This is necessary because the ordinary `u` output is unscaled, whereas `v` contains the required multiplication by 15 modulo 17.

The existing butterfly datapath, modular arithmetic, and coefficient memory are reused. The changes are isolated in `experiments/intt/rtl/`; the baseline RTL is not modified.

## Verification

The implementation was checked using an independent Python reference model and RTL simulation.

| Verification | Result |
|---|---:|
| Python mathematical validation | 1,661 checks, 0 failures |
| RTL verification | 335 checks, 0 failures |
| Forward test vectors | 31/31 passed |
| Inverse test vectors | 31/31 passed |
| Round-trip tests | 16/16 passed |
| Normalization checks | All 8 memory locations verified |

The tests also cover operation-mode stability, start requests while busy, and reset during normalization.

## Results

Both implementations were synthesized using the same generic Yosys flow (`synth -top ntt_top; stat`). The results are compared below.

| Metric | Baseline | INTT implementation |
|---|---:|---:|
| Forward latency | 37 cycles | 37 cycles |
| Inverse latency | — | 61 cycles |
| Generic synthesis cells | 603 | 673 |
| — combinational cells | 364 | 417 |
| — multiplexers | 159 | 171 |
| — flip-flops | 80 | 85 |

The INTT implementation uses 70 more generic synthesis cells than the baseline, an increase of 11.6%. This comprises 53 additional combinational cells, 12 additional multiplexers, and 5 additional flip-flops. Forward-transform correctness and latency remain unchanged. The existing butterfly datapath and coefficient memory are reused, so no separate arithmetic datapath is required. Inverse-transform latency increases by 24 cycles because normalization is performed sequentially.

These five additional flip-flops are associated with the inverse-mode register (`mode_reg`), normalization control (`phase`), and the 3-bit normalization index (`nidx`) — the only new registers declared in the controller. No additional sequential datapath registers are required.

### Module-level synthesis analysis

The module-level synthesis results show where the additional cells are used:

| Module | Baseline cells | INTT cells |
|---|---:|---:|
| Controller | 117 | 172 |
| Twiddle ROM | 7 | 20 |
| Coefficient memory | 242 | 242 |
| Modular arithmetic (combined) | 237 | 239 |

Nearly all of the overhead is in the controller (+55 cells, for the normalization-phase state machine and `phase`/`nidx` logic) and the twiddle ROM (+13 cells, for the added inverse-twiddle table and the `inv` select). The coefficient memory implementation remains unchanged, with the same synthesized cell count in both designs. The combined modular-arithmetic count increases by two cells even though none of `mod_add.v`, `mod_sub.v`, or `mod_mul.v` were modified. This illustrates that unchanged RTL does not necessarily produce identical generic cell counts when synthesis is performed in different design contexts.

## Run commands

```bash
# Python mathematical validation
cd experiments/intt/reference
python3 intt_reference_model.py
python3 intt_math_validation.py

# RTL verification
cd ../../..
bash scripts/run_intt.sh

# Full regression
bash scripts/run_all_experiments.sh

# Synthesis comparison
bash scripts/run_synthesis.sh
```

---

[← Back to main README](../../README.md) · [Experiments and evaluation](../../docs/experiments.md)
