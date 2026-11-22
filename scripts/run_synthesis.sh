#!/usr/bin/env bash
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$HERE" || exit 1

required_tools=(yosys nextpnr-ecp5)
missing_tools=()
for tool in "${required_tools[@]}"; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        missing_tools+=("$tool")
    fi
done
if [ "${#missing_tools[@]}" -ne 0 ]; then
    echo "ERROR: required tool(s) not found on PATH: ${missing_tools[*]}" >&2
    echo "Run: source scripts/setup_toolchain.sh" >&2
    exit 1
fi

echo "=== toolchain in use ==="
yosys -V
nextpnr-ecp5 --version 2>&1 | head -1

versions_file="toolchain/versions.txt"
if [ -f "$versions_file" ]; then
    expected_yosys="$(grep '^Yosys:' "$versions_file" | sed 's/^Yosys: //')"
    actual_yosys="$(yosys -V)"
    if [ -n "$expected_yosys" ] && [ "$actual_yosys" != "$expected_yosys" ]; then
        echo "WARNING: yosys version differs from $versions_file:" >&2
        echo "  expected: $expected_yosys" >&2
        echo "  actual:   $actual_yosys" >&2
        echo "  A different yosys build can produce different LUT/FF counts and timing results." >&2
    fi
fi
echo "========================="

fail_count=0

run_ecp5() {
    local name="$1"
    local json="$2"
    echo
    echo "--- synthesizing: $name (ECP5 target: LFE5U-85F, CABGA381, speed 6, -nodsp) ---"
    if [ ! -f "reports/$name/synth.ys" ]; then
        echo "SKIP: reports/$name/synth.ys not found"
        return
    fi
    if ! (cd "reports/$name" && yosys -s synth.ys > synth_report.txt 2>&1); then
        echo "FAILED: synthesis for $name"
        fail_count=$((fail_count + 1))
        return
    fi
    echo "wrote reports/$name/synth_report.txt"
    echo "post-synthesis resource usage:"
    grep -E "^[[:space:]]+[0-9]+[[:space:]]+(LUT4|TRELLIS_FF|MULT18X18D|CCU2C|PFUMX|L6MUX21)[[:space:]]*$" "reports/$name/synth_report.txt" | tail -5 || true

    if ! (cd "reports/$name" && nextpnr-ecp5 \
            --85k --package CABGA381 --speed 6 \
            --json "$json" \
            --lpf-allow-unconstrained \
            --report nextpnr_report.json \
            > nextpnr_report.txt 2>&1); then
        echo "FAILED: nextpnr-ecp5 place-and-route for $name"
        fail_count=$((fail_count + 1))
        return
    fi
    if ! grep -q "^Info: Max frequency" "reports/$name/nextpnr_report.txt"; then
        echo "FAILED: nextpnr-ecp5 did not report a timing result for $name"
        fail_count=$((fail_count + 1))
        return
    fi
    echo "wrote reports/$name/nextpnr_report.txt"
    echo "post-route device utilisation (DSP/BRAM):"
    grep -E "MULT18X18D|DP16KD" "reports/$name/nextpnr_report.txt" | tail -2 || true
    echo "post-route timing:"
    grep "^Info: Max frequency" "reports/$name/nextpnr_report.txt" | tail -1
}

run_ecp5 baseline ntt_top.json
run_ecp5 intt ntt_top.json
run_ecp5 ntt16 ntt_top16.json
run_ecp5 pipelined ntt_top_pipelined.json

echo
echo "=== synthesis summary ==="
if [ "$fail_count" -eq 0 ]; then
    echo "ALL SYNTHESIS RUNS COMPLETED"
else
    echo "$fail_count SYNTHESIS RUN(S) FAILED"
fi

exit "$fail_count"
