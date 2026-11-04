#!/usr/bin/env bash
# Run generic (technology-independent) Yosys synthesis for the baseline and
# every completed experiment, using the same tool and settings for each, and
# refresh the raw reports under reports/<name>/synth_report.txt.

set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$HERE" || exit 1

fail_count=0

run_one() {
    local name="$1"
    echo
    echo "--- synthesizing: $name ---"
    if [ ! -f "reports/$name/synth.ys" ]; then
        echo "SKIP: reports/$name/synth.ys not found"
        return
    fi
    if (cd "reports/$name" && yosys -s synth.ys > synth_report.txt 2>&1); then
        echo "wrote reports/$name/synth_report.txt"
        tail -20 "reports/$name/synth_report.txt"
    else
        echo "FAILED: synthesis for $name"
        fail_count=$((fail_count + 1))
    fi
}

run_one baseline
run_one intt
run_one ntt16
run_one pipelined

echo
echo "=== synthesis summary ==="
if [ "$fail_count" -eq 0 ]; then
    echo "ALL SYNTHESIS RUNS COMPLETED"
else
    echo "$fail_count SYNTHESIS RUN(S) FAILED"
fi

exit "$fail_count"
