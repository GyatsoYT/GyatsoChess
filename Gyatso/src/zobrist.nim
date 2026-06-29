type
  ZobristKey* = distinct uint64

func uint64*(k: ZobristKey): uint64 {.inline.} = cast[uint64](k)
func `xor`*(a, b: ZobristKey): ZobristKey {.inline.} = ZobristKey(a.uint64 xor b.uint64)
func `==`*(a, b: ZobristKey): bool {.inline.} = a.uint64 == b.uint64
func `$`*(a: ZobristKey): string {.inline.} = $(a.uint64)

# Splitmix64 — fast, high quality, fully deterministic
func splitmix64(state: var uint64): uint64 {.inline.} =
  state += 0x9e3779b97f4a7c15'u64
  var z = state
  z = (z xor (z shr 30)) * 0xbf58476d1ce4e5b9'u64
  z = (z xor (z shr 27)) * 0x94d049bb133111eb'u64
  z xor (z shr 31)

type ZobristTable = object
  pieceKeys:    array[12, array[64, ZobristKey]]
  sideKey:      ZobristKey
  castlingKeys: array[16, ZobristKey]
  epKeys:       array[8, ZobristKey]

const ZT: ZobristTable = block:
  var state = 0xDEADBEEFCAFEBABE'u64
  var t: ZobristTable
  for p in 0..11:
    for sq in 0..63:
      t.pieceKeys[p][sq] = ZobristKey(splitmix64(state))
  t.sideKey = ZobristKey(splitmix64(state))
  for i in 0..15:
    t.castlingKeys[i] = ZobristKey(splitmix64(state))
  for f in 0..7:
    t.epKeys[f] = ZobristKey(splitmix64(state))
  t

template pieceKeys*: auto = ZT.pieceKeys
template sideKey*: auto = ZT.sideKey
template castlingKeys*: auto = ZT.castlingKeys
template epKeys*: auto = ZT.epKeys