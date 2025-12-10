<div align="center">
<h1>Gyatso</h1>
<i><h4>A decent Chess engine written in Nim 🐉</h4></i>
</div>

Gyatso is a high-performance chess engine compatible with the Universal Chess Interface (UCI). Written in Nim, it combines modern programming paradigms with classical chess programming techniques to deliver a strong playing experience.

## Features

### Search
- **Principal Variation Search (PVS)**: Efficiently explores the game tree.
- **Transposition Table**: Caches search results to avoid re-searching identical positions.
- **Quiescence Search**: Checks handling to resolve tactical lines at the horizon.
- **Advanced Pruning**:
  - Null Move Pruning
  - Late Move Reduction (LMR)
  - Futility Pruning
  - Delta Pruning
- **Selectivity**:
  - Static Exchange Evaluation (SEE) for move ordering and pruning.
  - Killermoves and History Heuristics.

### Evaluation
- **Hand-Crafted Evaluation (HCE)**: Tuned evaluation terms for material, piece-square tables, pawn structure, and piece mobility.
- **Efficient Bitboards**: Uses Magic Bitboards for sliding piece attacks.

### Technology
- **Language**: Written in [Nim](https://nim-lang.org/), offering C-like speed with Python-like syntax.
- **Protocol**: Fully UCI compatible, works with Arena, BanksiaGUI, Cute Chess, etc.(Tested only with Cute Chess)

## Download

You can clone the repository to build from source:

```bash
```bash
git clone https://github.com/GyatsoYT/GyatsoChess.git
cd GyatsoChess
```


**Note:** You can find prebuilt binaries for Windows in the [Releases](https://github.com/GyatsoYT/GyatsoChess/releases) section.

## Compilation

You need the [Nim compiler](https://nim-lang.org/install.html) installed on your system.

### Easy Compilation (Recommended)

**Windows**
Double-click `compile.bat` or run:
```cmd
compile.bat
```

**Linux / macOS**
Run the shell script:
```bash
./compile.sh
```

### Manual Compilation
For maximum performance (native architecture):
```bash
nim c -d:danger --passC:-march=native -o:Gyatso src/main.nim
```

For a portable build (runs on most modern CPUs):
```bash
nim c -d:release -o:Gyatso src/main.nim
```

## Usage

### UCI Protocol
Gyatso determines its mode based on input. Connect it to any UCI-compatible GUI.

### Lichess Bot
Gyatso is live on Lichess! You can play against it here: [https://lichess.org/@/GyatsoBot](https://lichess.org/@/GyatsoBot)

To run your own bot instance, use [lichess-bot](https://github.com/ShailChoksi/lichess-bot).

## Future Implementation / Roadmap

We are constantly working to improve Gyatso. Here are some planned features:
- [ ] **NNUE Support**: Implement Efficiently Updatable Neural Networks for state-of-the-art evaluation.
- [ ] **Syzygy Tablebases**: Support for endgame tablebases to play perfectly in known endgames.
- [ ] **ProbCut**: Add probabilistic cut pruning for additional search efficiency.
- [ ] **Advanced Time Management**: Implement stability-based time allocation and dynamic time scaling.
- [ ] **History Extensions**: Extend search for moves with high history scores.
- [ ] **Multi-PV Support**: Display multiple principal variations during search.
- [ ] **Chess960/FRC**: Full Fischer Random Chess support.
- [ ] **Automated Tuning**: SPRT framework for search parameter tuning.


## Contributing

Contributions are welcome! Whether it's code improvements, bug fixes, or documentation updates.

1. **Fork the repository**.
2. **Create a feature branch**: `git checkout -b feature/MyNewFeature`
3. **Commit your changes**: `git commit -m 'Add some feature'`
4. **Push to the branch**: `git push origin feature/MyNewFeature`
5. **Open a Pull Request**.

Please ensure your code follows the Nim style guide and passes existing tests.

## License

Gyatso is free software: you can redistribute it and/or modify it under the terms of the **GNU General Public License as published by the Free Software Foundation, either version 3 of the License**, or (at your option) any later version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.