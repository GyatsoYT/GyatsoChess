import std/bitops
import coretypes

type
  Bitboard* = distinct uint64

func uint64*(bb: Bitboard): uint64 {.inline.} = cast[uint64](bb)

func int*(sq: Square): int {.inline.} = system.int(cast[int8](sq))

func `and`*(a, b: Bitboard): Bitboard {.borrow, inline.}

func `or`*(a, b: Bitboard): Bitboard {.borrow, inline.}

func `xor`*(a, b: Bitboard): Bitboard {.borrow, inline.}

func `not`*(a: Bitboard): Bitboard {.borrow, inline.}

func `shl`*(a: Bitboard, b: int): Bitboard {.borrow, inline.}

func `shr`*(a: Bitboard, b: int): Bitboard {.borrow, inline.}

func `+`*(a, b: Bitboard): Bitboard {.borrow, inline.}

func `-`*(a, b: Bitboard): Bitboard {.borrow, inline.}

func `*`*(a, b: Bitboard): Bitboard {.borrow, inline.}

func `==`*(a, b: Bitboard): bool {.borrow, inline.}

func `!=`*(a, b: Bitboard): bool {.inline.} = not (a == b)

func isEmpty*(bb: Bitboard): bool {.inline.} =
  bb == Bitboard(0)

func moreThanOne*(bb: Bitboard): bool {.inline.} =
  (bb and (bb - Bitboard(1))) != Bitboard(0)

func popcount*(bb: Bitboard): int {.inline.} =
  countSetBits(bb.uint64)

func lsb*(bb: Bitboard): Square {.inline.} =
  Square(countTrailingZeroBits(bb.uint64))

func msb*(bb: Bitboard): Square {.inline.} =
  Square(63 - countLeadingZeroBits(bb.uint64))

func poplsb*(bb: var Bitboard): Square {.inline.} =
  result = bb.lsb()
  bb = bb and (bb - Bitboard(1))

func bit*(sq: Square): Bitboard {.inline.} =
  Bitboard(1'u64 shl sq.int)

func hasSq*(bb: Bitboard, sq: Square): bool {.inline.} =
  (bb and sq.bit) != Bitboard(0)

iterator items*(bb: Bitboard): Square {.inline.} =
  var b = bb
  while not b.isEmpty():
    yield poplsb(b)

# File and Rank masks
func fileMask*(f: int): Bitboard {.inline.} =
  Bitboard(0x0101010101010101'u64 shl f)

func rankMask*(r: int): Bitboard {.inline.} =
  Bitboard(0xFF'u64 shl (r * 8))

const
  FileA* = fileMask(0)
  FileH* = fileMask(7)
  Rank1* = rankMask(0)
  Rank8* = rankMask(7)
  Rank2* = rankMask(1)
  Rank7* = rankMask(6)
  AllSquares* = Bitboard(0xFFFFFFFFFFFFFFFF'u64)

func toSquare*(bb: Bitboard): Square {.inline.} =
  bb.lsb()

func pretty*(bb: Bitboard): string =
  result = ""
  for r in countdown(7, 0):
    for f in 0..7:
      let sq = makeSquare(r, f)
      if bb.hasSq(sq):
        result.add("1")
      else:
        result.add(".")
      if f < 7:
        result.add(" ")
    if r > 0:
      result.add("\n")

