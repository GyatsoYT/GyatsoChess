import coretypes

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
  ttMask*:       uint64 = 0
  ttGeneration*: uint8  = 0

func prefetch(p: pointer; rw: cint = 0; locality: cint = 3) {.importc: "__builtin_prefetch", nodecl, varargs, inline.}

proc prefetchTT*(key: uint64) {.inline.} =
  if ttTable != nil and ttMask != 0:
    prefetch(addr ttTable[key and ttMask], 0, 3)

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
           (uint64(ttPv.uint8)                shl 47) or
           (uint64(cast[uint16](eval))        shl 48)

func unpackData*(data: uint64, move: var Move, score: var int16,
                 depth: var int8, bound: var uint8, generation: var uint8,
                 eval: var int16, ttPv: var bool) {.inline.} =
  move       = Move(uint16(data and 0xFFFF'u64))
  score      = cast[int16](uint16((data shr 16) and 0xFFFF'u64))
  depth      = cast[int8](uint8((data shr 32) and 0xFF'u64))
  bound      = uint8((data shr 40) and 0x3'u64)
  generation = uint8((data shr 42) and GenMask)
  ttPv       = bool((data shr 47) and 0x1'u64)
  eval       = cast[int16](uint16(data shr 48))

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

proc probeTT*(key: uint64, ply: int, move: var Move, score: var int,
              depth: var int, bound: var uint8, eval: var int16,
              ttPv: var bool): bool =
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
      var e: int16
      var p: bool
      unpackData(dataVal, m, s, d, b, g, e, p)

      move  = m
      depth = int(d)
      bound = b
      eval  = e
      ttPv  = p

      var finalScore = int(s)
      if finalScore > MateThreshold:
        finalScore = finalScore - ply
      elif finalScore < -MateThreshold:
        finalScore = finalScore + ply
      score = finalScore
      return true

  return false

proc storeTT*(key: uint64, move: Move, score: int16, depth: int8,
              bound: uint8, ply: int, eval: int16, ttPv: bool = false) =
  if ttTable == nil or ttMask == 0: return

  let cluster = addr ttTable[key and ttMask]

  var storedScore = score
  if score > MateThreshold:
    storedScore = score + int16(ply)
  elif score < -MateThreshold:
    storedScore = score - int16(ply)

  var finalTtPv = ttPv
  for i in 0 ..< EntriesPerCluster:
    if (cluster.entries[i].key xor cluster.entries[i].data) == key:
      var em: Move; var es: int16; var ed: int8
      var eb, eg: uint8; var ee: int16; var ep: bool
      unpackData(cluster.entries[i].data, em, es, ed, eb, eg, ee, ep)
      finalTtPv = finalTtPv or ep
      break

  let dataVal = packData(move, storedScore, depth, bound, ttGeneration, eval, finalTtPv)

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

    var eg: uint8
    var em: Move
    var es: int16
    var ed: int8
    var eb: uint8
    var ee: int16
    var ep: bool
    unpackData(entryData, em, es, ed, eb, eg, ee, ep)

    let relativeAge  = int((32'u16 + uint16(ttGeneration) - uint16(eg)) and 31'u16)
    let replaceScore = int(ed) - relativeAge * 2

    if replaceScore < minScore:
      minScore = replaceScore
      target = i

  cluster.entries[target].data = dataVal
  cluster.entries[target].key  = key xor dataVal
