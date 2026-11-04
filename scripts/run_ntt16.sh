#!/usr/bin/env bash
# Run the N=16 experiment's RTL testbench and independent Python validation.

set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$HERE" || exit 1

RTL="rtl/modular_arithmetic.v rtl/butterfly_datapath.v \
     experiments/ntt16/rtl/twiddle_rom16.v experiments/ntt16/rtl/coefficient_memory16.v \
     experiments/ntt16/rtl/ntt_controller16.v experiments/ntt16/rtl/ntt_top16.v"
BUILD_DIR="$(mktemp -d)"
trap 'rm -rf "$BUILD_DIR"' EXIT

fail_count=0
echo "=== N=16 experiment verification ==="

echo
echo "--- tb_ntt16 (RTL) ---"
if ! iverilog -g2001 -Wall -o "$BUILD_DIR/tb_ntt16.out" $RTL experiments/ntt16/tb/tb_ntt16.v \
        > "$BUILD_DIR/tb_ntt16.compile.log" 2>&1; then
    echo "COMPILE FAILED: tb_ntt16"
    cat "$BUILD_DIR/tb_ntt16.compile.log"
    fail_count=$((fail_count + 1))
else
    if [ -s "$BUILD_DIR/tb_ntt16.compile.log" ]; then
        echo "compile warnings:"
        cat "$BUILD_DIR/tb_ntt16.compile.log"
    fi
    if vvp "$BUILD_DIR/tb_ntt16.out" > "$BUILD_DIR/tb_ntt16.run.log" 2>&1; then
        run_status=0
    else
        run_status=1
    fi
    cat "$BUILD_DIR/tb_ntt16.run.log"
    if [ "$run_status" -ne 0 ] || ! grep -q "^RESULT: PASS" "$BUILD_DIR/tb_ntt16.run.log"; then
        echo "FAILED: tb_ntt16 (exit=$run_status)"
        fail_count=$((fail_count + 1))
    else
        echo "PASSED: tb_ntt16"
    fi
fi

echo
echo "--- ntt16_math_validation.py (independent Python) ---"
if (cd experiments/ntt16/reference && python3 ntt16_math_validation.py) > "$BUILD_DIR/ntt16_math.log" 2>&1; then
    py_status=0
else
    py_status=1
fi
cat "$BUILD_DIR/ntt16_math.log"
if [ "$py_status" -ne 0 ] || ! grep -q "^RESULT: PASS" "$BUILD_DIR/ntt16_math.log"; then
    echo "FAILED: ntt16_math_validation.py (exit=$py_status)"
    fail_count=$((fail_count + 1))
else
    echo "PASSED: ntt16_math_validation.py"
fi

echo
echo "=== N=16 experiment summary ==="
if [ "$fail_count" -eq 0 ]; then
    echo "ALL N=16 CHECKS PASSED"
else
    echo "$fail_count N=16 CHECK(S) FAILED"
fi

exit "$fail_count"
