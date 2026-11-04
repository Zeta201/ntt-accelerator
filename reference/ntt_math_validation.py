#!/usr/bin/env python3
"""Validate the mathematics and test vectors for the 8-point NTT accelerator."""

import os
import sys

import ntt_reference_model as reference

Q = 17
OMEGA = 9
N = 8
STAGES = 3

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
    """Verify the multiplicative order and power table of omega."""
    powers = [pow(OMEGA, i, Q) for i in range(N + 1)]
    expected = [1, 9, 13, 15, 16, 8, 4, 2, 1]
    check(powers == expected,
          f"omega power table mismatch: got {powers}, expected {expected}")
    check(powers[8] == 1, f"omega^8 mod {Q} != 1 (got {powers[8]})")
    for i in (1, 2, 4):
        check(powers[i] != 1,
              f"omega^{i} mod {Q} == 1 -- order would divide {i}, not 8 "
              f"(got omega^{i}={powers[i]})")
    return powers


def dif_schedule_pairs():
    """Generate the DIF butterfly address and twiddle schedule."""
    schedule = []
    for s in range(STAGES):
        half = 4 >> s
        stage_pairs = []
        for bidx in range(4):
            group = bidx >> (2 - s)
            j = bidx & (half - 1)
            lo = group * (2 * half) + j
            hi = lo + half
            texp = (j << s) & 7
            stage_pairs.append((lo, hi, texp))
        schedule.append(stage_pairs)
    return schedule


EXPECTED_SCHEDULE = [
    [(0, 4, 0), (1, 5, 1), (2, 6, 2), (3, 7, 3)],
    [(0, 2, 0), (1, 3, 2), (4, 6, 0), (5, 7, 2)],
    [(0, 1, 0), (2, 3, 0), (4, 5, 0), (6, 7, 0)],
]


def verify_schedule():
    """Verify the DIF butterfly schedule."""
    schedule = dif_schedule_pairs()
    check(schedule == EXPECTED_SCHEDULE,
          f"DIF schedule mismatch: got {schedule}, expected {EXPECTED_SCHEDULE}")

    total_pairs = sum(len(s) for s in schedule)
    check(total_pairs == 12,
          f"expected exactly 12 butterflies total, got {total_pairs}")

    for s, pairs in enumerate(schedule):
        check(len(pairs) == 4, f"stage {s}: expected 4 butterflies, got {len(pairs)}")
        touched = sorted([lo for lo, hi, _ in pairs] + [hi for lo, hi, _ in pairs])
        check(touched == list(range(8)),
              f"stage {s} does not partition addresses 0..7 exactly once "
              f"(no omissions/duplicates): got {touched}")
        for (lo, hi, texp) in pairs:
            check(0 <= texp <= 7, f"stage {s}: twiddle exponent {texp} out of ROM range 0..7 for pair ({lo},{hi})")
            check(hi == lo + (4 >> s), f"stage {s}: pair ({lo},{hi}) distance is not {4 >> s}")

    return schedule


_BITREV3_TABLE = [0, 4, 2, 6, 1, 5, 3, 7]  # bitrev3(i) for i=0..7, checked below


def bitrev3(i):
    """Reverse the three bits of an index."""
    return int(format(i, "03b")[::-1], 2)


def verify_bitrev3():
    """Verify the three-bit reversal mapping."""
    computed = [bitrev3(i) for i in range(8)]
    check(computed == _BITREV3_TABLE,
          f"bitrev3 table mismatch: got {computed}, expected {_BITREV3_TABLE}")
    # This is an involution, so applying it twice returns the original index.
    for i in range(8):
        check(bitrev3(bitrev3(i)) == i, f"bitrev3 is not self-inverse at i={i}")


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
    natural = [final_bitrev[bitrev3(k)] for k in range(N)]
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


def independent_stage1(x):
    """Compute the first DIF stage independently."""
    a = [(x[j] + x[j + 4]) % Q for j in range(4)]
    b = [((x[j] - x[j + 4]) % Q * pow(OMEGA, j, Q)) % Q for j in range(4)]
    out = [None] * 8
    for j in range(4):
        out[j] = a[j]
        out[j + 4] = b[j]
    return out


def independent_stage2(stage1_bank):
    """Compute the second DIF stage independently."""
    out = [None] * 8
    w2 = pow(OMEGA, 2, Q)
    for base in (0, 4):
        half = stage1_bank[base:base + 4]
        for j in range(2):
            lo, hi = base + j, base + j + 2
            a = (half[j] + half[j + 2]) % Q
            b = ((half[j] - half[j + 2]) % Q * pow(w2, j, Q)) % Q
            out[lo] = a
            out[hi] = b
    return out


def independent_stage3(stage2_bank):
    """Compute the third DIF stage independently."""
    out = [None] * 8
    for base in range(0, 8, 2):
        a = (stage2_bank[base] + stage2_bank[base + 1]) % Q
        b = ((stage2_bank[base] - stage2_bank[base + 1]) % Q * 1) % Q  # omega^0 = 1
        out[base] = a
        out[base + 1] = b
    return out


def verify_dif_against_independent_derivations(x):
    """Cross check the DIF stages against independent derivations."""
    schedule = dif_schedule_pairs()
    intermediates, final_bitrev, natural = dif_transform(x, schedule)

    rec = recursive_dif(x)
    check(rec == final_bitrev,
          f"x={x}: flat-schedule bit-reversed bank {final_bitrev} != "
          f"recursive DIF derivation {rec}")

    i1 = independent_stage1(x)
    i2 = independent_stage2(i1)
    i3 = independent_stage3(i2)
    check(intermediates[0] == i1,
          f"x={x}: stage-1 intermediate {intermediates[0]} != independent closed-form {i1}")
    check(intermediates[1] == i2,
          f"x={x}: stage-2 intermediate {intermediates[1]} != independent closed-form {i2}")
    check(intermediates[2] == i3,
          f"x={x}: stage-3 intermediate {intermediates[2]} != independent closed-form {i3}")

    return intermediates, final_bitrev, natural


def read_vector_file(path, label):
    """Read and validate eight canonical coefficients from a file."""
    if not os.path.isfile(path):
        check(False, f"{label}: missing file {path}")
        return None

    with open(path) as f:
        raw_lines = f.readlines()

    check(len(raw_lines) == 8,
          f"{label} ({path}): expected exactly 8 lines, got {len(raw_lines)}")

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

    check(len(vals) == 8,
          f"{label} ({path}): expected exactly 8 valid decimal coefficients in 0..16, got {len(vals)}")
    if len(vals) != 8:
        return None
    return vals


def _report_vector_mismatch(name, source_label, natural, other):
    """Format a coefficient mismatch report."""
    diffs = [(k, natural[k], other[k]) for k in range(8) if natural[k] != other[k]]
    return (f"{name}: computed result does not match {source_label}; "
            f"mismatched position(s) [(index, computed, {source_label})]={diffs}; "
            f"computed={natural} {source_label}={other}")


def verify_against_test_vectors(vecdir):
    """Validate test vector files against independent NTT results."""
    if not os.path.isdir(vecdir):
        check(False, f"test_vectors directory does not exist: {vecdir} "
                      f"(run 'python3 ntt_reference_model.py' to generate it)")
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

        intermediates, final_bitrev, natural = verify_dif_against_independent_derivations(x)
        direct = reference.direct_dft(x)

        check(natural == direct, _report_vector_mismatch(name, "independent direct NTT", natural, direct))
        check(natural == expected, _report_vector_mismatch(name, "expected output file", natural, expected))
        n_checked += 1

    return n_checked


def hw_mod_add(a, b):
    """Add two coefficients modulo 17."""
    s = a + b
    return s - 17 if s >= 17 else s


def hw_mod_sub(a, b):
    """Subtract two coefficients modulo 17."""
    return a - b if a >= b else a + 17 - b


def hw_mod_mul_reduce(p):
    """Reduce a product modulo 17 using the hardware reduction method."""
    h = p >> 4
    l = p & 15
    r = l - h
    return r + 17 if r < 0 else r


def hw_mod_mul(a, b):
    """Multiply two coefficients modulo 17."""
    p = a * b
    return hw_mod_mul_reduce(p)


def verify_modular_arithmetic():
    """Exhaustively verify the modular arithmetic operations."""
    n = 0
    for a in range(17):
        for b in range(17):
            n += 1
            expected_add = (a + b) % 17
            expected_sub = (a - b) % 17
            expected_mul = (a * b) % 17

            got_add = hw_mod_add(a, b)
            got_sub = hw_mod_sub(a, b)
            got_mul = hw_mod_mul(a, b)

            check(got_add == expected_add,
                  f"mod_add mismatch a={a} b={b}: got {got_add}, expected {expected_add}")
            check(got_sub == expected_sub,
                  f"mod_sub mismatch a={a} b={b}: got {got_sub}, expected {expected_sub}")
            check(got_mul == expected_mul,
                  f"mod_mul (16==-1 reduction) mismatch a={a} b={b}: "
                  f"got {got_mul}, expected {expected_mul} (p={a*b})")

            check(0 <= got_add <= 16, f"mod_add result {got_add} outside canonical range (a={a},b={b})")
            check(0 <= got_sub <= 16, f"mod_sub result {got_sub} outside canonical range (a={a},b={b})")
            check(0 <= got_mul <= 16, f"mod_mul result {got_mul} outside canonical range (a={a},b={b})")
    return n


def main():
    """Run the mathematical and reference-model validation suite."""
    here = os.path.dirname(os.path.abspath(__file__))
    vecdir = os.path.join(here, "test_vectors")

    print("=== 1/2: multiplicative order of omega=9 mod 17, power table ===")
    powers = verify_omega_order()
    print(f"omega^0..omega^8 mod 17 = {powers}")

    print("\n=== 3: DIF address / twiddle-exponent schedule (12 butterflies) ===")
    schedule = verify_schedule()
    for s, pairs in enumerate(schedule):
        print(f"stage {s} (distance {4 >> s}): {pairs}")

    print("\n=== 4/5: bit-reversal mapping ===")
    verify_bitrev3()
    print(f"bitrev3 table (i -> bitrev3(i)): {_BITREV3_TABLE}")

    print("\n=== 6: test vectors (READ-ONLY validation -- this script never writes to test_vectors/) ===")
    print(f"reading existing files from {vecdir}; run 'python3 ntt_reference_model.py' "
          f"separately to (re)generate them -- validation never regenerates or repairs them")
    n_checked = verify_against_test_vectors(vecdir)
    print(f"checked {n_checked} existing test vector pairs: DIF intermediates (independently "
          f"cross-derived), final DIF vs direct NTT, and vs the on-disk expected files")

    print("\n=== 7/8: exhaustive modular arithmetic (add/sub/mul, 16==-1 reduction) ===")
    n_pairs = verify_modular_arithmetic()
    print(f"checked {n_pairs} (a,b) pairs (a,b in 0..16) for mod_add, mod_sub, "
          f"and mod_mul (via the 16==-1 reduction identity), each against Python's "
          f"native % as the independent reference")

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
