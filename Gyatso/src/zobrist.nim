import std/sysrand

type
  ZobristKey* = distinct uint64

func uint64*(k: ZobristKey): uint64 {.inline.} = cast[uint64](k)

func `xor`*(a, b: ZobristKey): ZobristKey {.inline.} = ZobristKey(a.uint64 xor b.uint64)
func `==`*(a, b: ZobristKey): bool {.inline.} = a.uint64 == b.uint64
func `$`*(a: ZobristKey): string {.inline.} = $(a.uint64)

var pieceKeys*:    array[12, array[64, ZobristKey]]  # [piece.ord][sq]
var sideKey*:      ZobristKey
var castlingKeys*: array[16, ZobristKey]
var epKeys*:       array[8, ZobristKey]              # indexed by file

proc initZobrist*() =
  for p in 0..11:
    for sq in 0..63:
      var bytes: array[8, byte]
      discard urandom(bytes)
      pieceKeys[p][sq] = ZobristKey(cast[uint64](bytes))
  
  var bytes: array[8, byte]
  discard urandom(bytes)
  sideKey = ZobristKey(cast[uint64](bytes))

  for i in 0..15:
    var bytes: array[8, byte]
    discard urandom(bytes)
    castlingKeys[i] = ZobristKey(cast[uint64](bytes))

  for f in 0..7:
    var bytes: array[8, byte]
    discard urandom(bytes)
    epKeys[f] = ZobristKey(cast[uint64](bytes))
