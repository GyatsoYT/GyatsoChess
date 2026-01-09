import std/bitops
import coretypes

export bitops

type
  Bitboard* = uint64

template setBit*(bb: var Bitboard, sq: Square) =
  bb = bb or (1'u64 shl sq)

template clearBit*(bb: var Bitboard, sq: Square) =
  bb = bb and not (1'u64 shl sq)

template getBit*(bb: Bitboard, sq: Square): bool =
  (bb and (1'u64 shl sq)) != 0

template popBit*(bb: var Bitboard): Square =
  let sq = countTrailingZeroBits(bb)
  bb = bb and (bb - 1)
  sq.Square

template countBits*(bb: Bitboard): int =
  countSetBits(bb)

template bitScanForward*(bb: Bitboard): int =
  countTrailingZeroBits(bb)
