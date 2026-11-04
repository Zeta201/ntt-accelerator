# Synthesis methodology

**Tool:** Yosys 0.70+post (git sha1 0c11ea098be065e585a90a06e7b7da49936cf231), AppleClang clang++ 21.0.0.

**Target:** None. This is a generic, technology-independent synthesis (`synth`
with no `-family`/target flag), producing gate-level statistics in Yosys's
internal generic cell library. It is not mapped to any FPGA or ASIC cell
library, and no place-and-route or static timing analysis was performed.

**No FPGA implementation or PnR tools are available in this environment**
(`nextpnr-ice40`, `nextpnr-ecp5`, `sta`, `opensta` were all checked and are
absent). Consequently:

- LUT, BRAM, and DSP counts are **not measured** — those are specific to a
  target FPGA architecture and require a target-specific synthesis flow.
- Maximum operating frequency and critical-path delay are **not measured** —
  those require static timing analysis against a real timing library (or a
  placed-and-routed FPGA netlist), neither of which is available here.

What this flow **does** provide, and what the comparison below is based on,
is generic gate/cell and flip-flop counts after logic optimization (`abc`),
which is a legitimate basis for comparing the relative hardware cost of two
RTL designs under the same flow and settings, but is not a substitute for a
real FPGA/ASIC implementation result.

**Settings:** identical for both designs — `hierarchy -top ntt_top; synth
-top ntt_top; stat`. No constraints file (none applicable without a target).

**Source files:**

- Baseline: `rtl/modular_arithmetic.v`, `rtl/twiddle_rom.v`,
  `rtl/butterfly_datapath.v`, `rtl/coefficient_memory.v`,
  `rtl/ntt_controller.v`, `rtl/ntt_top.v`.
- INTT: `rtl/modular_arithmetic.v`, `rtl/butterfly_datapath.v`,
  `rtl/coefficient_memory.v` (all three unchanged, shared with baseline),
  `experiments/intt/rtl/twiddle_rom.v`,
  `experiments/intt/rtl/ntt_controller.v`,
  `experiments/intt/rtl/ntt_top.v`.

**Exact commands:**

```bash
cd reports/baseline && yosys -s synth.ys > synth_report.txt
cd reports/intt     && yosys -s synth.ys > synth_report.txt
```

**Raw reports:** `reports/baseline/synth_report.txt`,
`reports/intt/synth_report.txt` (both retained in full).

**Tool warnings:** both runs reported `ABC: Warning: The network is
combinational (run "fraig" or "fraig_sweep")` — a known, benign informational
message from this generic flow; both designs synthesized completely and
produced the expected flip-flop counts (confirmed below), so this warning
does not indicate a synthesis problem.

## Results

| Metric | Baseline N=8 | INTT-capable N=8 | Delta |
|---|---:|---:|---:|
| Total cells (top, incl. submodules) | 603 | 673 | +70 (+11.6%) |
| Flip-flops | 80 | 85 | +5 |
| `ntt_controller` cells | 117 | 172 | +55 |
| `twiddle_rom` cells | 7 | 20 | +13 |
| `coefficient_memory` cells | 242 | 242 | +0 (unchanged, as designed) |
| `butterfly_datapath`/`modular_arithmetic` cells | 237 | 239 | +2 (synthesis-context variance; same source file in both) |
| LUT / logic-cell usage (target-mapped) | Not measured | Not measured | — |
| Flip-flop usage (target-mapped) | Not measured | Not measured | — |
| BRAM / memory usage | Not measured | Not measured | — |
| DSP / multiplier usage | Not measured | Not measured | — |
| Critical-path delay | Not measured | Not measured | — |
| Maximum estimated frequency | Not measured | Not measured | — |

The +5 flip-flop delta is cross-checked against the RTL: the INTT extension
adds exactly `mode_reg` (1 bit), `phase` (1 bit), and `nidx` (3 bits) to
`ntt_controller` — 5 bits of new state, nothing else. The exact match between
this independent arithmetic check and the synthesized netlist's flip-flop
count is a sanity check that the netlist reflects the intended design, not
proof of timing or area quality.

`coefficient_memory` is synthesized to the identical cell count in both runs,
confirming it is genuinely untouched (the INTT extension reuses its existing
two-port write interface rather than modifying it, as described in the
architecture section).

The small `modular_arithmetic`-family cell-count difference (237 vs 239,
`mod_add` specifically: 39 vs 41) comes from the same unmodified source file
(`rtl/modular_arithmetic.v`) read in both flows; Yosys's `synth` optimizes
the whole flattened design together, so the same leaf module can synthesize
to a slightly different gate count depending on the surrounding netlist's
optimization opportunities. This is a synthesis-tool artifact, not a design
difference, and is not treated as a meaningful comparison point.
