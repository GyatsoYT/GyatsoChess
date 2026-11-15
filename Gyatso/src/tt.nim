import coretypes
import hugepage
export hugepage.hugePagesActive

const
  BoundExact* = 0'u8
  BoundAlpha* = 1'u8
  BoundBeta*  = 2'u8

  EntriesPerCluster* = 3

  NoEval* = 32767'i16

type
  TTEntry* = object
    key*: uint64
    data*: uint64

  TTCluster* = object
    entries*: array[EntriesPerCluster, TTEntry]

var
  ttTable*:      ptr UncheckedArray[TTCluster] = nil
  ttClusters*:   uint64 = 0
  ttGeneration*: uint8  = 0
  ttBytes:       int  = 0
  ttFromOs:      bool = false

func prefetch(p: pointer; rw: cint = 0; locality: cint = 3) {.importc: "__builtin_prefetch", nodecl, varargs, inline.}

## High 64 bits of the 128-bit product a * b.
func mulHi64(a, b: uint64): uint64 {.inline.} =
  when defined(gcc) or defined(clang):
    var r: uint64
    {.emit: "`r` = (NU64)(((unsigned __int128)`a` * (unsigned __int128)`b`) >> 64);".}
    return r
  else:
    let
      aLo = a and 0xFFFFFFFF'u64
      aHi = a shr 32
      bLo = b and 0xFFFFFFFF'u64
      bHi = b shr 32
      ll = aLo * bLo
      lh = aLo * bHi
      hl = aHi * bLo
      hh = aHi * bHi
      mid = (ll shr 32) + (lh and 0xFFFFFFFF'u64) + (hl and 0xFFFFFFFF'u64)
    return hh + (lh shr 32) + (hl shr 32) + (mid shr 32)

## Maps a key to a cluster index in [0, ttClusters) for any cluster count.
proc ttIndex(key: uint64): uint64 {.inline.} =
  mulHi64(key, ttClusters)

proc prefetchTT*(key: uint64) {.inline.} =
  if ttTable != nil:
    prefetch(addr ttTable[ttIndex(key)], 0, 3)

proc newTTGeneration*() {.inline.} =
  inc ttGeneration

const GenMask* = 0x1F'u8

func packData*(move: Move, score: int16, depth: int8, bound: uint8,
               generation: uint8, eval: int16, ttPv: bool): uint64 {.inline.} =
  result = (uint64(uint16(move))              shl  0) or
           (uint64(cast[uint16](score))       shl 16) or
           (uint64(cast[uint8](depth))        shl 32) or
           (uint64(bound and 0x3'u8)          shl 40) or
           (uint64(generation and GenMask)    shl 42) or
           (uint64(uint8(ttPv))               shl 47) or
           (uint64(cast[uint16](eval))        shl 48)

func unpackData*(data: uint64, move: var Move, score: var int16,
                 depth: var int8, bound: var uint8, generation: var uint8,
                 eval: var int16, ttPv: var bool) {.inline.} =
  move       = Move(uint16(data and 0xFFFF'u64))
  score      = cast[int16](uint16((data shr 16) and 0xFFFF'u64))
  depth      = cast[int8](uint8((data shr 32) and 0xFF'u64))
  bound      = uint8((data shr 40) and 0x3'u64)
  generation = uint8((data shr 42) and 0x1F'u64)
  ttPv       = bool((data shr 47) and 0x1'u64)
  eval       = cast[int16](uint16(data shr 48))

proc freeTT*() =
  if ttTable != nil:
    if ttFromOs: osFree(ttTable, ttBytes)
    else: deallocShared(ttTable)
    ttTable = nil
  ttBytes = 0
  ttFromOs = false

proc initTT*(sizeMB: int) =
  freeTT()

  if sizeMB <= 0:
    ttClusters = 0
    return

  let clusterSize = uint64(sizeof(TTCluster))
  let bytes = uint64(sizeMB) * 1024'u64 * 1024'u64

  var numClusters = bytes div clusterSize
  if numClusters == 0: numClusters = 1

  ttClusters = numClusters
  ttBytes = int(numClusters * clusterSize)

  # OS huge pages first
  let mem = osAlloc(ttBytes)
  if mem != nil:
    ttTable = cast[ptr UncheckedArray[TTCluster]](mem)
    ttFromOs = true
  else:
    ttTable = cast[ptr UncheckedArray[TTCluster]](allocShared0(ttBytes))
    ttFromOs = false
    hugePagesActive = false

proc clearTT*() =
  if ttTable != nil:
    zeroMem(ttTable, ttBytes)

proc probeTT*(key: uint64, ply: int, move: var Move, score: var int,
              depth: var int, bound: var uint8, eval: var int16,
              ttPv: var bool): bool {.inline.} =
  if ttTable == nil or ttClusters == 0: return false

  let cluster = addr ttTable[ttIndex(key)]

  for i in 0 ..< EntriesPerCluster:
    let dataVal = cluster.entries[i].data
    let keyVal  = cluster.entries[i].key

    if (keyVal xor dataVal) == key:
      var m: Move
      var s: int16
      var d: int8
      var b: uint8
      var g: uint8
      var e: int16
      var tp: bool
      unpackData(dataVal, m, s, d, b, g, e, tp)

      move = m
      depth = int(d)
      bound = b
      eval = e
      ttPv = tp

      var finalScore = int(s)
      if finalScore > MateThreshold:
        finalScore = finalScore - ply
      elif finalScore < -MateThreshold:
        finalScore = finalScore + ply
      score = finalScore
      return true

  return false

proc storeTT*(key: uint64, move: Move, score: int16, depth: int8,
              bound: uint8, ply: int, eval: int16, ttPv: bool) =
  if ttTable == nil or ttClusters == 0: return

  let cluster = addr ttTable[ttIndex(key)]

  var storedScore = score
  if score > MateThreshold:
    storedScore = score + int16(ply)
  elif score < -MateThreshold:
    storedScore = score - int16(ply)

  let dataVal = packData(move, storedScore, depth, bound, ttGeneration, eval, ttPv)

  # Replacement policy: always reuse a matching key slot; otherwise replace
  # the entry with the lowest score = depth - relativeAge * 2, where
  # relativeAge = (32 + ttGeneration - entry.generation) mod 32.
  var target   = 0
  var minScore = high(int)

  for i in 0 ..< EntriesPerCluster:
    let entryData = cluster.entries[i].data
    let entryKey  = cluster.entries[i].key

    if (entryKey xor entryData) == key:
      target = i
      break

    let ed = system.int(cast[int8](uint8((entryData shr 32) and 0xFF'u64)))
    let eg = uint8((entryData shr 42) and 0x1F'u64)

    let relativeAge  = int((32'u16 + uint16(ttGeneration) - uint16(eg)) and 31'u16)
    let replaceScore = ed - relativeAge * 2

    if replaceScore < minScore:
      minScore = replaceScore
      target = i

  cluster.entries[target].data = dataVal
  cluster.entries[target].key  = key xor dataVal
