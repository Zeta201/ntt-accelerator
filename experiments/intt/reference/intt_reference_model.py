#!/usr/bin/env python3
"""Compute the direct-definition inverse NTT and generate INTT test vectors."""

import os
import random

Q = 17
OMEGA = 9
N = 8
OMEGA_INV = pow(OMEGA, Q - 2, Q)  # 2, via Fermat's little theorem (Q is prime)
N_INV = pow(N, Q - 2, Q)          # 15


def direct_idft(X):
    """Compute the direct-definition inverse NTT for eight canonical residues."""
    if len(X) != N:
        raise ValueError(f"expected {N} coefficients, got {len(X)}")
    for v in X:
        if not (0 <= v <= 16):
            raise ValueError(f"coefficient {v} outside canonical range 0..16")
    x = [0] * N
    for j in range(N):
        s = 0
        for k in range(N):
            s = (s + X[k] * pow(OMEGA_INV, (j * k) % N, Q)) % Q
        x[j] = (s * N_INV) % Q
    return x


def _build_test_vectors(seed=20261104, n_random=16):
    """Generate deterministic INTT test vectors covering boundary and random cases."""
    rng = random.Random(seed)
    vectors = {}
    vectors["zeros"] = [0] * 8
    vectors["ones"] = [1] * 8
    for i in range(8):
        v = [0] * 8
        v[i] = 1
        vectors[f"impulse_{i}"] = v
    vectors["max_all"] = [16] * 8
    vectors["alt_0_16"] = [0, 16, 0, 16, 0, 16, 0, 16]
    vectors["increasing"] = [0, 1, 2, 3, 4, 5, 6, 7]
    vectors["decreasing"] = [7, 6, 5, 4, 3, 2, 1, 0]
    vectors["boundary_0_16"] = [0, 16, 16, 0, 0, 16, 16, 0]
    for i in range(n_random):
        vectors[f"random_{i}"] = [rng.randint(0, 16) for _ in range(8)]
    return vectors


TEST_VECTOR_SEED = 20261104
TEST_VECTORS = _build_test_vectors(seed=TEST_VECTOR_SEED)


def write_test_vectors(outdir):
    """Write input (frequency-domain) and expected (time-domain) files for all test vectors."""
    os.makedirs(outdir, exist_ok=True)
    for name, X in TEST_VECTORS.items():
        x = direct_idft(X)
        with open(os.path.join(outdir, f"input_{name}.txt"), "w") as f:
            for v in X:
                f.write(f"{v}\n")
        with open(os.path.join(outdir, f"expected_{name}.txt"), "w") as f:
            for v in x:
                f.write(f"{v}\n")
    return len(TEST_VECTORS)


if __name__ == "__main__":
    here = os.path.dirname(os.path.abspath(__file__))
    outdir = os.path.join(here, "test_vectors")
    n = write_test_vectors(outdir)
    print(f"intt_reference_model: wrote {n} input/expected vector pairs to {outdir}")
    print(f"omega_inv = {OMEGA_INV}, N_inv = {N_INV}, seed = {TEST_VECTOR_SEED}")
    for name, X in TEST_VECTORS.items():
        print(f"  {name}: X={X} -> x={direct_idft(X)}")
