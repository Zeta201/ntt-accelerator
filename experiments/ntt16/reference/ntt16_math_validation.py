#!/usr/bin/env python3
"""Validate the mathematics and test vectors for the 16-point NTT experiment."""

import os
import sys

import ntt16_reference_model as reference

Q = 17
OMEGA = 3
N = 16
STAGES = 4

error_count = 0
check_count = 0


def check(cond, msg):
    """Record the result of a validation check."""
    global error_count, check_count
    check_count += 1
    if not cond:
        error_count += 1
        print(f"FAIL: {msg}")
    return cond


def verify_omega_order():
    """Verify that omega has order 16 and check its power table."""
    powers = [pow(OMEGA, i, Q) for i in range(N + 1)]
    expected = [1, 3, 9, 10, 13, 5, 15, 11, 16, 14, 8, 7, 4, 12, 2, 6, 1]
    check(powers == expected,
          f"omega power table mismatch: got {powers}, expected {expected}")
    check(powers[16] == 1, f"omega^16 mod {Q} != 1 (got {powers[16]})")
    for i in (1, 2, 4, 8):
        check(powers[i] != 1,
              f"omega^{i} mod {Q} == 1 -- order would divide {i}, not 16 "
              f"(got omega^{i}={powers[i]})")
    return powers


def dif_schedule_pairs():
    """Generate the DIF butterfly address and twiddle schedule."""
    schedule = []
    for s in range(STAGES):
        half = (N // 2) >> s
        stage_pairs = []
        for bidx in range(N // 2):
            group = bidx >> ((STAGES - 1) - s)
            j = bidx & (half - 1)
            lo = group * (2 * half) + j
            hi = lo + half
            texp = (j << s) & (N - 1)
            stage_pairs.append((lo, hi, texp))
        schedule.append(stage_pairs)
    return schedule


EXPECTED_SCHEDULE = [
    [(0, 8, 0), (1, 9, 1), (2, 10, 2), (3, 11, 3), (4, 12, 4), (5, 13, 5), (6, 14, 6), (7, 15, 7)],
    [(0, 4, 0), (1, 5, 2), (2, 6, 4), (3, 7, 6), (8, 12, 0), (9, 13, 2), (10, 14, 4), (11, 15, 6)],
    [(0, 2, 0), (1, 3, 4), (4, 6, 0), (5, 7, 4), (8, 10, 0), (9, 11, 4), (12, 14, 0), (13, 15, 4)],
    [(0, 1, 0), (2, 3, 0), (4, 5, 0), (6, 7, 0), (8, 9, 0), (10, 11, 0), (12, 13, 0), (14, 15, 0)],
]


def verify_schedule():
    """Verify the DIF butterfly schedule."""
    schedule = dif_schedule_pairs()
    check(schedule == EXPECTED_SCHEDULE,
          f"DIF schedule mismatch: got {schedule}, expected {EXPECTED_SCHEDULE}")

    total_pairs = sum(len(s) for s in schedule)
    check(total_pairs == 32,
          f"expected exactly 32 butterflies total, got {total_pairs}")

    for s, pairs in enumerate(schedule):
        check(len(pairs) == 8, f"stage {s}: expected 8 butterflies, got {len(pairs)}")
        touched = sorted([lo for lo, hi, _ in pairs] + [hi for lo, hi, _ in pairs])
        check(touched == list(range(N)),
              f"stage {s} does not partition addresses 0..{N - 1} exactly once "
              f"(no omissions/duplicates): got {touched}")
        for (lo, hi, texp) in pairs:
            check(0 <= texp <= N - 1,
                  f"stage {s}: twiddle exponent {texp} out of ROM range 0..{N - 1} for pair ({lo},{hi})")
            check(texp <= 7,
                  f"stage {s}: twiddle exponent {texp} exceeds the maximum exponent used by this DIF schedule")
            check(hi == lo + ((N // 2) >> s), f"stage {s}: pair ({lo},{hi}) distance is not {(N // 2) >> s}")

    return schedule


_BITREV4_TABLE = [int(format(i, "04b")[::-1], 2) for i in range(N)]


def bitrev4(i):
    """Reverse the four bits of an index."""
    return int(format(i, "04b")[::-1], 2)


def verify_bitrev4():
    """Verify the four-bit reversal mapping."""
    computed = [bitrev4(i) for i in range(N)]
    check(computed == _BITREV4_TABLE,
          f"bitrev4 table mismatch: got {computed}, expected {_BITREV4_TABLE}")
    # This is an involution, so applying it twice returns the original index.
    for i in range(N):
        check(bitrev4(bitrev4(i)) == i, f"bitrev4 is not self-inverse at i={i}")


def dif_transform(x, schedule=None):
    """Compute the DIF transform and its intermediate stages."""
    if schedule is None:
        schedule = dif_schedule_pairs()
    if len(x) != N:
        raise ValueError(f"expected {N} coefficients, got {len(x)}")
    for v in x:
        if not (0 <= v <= 16):
            raise ValueError(f"coefficient {v} outside canonical range 0..16")

    bank = list(x)
    intermediates = []
    for s in range(STAGES):
        new_bank = [None] * N
        for (lo, hi, texp) in schedule[s]:
            a, b = bank[lo], bank[hi]
            tw = pow(OMEGA, texp, Q)
            u = (a + b) % Q
            v = ((a - b) % Q) * tw % Q
            new_bank[lo] = u
            new_bank[hi] = v
        bank = new_bank
        intermediates.append(list(bank))

    final_bitrev = bank
    natural = [final_bitrev[bitrev4(k)] for k in range(N)]
    return intermediates, final_bitrev, natural


def recursive_dif(x, w=OMEGA):
    """Compute the recursive radix-2 DIF transform."""
    n = len(x)
    if n == 1:
        return list(x)
    half = n // 2
    a = [(x[j] + x[j + half]) % Q for j in range(half)]
    b = [((x[j] - x[j + half]) % Q * pow(w, j, Q)) % Q for j in range(half)]
    ra = recursive_dif(a, pow(w, 2, Q))
    rb = recursive_dif(b, pow(w, 2, Q))
    return ra + rb


def verify_dif_against_recursive(x):
    """Compare the flat DIF schedule with an independent recursive implementation."""
    schedule = dif_schedule_pairs()
    intermediates, final_bitrev, natural = dif_transform(x, schedule)

    rec = recursive_dif(x)
    check(rec == final_bitrev,
          f"x={x}: flat-schedule bit-reversed bank {final_bitrev} != "
          f"recursive DIF derivation {rec}")

    return intermediates, final_bitrev, natural


def read_vector_file(path, label):
    """Read and validate sixteen canonical coefficients from a file."""
    if not os.path.isfile(path):
        check(False, f"{label}: missing file {path}")
        return None

    with open(path) as f:
        raw_lines = f.readlines()

    check(len(raw_lines) == N,
          f"{label} ({path}): expected exactly {N} lines, got {len(raw_lines)}")

    vals = []
    for idx, raw in enumerate(raw_lines, start=1):
        stripped = raw.rstrip("\n").rstrip("\r").strip()

        not_blank = check(stripped != "",
                           f"{label} ({path}): blank line at line {idx} -- "
                           f"blank lines are rejected, not skipped")
        if not not_blank:
            continue

        try:
            v = int(stripped)
            is_int = True
        except ValueError:
            v = None
            is_int = False
        check(is_int, f"{label} ({path}): non-integer value {stripped!r} at line {idx}")
        if not is_int:
            continue

        in_range = check(0 <= v <= 16,
                          f"{label} ({path}): coefficient {v} at line {idx} outside canonical range 0..16")
        if in_range:
            vals.append(v)

    check(len(vals) == N,
          f"{label} ({path}): expected exactly {N} valid decimal coefficients in 0..16, got {len(vals)}")
    if len(vals) != N:
        return None
    return vals


def _report_vector_mismatch(name, source_label, natural, other):
    """Format a report identifying mismatched coefficients."""
    diffs = [(k, natural[k], other[k]) for k in range(N) if natural[k] != other[k]]
    return (f"{name}: computed result does not match {source_label}; "
            f"mismatched position(s) [(index, computed, {source_label})]={diffs}; "
            f"computed={natural} {source_label}={other}")


def verify_against_test_vectors(vecdir):
    """Validate the test vectors against independently computed NTT results."""
    if not os.path.isdir(vecdir):
        check(False, f"test_vectors directory does not exist: {vecdir} "
                      f"(run 'python3 ntt16_reference_model.py' to generate it)")
        return 0

    all_files = os.listdir(vecdir)
    input_names = {fn[len("input_"):-4] for fn in all_files
                   if fn.startswith("input_") and fn.endswith(".txt")}
    expected_names = {fn[len("expected_"):-4] for fn in all_files
                       if fn.startswith("expected_") and fn.endswith(".txt")}

    orphan_inputs = sorted(input_names - expected_names)
    orphan_expected = sorted(expected_names - input_names)
    for name in orphan_inputs:
        check(False, f"orphaned/incomplete vector '{name}': input_{name}.txt exists "
                      f"but expected_{name}.txt is missing")
    for name in orphan_expected:
        check(False, f"orphaned/unexpected file: expected_{name}.txt exists "
                      f"with no matching input_{name}.txt")

    names = sorted(input_names & expected_names)
    check(len(names) > 0, f"no matched input/expected vector pairs found under {vecdir}")

    n_checked = 0
    for name in names:
        in_path = os.path.join(vecdir, f"input_{name}.txt")
        exp_path = os.path.join(vecdir, f"expected_{name}.txt")

        x = read_vector_file(in_path, f"input_{name}")
        expected = read_vector_file(exp_path, f"expected_{name}")
        if x is None or expected is None:
            continue  # already recorded as a failure by read_vector_file

        intermediates, final_bitrev, natural = verify_dif_against_recursive(x)
        direct = reference.direct_dft(x)

        check(natural == direct, _report_vector_mismatch(name, "independent direct NTT", natural, direct))
        check(natural == expected, _report_vector_mismatch(name, "expected output file", natural, expected))
        n_checked += 1

    return n_checked


def verify_modular_arithmetic_reused():
    """Re-verify the exhaustive mod-17 arithmetic identities used by the hardware."""
    n = 0
    for a in range(17):
        for b in range(17):
            n += 1
            s = a + b
            hw_add = s - 17 if s >= 17 else s
            hw_sub = a - b if a >= b else a + 17 - b
            p = a * b
            h, l = p >> 4, p & 15
            r = l - h
            hw_mul = r + 17 if r < 0 else r

            check(hw_add == (a + b) % 17, f"mod_add mismatch a={a} b={b}")
            check(hw_sub == (a - b) % 17, f"mod_sub mismatch a={a} b={b}")
            check(hw_mul == (a * b) % 17, f"mod_mul mismatch a={a} b={b}")
    return n


def main():
    """Run the mathematical and reference-model validation suite."""
    here = os.path.dirname(os.path.abspath(__file__))
    vecdir = os.path.join(here, "test_vectors")

    print("=== 1/2: multiplicative order of omega=3 mod 17, power table ===")
    powers = verify_omega_order()
    print(f"omega^0..omega^16 mod 17 = {powers}")

    print("\n=== 3: DIF address / twiddle-exponent schedule (32 butterflies) ===")
    schedule = verify_schedule()
    for s, pairs in enumerate(schedule):
        print(f"stage {s} (distance {(N // 2) >> s}): {pairs}")

    print("\n=== 4: bit-reversal mapping ===")
    verify_bitrev4()
    print(f"bitrev4 table (i -> bitrev4(i)): {_BITREV4_TABLE}")

    print("\n=== 6: test vectors (READ-ONLY validation -- this script never writes to test_vectors/) ===")
    print(f"reading existing files from {vecdir}; run 'python3 ntt16_reference_model.py' "
          f"separately to (re)generate them -- validation never regenerates or repairs them")
    n_checked = verify_against_test_vectors(vecdir)
    print(f"checked {n_checked} existing vector pairs: recursive DIF cross-check, "
          f"direct NTT comparison, and expected-output comparison")

    print("\n=== 7: exhaustive modular arithmetic (add/sub/mul), re-confirmed for reuse ===")
    n_pairs = verify_modular_arithmetic_reused()
    print(f"checked {n_pairs} operand pairs for modular addition, subtraction, and "
          f"multiplication against Python's modulo operator")

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
