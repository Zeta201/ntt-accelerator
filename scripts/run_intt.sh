#!/usr/bin/env bash
# Run the INTT experiment's RTL testbench and independent Python validation.

set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$HERE" || exit 1

RTL="rtl/modular_arithmetic.v rtl/butterfly_datapath.v rtl/coefficient_memory.v \
     experiments/intt/rtl/twiddle_rom.v experiments/intt/rtl/ntt_controller.v experiments/intt/rtl/ntt_top.v"
BUILD_DIR="$(mktemp -d)"
trap 'rm -rf "$BUILD_DIR"' EXIT

fail_count=0
echo "=== INTT experiment verification ==="

echo
echo "--- tb_intt (RTL) ---"
if ! iverilog -g2001 -Wall -o "$BUILD_DIR/tb_intt.out" $RTL experiments/intt/tb/tb_intt.v \
        > "$BUILD_DIR/tb_intt.compile.log" 2>&1; then
    echo "COMPILE FAILED: tb_intt"
    cat "$BUILD_DIR/tb_intt.compile.log"
    fail_count=$((fail_count + 1))
else
    if [ -s "$BUILD_DIR/tb_intt.compile.log" ]; then
        echo "compile warnings:"
        cat "$BUILD_DIR/tb_intt.compile.log"
    fi
    if vvp "$BUILD_DIR/tb_intt.out" > "$BUILD_DIR/tb_intt.run.log" 2>&1; then
        run_status=0
    else
        run_status=1
    fi
    cat "$BUILD_DIR/tb_intt.run.log"
    if [ "$run_status" -ne 0 ] || ! grep -q "^RESULT: PASS" "$BUILD_DIR/tb_intt.run.log"; then
        echo "FAILED: tb_intt (exit=$run_status)"
        fail_count=$((fail_count + 1))
    else
        echo "PASSED: tb_intt"
    fi
fi

echo
echo "--- intt_math_validation.py (independent Python) ---"
if (cd experiments/intt/reference && python3 intt_math_validation.py) > "$BUILD_DIR/intt_math.log" 2>&1; then
    py_status=0
else
    py_status=1
fi
cat "$BUILD_DIR/intt_math.log"
if [ "$py_status" -ne 0 ] || ! grep -q "^RESULT: PASS" "$BUILD_DIR/intt_math.log"; then
    echo "FAILED: intt_math_validation.py (exit=$py_status)"
    fail_count=$((fail_count + 1))
else
    echo "PASSED: intt_math_validation.py"
fi

echo
echo "=== INTT experiment summary ==="
if [ "$fail_count" -eq 0 ]; then
    echo "ALL INTT CHECKS PASSED"
else
    echo "$fail_count INTT CHECK(S) FAILED"
fi

exit "$fail_count"
