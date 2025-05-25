import coretypes
import std/random
import std/os # For seeding random number generator
import std/hashes # For string hashing
import std/times # For epochTime


type
  ZobristKey* = uint64

var
  zobristTable*: array[Piece.low..Piece.high, array[Square.low..Square.high, ZobristKey]]
  zobristSideToMove*: ZobristKey # Key to XOR if it's Black's turn
  zobristCastling*: array[0..15, ZobristKey] # For all 16 combinations of castling rights
  zobristEnPassant*: array[0..7, ZobristKey] # For each possible en passant file (0-7 for a-h)

proc initializeZobristKeys*() =
  ## Initializes all Zobrist keys with random uint64 values.
  ## Should be called once at program startup.
  # Seed the global random number generator
  randomize(epochTime().int64 + hashes.hash(os.getAppFilename()).int64)

  # Initialize piece keys
  for pVal in Piece.low..Piece.high:
    if pVal == Piece.Empty: # No key for empty piece, or ensure its key is 0
      for sqVal in Square.low..Square.high:
        zobristTable[pVal][sqVal] = 0'u64
      continue
    for sqVal in Square.low..Square.high:
      zobristTable[pVal][sqVal] = rand(ZobristKey)
      while zobristTable[pVal][sqVal] == 0'u64: # Ensure keys are non-zero for XOR properties
        zobristTable[pVal][sqVal] = rand(ZobristKey)


  # Initialize side to move key
  zobristSideToMove = rand(ZobristKey)
  while zobristSideToMove == 0'u64:
    zobristSideToMove = rand(ZobristKey)

  # Initialize castling keys (0-15 for castling rights combinations)
  for i in 0..15:
    zobristCastling[i] = rand(ZobristKey)
    while zobristCastling[i] == 0'u64:
      zobristCastling[i] = rand(ZobristKey)

  # Initialize en passant file keys (files a-h, so 0-7)
  for i in 0..7:
    zobristEnPassant[i] = rand(ZobristKey)
    while zobristEnPassant[i] == 0'u64:
      zobristEnPassant[i] = rand(ZobristKey)

# Automatically initialize keys when this module is imported
initializeZobristKeys() 