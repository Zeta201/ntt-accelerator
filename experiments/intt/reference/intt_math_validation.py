#!/usr/bin/env python3
"""Validate the INTT mathematics, hardware schedule model, and on-disk test vectors."""

import os
import sys

import intt_reference_model as intt_ref

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "..", "reference"))
import ntt_reference_model as fwd_ref  # noqa: E402

Q = 17
OMEGA = 9
N = 8
OMEGA_INV = intt_ref.OMEGA_INV
N_INV = intt_ref.N_INV

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


def verify_inverses():
    """Verify the modular inverses of omega and N used by the inverse transform."""
    check(OMEGA_INV == 2, f"omega_inv expected 2, got {OMEGA_INV}")
    check((OMEGA * OMEGA_INV) % Q == 1, f"omega*omega_inv != 1 mod {Q}")
    check(N_INV == 15, f"N_inv expected 15, got {N_INV}")
    check((N * N_INV) % Q == 1, f"N*N_inv != 1 mod {Q}")


INV_ROM = [1, 2, 4, 8, 16, 15, 13, 9]


def verify_inverse_twiddle_table():
    """Verify the inverse-twiddle ROM table against omega_inv^e mod 17."""
    computed = [pow(OMEGA_INV, e, Q) for e in range(8)]
    check(computed == INV_ROM, f"inverse twiddle table mismatch: got {computed}, expected {INV_ROM}")


def addr_gen(stage, bidx):
    """Reproduce the hardware's shift/mask address and twiddle-exponent generation."""
    half = 4 >> stage
    group = bidx >> (2 - stage)
    j = bidx & (half - 1)
    lo = group * (2 * half) + j
    hi = lo + half
    texp = (j << stage) & 7
    return lo, hi, texp


def bitrev3(i):
    """Reverse the three bits of an index."""
    return int(format(i, "03b")[::-1], 2)


def hw_intt_network(X):
    """Model the hardware's INTT datapath: same DIF network and schedule as
    the forward transform, natural-order input, inverse twiddles, the same
    bitrev3 output read, and a final N^-1 scaling pass over all 8 locations."""
    bank = list(X)
    for stage in range(3):
        new = [None] * 8
        for bidx in range(4):
            lo, hi, texp = addr_gen(stage, bidx)
            a, b = bank[lo], bank[hi]
            tw = INV_ROM[texp]
            u = (a + b) % Q
            v = ((a - b) % Q * tw) % Q
            new[lo] = u
            new[hi] = v
        bank = new
    natural = [bank[bitrev3(k)] for k in range(8)]
    scaled = [(v * N_INV) % Q for v in natural]
    return scaled


def verify_hw_schedule_model():
    """Verify the hardware INTT schedule model against the direct inverse definition."""
    import random
    rng = random.Random(7)
    for _ in range(500):
        X = [rng.randint(0, 16) for _ in range(8)]
        got = hw_intt_network(X)
        expected = intt_ref.direct_idft(X)
        check(got == expected,
              f"hw INTT schedule mismatch for X={X}: got {got}, expected {expected}")


def verify_round_trips():
    """Verify INTT(NTT(x)) == x and NTT(INTT(X)) == X for many vectors."""
    import random
    rng = random.Random(11)
    for _ in range(500):
        x = [rng.randint(0, 16) for _ in range(8)]
        X = fwd_ref.direct_dft(x)
        x_back = intt_ref.direct_idft(X)
        check(x_back == x, f"INTT(NTT(x)) != x for x={x}: got {x_back}")

        X2 = [rng.randint(0, 16) for _ in range(8)]
        x2 = intt_ref.direct_idft(X2)
        X2_back = fwd_ref.direct_dft(x2)
        check(X2_back == X2, f"NTT(INTT(X)) != X for X={X2}: got {X2_back}")


def read_vector_file(path, label):
    """Read and validate eight canonical coefficients from a file."""
    if not os.path.isfile(path):
        check(False, f"{label}: missing file {path}")
        return None
    with open(path) as f:
        lines = [ln.strip() for ln in f if ln.strip() != ""]
    check(len(lines) == 8, f"{label} ({path}): expected exactly 8 lines, got {len(lines)}")
    if len(lines) != 8:
        return None
    vals = [int(v) for v in lines]
    check(all(0 <= v <= 16 for v in vals), f"{label} ({path}): value outside canonical range 0..16")
    return vals


def verify_against_test_vectors(vecdir):
    """Validate the on-disk INTT test vectors against the direct inverse definition."""
    if not os.path.isdir(vecdir):
        check(False, f"test_vectors directory does not exist: {vecdir} "
                      f"(run 'python3 intt_reference_model.py' to generate it)")
        return 0
    names = sorted(
        fn[len("input_"):-4] for fn in os.listdir(vecdir)
        if fn.startswith("input_") and fn.endswith(".txt")
    )
    check(len(names) > 0, f"no input_*.txt vectors found under {vecdir}")
    n_checked = 0
    for name in names:
        X = read_vector_file(os.path.join(vecdir, f"input_{name}.txt"), f"input_{name}")
        expected = read_vector_file(os.path.join(vecdir, f"expected_{name}.txt"), f"expected_{name}")
        if X is None or expected is None:
            continue
        computed = intt_ref.direct_idft(X)
        check(computed == expected,
              f"{name}: computed INTT does not match expected file; computed={computed} expected={expected}")
        n_checked += 1
    return n_checked


def main():
    """Run the INTT mathematical and hardware-schedule validation suite."""
    here = os.path.dirname(os.path.abspath(__file__))
    vecdir = os.path.join(here, "test_vectors")

    print("=== 1: omega_inv and N_inv ===")
    verify_inverses()
    print(f"omega_inv={OMEGA_INV}, N_inv={N_INV}")

    print("\n=== 2: inverse twiddle ROM table ===")
    verify_inverse_twiddle_table()
    print(f"inverse twiddle table = {INV_ROM}")

    print("\n=== 3: hardware INTT schedule model vs direct inverse definition (500 random vectors) ===")
    verify_hw_schedule_model()

    print("\n=== 4: round-trip identities INTT(NTT(x))=x and NTT(INTT(X))=X (500 vectors each) ===")
    verify_round_trips()

    print("\n=== 5: on-disk INTT test vectors ===")
    n_checked = verify_against_test_vectors(vecdir)
    print(f"checked {n_checked} existing INTT test vector pairs")

    print("\n=== summary ===")
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
