<div align="center">
<h1>Gyatso</h1>
<i><h4>A decent Chess engine written in Nim 🐉</h4></i>
</div>

Gyatso is a high-performance chess engine compatible with the Universal Chess Interface (UCI). Written in Nim, it combines modern programming paradigms with classical chess programming techniques to deliver a strong playing experience.

## Strength & Ratings

| Version | Rating (CCRL 40/15*) |
| :--- | :--- |
| **v1.0** | **2095** |
| **v1.1** | **2555** |
| **v1.2** | **~2654**|
| **v1.3** | **~3100** (Estimated) |

## Features

### Search
- **Principal Variation Search (PVS)**: Advanced alpha-beta search with aspiration windows.
- **Transposition Table**: Efficient caching with Zobrist hashing.
- **Selectivity & Pruning**:
  - **Null Move Pruning**: Adaptive reduction based on depth.
  - **ProbCut**: Probabilistic cut pruning for tactical stability.
  - **Multi-Cut Pruning**: Prunes branches where multiple moves fail high.
  - **Late Move Reduction (LMR)**: Logarithmic reduction for quiet moves.
  - **Singular Extensions**: Extends the search for forced moves (Single & Double extensions).
  - **Reverse Futility Pruning (RFP)**: Static null move pruning.
  - **Futility & Delta Pruning**: Prunes moves that can't improve alpha.
  - **Internal Iterative Reduction (IIR)**: Reduces depth when no TT move is found.
  - **Check Extensions**: Extends search depth when playing checking moves.
  - **Mate Distance Pruning**: Eliminates paths that cannot find a faster mate.
- **Move Ordering**:
  - **Killer Moves**: Prioritizes moves that caused cutoffs at the same ply.
  - **History Heuristics**: Main, Counter, Follow-up, and Tactical history tables.
  - **Static Exchange Evaluation (SEE)**: Filters bad captures.

### Evaluation
- **Hand-Crafted Evaluation (HCE)**: A sophisticated evaluation function featuring:
  - **Tapered Interpolation**: Smooth transition between Middlegame and Endgame phases.
  - **Piece-Square Tables (PST)**: Tuned tables for granular piece placement.
  - **King Safety**: Complex safety analysis including attack units, zone control, and pawn shields.
  - **Pawn Structure**: Evaluates doubled, isolated, and passed pawns.
  - **Piece Mobility**: Bonus for safe available squares.
  - **Piece-Relative Evaluation**: contextual bonuses (e.g., Knight near own Rook, Bishop near enemy King).
  - **Mop-up Evaluation**: Efficient logic to force checkmate in winning endgames.

### Performance
- **Magic Bitboards**: Fast sliding piece attack generation.
- **PGO Support**: optimized build system using Profile Guided Optimization.

### Technology
- **Language**: Written in [Nim](https://nim-lang.org/), offering C-like speed with Python-like syntax.
- **Protocol**: Fully UCI compatible.

### Lichess Bot
Gyatso is live on Lichess! You can play against it here: [https://lichess.org/@/GyatsoBot](https://lichess.org/@/GyatsoBot)

## Download

You can clone the repository to build from source:

```bash
git clone https://github.com/GyatsoYT/GyatsoChess.git
cd GyatsoChess
```

**Note:** You can find prebuilt binaries for Windows in the [Releases](https://github.com/GyatsoYT/GyatsoChess/releases) section.

## Compilation

You need the following tools installed and in your PATH:
1.  [Nim compiler](https://nim-lang.org/install.html)
2.  **Clang** compiler (required for PGO builds)
3.  **LLD** linker (part of LLVM)
4.  **llvm-profdata** (for PGO profile merging)

### Easy Compilation (Recommended)

**Windows**
Double-click `compile.bat` or run it in a terminal.
- Select **Option 1** for a standard native build (Build Fast, Might not give best performance.).
- Select **Option 2** for a **PGO Build** (Slow Build Process, Highest Performance).
  - This automatically runs a benchmark workload to optimize the engine for your CPU.

```cmd
compile.bat
```

**Linux / macOS**
Run the shell script:
```bash
./compile.sh
```
Follow the interactive menu to select Normal or PGO build.



## Usage

### UCI Protocol
Gyatso determines its mode based on input. Connect it to any UCI-compatible GUI like Arena, BanksiaGUI, or Cutechess.

## Future Implementation / Roadmap

We are constantly working to improve Gyatso. Here are some planned features:
- [ ] **Syzygy Tablebases**: Support for endgame tablebases to play perfectly in known endgames.
- [ ] **Multi-PV Support**: Display multiple principal variations during search.
- [ ] **Chess960/FRC**: Full Fischer Random Chess support.

## Contributing

Contributions are welcome! Whether it's code improvements, bug fixes, or documentation updates.

1. **Fork the repository**.
2. **Create a feature branch**: `git checkout -b feature/MyNewFeature`
3. **Commit your changes**: `git commit -m 'Add some feature'`
4. **Push to the branch**: `git push origin feature/MyNewFeature`
5. **Open a Pull Request**.

Please ensure your code follows the Nim style guide and passes existing tests.


## Special Thanks

- **Heimdall Chess Engine** - For the Simd and NNUE Integration.
- **Nalwald and Tsoj** - For Helping me At each step.
- **Bullet** - Amzaing Tool for Training A Neural Network.
- **Stockfish Dev Community** - For Helping me With Bugs and Speedups in the code.
- **[Nabdevorg](https://github.com/nabdevdotorg) and [Mrpineapple.org](https://github.com/PineappleChad)** - For helping me with datagen.

## License

Gyatso is free software: you can redistribute it and/or modify it under the terms of the **GNU General Public License as published by the Free Software Foundation, either version 3 of the License**, or (at your option) any later version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.