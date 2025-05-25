import coretypes # For Square type
from std/bitops import countTrailingZeroBits, popcount

type
  Bitboard* = uint64

proc setBit*(bb: var Bitboard, sq: Square) {.inline.} =
  bb = bb or (1'u64 shl int(sq))

proc clearBit*(bb: var Bitboard, sq: Square) {.inline.} =
  bb = bb and not (1'u64 shl int(sq))

proc getBit*(bb: Bitboard, sq: Square): bool {.inline.} =
  (bb and (1'u64 shl int(sq))) != 0'u64

proc popBit*(bb: var Bitboard): Square {.inline.} =
  assert(bb != 0'u64, "popBit called on empty bitboard")
  let sqVal = countTrailingZeroBits(bb)
  bb = bb and (bb - 1'u64) # Clears the LSB
  return Square(sqVal)

proc countBits*(bb: Bitboard): int {.inline.} =
  return popcount(bb) 