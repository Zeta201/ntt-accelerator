# 8-Point NTT Accelerator

This project implements an 8-point Number Theoretic Transform (NTT) accelerator in Verilog-2001 for the [ARCH Lab hardware task](https://archlabs.us/apply/task26fhe/). The design is simulated using Icarus Verilog.

The accelerator uses a single reusable butterfly datapath for all three stages of the transform, rather than separate hardware for each stage. A ROM stores the twiddle factors, while a finite-state machine (FSM) controls the transform sequence.

The NTT is the finite-field counterpart of the Fast Fourier Transform (FFT). It is widely used in polynomial multiplication, where two polynomials are transformed, multiplied coefficient-wise in the transform domain, and then inverse-transformed. With suitable transform parameters, this reduces the computational complexity from $O(n^2)$ for direct multiplication to $O(n\log n)$.

Unlike FFT implementations that use floating-point arithmetic, an NTT operates over a finite field using integer arithmetic and modular reduction. This avoids floating-point rounding errors and makes NTTs particularly useful in lattice-based cryptography and Fully Homomorphic Encryption (FHE), where efficient polynomial arithmetic is essential. See the task's *Why NTT Matters in Hardware* section for further motivation.

## Table of contents

- [Mathematical foundation](#mathematical-foundation)
- [NTT algorithm and butterfly convention](#ntt-algorithm-and-butterfly-convention)
- [Top-level interface](#top-level-interface)
- [Architecture](#architecture)
- [Transform execution](#transform-execution)
- [Implementation details](#implementation-details)
- [Design decisions and trade-offs](#design-decisions-and-trade-offs)
- [Input and output format](#input-and-output-format)
- [Project structure](#project-structure)
- [Simulation and verification](#simulation-and-verification)
- [Simulation waveforms](#simulation-waveforms)
- [Verification results](#verification-results)
- [Limitations and future extensions](#limitations-and-future-extensions)
- [Assignment coverage](#assignment-coverage)
- [Experiments and evaluation](#experiments-and-evaluation)

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

## Top-level interface

The `ntt_top` module accepts eight 5-bit input coefficients packed into a 40-bit bus and returns the eight NTT coefficients in natural order through another 40-bit bus.

| Signal | Direction | Width | Description |
|---|---|---:|---|
| `clk` | Input | 1 | System clock |
| `rst` | Input | 1 | Synchronous active-high reset |
| `start` | Input | 1 | Transform start request |
| `coef_in` | Input | 40 | Eight packed 5-bit input coefficients |
| `busy` | Output | 1 | High while a transform is in progress |
| `done` | Output | 1 | Asserted when the transform completes |
| `coef_out` | Output | 40 | Eight packed 5-bit output coefficients |

## Architecture

The design uses an iterative architecture with a single shared butterfly datapath and one in-place coefficient memory. Rather than instantiating separate arithmetic units for every butterfly, the same datapath is reused for all 12 butterflies across the three NTT stages.

The design consists of two main blocks:

- **`ntt_controller`**: Controls the transform, generates coefficient addresses and twiddle indices, and schedules the butterfly operations.
- **`coefficient_memory`**: Stores the input coefficients, intermediate stage results, and final output.

The controller contains the twiddle ROM and the shared butterfly datapath.

```text
ntt_top
├── ntt_controller
│   ├── FSM and control registers
│   ├── twiddle_rom
│   └── butterfly_datapath
│       ├── mod_add
│       ├── mod_sub
│       └── mod_mul
└── coefficient_memory
    └── mem[0:7]  (8 × 5-bit)
```

The following diagram shows the main data and control connections.

```mermaid
flowchart TB
    subgraph top["ntt_top"]
        direction TB

        subgraph ctrl["ntt_controller"]
            direction TB
            fsm["FSM and registers"]
            rom["twiddle_rom"]
            subgraph datapath["butterfly_datapath"]
                direction LR
                add["mod_add"]
                sub["mod_sub"]
                mul["mod_mul"]
                sub --> mul
            end
            fsm -.->|twiddle exponent| rom
            rom -->|twiddle| mul
            fsm -->|operands| add
            fsm -->|operands| sub
            add -->|sum result| fsm
            mul -->|product result| fsm
        end

        mem["coefficient_memory<br/>mem[0:7]"]
        fsm -.->|addresses and enables| mem
        mem -->|coefficient values| fsm
        fsm -->|butterfly results| mem
    end

    input(["coef_in"]) --> mem
    mem --> output(["coef_out"])
    start(["start"]) -.-> fsm
    fsm -.-> handshake(["busy, done"])
```

Solid arrows represent coefficient or arithmetic data. Dashed arrows represent control and address signals.

The main responsibilities are:

- **`ntt_top`** connects the controller and coefficient memory, exposes the external interface, and applies the bit-reversal permutation to produce natural-order output.
- **`ntt_controller`** contains the FSM, stage and butterfly counters, address and twiddle-index generation logic, and registers used to capture butterfly inputs and outputs.
- **`coefficient_memory`** is a single in-place bank containing eight 5-bit coefficients. It supports loading all eight inputs and reading or writing the two coefficients involved in a butterfly.
- **`twiddle_rom`** provides the precomputed values of $\omega^e \bmod 17$.
- **`butterfly_datapath`** contains one shared combinational adder, subtractor, and multiplier. The adder and subtractor operate on the same input pair; the subtraction result is multiplied by the twiddle factor.

The butterfly datapath has no internal registers. Its inputs and outputs are captured by registers in the controller.

## Transform execution

The controller executes the NTT by processing one butterfly at a time. Each of the three stages contains four butterflies, giving a total of 12 butterfly operations.

### Butterfly operation

The radix-2 DIF butterfly computes:

$$
u=(a+b)\bmod 17
$$

$$
v=(a-b)\omega^e\bmod 17
$$

where $a$ and $b$ are the selected coefficient pair, and $\omega^e$ is the corresponding twiddle factor.

The shared datapath computes both results combinationally:

1. `mod_add` calculates the sum $u$.
2. `mod_sub` calculates the difference $a-b$ modulo 17.
3. `mod_mul` multiplies the difference by the selected twiddle factor to produce $v$.

The controller captures the two results and writes them back to their respective memory locations.

### Butterfly schedule

The controller uses two counters:

- `stage` identifies the current NTT stage, ranging from 0 to 2.
- `bidx` identifies the butterfly within the current stage, ranging from 0 to 3.

The schedule is:

| Stage | Distance | Butterfly pairs | Twiddle exponents |
|---|---:|---|---|
| 1 | 4 | (0,4), (1,5), (2,6), (3,7) | 0, 1, 2, 3 |
| 2 | 2 | (0,2), (1,3), (4,6), (5,7) | 0, 2, 0, 2 |
| 3 | 1 | (0,1), (2,3), (4,5), (6,7) | 0, 0, 0, 0 |

Each stage processes four butterflies. Once all four have completed, the controller advances to the next stage. After the fourth butterfly of the third stage, the transform is complete.

### Controller state machine

Five states control the execution:

| State | Operation |
|---|---|
| `IDLE` | Wait for a start request |
| `LOAD` | Write all eight input coefficients into memory |
| `READ` | Read the selected coefficient pair and twiddle factor |
| `COMPUTE` | Capture the butterfly results |
| `WRITE` | Write both results back to memory and advance the schedule |

The execution sequence is:

```mermaid
stateDiagram-v2
    [*] --> IDLE
    IDLE --> LOAD: start_pulse
    LOAD --> READ
    READ --> COMPUTE
    COMPUTE --> WRITE
    WRITE --> READ: bidx &lt; 3
    WRITE --> READ: bidx == 3 &amp;&amp; stage &lt; 2
    WRITE --> IDLE: bidx == 3 &amp;&amp; stage == 2 / done &lt;= 1

    note right of IDLE
        Synchronous active-high reset
        forces the FSM to IDLE from
        any state.
    end note
```

The `READ`, `COMPUTE`, and `WRITE` states repeat for each butterfly. The controller does not begin the next butterfly until the current butterfly's results have been written to memory.

The `stage` and `bidx` counters are advanced as part of the `WRITE` state's exit logic. This avoids introducing additional FSM states or clock cycles just for schedule bookkeeping.

### Cycle-by-cycle operation

Each butterfly takes three clock cycles:

1. **READ:** The controller reads the two coefficients from memory, selects the twiddle factor from the ROM, and captures these values into `a_reg`, `b_reg`, and `tw_reg`.
2. **COMPUTE:** The combinational butterfly datapath calculates the sum and twiddle-multiplied difference. The controller captures the results into `u_reg` and `v_reg`.
3. **WRITE:** The controller writes `u_reg` and `v_reg` back to the two selected memory locations.

This sequence ensures that each butterfly completes before the next one begins. There are no overlapping butterfly operations or pending writes when a subsequent butterfly starts.

## Implementation details

This section describes how the architecture is realized in RTL, including the arithmetic circuits, memory organization, address generation, and control behavior.

### Modular arithmetic

All three arithmetic units operate on canonical 5-bit residues in the range $[0,16]$, the same canonical range required by [Mathematical foundation](#mathematical-foundation). They do not normalize arbitrary 5-bit values and their inputs must already be reduced modulo 17.

**Addition**

The adder calculates $a+b$. Since both inputs are at most 16, the maximum sum is 32, so a 6-bit intermediate result is sufficient. The result is reduced by subtracting 17 when the sum is greater than or equal to 17. One correction is sufficient.

**Subtraction**

The subtractor calculates $a-b$. If $a\geq b$, the difference is already in the valid range. Otherwise, it adds 17 to the difference:

$$
(a-b)\bmod 17 =
\begin{cases}
a-b, & a\geq b\\
a+17-b, & a<b
\end{cases}
$$

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
| Twiddle exponent | 7 | 3 bits |

The twiddle exponent is calculated from `j` and `stage`. Since $j<4>>stage$, the shifted value remains below 4 for this schedule, so the 3-bit exponent is sufficient.

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

### Latency

The transform requires:

- 1 cycle to load the eight input coefficients.
- 12 butterflies.
- 3 cycles per butterfly.

Therefore:

$$
1+(12\times3)=37\text{ cycles}
$$

The measured latency is 37 busy cycles, from the accepted-start edge to the final `WRITE` edge. This was independently checked using a busy-cycle counter and the distance between the accepted-start and completion edges. See [Verification results](#verification-results).

## Design decisions and trade-offs

The architecture makes several deliberate trade-offs between hardware resource usage, execution latency, and implementation complexity. The choices below reflect the fixed 8-point transform parameters and the requirement to implement the transform using reusable hardware.

### Single shared butterfly versus parallel units

The design uses one shared butterfly datapath consisting of a modular adder, modular subtractor, and multiplier. This datapath is reused for all 12 butterfly operations across the three transform stages.

The main advantage is reduced arithmetic hardware. Instead of implementing four butterfly units to process the four disjoint pairs in a stage simultaneously, the controller reuses the same arithmetic resources sequentially. This keeps the datapath small and avoids the need for multiple simultaneous memory accesses.

The trade-off is execution latency: each butterfly requires three controller cycles (`READ`, `COMPUTE`, and `WRITE`), resulting in 37 busy cycles per transform, including the initial `LOAD` cycle.

Four parallel butterfly units could reduce the execution time by processing an entire stage concurrently. However, this would require four sets of arithmetic resources and a memory organization capable of supplying and storing multiple coefficient pairs simultaneously. The parallel alternative was not synthesized or measured, so this comparison is architectural rather than a measured PPA result.

### Sequential execution versus pipelining

The controller executes each butterfly through a strict `READ → COMPUTE → WRITE` sequence. Each operation completes its memory updates before the next butterfly begins.

This approach simplifies operand capture, result storage, and memory access scheduling. It also avoids the need to manage overlapping operations that may depend on the same shared datapath or memory resources.

A pipelined implementation could improve throughput by overlapping operations, but would require additional pipeline registers, control logic, and careful handling of memory dependencies. Since the current design prioritizes resource reuse and straightforward control over maximum throughput, the additional complexity was not introduced.

### Five-state FSM versus additional bookkeeping states

The controller uses five states: `IDLE`, `LOAD`, `READ`, `COMPUTE`, and `WRITE`. Stage and butterfly progression are handled by the `stage` and `bidx` counters within the existing state transitions, rather than introducing separate FSM states for counter updates.

The `bidx` counter advances after each completed butterfly. When the final butterfly of a stage is written, `bidx` is reset and `stage` advances. After the final butterfly of the final stage, the controller returns to `IDLE` and asserts `done`.

Keeping this bookkeeping within the `WRITE` exit logic avoids additional state transitions and keeps the FSM focused on the actual datapath operations. Every state in this controller occupies exactly one clock cycle, so a dedicated counter-update state reachable only through its own transition would add one clock cycle per occurrence, not just a theoretical risk of one. Separate counter-update states could make individual control actions more explicit, but would increase execution latency without providing a functional benefit for this design.

### Single in-place bank versus double buffering

All eight coefficients are stored in a single 8×5-bit memory bank, requiring only 40 bits of coefficient storage.

The DIF schedule pairs disjoint coefficient locations within each stage. Consequently, each butterfly reads two locations and writes its two results back to those same locations. No other butterfly in that stage accesses either location, so the operations can safely update the bank in place.

A double-buffered architecture would require two 8×5-bit banks, increasing coefficient storage to 80 bits, together with additional bank-selection logic. It would be useful in an architecture that overlaps stages or requires separate input and output storage, but provides no execution-time advantage in the current sequential design.

### Algorithmic address generation versus a lookup table

The butterfly addresses and twiddle exponents are generated algorithmically from the current stage and butterfly index using shift, mask, and arithmetic operations.

This avoids storing a fixed table containing all 12 butterfly address pairs and makes the relationship between the DIF schedule and the hardware control explicit. The same generation approach also provides a starting point for supporting larger power-of-two transform sizes.

A lookup table would be simpler for a fixed schedule, but would explicitly encode the address and exponent sequence. The current implementation favors algorithmic generation, although the address-generation logic and supported transform size remain specialized for the 8-point design.

### Precomputed twiddle ROM versus runtime computation

The twiddle factors are stored as constants in a ROM, avoiding runtime modular exponentiation.

This is appropriate because the transform size, modulus, and primitive root are fixed. All required powers can be calculated before implementation, allowing the controller to select the appropriate value directly using the generated twiddle exponent.

The ROM contains the eight powers of the selected primitive root, while the current DIF schedule uses only exponents 0 through 3. Storing the complete set keeps the ROM representation straightforward and leaves the available powers explicit.

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

The trade-off is limited generality: this reduction is specialized for modulus 17 and cannot be applied unchanged to arbitrary primes. Supporting other moduli would require a different reduction method. See [Limitations and future extensions](#limitations-and-future-extensions).

### Fixed-width arithmetic

The design uses fixed-width unsigned vectors rather than integer or floating-point arithmetic. Since every coefficient is maintained in the canonical range 0 to 16, five bits are sufficient to represent each stored coefficient.

The intermediate widths are selected to accommodate the maximum values before modular reduction:

- Addition: the maximum sum is 16 + 16 = 32, requiring 6 bits.
- Subtraction: the difference is handled using the implementation's conditional correction by 17.
- Multiplication: the maximum product is 16 × 16 = 256, requiring 9 bits.

These widths avoid unnecessary datapath width while preserving the complete intermediate arithmetic range. They are specific to the selected modulus and operand range.

### Natural-order output through bit reversal

The iterative DIF algorithm produces its final coefficients in bit-reversed order. Rather than performing an additional memory-reordering pass, the design maps the internal memory locations to natural coefficient order through fixed output indexing.

For an 8-point transform, the three-bit index is reversed when selecting the output coefficient:

$$
\text{coef\_out}[k]=\text{mem}[\operatorname{bitrev}_3(k)]
$$

This keeps the internal transform schedule unchanged and avoids additional clock cycles and memory writes for output reordering. The trade-off is that the output mapping is tied to the fixed 8-point transform size.

## Input and output format

Both `coef_in` and `coef_out` pack eight 5-bit coefficients into a 40-bit bus. Coefficients are packed least-significant first:

$$
coef\_in[5k+:5]=x[k]
$$

For example, to drive the input vector $x[0..7]$:

```verilog
coef_in = {
    x[7], x[6], x[5], x[4],
    x[3], x[2], x[1], x[0]
};
```

The output bus uses the same packing convention:

$$
coef\_out[5k+:5]=X[k]
$$

The output is already in natural order. The controller performs the transform using the radix-2 DIF schedule, which produces results in bit-reversed order. `ntt_top` applies the output permutation:

$$
coef\_out[5k+:5]=mem[bitrev3(k)]
$$

where `bitrev3` reverses the three bits of the index.

**Input contract**

Every input coefficient must be a canonical residue in $[0,16]$. The hardware does not normalize invalid inputs. Although a 5-bit field can represent values from 0 to 31, values from 17 to 31 are outside the supported input domain.

The testbench reads input and expected-output vectors from decimal text files, with one coefficient per line and eight lines per vector:

- `reference/test_vectors/input_<name>.txt`
- `reference/test_vectors/expected_<name>.txt`

The list of vector names is read from `tb/vector_names.txt`, which is generated from the input-vector files present rather than being hardcoded.

For each vector, the testbench also reads the expected intermediate memory contents after each DIF stage:

- `reference/stage_checkpoints/stage1_<name>.txt`
- `reference/stage_checkpoints/stage2_<name>.txt`
- `reference/stage_checkpoints/stage3_<name>.txt`

This allows the testbench to check not only the final transform output but also the intermediate results produced at each stage.

## Project structure

The repository is organized into five main directories, separating the RTL implementation, testbenches, mathematical reference code, execution scripts, and waveform artifacts.

```text
ntt_accelerator/
├── README.md
├── .gitignore
├── rtl/                            # Verilog implementation
│   ├── ntt_top.v                   # Top-level module and output bit reversal
│   ├── ntt_controller.v            # FSM, address/twiddle generation, registers
│   ├── coefficient_memory.v        # In-place 8×5-bit coefficient memory
│   ├── butterfly_datapath.v        # Shared combinational butterfly
│   ├── modular_arithmetic.v        # mod_add, mod_sub, mod_mul
│   └── twiddle_rom.v               # Twiddle-factor lookup table
├── tb/                             # Verilog testbenches and fixtures
│   ├── tb_ntt_top.v                # Transform, intermediate, sequencing, timing checks
│   ├── tb_modular_arithmetic.v     # Exhaustive 17×17 arithmetic checks
│   ├── tb_control.v                # Reset and start/busy/done tests
│   ├── tb_negative.v               # Invalid-input and timeout tests
│   ├── vector_names.txt            # Generated test-vector manifest
│   └── fixtures/                   # Malformed, short, and out-of-range inputs
├── reference/                      # Independent mathematical reference code
│   ├── ntt_reference_model.py      # Direct NTT definition and vector generation
│   ├── ntt_math_validation.py      # Independent mathematical validation
│   ├── export_stage_checkpoints.py # Generates intermediate-stage checkpoints
│   ├── test_vectors/               # 31 input/expected-output vector pairs
│   └── stage_checkpoints/          # Expected memory contents after each stage
├── scripts/
│   └── run_all_tests.sh            # Compiles and runs all four testbenches
├── waves/                          # Waveform capture and inspection artifacts
│   ├── dump_waveforms.v            # Standalone VCD capture harness
│   ├── render_waveforms.py         # Generates waveform screenshots from VCD
│   ├── ntt_top.vcd                 # Recorded full-transform waveform
│   └── trace.log                   # Per-cycle execution trace
└── docs/
    └── images/                     # Waveform screenshots used in this README
```

The main directories have distinct responsibilities:

- `rtl/` contains the synthesizable Verilog implementation.
- `tb/` contains the testbenches that exercise the RTL, along with fixtures used by negative tests.
- `reference/` contains the Python reference implementations, mathematical checks, and expected test data.
- `scripts/` contains the script used to run the complete RTL test suite.
- `waves/` contains the standalone waveform-capture harness, recorded VCD, and trace-generation utilities.
- `docs/images/` contains the rendered waveform screenshots included in this documentation.

## Simulation and verification

### Prerequisites

The project requires:

- Icarus Verilog (`iverilog` and `vvp`).
- Python 3.

**Tested versions:** Icarus Verilog 13.0 (stable) and Python 3.11.13.

### Running the test suite

The complete RTL test suite can be executed using:

```bash
cd ntt_accelerator
./scripts/run_all_tests.sh
```

The script compiles and runs all four Verilog testbenches and aggregates their pass/fail results.

### Verification strategy

Verification is performed at four levels. Each level checks a different aspect of the implementation, from the mathematical transform to the behavior of the RTL controller.

**1. Mathematical validation**

`reference/ntt_math_validation.py` performs independent Python checks without involving the RTL.

It validates:

- The multiplicative order of the selected root of unity.
- The radix-2 DIF butterfly schedule.
- The bit-reversal permutation.
- The modular arithmetic operations.
- The on-disk test vectors in `reference/test_vectors/`, checking each one's expected output against both the direct NTT definition and independently-derived DIF computations.

This establishes that the mathematical conventions and expected intermediate values used by the project are internally consistent. It does not read `reference/stage_checkpoints/`; those files are consumed only by `tb_ntt_top.v` for the RTL-level intermediate-stage checks described below.

**2. Independent reference-model comparison**

`reference/ntt_reference_model.py` implements the NTT directly from its mathematical definition:

$$
X[k]=\sum_{j=0}^{7}x[j]\omega^{jk}\pmod{17}
$$

It does not implement the DIF butterfly schedule or reuse the RTL's address-generation logic.

The direct transform is compared against the DIF-based implementation for all 31 test vectors. Because the two approaches calculate the transform differently, their agreement provides an independent check of the algorithm and output ordering.

**3. RTL functional verification**

`tb/tb_ntt_top.v` exercises the actual `ntt_top` module through its external interface.

For all 31 test vectors, it checks:

- The final NTT coefficients against the expected outputs.
- The coefficient memory contents after each of the three DIF stages.
- The coefficient addresses selected for every butterfly.
- The twiddle exponent used by every butterfly.
- The expected execution sequence and transform timing.

The intermediate-stage checks are particularly useful because they can identify errors in the butterfly schedule or address generation even when examining only the final output might not reveal where the error occurred.

**4. Control and negative testing**

The remaining testbenches check behavior that is not covered by the normal transform-vector sweep.

- `tb/tb_control.v` tests reset behavior, start-edge detection, and the `busy`/`done` handshake.
- `tb/tb_negative.v` tests that its own file-reading logic (not the RTL) correctly classifies missing, malformed, wrong-count, and out-of-range input fixtures as setup errors — the hardware itself does not parse or validate input files. Separately, it verifies that the DUT's `done` output never asserts and the FSM stays in `IDLE` during a bounded polling window while reset is held.

Together, these tests cover both normal operation and the handling of invalid or incomplete test inputs.

### Run the full RTL verification suite

```bash
cd ntt_accelerator
./scripts/run_all_tests.sh
```

Compiles and runs all four testbenches against `rtl/` in order and
aggregates pass/fail. It needs to run with `ntt_accelerator/` as the
working directory (the script `cd`s there itself), since the
testbenches open input and fixture files using relative paths.
Successful output looks like this:

```text
=== NTT accelerator verification suite ===

--- tb_modular_arithmetic ---
...
PASSED: tb_modular_arithmetic

--- tb_ntt_top ---
...
PASSED: tb_ntt_top

--- tb_control ---
...
PASSED: tb_control

--- tb_negative ---
...
PASSED: tb_negative

=== summary ===
ALL TESTBENCHES PASSED
```

(each `...` stands for that testbench's own per-check output, left out
here for space). Success means `ALL TESTBENCHES PASSED` and exit code
`0`.

### Run the independent mathematical validation

```bash
cd ntt_accelerator/reference
python3 ntt_math_validation.py
```

This is read-only with respect to `test_vectors/`. It never
regenerates or repairs a vector file; a missing or corrupted one just
gets reported as a failure. Success means `RESULT: PASS (0 failures)`
and exit code `0`.

### Regenerating test vectors or stage checkpoints (not part of ordinary validation)

These are one-time generation steps. They're not run automatically by
the validator or the test suite, and you don't need them to validate
what's already committed. They do need to run in order, since each step
depends on the previous one's output:

1. `ntt_reference_model.py` generates the `input_*.txt`/`expected_*.txt`
   vector files from the direct NTT definition.
2. `export_stage_checkpoints.py` reads those input files and generates
   the intermediate stage checkpoint files and the `tb/vector_names.txt`
   manifest.
3. `tb_ntt_top.v` (run via `run_all_tests.sh`) loads all of the above
   and verifies the actual RTL against them.

```bash
cd ntt_accelerator/reference
python3 ntt_reference_model.py          # (re)generates test_vectors/
python3 export_stage_checkpoints.py     # (re)generates stage_checkpoints/ and tb/vector_names.txt
```

## Simulation waveforms

The waveform artifacts provide a signal-level view of the actual RTL execution. They complement the automated verification results by showing how the controller, memory, and arithmetic datapath behave during a transform.

### Capturing a transform

`waves/dump_waveforms.v` is a standalone simulation harness, separate from the four automated testbenches. It instantiates the actual `ntt_top` module and drives one complete transform using the worked-example input:

$$
x=[1,2,3,4,5,6,7,8]
$$

The harness records the signal transitions throughout the execution and writes them to `waves/ntt_top.vcd`. The same simulation also produces `waves/trace.log`, a per-cycle text trace of the execution.

The VCD is retained in the repository so that the recorded signal transitions can be independently inspected using GTKWave or another compatible waveform viewer.

### Complete transform

![Complete execution waveform](docs/images/ntt-complete-execution.png)

This waveform shows `clk`, `rst`, `start`, `busy`, `done`, and the controller's `state`, `stage`, and `bidx` signals across the complete transform.

It shows that:

- `busy` rises after the accepted start request and remains asserted throughout the 37-cycle execution.
- `done` is asserted on the final `WRITE` edge, when `busy` returns low.
- `stage` progresses through 0, 1, and 2.
- `bidx` progresses from 0 to 3 within each stage.

### Single butterfly operation

![Single butterfly waveform](docs/images/butterfly-operation.png)

This waveform focuses on stage 0, `bidx = 1`, and shows the controller's `READ → COMPUTE → WRITE` sequence.

The signals include `state`, `stage`, `bidx`, `lo`, `hi`, `twiddle_exp`, `a_reg`, `b_reg`, `tw_reg`, `u_reg`, `v_reg`, and `write_enable`.

The sequence shows how the controller:

1. Captures the selected operands and twiddle factor during `READ`.
2. Captures the butterfly results during `COMPUTE`.
3. Asserts `write_enable` during `WRITE` to commit both results to memory.

The same registers and combinational butterfly datapath are reused for all 12 operations, illustrating the iterative reuse of the hardware rather than separate per-butterfly units.

### Modular arithmetic datapath

![Modular arithmetic datapath waveform](docs/images/modular-arithmetic.png)

This waveform zooms into the arithmetic operations performed during the same butterfly.

It shows:

- `a` and `b`, the shared operands supplied to the adder and subtractor.
- `sum`, the result from `mod_add`.
- `diff`, the result from `mod_sub`.
- `tw`, the multiplier's twiddle-factor input.
- `p`, the raw 9-bit multiplication result.
- `l` and `h`, the lower-nibble and upper-bit portions of the product.
- `v`, the final modulo-17 multiplication result.

The waveform illustrates the specialized modulo-17 reduction:

$$
p=16h+l\equiv l-h\pmod{17}
$$

The final result is obtained from `l-h`, with 17 added when the difference is negative, rather than using a general-purpose modulo operation.

### Inspecting the recorded waveform

To inspect the recorded execution in GTKWave:

```bash
cd ntt_accelerator
gtkwave waves/ntt_top.vcd
```

To regenerate the waveform and trace artifacts, run the standalone simulation harness:

```bash
iverilog -g2001 -Wall -o /tmp/dump.vvp \
    rtl/*.v waves/dump_waveforms.v

vvp /tmp/dump.vvp
```

The accompanying `waves/trace.log` provides a textual view of the same execution. It contains 37 busy-cycle entries before the final output comparison, consistent with the measured transform latency. Its final `coef_out` also matches the worked example's natural-order NTT output.

## Verification results

The accelerator was verified using a combination of RTL simulation and independent mathematical validation. The RTL testbenches exercise the implemented hardware, while the Python validation checks the transform mathematics and reference results independently. All reported checks completed successfully with zero failures.

### Test results

The following results were obtained from the current verification run:

| Check | Count | Failures |
|---|---:|---:|
| Exhaustive modular arithmetic (289 operand pairs, 6 checks per pair) | 1,734 | 0 |
| Test-vector outputs, intermediate-stage results, and sequencing | 3,511 | 0 |
| Control, reset, start, and done (7 directed scenarios) | 111 | 0 |
| Negative tests, setup errors, and timeout handling (6 scenarios) | 7 | 0 |
| **RTL suite total** | **5,363** | **0** |
| Mathematical validation (`ntt_math_validation.py`) | **3,579** | **0** |

**Simulation environment:**
- Simulator: Icarus Verilog 13.0 (stable).
- Reference validation: Python 3.11.13.
- RTL language standard: Verilog-2001.

### RTL verification coverage

The RTL verification is divided into four testbenches, each targeting a different part of the design.

**1. Modular arithmetic (`tb_modular_arithmetic.v`)**

The modular arithmetic unit is tested exhaustively over all possible pairs of canonical coefficients in the range 0 to 16. This gives 17 × 17 = 289 operand pairs.

Each pair is checked against six arithmetic conditions covering modular addition, subtraction, and multiplication, including the specialized modulo-17 reduction. This produces 1,734 checks in total.

**2. Transform execution (`tb_ntt_top.v`)**

The top-level testbench runs all 31 input vectors through the complete 8-point transform. It checks the final output against the expected results and verifies intermediate-stage memory contents against independently generated stage checkpoints.

It also checks the butterfly address and twiddle-factor sequence to ensure that the controller follows the intended DIF schedule.

Across the 31 transforms, the controller executes 12 butterflies per transform, giving 372 butterfly operations. All 372 operations are sequenced correctly, and the corresponding intermediate-stage and final results pass verification.

**3. Control and handshake (`tb_control.v`)**

Directed scenarios exercise the controller's reset and handshake behavior. These checks cover start acceptance, busy-state behavior, completion signaling, and the controller's response to reset.

They verify that the control logic follows the expected state transitions and that `busy` and `done` behave correctly throughout a transform.

**4. Negative and setup-error tests (`tb_negative.v`)**

The negative tests cover missing files, malformed input, incorrect coefficient counts, out-of-range values, and timeout handling.

An important distinction is that the file-related cases exercise the testbench's own input-file handling logic, not the RTL. The hardware itself does not parse or validate input files. A separate reset-held scenario exercises the actual DUT and checks that `done` remains deasserted and the FSM stays in `IDLE`.

### Independent mathematical validation

The Python validation script (`reference/ntt_math_validation.py`) performs 3,579 checks independently of the RTL simulation.

It validates the mathematical properties used by the implementation, including the primitive-root properties of the selected transform parameters, the DIF butterfly schedule, the bit-reversal mapping, and modular arithmetic behavior. It also checks the on-disk test vectors in `reference/test_vectors/` against the mathematical reference results.

The stage checkpoint files in `reference/stage_checkpoints/` are generated separately by `export_stage_checkpoints.py` and consumed by the top-level RTL testbench. They are not read by `ntt_math_validation.py`.

The mathematical validation and RTL simulation therefore provide complementary evidence: the Python checks validate the mathematical reference, while the RTL testbenches verify that the hardware implementation follows the intended operations and produces the expected results.

### Measured transform latency

The implementation completes each transform in **37 busy cycles**, consistently across all 31 test vectors.

The latency follows directly from the controller's execution sequence:

| Operation | Cycles |
|---|---:|
| Initial input loading (`LOAD`) | 1 |
| Butterfly operations (`12 × 3 cycles`) | 36 |
| **Total busy cycles** | **37** |

Each butterfly uses three controller cycles: `READ`, `COMPUTE`, and `WRITE`. The same datapath is reused for all 12 operations rather than executing them in parallel.

The 37-cycle measurement is taken from the accepted start edge through the completion edge of the final `WRITE` operation. It represents the simulated controller latency for one transform, not a measured maximum operating frequency or physical hardware performance.

## Limitations and future extensions

The implementation is intentionally scoped to the fixed 8-point transform specified by the task. The following limitations describe what the current RTL does not support; they are not failures to meet the task requirements.

### Current limitations

- **Fixed transform parameters:** The transform size $N=8$, modulus $q=17$, and primitive root $\omega=9$ are hardcoded. The design is not parameterized for other transform sizes or moduli.
- **Canonical input requirement:** Each input coefficient must be in the range $0$ to $16$. Although the input interface uses 5-bit values, the hardware does not normalize values outside the canonical range before processing them.
- **Iterative execution:** A single butterfly datapath is reused sequentially for all 12 butterfly operations. The design does not execute multiple butterflies in parallel or pipeline successive operations. Each transform takes 37 busy cycles.
- **Forward transform only:** The implementation supports the forward NTT but does not include an inverse NTT (INTT).
- **No synthesis or physical implementation:** The design has been simulated and functionally verified, but has not been synthesized for an FPGA or ASIC. Consequently, no hardware area, maximum operating frequency, timing closure, or power measurements are reported.

**Possible future extensions.** The task's *Design Freedom* section identifies several possible directions for extending the implementation. These are opportunities for further development rather than requirements of the current submission.

### Inverse Number Theoretic Transform

An inverse transform would require using inverse powers of the primitive root and applying a final normalization factor.

For the current parameters:

$$
\omega^{-1}=2\pmod{17}
$$

because $9\times2\equiv1\pmod{17}$.

The inverse transform would also require scaling each output coefficient by the modular inverse of the transform length:

$$
N^{-1}=8^{-1}=15\pmod{17}
$$

because $8\times15\equiv1\pmod{17}$.

This would require an inverse-twiddle ROM or equivalent twiddle-generation logic, together with a final scaling operation for each output coefficient.

### Pipelined execution

The current controller completes each butterfly through separate `READ`, `COMPUTE`, and `WRITE` cycles before starting the next operation.

A pipelined implementation could overlap different execution phases of successive butterflies to improve throughput. However, this would require changes to the datapath and controller, including pipeline registers, resource scheduling, and appropriate handling of memory dependencies.

The current sequential execution avoids these complications by allowing only one butterfly operation to be active at a time.

### Larger transform sizes

The address-generation logic, coefficient memory, counters, and twiddle ROM could be extended to support larger power-of-two transform sizes.

The choice of modulus must also support the required transform length. For a radix-2 NTT of length $N$, the modulus must admit a primitive $N$-th root of unity, which requires:

$$
N\mid(q-1)
$$

For the current modulus $q=17$, the multiplicative group has order $q-1=16$. Therefore, a primitive 16th root of unity exists, making an $N=16$ transform mathematically possible without changing the modulus.

An $N=32$ transform would require a different modulus for which 32 divides $q-1$.

### Generalized modular multiplication

The current multiplier exploits the identity:

$$
16\equiv-1\pmod{17}
$$

This allows the product to be reduced using subtraction and conditional correction rather than a general-purpose modulo operation.

For other moduli, this specific reduction is not generally applicable. Supporting a wider range of primes would require a more general modular reduction method, such as Barrett or Montgomery reduction, selected according to the target modulus and hardware requirements.

## Assignment coverage

| Requirement | Implemented as |
|---|---|
| 8-point transform, 8 in / 8 out | `coef_in[39:0]` / `coef_out[39:0]`, 8×5-bit packed |
| N=8, q=17, ω=9 | Fixed by memory depth, ROM contents, and address-generation width |
| Single iterative butterfly | One `butterfly_datapath` instance, reused for all 12 butterflies |
| ROM-based precomputed twiddles | `twiddle_rom.v`, 8 literal constants |
| FSM-based control | `ntt_controller.v`, 5-state FSM |
| Correct address/twiddle generation | Shift/mask formula, independently re-derived and matched in `ntt_math_validation.py` |
| Modular arithmetic | `modular_arithmetic.v`, exhaustively checked over all 289 canonical operand pairs; additional mathematical validation performed by `ntt_math_validation.py` |
| Working testbench | `tb/tb_ntt_top.v` + 3 supporting testbenches, `scripts/run_all_tests.sh` |
| Text-file input loading | `$fscanf`-based readers in `tb_ntt_top.v`, against `reference/test_vectors/` |
| Correct output verification | 31/31 test vectors match, independently cross-checked against the direct NTT definition |
| Open-source simulation | Icarus Verilog 13.0 |

## Experiments and evaluation

Everything above this section documents the required 8-point forward NTT
submission. This section documents additional, optional experiments built
on top of that baseline, kept in `experiments/` so the baseline RTL in
`rtl/` stays untouched and independently verifiable. Experiments are
implemented and verified one at a time; this README section is updated only
for experiments that have actually been completed, verified, and committed.

### Baseline implementation

The baseline is the forward-only 8-point NTT accelerator documented in the
rest of this README: `N=8`, `q=17`, `ω=9`, a single shared butterfly
datapath, a 5-state FSM (`IDLE`/`LOAD`/`READ`/`COMPUTE`/`WRITE`), 37 busy
cycles per transform, 5363 RTL verification checks and 3579 independent
Python mathematical checks, both at 0 failures. See
[Architecture](#architecture), [Transform execution](#transform-execution),
and [Verification results](#verification-results) for the full
documentation; it is not repeated here.

### Experiment 1: Inverse NTT (INTT)

**Objective.** Add inverse-transform support (`INTT`) to the accelerator
while leaving the forward transform's RTL, behavior, and verification
results completely unchanged, and reusing the existing butterfly datapath
and memory ports rather than duplicating hardware.

**Implementation.** The inverse transform turned out to be computable with
the *same* DIF network, the *same* address schedule, and the *same*
butterfly shape as the forward transform — only the twiddle source and one
extra post-processing pass differ. This was derived and verified in Python
before any RTL was written: feeding the frequency-domain coefficients `X`
in natural order through the unmodified forward schedule, using inverse
twiddles (`ω⁻¹=2`) instead of forward twiddles, reading the result through
the same `bitrev3` output mapping, and scaling every coefficient by
`N⁻¹=15 mod 17`, exactly reproduces the direct inverse-DFT definition
(verified against 500 random vectors before touching RTL).

Three new files implement this, kept in `experiments/intt/rtl/` rather than
modifying `rtl/`:

- `twiddle_rom.v` — adds an `inv` select input and a second ROM table
  (`ω⁻¹` powers: `[1,2,4,8,16,15,13,9]`) alongside the unchanged forward
  table.
- `ntt_controller.v` — adds an `inv` input, a `mode_reg` (captured once, at
  the accepted-start edge, exactly like the existing start-pulse
  edge-detection — so changing `inv` while busy cannot affect an in-flight
  transform), and a `phase`/`nidx` pair implementing one extra pass after
  the 12 inverse butterflies: `phase=1` revisits all 8 memory locations
  (`nidx=0..7`), and for each one drives the *same* `a_reg`/`b_reg`/`tw_reg`
  registers and the *same* `butterfly_datapath` instance with
  `(mem[nidx], 0, 15)` — since `mod_sub(a,0)=a`, this makes the shared
  datapath compute exactly `mem[nidx] × 15 mod 17` with no new arithmetic
  hardware. The result is written back through the existing two-port
  memory write (`lo_reg=hi_reg=nidx`), which is race-free because both
  `u_reg` and `v_reg` are registered to the identical scaled value in
  normalization mode, so the dual write is not order-dependent.
- `ntt_top.v` — adds the `inv` port and wires it through; otherwise
  identical to `rtl/ntt_top.v`.

`coefficient_memory.v`, `butterfly_datapath.v`, and `modular_arithmetic.v`
are reused unchanged directly from `rtl/`.

Forward-mode behavior (`inv=0`) is unchanged by construction: the
`phase`/`nidx` extension only activates `if (mode_reg)` at the point where
the baseline FSM would otherwise assert `done`, so the forward path's
states, transitions, and 37-cycle latency are bit-for-bit identical to the
baseline.

**Verification.** Two independent layers, mirroring the baseline's
structure:

- `experiments/intt/reference/intt_math_validation.py`: verifies
  `ω⁻¹=2` and `N⁻¹=15`, the inverse twiddle table, the hardware schedule
  model against the direct inverse-DFT definition (500 random vectors),
  round-trip identities `INTT(NTT(x))=x` and `NTT(INTT(X))=X` (500 vectors
  each), and the 31 on-disk INTT test vectors — **1661 checks, 0
  failures**.
- `experiments/intt/tb/tb_intt.v`: forward-mode regression (the INTT-capable
  `ntt_top` reproduces all 31 baseline forward vectors and the exact
  37-cycle latency), the 31 independently-generated INTT vectors (checked
  against the 61-cycle latency and the Python reference), 16 round-trip
  vectors, operation-mode stability while busy, start-pulse-while-busy
  immunity, and reset recovery mid-normalization-phase — **326 checks, 0
  failures**.

A deliberate testbench bug was found and fixed during this work: the
initial `run_transform` task checked `done` immediately after a clock edge
without the settling delay this project's other testbenches consistently
use, and separately, `cycle_count` was never explicitly initialized,
leaving it `X` at simulation start. Both were root-caused by tracing a
minimal single-call reproduction rather than guessing, fixed, and
re-verified; this did not require any RTL change.

**Evaluation.**

| Metric | Baseline (forward only) | INTT-capable |
|---|---:|---:|
| Forward latency | 37 busy cycles | 37 busy cycles (unchanged) |
| Inverse latency | N/A | 61 busy cycles (1 `LOAD` + 36 butterfly + 24 normalization) |
| New FSM states | — | 0 (reuses `READ`/`COMPUTE`/`WRITE`) |
| New registers | — | `mode_reg` (1 bit), `phase` (1 bit), `nidx` (3 bits) |
| Synthesized cells (generic, Yosys) | 603 | 673 (+70, +11.6%) |
| Synthesized flip-flops | 80 | 85 (+5, exactly matching the new register bits above) |
| `coefficient_memory` cells | 242 | 242 (+0, confirmed unmodified) |
| LUT / FF / BRAM (target-mapped) | Not measured | Not measured |
| Critical-path delay / max frequency | Not measured | Not measured |

No FPGA place-and-route or static-timing tool is available in this
environment (checked directly: no `nextpnr-ice40`, `nextpnr-ecp5`, `sta`,
or `opensta`), so only generic, technology-independent Yosys synthesis
statistics are reported; see
[`reports/synthesis_methodology.md`](reports/synthesis_methodology.md) for
the full methodology, exact commands, and raw reports. These are not FPGA
resource counts and no timing claim is made.

**Reproduction.**

```bash
cd ntt_accelerator

# Independent Python validation
cd experiments/intt/reference
python3 intt_reference_model.py        # (re)generates test_vectors/
python3 intt_math_validation.py

# RTL verification (just this experiment)
cd ../../..
bash experiments/intt/scripts/run_intt_tests.sh

# Baseline + this experiment together
bash scripts/run_all_experiments.sh

# Waveform capture and screenshots
iverilog -g2001 -Wall -o /tmp/intt_dump.vvp \
    rtl/modular_arithmetic.v rtl/butterfly_datapath.v rtl/coefficient_memory.v \
    experiments/intt/rtl/twiddle_rom.v experiments/intt/rtl/ntt_controller.v experiments/intt/rtl/ntt_top.v \
    experiments/intt/waves/dump_intt_waveforms.v
vvp /tmp/intt_dump.vvp
python3 experiments/intt/waves/render_intt_waveforms.py

# Synthesis (generic Yosys statistics; see reports/synthesis_methodology.md)
cd reports/baseline && yosys -s synth.ys
cd ../intt && yosys -s synth.ys
```

**Waveform evidence.** Captured the same way as the baseline waveforms
(real simulation, VCD parsed and rendered to SVG/PNG, no hand-drawn
diagrams): a round trip through the worked-example vector
(`x=[1,2,3,4,5,6,7,8]`, forward then inverse), and a zoom into the
normalization phase.

![INTT round-trip execution](experiments/intt/docs/images/intt-complete-execution.png)

This shows `inv` asserted for the second (inverse) leg, `busy` staying high
for the longer 61-cycle duration, and `phase` rising partway through to
mark the start of normalization; `nidx` then counts 0 through 7.

![INTT normalization phase](experiments/intt/docs/images/intt-normalization-phase.png)

This shows the 8-location normalization pass: `state` cycling through
`READ`/`COMPUTE`/`WRITE` once per location (reusing the same states the
butterflies use), `tw_reg` fixed at 15 (`N⁻¹`) with `b_reg` fixed at 0, and
`write_enable` pulsing once per location.

**Results and comparison with baseline.** The baseline's forward-only
behavior is unchanged: the same 31 test vectors, the same 37-cycle latency,
the same 5363+3579 verification checks, all still passing (confirmed by
rerunning `scripts/run_all_tests.sh` after this experiment, with `rtl/`
untouched). The INTT extension adds a real, independently-verified inverse
transform at the cost of +70 generic synthesis cells (+11.6%) and exactly
5 new flip-flops, with zero new FSM states and zero duplicated arithmetic
hardware — the entire inverse capability is implemented as a different
twiddle-ROM table and 8 extra passes through the existing shared
butterfly datapath.
