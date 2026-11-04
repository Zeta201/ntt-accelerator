#!/usr/bin/env python3
"""Compute the direct-definition NTT and generate test vectors for N=16."""

import os
import random

Q = 17
OMEGA = 3
N = 16


def direct_dft(x):
    """Compute the direct-definition NTT for sixteen canonical residues."""
    if len(x) != N:
        raise ValueError(f"expected {N} coefficients, got {len(x)}")
    for v in x:
        if not (0 <= v <= 16):
            raise ValueError(f"coefficient {v} outside canonical range 0..16")
    X = [0] * N
    for k in range(N):
        s = 0
        for j in range(N):
            s = (s + x[j] * pow(OMEGA, (j * k) % N, Q)) % Q
        X[k] = s
    return X


def _build_test_vectors(seed=20261104, n_random=16):
    """Generate deterministic test vectors covering boundary and random cases."""
    rng = random.Random(seed)
    vectors = {}
    vectors["zeros"] = [0] * N
    vectors["ones"] = [1] * N
    for i in range(N):
        v = [0] * N
        v[i] = 1
        vectors[f"impulse_{i}"] = v
    vectors["max_all"] = [16] * N
    vectors["alt_0_16"] = [0, 16] * (N // 2)
    vectors["increasing"] = list(range(N))
    vectors["decreasing"] = list(range(N - 1, -1, -1))
    vectors["boundary_0_16"] = [0, 16, 16, 0] * (N // 4)
    for i in range(n_random):
        vectors[f"random_{i}"] = [rng.randint(0, 16) for _ in range(N)]
    return vectors


TEST_VECTOR_SEED = 20261104
TEST_VECTORS = _build_test_vectors(seed=TEST_VECTOR_SEED)


def write_test_vectors(outdir):
    """Write input and expected output files for all test vectors."""
    os.makedirs(outdir, exist_ok=True)
    for name, x in TEST_VECTORS.items():
        X = direct_dft(x)
        with open(os.path.join(outdir, f"input_{name}.txt"), "w") as f:
            for v in x:
                f.write(f"{v}\n")
        with open(os.path.join(outdir, f"expected_{name}.txt"), "w") as f:
            for v in X:
                f.write(f"{v}\n")
    return len(TEST_VECTORS)


if __name__ == "__main__":
    here = os.path.dirname(os.path.abspath(__file__))
    outdir = os.path.join(here, "test_vectors")
    n = write_test_vectors(outdir)
    print(f"ntt16_reference_model: wrote {n} input/expected vector pairs to {outdir}")
    print(f"test-vector seed = {TEST_VECTOR_SEED}")
    for name, x in TEST_VECTORS.items():
        print(f"  {name}: x={x} -> X={direct_dft(x)}")
