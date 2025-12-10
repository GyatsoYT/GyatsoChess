import std/bitops
import coretypes

export bitops

type
  Bitboard* = uint64

func setBit*(bb: var Bitboard, sq: Square) {.inline.} =
  bb = bb or (1'u64 shl sq)

func clearBit*(bb: var Bitboard, sq: Square) {.inline.} =
  bb = bb and not (1'u64 shl sq)

func getBit*(bb: Bitboard, sq: Square): bool {.inline.} =
  (bb and (1'u64 shl sq)) != 0

func popBit*(bb: var Bitboard): Square {.inline.} =
  let sq = countTrailingZeroBits(bb)
  bb = bb and (bb - 1)
  return sq.Square

func countBits*(bb: Bitboard): int {.inline.} =
  countSetBits(bb)

func bitScanForward*(bb: Bitboard): int {.inline.} =
  countTrailingZeroBits(bb)
