<div align="center">
  <h1>Gyatso Chess Engine</h1>
  <i><h4>A decent, open-source chess engine written in Nim</h4></i>

  [![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](https://www.gnu.org/licenses/gpl-3.0)
  [![Language: Nim](https://img.shields.io/badge/Language-Nim-yellow.svg)](https://nim-lang.org/)
  [![UCI Compatible](https://img.shields.io/badge/Protocol-UCI-green.svg)](https://www.chessprogramming.org/UCI)

  Play against Gyatso on Lichess → [**GyatsoBot**](https://lichess.org/@/GyatsoBot)
</div>

---

Gyatso is a high-performance chess engine compatible with the Universal Chess Interface (UCI). Written in [Nim](https://nim-lang.org/), it combines modern search techniques with a neural-network evaluation (NNUE) to deliver a strong playing experience.

---

## Strength & Ratings

> Ratings marked **Estimated** are interpolated from SPRT test data and may not reflect official lists yet.

| Version | CCRL 40/15 | CCRL Blitz (2'+1") |
| :--- | :---: | :---: |
| **v1.0** | 2094 | — |
| **v1.1** | 2537 | 2406 |
| **v1.2** | 2651 | — |
| **v1.3** | 3054 | 3052 |
| **v1.4** | 3212 | 3251 |
| **v1.5** | ~3360 *(Est.)* | ~3347 *(Est.)* |

---

## Features

### Search

- **Iterative Deepening** with **Principal Variation Search (PVS)**
- **Aspiration Windows** — adaptive window widening on fail-low/fail-high
- **Quiescence Search** — captures-only search to resolve tactical noise
- **Transposition Table** — 3-entry clustered design with Zobrist hashing, generation aging, and TT prefetching

#### Pruning & Reductions
- **Null Move Pruning (NMP)** — adaptive reduction `R = 2 + depth/4`, with verification at high depths
- **Reverse Futility Pruning (RFP)** — linear + quadratic margin; improvement-aware
- **Futility Pruning** — quiet move pruning near the horizon
- **Late Move Reductions (LMR)** — logarithmic table with history-based adjustments, improving flag, cut-node bonus, and SMP jitter
- **Late Move Pruning (LMP)** — depth-scaled quiet move count threshold
- **SEE Quiet Pruning** — skip quiet moves with a negative static exchange evaluation
- **Internal Iterative Reduction (IIR)** — reduce depth when no TT move is available

#### Extensions
- **Check Extensions** — extend search by 1 ply when a move gives check

#### Draw Detection
- **Threefold Repetition** detection
- **Fifty-Move Rule** detection

### Move Ordering

Moves are scored and tried in this order for maximum cutoffs:

1. **TT Move** — hash move from the transposition table
2. **Good Captures** — SEE-positive captures scored by MVV-LVA
3. **Killer Moves** — 2 quiet moves that caused cutoffs at the same ply
4. **Quiet Moves** — ordered by combined history score:
   - **Threat-Aware Main History** — `[side][from][to][fromAttacked][toAttacked]`
   - **1-ply Continuation History** (counter-move heuristic)
   - **2-ply Continuation History** (follow-up move heuristic)
5. **Bad Captures** — SEE-negative captures tried last

History tables use **gravity-based aging** and are scaled per-move with bonus/malus on cutoff/fail.

### Evaluation — NNUE

> **HCE (Hand-Crafted Evaluation) has been deprecated** as of v1.5.0.
> HCE was the evaluation backbone up through **v1.4.0** and can still be found in those older releases.
> Starting with **v1.5.0**, Gyatso uses **NNUE exclusively**.
> HCE may return in a future version, but is not a current priority.

Gyatso uses a custom-trained **NNUE** (Efficiently Updatable Neural Network) for evaluation:

- **Architecture:** `768 → 512HM` (Horizontally Mirrored)
  - Input: 768 features (piece × color × square)
  - Hidden Layer: 512 neurons, one accumulator per side (white / black)
  - Output: single scalar centipawn score
- **Activation:** SCReLU (Squared Clipped ReLU — `clamp(x, 0, QA)² × weight`)
- **Incremental Updates:** accumulator is updated incrementally on each move (add/sub/addSub patterns)
- **Lazy Refresh:** full accumulator recompute only when the king crosses the horizontal mirror boundary (file 3↔4 threshold)
- **SIMD Acceleration:** AVX2, AVX-512, and NEON code paths for vectorized accumulator math
- **Embedded Network:** the `.bin` file (`GyatsoNet512HM.bin`) is compiled directly into the binary — no external files needed at runtime
- **Training:** network trained with [Bullet](https://github.com/jw1912/bullet) on self-generated data

### Performance

- **Magic Bitboards** — fast sliding piece attack generation (bishops, rooks, queens)
- **Lazy SMP (Multi-threading)** — parallel search across all available CPU cores with per-thread history, randomized LMR jitter to avoid search collapse, and vote-based best-thread selection
- **Profile-Guided Optimization (PGO)** — 5-stage build pipeline (instrument → perft workload → bench → timed search → merge → optimized build) for maximum CPU-specific performance
- **SIMD** — vectorized NNUE operations (AVX2/AVX-512/NEON selectable at compile time)
- **TT Prefetch** — cache-line prefetch of TT entries before recursive calls
- **Bestmove Stability** — time management reduces soft limit when the best move has been stable across iterations

### Technology

- **Language:** [Nim](https://nim-lang.org/) — C-like performance with high-level syntax
- **Protocol:** Fully UCI compatible
- **UCI Options:**
  - `Hash` — transposition table size in MB (default 16, max 65536)
  - `Threads` — number of search threads (default 1, max 512)

---

## Download

### Pre-built Binaries

The easiest way to get started. Download the correct binary for your system from the [**Releases page**](https://github.com/GyatsoYT/GyatsoChess/releases).

See **[Which Binary Should I Use?](#-which-binary-should-i-use)** below to pick the right file.

### Build From Source

```bash
git clone https://github.com/GyatsoYT/GyatsoChess.git
cd GyatsoChess
```

---

## Which Binary Should I Use?

Gyatso is distributed in several variants optimized for different CPU instruction sets.

| Binary Suffix | Who Should Use It |
| :--- | :--- |
| `avx512` | Intel Ice Lake / Skylake-X or AMD Zen 4+ (AVX-512 NNUE + BMI2 PEXT/PDEP) |
| `bmi2` | Intel Haswell+ / AMD Zen 3+ (AVX2 NNUE + hardware PEXT/PDEP bitboards) — **recommended for modern x86-64** |
| `avx2` | AMD Zen 1 / Zen 2 or CPUs without fast hardware PEXT (AVX2 NNUE + Magic Bitboards) |
| `x86-64` | Older CPUs without AVX2, or for maximum compatibility |
| `native` | Self-compiled from source; auto-detects and optimizes for **your specific CPU** |

**Not sure?**
- On **Windows**: Open Task Manager → Performance → CPU → check your CPU name on [ark.intel.com](https://ark.intel.com) or [AMD Product Specs](https://www.amd.com/en/products/specifications/processors).
- On **Linux**: Run `lscpu | grep -i 'avx\|bmi2'` to check flags (`avx2`, `bmi2`). Note that AMD Zen 1 & Zen 2 support BMI2 in software emulation so `avx2` (Magic bitboards) is faster on those CPUs.

> ⚠️ Running an AVX-512 or BMI2 binary on an unsupported CPU will crash immediately. When in doubt, use `avx2`.

---

## Compilation

### Prerequisites

Make sure the following tools are installed and on your `PATH`:

1. [**Nim compiler**](https://nim-lang.org/install.html) — the language runtime
2. **Clang** — required C backend for performance and PGO builds
3. **LLD** — LLVM linker (part of the LLVM suite)
4. **llvm-profdata** — for merging PGO profile data (PGO builds only)
5. **nimsimd** — SIMD intrinsics library (auto-installed by build scripts)

---

### Option A: Makefile (Recommended for OpenBench / CI)

The [`Makefile`](Makefile) is the primary build target used by OpenBench.

```bash
# Standard AVX2 build
make

# Custom output name (required by OpenBench)
make EXE=Gyatso-ABCDEF12

# With a custom network file
make EXE=Gyatso-ABCDEF12 EVALFILE=/path/to/custom.bin

# Clean build artifacts
make clean
```

The Makefile defaults to AVX2 + BMI2 + SIMD. Adjust `ARCH_DEFS` in the Makefile for other targets.

---

### Option B: Interactive Script (Recommended for Local Use)

**Windows — `compile.bat`**
```cmd
compile.bat
```
- **Option 1:** Normal build (fast compile, good performance)
- **Option 2:** PGO build (slow compile, maximum performance — recommended for regular use)

Then choose your SIMD level: Default / AVX2 / AVX-512 / NEON.

**Linux / macOS — `compile.sh`**
```bash
chmod +x compile.sh
./compile.sh
```
Same menu as the Windows script.

---


## Roadmap

The following features are planned or under consideration for future versions:

- [ ] **Syzygy Tablebases** — perfect play in known endgame positions
- [ ] **Multi-PV** — display multiple principal variations during analysis
- [ ] **Chess960 / FRC** — Fischer Random Chess support
- [ ] **Singular Extensions** — extend the PV move when it is uniquely best
- [ ] **Mate Distance Pruning** — prune branches that cannot improve on a known mate
- [ ] **ProbCut** — probabilistic forward pruning for high-depth nodes
- [ ] **NNUE training improvements** — larger networks, more data, refined architecture
- [ ] **HCE restoration** — optional fallback for very constrained environments (no plans for v1.5.x)

---

## Contributing

Contributions are welcome! Whether you want to improve the engine, fix bugs, or donate CPU time for testing, see the full guide:

📖 **[CONTRIBUTING.md](CONTRIBUTING.md)**

### Quick Code Contribution Steps

1. **Fork** the repository
2. **Create a feature branch:** `git checkout -b feature/MyFeature`
3. **Commit your changes:** `git commit -m 'Add: brief description'`
4. **Push:** `git push origin feature/MyFeature`
5. **Open a Pull Request** with a clear description and bench numbers if applicable and also a locally performed SPRT Showing the gain of elo through the changes you made.

Please ensure your code follows the Nim style guide. Any search change should include `bench` output before and after.

---

## Special Thanks

- **[Heimdall Chess Engine](https://github.com/nocturn9x/heimdall)** — SIMD and NNUE integration reference
- **Nalwald & Tsoj** — guidance and support throughout development
- **[Bullet](https://github.com/jw1912/bullet)** — the NNUE training framework used for Gyatso's networks
- **Stockfish Dev Community** — for help with bugs and performance ideas
- **[Nabdevorg](https://github.com/nabdevdotorg), [Catto](https://github.com/harrowfung) & [Mrpineapple.org](https://github.com/PineappleChad)** — data generation assistance, Openbench Cpu donations, and much more.

---

## License

Gyatso is free software released under the **GNU General Public License v3**.
See [LICENSE](LICENSE) for full details.

This program is distributed without any warranty. See the GPL for details.