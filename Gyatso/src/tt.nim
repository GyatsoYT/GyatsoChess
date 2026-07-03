import coretypes

const
  BoundExact* = 0'u8
  BoundAlpha* = 1'u8
  BoundBeta*  = 2'u8

  EntriesPerCluster* = 3

type
  TTEntry* = object
    key*: uint64
    data*: uint64

  TTCluster* = object
    entries*: array[EntriesPerCluster, TTEntry]

var
  ttTable*:      ptr UncheckedArray[TTCluster] = nil
  ttMask*:       uint64 = 0
  ttGeneration*: uint8  = 0

func prefetch(p: pointer; rw: cint = 0; locality: cint = 3) {.importc: "__builtin_prefetch", nodecl, varargs, inline.}

proc prefetchTT*(key: uint64) {.inline.} =
  if ttTable != nil and ttMask != 0:
    prefetch(addr ttTable[key and ttMask], 0, 3)

proc newTTGeneration*() {.inline.} =
  inc ttGeneration

func packData*(move: Move, score: int16, depth: int8, bound: uint8, generation: uint8): uint64 {.inline.} =
  result = (uint64(uint16(move))        shl 0)  or
           (uint64(cast[uint16](score)) shl 16) or
           (uint64(cast[uint8](depth))  shl 32) or
           (uint64(bound and 0x3'u8)   shl 40) or
           (uint64(generation)          shl 42)

func unpackData*(data: uint64, move: var Move, score: var int16, depth: var int8, bound: var uint8, generation: var uint8) {.inline.} =
  move       = Move(uint16(data and 0xFFFF'u64))
  score      = cast[int16](uint16((data shr 16) and 0xFFFF'u64))
  depth      = cast[int8](uint8((data shr 32) and 0xFF'u64))
  bound      = uint8((data shr 40) and 0x3'u64)
  generation = uint8((data shr 42) and 0xFF'u64)

proc initTT*(sizeMB: int) =
  if ttTable != nil:
    deallocShared(ttTable)
    ttTable = nil

  if sizeMB <= 0:
    ttMask = 0
    return

  let clusterSize = sizeof(TTCluster)
  let bytes = sizeMB * 1024 * 1024

  var numClusters = 1'u64
  while numClusters * uint64(clusterSize) * 2'u64 <= uint64(bytes):
    numClusters = numClusters shl 1

  if numClusters == 0:
    numClusters = 1024

  ttMask = numClusters - 1
  ttTable = cast[ptr UncheckedArray[TTCluster]](allocShared0(numClusters * uint64(clusterSize)))

proc probeTT*(key: uint64, ply: int, move: var Move, score: var int, depth: var int, bound: var uint8): bool =
  if ttTable == nil or ttMask == 0: return false

  let cluster = addr ttTable[key and ttMask]

  for i in 0 ..< EntriesPerCluster:
    let dataVal = cluster.entries[i].data
    let keyVal  = cluster.entries[i].key

    if (keyVal xor dataVal) == key:
      var m: Move
      var s: int16
      var d: int8
      var b: uint8
      var g: uint8
      unpackData(dataVal, m, s, d, b, g)

      move  = m
      depth = int(d)
      bound = b

      var finalScore = int(s)
      if finalScore > MateThreshold:
        finalScore = finalScore - ply
      elif finalScore < -MateThreshold:
        finalScore = finalScore + ply
      score = finalScore
      return true

  return false

proc storeTT*(key: uint64, move: Move, score: int16, depth: int8, bound: uint8, ply: int) =
  if ttTable == nil or ttMask == 0: return

  let cluster = addr ttTable[key and ttMask]

  var storedScore = score
  if score > MateThreshold:
    storedScore = score + int16(ply)
  elif score < -MateThreshold:
    storedScore = score - int16(ply)

  let dataVal = packData(move, storedScore, depth, bound, ttGeneration)

  # Replacement policy: always reuse a matching key slot; otherwise replace
  # the entry with the lowest score = depth - relativeAge * 2, where
  # relativeAge = (256 + ttGeneration - entry.generation) mod 256.
  var target   = 0
  var minScore = high(int)

  for i in 0 ..< EntriesPerCluster:
    let entryData = cluster.entries[i].data
    let entryKey  = cluster.entries[i].key

    if (entryKey xor entryData) == key:
      target = i
      break

    var eg: uint8
    var em: Move
    var es: int16
    var ed: int8
    var eb: uint8
    unpackData(entryData, em, es, ed, eb, eg)

    let relativeAge  = int((256'u16 + uint16(ttGeneration) - uint16(eg)) and 255'u16)
    let replaceScore = int(ed) - relativeAge * 2

    if replaceScore < minScore:
      minScore = replaceScore
      target = i

  cluster.entries[target].data = dataVal
  cluster.entries[target].key  = key xor dataVal
