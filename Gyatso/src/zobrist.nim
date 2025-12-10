import coretypes
import std/sysrand

type
  ZobristKey* = uint64

var
  zobristTable*: array[Piece, array[Square, ZobristKey]]
  zobristSideToMove*: ZobristKey
  zobristCastling*: array[16, ZobristKey]
  zobristEnPassant*: array[8, ZobristKey] # File 0-7

proc randomKey(): ZobristKey =
  var bytes: array[8, byte]
  if not urandom(bytes):
    raise newException(IOError, "Failed to generate random bytes")
  cast[ZobristKey](bytes)

proc initializeZobristKeys*() =
  for p in Piece:
    for s in 0..63:
      zobristTable[p][s.Square] = randomKey()

  zobristSideToMove = randomKey()

  for i in 0..15:
    zobristCastling[i] = randomKey()

  for f in 0..7:
    zobristEnPassant[f] = randomKey()
