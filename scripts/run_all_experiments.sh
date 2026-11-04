#!/usr/bin/env bash
# Run the baseline verification suite plus every completed experiment's suite.

set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$HERE" || exit 1

fail_count=0

echo "########## BASELINE ##########"
bash scripts/run_all_tests.sh
baseline_status=$?
if [ "$baseline_status" -ne 0 ]; then
    fail_count=$((fail_count + 1))
fi

echo
echo "########## EXPERIMENT: INTT ##########"
bash scripts/run_intt.sh
intt_status=$?
if [ "$intt_status" -ne 0 ]; then
    fail_count=$((fail_count + 1))
fi

echo
echo "########## EXPERIMENT: N=16 ##########"
bash scripts/run_ntt16.sh
ntt16_status=$?
if [ "$ntt16_status" -ne 0 ]; then
    fail_count=$((fail_count + 1))
fi

echo
echo "########## EXPERIMENT: PIPELINED ##########"
bash scripts/run_pipelined.sh
pipelined_status=$?
if [ "$pipelined_status" -ne 0 ]; then
    fail_count=$((fail_count + 1))
fi

echo
echo "=== overall summary ==="
echo "baseline:            $([ "$baseline_status" -eq 0 ] && echo PASS || echo FAIL)"
echo "experiment INTT:     $([ "$intt_status" -eq 0 ] && echo PASS || echo FAIL)"
echo "experiment N=16:     $([ "$ntt16_status" -eq 0 ] && echo PASS || echo FAIL)"
echo "experiment pipelined: $([ "$pipelined_status" -eq 0 ] && echo PASS || echo FAIL)"

if [ "$fail_count" -eq 0 ]; then
    echo "ALL SUITES PASSED"
else
    echo "$fail_count SUITE(S) FAILED"
fi

exit "$fail_count"
