#!/usr/bin/env bash
# Run the pipelined-N=8 experiment's RTL testbench and independent Python
# schedule-model validation.

set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$HERE" || exit 1

if ! command -v iverilog >/dev/null 2>&1; then
    echo "FATAL: iverilog not found"
    exit 1
fi
if ! command -v python3 >/dev/null 2>&1; then
    echo "FATAL: python3 not found"
    exit 1
fi

RTL="rtl/modular_arithmetic.v rtl/twiddle_rom.v rtl/butterfly_datapath.v rtl/coefficient_memory.v \
     experiments/pipelined/rtl/ntt_controller_pipelined.v experiments/pipelined/rtl/ntt_top_pipelined.v"
BUILD_DIR="$(mktemp -d)"
trap 'rm -rf "$BUILD_DIR"' EXIT

fail_count=0
echo "=== Pipelined-N=8 experiment verification ==="

echo
echo "--- tb_pipelined (RTL) ---"
if ! iverilog -g2001 -Wall -o "$BUILD_DIR/tb_pipelined.out" $RTL experiments/pipelined/tb/tb_pipelined.v \
        > "$BUILD_DIR/tb_pipelined.compile.log" 2>&1; then
    echo "COMPILE FAILED: tb_pipelined"
    cat "$BUILD_DIR/tb_pipelined.compile.log"
    fail_count=$((fail_count + 1))
else
    if [ -s "$BUILD_DIR/tb_pipelined.compile.log" ]; then
        echo "compile warnings:"
        cat "$BUILD_DIR/tb_pipelined.compile.log"
    fi
    if vvp "$BUILD_DIR/tb_pipelined.out" > "$BUILD_DIR/tb_pipelined.run.log" 2>&1; then
        run_status=0
    else
        run_status=1
    fi
    cat "$BUILD_DIR/tb_pipelined.run.log"
    if [ "$run_status" -ne 0 ] || ! grep -q "^RESULT: PASS" "$BUILD_DIR/tb_pipelined.run.log"; then
        echo "FAILED: tb_pipelined (exit=$run_status)"
        fail_count=$((fail_count + 1))
    else
        echo "PASSED: tb_pipelined"
    fi
fi

echo
echo "--- pipelined_schedule_model.py (independent Python) ---"
if (cd experiments/pipelined/reference && python3 pipelined_schedule_model.py) > "$BUILD_DIR/pipelined_schedule.log" 2>&1; then
    py_status=0
else
    py_status=1
fi
cat "$BUILD_DIR/pipelined_schedule.log"
if [ "$py_status" -ne 0 ] || ! grep -q "^RESULT: PASS" "$BUILD_DIR/pipelined_schedule.log"; then
    echo "FAILED: pipelined_schedule_model.py (exit=$py_status)"
    fail_count=$((fail_count + 1))
else
    echo "PASSED: pipelined_schedule_model.py"
fi

echo
echo "=== Pipelined-N=8 experiment summary ==="
if [ "$fail_count" -eq 0 ]; then
    echo "ALL PIPELINED CHECKS PASSED"
else
    echo "$fail_count PIPELINED CHECK(S) FAILED"
fi

exit "$fail_count"
