# Gyatso Chess Engine

Gyatso is a modular chess engine written in Nim, designed with clean architecture and efficient memory management patterns.

## Project Structure

The codebase is organized into the following modules:

- **types.nim**: Core type definitions for chess entities (Square, Color, Piece, etc.)
- **bitboard.nim**: Bitboard representation and operations
- **utils.nim**: Utility functions and constants
- **move.nim**: Move representation and manipulation
- **position.nim**: Chess position representation and manipulation
- **zobrist.nim**: Zobrist hashing for positions
- **movegen.nim**: Move generation algorithms
- **evaluation.nim**: Position evaluation
- **search.nim**: Search algorithms (negamax, quiescence, etc.)
- **uci.nim**: UCI protocol implementation
- **Gyatso.nim**: Main entry point

## Features

- Bitboard-based board representation
- Efficient move generation
- Alpha-beta pruning with quiescence search
- Material and piece-square table evaluation
- UCI protocol support

## Building

To build Gyatso, you need to have Nim installed. Then run:

```
nim c -d:release src/Gyatso.nim
```

This will create an executable in the current directory.

## Usage

Gyatso implements the UCI (Universal Chess Interface) protocol, so it can be used with any UCI-compatible chess GUI like Arena, Cutechess, or Banksia.

## Development

Gyatso is designed with modularity in mind, making it easy to extend and improve. The codebase follows a clear separation of concerns, with each module responsible for a specific aspect of the chess engine.

## License

[Add your license information here]

## Acknowledgements

The project structure was inspired by the NALWALD chess engine.