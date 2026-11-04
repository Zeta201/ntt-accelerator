#!/usr/bin/env python3
"""Export intermediate NTT coefficient arrays for the test vectors."""

import os
import sys

import ntt_math_validation as val

HERE = os.path.dirname(os.path.abspath(__file__))
VECDIR = os.path.join(HERE, "test_vectors")
STAGEDIR = os.path.join(HERE, "stage_checkpoints")
TB_DIR = os.path.join(os.path.dirname(HERE), "tb")


def _read_vector(path):
    with open(path) as f:
        return [int(line.strip()) for line in f if line.strip() != ""]


def _write_vector(path, vec):
    with open(path, "w") as f:
        for v in vec:
            f.write(f"{v}\n")


def main():
    names = sorted(
        fn[len("input_"):-4]
        for fn in os.listdir(VECDIR)
        if fn.startswith("input_") and fn.endswith(".txt")
    )
    if not names:
        print(f"FAIL: no input_*.txt vectors found under {VECDIR}")
        sys.exit(1)

    os.makedirs(STAGEDIR, exist_ok=True)

    for name in names:
        x = _read_vector(os.path.join(VECDIR, f"input_{name}.txt"))
        intermediates, final_bitrev, natural = val.dif_transform(x)
        assert len(intermediates) == 3, "dif_transform must return 3 stage arrays"
        assert intermediates[2] == final_bitrev, (
            "stage-3 intermediate must equal the final bit-reversed bank"
        )
        for stage_idx in range(3):
            out_path = os.path.join(STAGEDIR, f"stage{stage_idx + 1}_{name}.txt")
            _write_vector(out_path, intermediates[stage_idx])

    os.makedirs(TB_DIR, exist_ok=True)
    manifest_path = os.path.join(TB_DIR, "vector_names.txt")
    with open(manifest_path, "w") as f:
        for name in names:
            f.write(f"{name}\n")

    print(f"exported stage checkpoints for {len(names)} vectors to {STAGEDIR}")
    print(f"wrote manifest of {len(names)} vector names to {manifest_path}")


if __name__ == "__main__":
    main()
