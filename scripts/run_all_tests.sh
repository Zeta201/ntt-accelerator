#!/usr/bin/env bash
# Run the complete NTT verification suite and report testbench failures.

set -u

# Resolve the repository root for testbench file paths.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$HERE" || exit 1

RTL="rtl/modular_arithmetic.v rtl/twiddle_rom.v rtl/coefficient_memory.v rtl/butterfly_datapath.v rtl/ntt_controller.v rtl/ntt_top.v"
BUILD_DIR="$(mktemp -d)"
trap 'rm -rf "$BUILD_DIR"' EXIT

TESTBENCHES="tb_modular_arithmetic tb_ntt_top tb_control tb_negative"

fail_count=0
echo "=== NTT accelerator verification suite ==="

for tb in $TESTBENCHES; do
    echo
    echo "--- $tb ---"
    if ! iverilog -g2001 -Wall -o "$BUILD_DIR/$tb.out" $RTL "tb/$tb.v" > "$BUILD_DIR/$tb.compile.log" 2>&1; then
        echo "COMPILE FAILED: $tb"
        cat "$BUILD_DIR/$tb.compile.log"
        fail_count=$((fail_count + 1))
        continue
    fi
    if [ -s "$BUILD_DIR/$tb.compile.log" ]; then
        echo "compile warnings:"
        cat "$BUILD_DIR/$tb.compile.log"
    fi

    if vvp "$BUILD_DIR/$tb.out" > "$BUILD_DIR/$tb.run.log" 2>&1; then
        run_status=0
    else
        run_status=1
    fi
    cat "$BUILD_DIR/$tb.run.log"

    if [ "$run_status" -ne 0 ] || ! grep -q "^RESULT: PASS" "$BUILD_DIR/$tb.run.log"; then
        echo "FAILED: $tb (exit=$run_status)"
        fail_count=$((fail_count + 1))
    else
        echo "PASSED: $tb"
    fi
done

echo
echo "=== summary ==="
if [ "$fail_count" -eq 0 ]; then
    echo "ALL TESTBENCHES PASSED"
else
    echo "$fail_count TESTBENCH(ES) FAILED"
fi

exit "$fail_count"
