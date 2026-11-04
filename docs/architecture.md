# Architecture and Design

[← Back to main README](../README.md)

This document contains the mathematical foundation, the DIF algorithm's derivation and schedule, the detailed RTL implementation (arithmetic, memory organization, address generation, reset/handshake), and the design trade-offs behind the baseline 8-point NTT accelerator under `rtl/`. It does not cover the experimental extensions (inverse NTT, N=16, pipelined execution) — see [docs/experiments.md](experiments.md) and the corresponding `experiments/*/README.md` for those.

The high-level hardware architecture, top-level interface, FSM, execution sequence, and baseline latency are covered in the main README instead — see [Top-level interface](../README.md#top-level-interface), [Hardware architecture](../README.md#hardware-architecture), and [Transform execution](../README.md#transform-execution).

## Mathematical foundation

The implementation computes an 8-point Number Theoretic Transform (NTT) over the finite field $\mathbb{Z}/17\mathbb{Z}$, using the following parameters:

| Parameter | Value |
|---|---|
| Transform size | $N = 8$ |
| Modulus | $q = 17$ |
| Primitive root of unity | $\omega = 9$ |

### Primitive root of unity

An N-point NTT requires a primitive Nth root of unity modulo $q$. Such a root satisfies:

$$
\omega^N \equiv 1 \pmod q
$$

and no smaller positive exponent produces 1.

For this transform, $\omega=9$ satisfies:

$$
9^8 \equiv 1 \pmod{17}
$$

while $9^1$, $9^2$, and $9^4$ are not congruent to 1 modulo 17. Therefore, 9 has multiplicative order exactly 8 and is a valid primitive eighth root of unity.

Its successive powers modulo 17 are:

```text
ω^0..ω^8 mod 17 = [1, 9, 13, 15, 16, 8, 4, 2, 1]
```

The existence of an element of order 8 is consistent with the structure of the multiplicative group of a finite field. Since 17 is prime, its nonzero residues form a multiplicative group of order $17-1=16$. By Lagrange's theorem, the order of any element must divide 16. Since $8$ divides $16$, an element of order 8 can exist modulo 17. The calculation above establishes that 9 is such an element.

More generally, for a prime modulus $q$, the condition $N\mid(q-1)$ is necessary for an Nth primitive root of unity to exist.

### Direct NTT definition

For an input sequence of eight coefficients $x[0],\ldots,x[7]$, the forward NTT produces eight output coefficients:

$$
X[k]=\sum_{j=0}^{7}x[j]\omega^{jk}\pmod{17},
\qquad 0\leq k<8
$$

Here, $j$ indexes the input coefficients, $k$ identifies the output coefficient, and powers of $\omega$ provide the corresponding transform factors. All arithmetic is performed modulo 17.

This mathematical definition specifies the transform independently of the algorithm used to evaluate it.

## NTT algorithm and butterfly convention

The direct definition describes each output as a sum involving all eight input coefficients. A radix-2 factorization evaluates the same transform through smaller operations called butterflies.

This implementation uses the **decimation-in-frequency (DIF)** form of the radix-2 Cooley-Tukey algorithm. DIF decomposes the transform by separating even-indexed and odd-indexed output components.

For two input values $a$ and $b$, the corresponding butterfly is:

$$
u=(a+b)\pmod{17}
$$

$$
v=(a-b)\omega^e\pmod{17}
$$

where $e$ is the twiddle-factor exponent determined by the stage and butterfly position.

The sum contributes to the even-indexed output branch, while the twiddle-multiplied difference contributes to the odd-indexed output branch. Repeating this decomposition produces the complete transform through $\log_2 N$ stages.

This is the standard radix-2 DIF factorization used in the Cooley-Tukey FFT. See [Burrus, *Fast Fourier Transforms*, Section 8: The Cooley-Tukey FFT Algorithm](https://eng.libretexts.org/Bookshelves/Electrical_Engineering/Signal_Processing_and_Modeling/Fast_Fourier_Transforms_%28Burrus%29/08%3A_The_Cooley-Tukey_Fast_Fourier_Transform_Algorithm/8.02%3A_Basic_Cooley-Tukey_FFT).

The same factorization applies to the NTT by performing the operations over a finite field and replacing complex roots of unity with powers of $\omega=9$ in $\mathbb{Z}/17\mathbb{Z}$. See [Optimization and implementation of the number theoretic transform butterfly unit for large integer multiplication (2021)](https://www.sciencedirect.com/science/article/pii/S2214212621000909) for further discussion of NTT butterfly arithmetic and implementation.

### Three stages and twiddle exponents

For an 8-point transform, radix-2 decomposition requires:

$$
\log_2 8=3
$$

stages. The butterfly distance decreases from 4 to 2 to 1, with four butterflies at each stage.

| Stage | Distance | Butterfly pairs | Twiddle exponents |
|---|---:|---|---|
| 1 | 4 | (0,4), (1,5), (2,6), (3,7) | 0, 1, 2, 3 |
| 2 | 2 | (0,2), (1,3), (4,6), (5,7) | 0, 2, 0, 2 |
| 3 | 1 | (0,1), (2,3), (4,5), (6,7) | 0, 0, 0, 0 |

The complete transform therefore consists of 12 butterfly operations across three stages.

### Bit-reversed output ordering

A characteristic of radix-2 DIF is that, when the input coefficients are in natural order, the final transform coefficients are produced in bit-reversed order.

For an 8-point transform, the three-bit reversal gives the following correspondence:

| Natural output index | Position in bit-reversed sequence |
|---:|---:|
| 0 | 0 |
| 1 | 4 |
| 2 | 2 |
| 3 | 6 |
| 4 | 1 |
| 5 | 5 |
| 6 | 3 |
| 7 | 7 |

Consequently, the final DIF stage produces:

$$
[X[0],X[4],X[2],X[6],X[1],X[5],X[3],X[7]]
$$

Reordering these coefficients according to their natural indices gives the conventional NTT output:

$$
[X[0],X[1],X[2],X[3],X[4],X[5],X[6],X[7]]
$$

This ordering follows from the recursive even/odd decomposition of the output indices in radix-2 DIF.

### Worked example

Consider the input sequence:

$$
x=[1,2,3,4,5,6,7,8]
$$

Applying the three DIF stages produces the following intermediate sequences:

| Step | Values |
|---|---|
| Stage 1 | `[6, 8, 10, 12, 13, 15, 16, 8]` |
| Stage 2 | `[16, 3, 13, 16, 12, 6, 14, 6]` |
| Stage 3 (bit-reversed order) | `[2, 13, 12, 14, 1, 6, 3, 8]` |

Using the bit-reversed index correspondence established above, the natural-order transform output is:

$$
X=[2,1,12,3,13,6,14,8]
$$

These values agree with the direct NTT definition for the same input.

## Implementation details

This section describes how the architecture is realized in RTL, including the arithmetic circuits, memory organization, address generation, and control behavior. For the module hierarchy, the architecture diagram, and each module's responsibilities, see [Hardware architecture](../README.md#hardware-architecture) in the main README.

### Modular arithmetic

All three arithmetic units operate on canonical 5-bit residues in the range $[0,16]$, the same canonical range required by [Mathematical foundation](#mathematical-foundation). They do not normalize arbitrary 5-bit values and their inputs must already be reduced modulo 17.

**Addition**

The adder calculates $a+b$. Since both inputs are at most 16, the maximum sum is 32, so a 6-bit intermediate result is sufficient. The result is reduced by subtracting 17 when the sum is greater than or equal to 17. One correction is sufficient.

**Subtraction**

The subtractor calculates $a-b$:

- If $a\geq b$, the difference is already in the valid range: $(a-b)\bmod 17=a-b$.
- If $a<b$, it adds 17 to the difference: $(a-b)\bmod 17=a+17-b$.

**Multiplication**

The multiplier first calculates the 9-bit product:

$$
p=a\times b
$$

Because the modulus is 17 and $17=2^4+1$, we can use:

$$
16\equiv -1\pmod{17}
$$

Split the product into its upper bits and lower nibble:

$$
p=16h+l
$$

where $h=p[8:4]$ and $l=p[3:0]$.

Therefore:

$$
p\equiv l-h\pmod{17}
$$

The product is reduced by calculating $l-h$ and adding 17 if the result is negative. This avoids a general-purpose division or modulo operator. The reduction relies on the specific modulus $q=17$ and does not directly generalize to arbitrary primes.

### In-place coefficient memory

The design uses one 8×5-bit memory bank, `mem[0:7]`, throughout the transform.

The same bank stores:

- The eight input coefficients after `LOAD`.
- The intermediate results after each NTT stage.
- The final bit-reversed output after the last stage.

Each butterfly reads two locations and writes the two corresponding results back to those locations.

This in-place organization is safe for the selected schedule. Within each stage, the four butterflies operate on disjoint pairs of addresses. The stages execute sequentially, so a stage finishes all its writes before the next stage begins. There are therefore no read-after-write conflicts in this schedule.

### Address and twiddle-index generation

The controller calculates the coefficient addresses and twiddle exponent from `stage` and `bidx`. It uses shifts and bit masks rather than division, modulo operations, or a fixed 12-entry address lookup table.

For this 8-point transform:

```text
half        = 4 >> stage
group       = bidx >> (2 - stage)
j           = bidx & (half - 1)
lo          = group * (2 * half) + j
hi          = lo + half
twiddle_exp = (j << stage) & 7
```

`lo` and `hi` identify the two coefficient locations used by the current butterfly. `twiddle_exp` selects the corresponding twiddle factor.

The formula is based on the radix-2 DIF schedule and can be adapted to other power-of-two transform sizes. However, this implementation is fixed to $N=8$; the constants are hardcoded and the design is not parameterized.

### Twiddle ROM

The design uses a combinational ROM containing the eight precomputed powers of the primitive root:

$$
[1,9,13,15,16,8,4,2]
$$

A 3-bit exponent selects the corresponding value of $\omega^e\bmod17$. The selected value is captured by the controller during `READ` and used by the multiplier during `COMPUTE`.

### Bit widths

The arithmetic widths are determined by the maximum possible values when the inputs are canonical residues in $[0,16]$.

| Quantity | Maximum value | Required width |
|---|---:|---:|
| Input coefficient | 16 | 5 bits |
| Addition intermediate | 32 | 6 bits |
| Multiplication intermediate | 256 | 9 bits |
| Generated twiddle exponent | 3 | 2 bits |
| Twiddle ROM address | 7 | 3 bits |

The current $N=8$ schedule generates exponents from 0 to 3, requiring two bits to represent the used exponent values. The ROM has eight entries and therefore uses a three-bit address. The implementation retains this three-bit ROM interface.

### Reset and handshake behavior

The design uses a synchronous, active-high reset. When `rst` is asserted, the FSM returns to `IDLE` regardless of its current state.

The memory write enables are also gated with the live reset signal, preventing a load or butterfly write from committing on an edge where reset is asserted.

The `start` input is edge-detected using a delayed copy of the signal:

$$
start\_pulse=start\land\neg start_d
$$

This means a continuously asserted `start` signal triggers only one transform. A start pulse received while the controller is busy is ignored.

The handshake signals behave as follows:

| Signal or behavior | Implementation |
|---|---|
| Start request | Rising-edge detection |
| Start while busy | Ignored |
| Start held high | One transform only |
| Reset | Synchronous, active-high |
| `busy` | High whenever the FSM is not in `IDLE` |
| `done` | Asserted on completion and held until the next accepted transform |

`busy` is combinationally derived from the FSM state. `done` is registered: it is cleared when a new transform is accepted and asserted on the final `WRITE` edge.

## Design decisions and trade-offs

The architecture makes several trade-offs between hardware resource usage, execution latency, and implementation complexity. The choices below reflect the fixed 8-point transform parameters and the requirement to implement the transform using reusable hardware.

### Single shared butterfly versus parallel units

The design uses one shared butterfly datapath consisting of a modular adder, modular subtractor, and multiplier. This datapath is reused for all 12 butterfly operations across the three transform stages.

The main advantage is reduced arithmetic hardware. Instead of implementing four butterfly units to process the four disjoint pairs in a stage simultaneously, the controller reuses the same arithmetic resources sequentially. This keeps the datapath small and avoids the need for multiple simultaneous memory accesses.

The trade-off is execution latency. Each butterfly requires three controller cycles (`READ`, `COMPUTE`, and `WRITE`), resulting in 37 busy cycles per transform, including the initial `LOAD` cycle.

Four parallel butterfly units could reduce execution time by processing an entire stage concurrently. However, this would require four sets of arithmetic resources and a memory organization capable of supplying and storing multiple coefficient pairs simultaneously. This alternative is not implemented or evaluated in this design.

### Sequential execution

The controller executes each butterfly through a strict `READ → COMPUTE → WRITE` sequence. Each operation completes its memory updates before the next butterfly begins.

This approach simplifies operand capture, result storage, and memory access scheduling. It also avoids managing overlapping operations that may depend on the same shared datapath or memory resources.

The trade-off is that the datapath remains idle during some controller phases, and successive butterfly operations cannot overlap. This limits throughput but keeps the control logic and resource requirements relatively simple.

### Five-state FSM versus additional bookkeeping states

The controller uses five states: `IDLE`, `LOAD`, `READ`, `COMPUTE`, and `WRITE`. Stage and butterfly progression are handled by the `stage` and `bidx` counters within the existing state transitions, rather than introducing separate FSM states for counter updates.

The `bidx` counter advances after each completed butterfly. When the final butterfly of a stage is written, `bidx` is reset and `stage` advances. After the final butterfly of the final stage, the controller returns to `IDLE` and asserts `done`.

Keeping this bookkeeping within the `WRITE` exit logic avoids additional state transitions and keeps the FSM focused on the actual datapath operations. Each active operation state (`LOAD`, `READ`, `COMPUTE`, and `WRITE`) occupies one clock cycle, while `IDLE` persists until a start request is accepted. A dedicated counter-update state would introduce an additional clock cycle each time it is visited. Separate counter-update states could make individual control actions more explicit, but would increase execution latency without providing a functional benefit for this design.

### Single in-place bank versus double buffering

All eight coefficients are stored in a single 8×5-bit memory bank, requiring only 40 bits of coefficient storage.

The DIF schedule pairs disjoint coefficient locations within each stage. Consequently, each butterfly reads two locations and writes its two results back to those same locations. No other butterfly in that stage accesses either location, so the operations can safely update the bank in place.

A double-buffered architecture would require two 8×5-bit banks, increasing coefficient storage to 80 bits, together with additional bank-selection logic. Double buffering can be useful when separate input and output storage is required, but it is unnecessary for this sequential in-place schedule.

### Algorithmic address generation versus a lookup table

The butterfly addresses and twiddle exponents are generated algorithmically from the current stage and butterfly index using shift, mask, and arithmetic operations.

This avoids storing a fixed table containing all 12 butterfly address pairs and makes the relationship between the DIF schedule and the hardware control explicit. It also provides a more general approach than explicitly encoding every operation in a lookup table.

A lookup table could simplify control for a fixed schedule, but would explicitly encode the address and exponent sequence. The current implementation favors algorithmic generation, although the address-generation logic is specialized for the 8-point design.

### Precomputed twiddle ROM versus runtime computation

The twiddle factors are stored as constants in a ROM, avoiding runtime modular exponentiation.

This is appropriate because the transform size, modulus, and primitive root are fixed. All required powers can be calculated before implementation, allowing the controller to select the appropriate value directly using the generated twiddle exponent.

The ROM contains the eight powers of the selected primitive root, while the current DIF schedule uses only exponents 0 through 3. Storing the complete set keeps the ROM representation straightforward and makes all powers available explicitly.

### Specialized modular reduction versus general modulo arithmetic

The multiplier uses the identity:

$$
16\equiv-1\pmod{17}
$$

For a product represented as:

$$
p=16h+l
$$

the reduction becomes:

$$
p\equiv l-h\pmod{17}
$$

The implementation therefore subtracts the upper portion of the product from the lower portion and adds 17 when the difference is negative. This avoids a general-purpose modulo operation and exploits the specific structure of the selected modulus.

The trade-off is limited generality. This reduction is specialized for modulus 17 and cannot be applied unchanged to arbitrary primes. Supporting other moduli would require a different reduction method. See [Future work](experiments.md#limitations-and-future-work).

### Fixed-width arithmetic

The design uses fixed-width unsigned vectors rather than integer or floating-point arithmetic. Since every coefficient is maintained in the canonical range 0 to 16, five bits are sufficient to represent each stored coefficient.

The intermediate widths are selected to accommodate the maximum values before modular reduction:

- **Addition:** The maximum sum is 16 + 16 = 32, requiring 6 bits.
- **Subtraction:** The difference is handled using the implementation's conditional correction by 17.
- **Multiplication:** The maximum product is 16 × 16 = 256, requiring 9 bits.

These widths avoid unnecessary datapath width while preserving the complete intermediate arithmetic range. They are specific to the selected modulus and operand range.

### Natural-order output through bit reversal

The iterative DIF algorithm produces its final coefficients in bit-reversed order. Rather than performing an additional memory-reordering pass, the design maps the internal memory locations to natural coefficient order through fixed output indexing.

For an 8-point transform, the three-bit index is reversed when selecting the output coefficient:

$$
coef\_out[k]=mem[bitrev3(k)]
$$

This keeps the internal transform schedule unchanged and avoids additional clock cycles and memory writes for output reordering. The trade-off is that the output mapping is tied to the fixed 8-point transform size.

---

[← Back to main README](../README.md) · [Verification and reproducibility](verification.md) · [Experiments and evaluation](experiments.md)
