#!/usr/bin/env python3
"""Independently model and verify the pipelined NTT controller's schedule.

Simulate the fixed-order issue policy, blocking a butterfly when either
read address conflicts with an outstanding write in the pipeline. Verify
the resulting issue and write cycles, concurrent memory accesses, and
NTT results against the independent baseline reference model.
"""

import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "..", "reference"))
import ntt_reference_model as reference
import ntt_math_validation as baseline_val

Q = 17
OMEGA = 9
N = 8
STAGES = 3
BUTTERFLIES_PER_STAGE = 4
PIPE_DEPTH = 3

error_count = 0
check_count = 0


def check(cond, msg):
    global error_count, check_count
    check_count += 1
    if not cond:
        error_count += 1
        print(f"FAIL: {msg}")
    return cond


def ordered_butterflies():
    """Return butterflies in stage order, preserving each stage's schedule."""
    schedule = baseline_val.dif_schedule_pairs()
    return [(s, b) + schedule[s][b] for s in range(STAGES) for b in range(BUTTERFLIES_PER_STAGE)]


def simulate_schedule(butterflies):
    """Simulate fixed-order issue with hazards from outstanding pipeline writes.

    A butterfly is blocked when either read address matches the destination
    of an uncommitted write in either of the two pipeline stages.
    """
    n = len(butterflies)
    issue_cycle = [None] * n
    write_cycle = [None] * n
    last_writer_of_addr = {}
    cycle = 0
    next_idx = 0
    stalls = 0
    while next_idx < n:
        _, _, lo, hi, _ = butterflies[next_idx]
        blocked = False
        for addr in (lo, hi):
            w = last_writer_of_addr.get(addr)
            if w is not None and (write_cycle[w] is None or write_cycle[w] >= cycle):
                blocked = True
        if blocked:
            stalls += 1
        else:
            issue_cycle[next_idx] = cycle
            write_cycle[next_idx] = cycle + (PIPE_DEPTH - 1)
            last_writer_of_addr[lo] = next_idx
            last_writer_of_addr[hi] = next_idx
            next_idx += 1
        cycle += 1
    total_busy_cycles = 1 + max(write_cycle) + 1  # LOAD cycle plus pipeline cycles through the final write
    return issue_cycle, write_cycle, stalls, total_busy_cycles


def verify_schedule_structure(butterflies, issue_cycle, write_cycle, stalls, total_busy_cycles):
    n = len(butterflies)
    check(len(set(issue_cycle)) == n, "two butterflies issued on the same cycle")
    check(len(set(write_cycle)) == n, "two butterflies written on the same cycle")

    # Verify the fixed issue-to-write pipeline latency.
    for i in range(n):
        check(write_cycle[i] == issue_cycle[i] + (PIPE_DEPTH - 1),
              f"butterfly {i}: write cycle does not trail issue cycle by {PIPE_DEPTH - 1}")

    # Verify that issue order is preserved.
    for i in range(1, n):
        check(issue_cycle[i] > issue_cycle[i - 1],
              f"butterfly {i} issued no later than butterfly {i - 1} -- order violated")

    check(stalls == 1, f"expected exactly 1 stall cycle for the N=8 schedule, modeled {stalls}")
    check(total_busy_cycles == 16, f"expected 16 total busy cycles, modeled {total_busy_cycles}")
    print(f"stalls = {stalls}, total busy cycles = {total_busy_cycles}")


def verify_concurrent_access_safety(butterflies, issue_cycle, write_cycle):
    """Verify that simultaneous butterfly issues and writes use disjoint addresses."""
    write_at = {write_cycle[i]: butterflies[i][2:4] for i in range(len(butterflies))}
    for i, cyc in enumerate(issue_cycle):
        if cyc in write_at:
            lo, hi = butterflies[i][2], butterflies[i][3]
            wlo, whi = write_at[cyc]
            overlap = {lo, hi} & {wlo, whi}
            check(not overlap,
                  f"cycle {cyc}: issuing ({lo},{hi}) collides with a concurrent write to ({wlo},{whi})")


def apply_schedule(x, butterflies, issue_cycle):
    """Apply butterflies in issue order and capture each completed stage bank."""
    bank = list(x)
    order = sorted(range(len(butterflies)), key=lambda i: issue_cycle[i])
    stage_banks = [None] * STAGES
    for i in order:
        s, b, lo, hi, texp = butterflies[i]
        a, bb = bank[lo], bank[hi]
        tw = pow(OMEGA, texp, Q)
        bank[lo] = (a + bb) % Q
        bank[hi] = ((a - bb) % Q) * tw % Q
        if b == BUTTERFLIES_PER_STAGE - 1:
            stage_banks[s] = list(bank)
    return stage_banks, bank


def verify_against_reference(vecdir, stagedir, butterflies, issue_cycle):
    """Verify final outputs and intermediate stage banks against reference data."""
    names = sorted(
        fn[len("input_"):-4] for fn in os.listdir(vecdir)
        if fn.startswith("input_") and fn.endswith(".txt")
    )
    check(len(names) > 0, f"no input_*.txt vectors found under {vecdir}")

    n_checked = 0
    for name in names:
        with open(os.path.join(vecdir, f"input_{name}.txt")) as f:
            x = [int(line) for line in f if line.strip() != ""]
        with open(os.path.join(vecdir, f"expected_{name}.txt")) as f:
            expected = [int(line) for line in f if line.strip() != ""]

        stage_banks, final_bitrev = apply_schedule(x, butterflies, issue_cycle)
        natural = [final_bitrev[baseline_val.bitrev3(k)] for k in range(N)]

        check(natural == reference.direct_dft(x),
              f"{name}: pipelined-schedule result disagrees with the independent direct NTT")
        check(natural == expected,
              f"{name}: pipelined-schedule result disagrees with the on-disk expected vector")

        for stage_idx in range(STAGES):
            ckpt_path = os.path.join(stagedir, f"stage{stage_idx + 1}_{name}.txt")
            with open(ckpt_path) as f:
                ckpt = [int(line) for line in f if line.strip() != ""]
            check(stage_banks[stage_idx] == ckpt,
                  f"{name}: pipelined stage-{stage_idx + 1} bank disagrees with the baseline's "
                  f"independently-generated checkpoint")

        n_checked += 1
    return n_checked


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    vecdir = os.path.join(here, "..", "..", "..", "reference", "test_vectors")
    stagedir = os.path.join(here, "..", "..", "..", "reference", "stage_checkpoints")

    butterflies = ordered_butterflies()

    print("=== 1: greedy hazard-aware issue schedule ===")
    issue_cycle, write_cycle, stalls, total_busy_cycles = simulate_schedule(butterflies)
    for i, (s, b, lo, hi, texp) in enumerate(butterflies):
        print(f"  stage{s} bidx{b}: ({lo},{hi}) issue@{issue_cycle[i]} write@{write_cycle[i]}")
    verify_schedule_structure(butterflies, issue_cycle, write_cycle, stalls, total_busy_cycles)

    print("\n=== 2: concurrent read/write address safety ===")
    verify_concurrent_access_safety(butterflies, issue_cycle, write_cycle)

    print("\n=== 3: schedule result vs. the baseline's independent reference ===")
    print(f"reading existing vectors/checkpoints from {vecdir} and {stagedir} "
          f"(both generated independently of this experiment)")
    n_checked = verify_against_reference(vecdir, stagedir, butterflies, issue_cycle)
    print(f"checked {n_checked} vectors: final natural-order output and all 3 intermediate "
          f"stage banks, both against independently-generated reference data")

    print(f"\n=== summary ===")
    print(f"total individual checks executed: {check_count}")
    print(f"failures: {error_count}")
    if error_count != 0:
        print(f"RESULT: FAIL ({error_count} check(s) failed)")
        sys.exit(1)
    else:
        print("RESULT: PASS (0 failures)")
        sys.exit(0)


if __name__ == "__main__":
    main()
