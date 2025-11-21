<div align="center">
<p><h1>Nalwald</h1>
<i><h4>Chess engine written in Nim ♜</h4></i>
<img src="res/logo.png" width="384px" style="border-radius: 20px;">
</h1>
</div>

Nalwald is a superhuman chess engine for classical and fischer random chess. It supports the Universal Chess Interface (UCI), so it can be used with most chess GUIs, such as Arena or Cute Chess. Nalwald is written in the programming language Nim, a modern compiled systems language.

### Download
```
git clone https://github.com/tsoj/Nalwald.git
```
Pre-compiled executables for Windows and Linux can be found [here](https://github.com/tsoj/Nalwald/releases).

### Compile

You need the [Nim](https://nim-lang.org/) compiler (version 2.1.1 or higher) and the [Clang](https://clang.llvm.org/) compiler.

**Prerequisites**
```bash
nimble install malebolgia@1.3.2
nimble install zippy@0.10.16
```

**Compiling for native CPU**
```bash
nim native Nalwald
```

**Compiling for generic CPUs**
```bash
nim default Nalwald
```

**Compiling for modern CPUs (BMI2 and POPCNT)**
```bash
nim modern Nalwald
```

### Features

- Evaluation:
  - Piece-relative piece square tables
  - 3x3 pawn structure tables
  - Piece combinations
  - Passed pawns
  - Tapered parameters
  - Optimized using gradient descent
- Search:
  - Principle variation search
  - Quiescence search
  - Transposition table
  - Move ordering:
    - Transposition table suggested best move
    - Static exchange evaluation
    - Killermoves
    - Relative and counter move history heuristic
  - Check extensions
  - Nullmove reduction
  - Late move reductions
  - Futility reductions
  - Hash result futility pruning
  - Delta pruning
  - Aspiration windows
  - Internal iterative reductions
- Multithreading support
- Supports Chess960/FRC
- Multi PV support
- UCI compatible

### About

I began writing chess programs pretty much immediately after my first "Hello world!" in 2016. My first big project was *jht-chess*, a chess playing program with a console GUI for Linux. I used C++ but it looked more like messy C. Looking back I would say that it's hard to write worse spaghetti code than I did then, but it played good enough chess to win against amateur players. Since then, I wrote numerous chess engines, most in C++ (*jht-chess*, *zebra-chess*, *jht-chess 2*, *squared-chess*, and *Googleplex Starthinker*) but also one in Rust (*Hactar*) and now in Nim as well. While my first chess engine could barely beat me (and I am not a very good chess player, and was much less so in 2016), today Nalwald would beat Magnus Carlsen almost every time.

On this journey from an at best mediocre chess program to a chess engine that can win against the best human players, the [chessprogramming.org](https://www.chessprogramming.org/Main_Page) wiki, the [talkchess.com](https://talkchess.com/forum3/index.php) forum, and the [Engine Programming Discord server](https://discord.com/invite/F6W6mMsTGN) have been a great source of information and motivation. At the beginning, the Wikipedia article "Schachprogramm" was really helpful, too.

Some noteworthy features of Nalwald:
- **Piece-relative PSTs** are piece square tables that are different depending on which square another piece is. They are added together for all pieces of all piece types.
- **Futility reductions** are an improvement to futility pruning. Here not only are moves skipped that are likely to be much worse than alpha. Additionally, moves that are likely slightly worse than alpha get their depth reduced accordingly to how bad they are expected to be.
- **3x3 pawn structure tables** are a way to evaluate the structure of multiple pawns. For this a 3x3 mask is used on any square for which at least two pawns (ours or enemy) fall into this mask. The pawns in that mask can be used to calculate an exact index for this structure of pawns in a 3x3 space. This index can be used to access a table, which contains values to evaluate this pawn structure. This table can then be optimized using a method like gradient descent.

### Rating

| Version | CCRL 40/40 | CCRL 40/4 | CCRL 40/2 FRC | Release Date |
| :------ | ---------: | --------: | ------------: | -----------: |
| **Nalwald**                                                     |
| 19      |       3306 |      3351 |        3438 |  July 11, 2024 |
| 18      |       3255 |      3286 |        3154 |   Aug 13, 2023 |
| 17.1    |       3188 |         – |           – |  June 20, 2023 |
| 17      |          – |      3201 |        3051 |   June 5, 2023 |
| 16      |       2974 |      3001 |        2995 |  July 11, 2022 |
| 15      |       2899 |      2913 |        2921 |    Feb 8, 2022 |
| 14      |       2840 |         – |        2821 |   Sep 16, 2021 |
| 1.12    |          – |         – |        2727 |    Aug 9, 2021 |
| 1.11    |          – |      2782 |           – |  July 22, 2021 |
| 1.10    |          – |         – |           – |   July 3, 2021 |
| 1.9     |       2594 |      2627 |           – |  June 15, 2021 |
| 1.8.1   |          – |      2496 |           – | April 29, 2021 |
| 1.8     |          – |      2416 |           – | April 25, 2021 |
| **Googleplex Starthinker**                                      |
| 1.6     |       2357 |      2347 |           – |   Aug 16, 2019 |
| 1.4     |       2279 |      2250 |           – |   Dec 11, 2018 |
| **Squared-Chess**                                               |
| 1.3.0   |       1979 |      2057 |           – |   Nov 24, 2018 |
| 1.2.0   |       1907 |      1850 |           – |   Sep 24, 2018 |
| 1.1.0   |          – |      1800 |           – |   Sep 20, 2018 |
| **Hactar**                                                      |
| 0.9.0   |          – |      1351 |           – |   Jan 13, 2018 |

### Other commands


**Generate training data**
```bash
nim genData --define:almostFullCPU --run Nalwald 6_000 50_000_000 false
```
**Create training data from PGNs**
```bash
nim dataFromPGNs --run Nalwald input1.pgn input2.pgn ... inputN.pgn
```

**Optimize evaluation parameters**
```bash
nim tuneEvalParams --run Nalwald
```

**Optimize search parameters using weather-factory**
```bash
# Requires fastchess to be in the PATH
# Values need to be updated manually in source code.
nim runWeatherFactory --run Nalwald
```

**Run SPRT test against the master branch**
```bash
# Requires fastchess to be in the PATH
nim sprt --run Nalwald
```

**Run bench test against commit**
```bash
nim bench --run Nalwald <branch, tag or commit hash>
```

**Run tests**
```bash
nim tests --run Nalwald
nim testsDanger --run Nalwald
```

### License

Nalwald © 2024 by Jost Triller is licensed under CC BY-NC-SA 4.0 <img style="height:22px!important;margin-left:3px;vertical-align:text-bottom;" src="https://mirrors.creativecommons.org/presskit/icons/cc.svg?ref=chooser-v1" alt=""><img style="height:22px!important;margin-left:3px;vertical-align:text-bottom;" src="https://mirrors.creativecommons.org/presskit/icons/by.svg?ref=chooser-v1" alt=""><img style="height:22px!important;margin-left:3px;vertical-align:text-bottom;" src="https://mirrors.creativecommons.org/presskit/icons/nc.svg?ref=chooser-v1" alt=""><img style="height:22px!important;margin-left:3px;vertical-align:text-bottom;" src="https://mirrors.creativecommons.org/presskit/icons/sa.svg?ref=chooser-v1" alt=""></a></p>
