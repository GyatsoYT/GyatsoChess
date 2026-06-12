import coretypes, zobrist, move, board

func prefetch*(p: pointer; rw: cint = 0; locality: cint = 3)
    {.importc: "__builtin_prefetch", nodecl, varargs, inline.}

type
  TTEntryFlag* = enum
    InvalidEntry,
    ExactScore,
    LowerBound,
    UpperBound

  TTEntry* = object
    hash*:       uint16
    depth*:      int8
    generation*: uint8   # TT Ageing
    score*:      int16
    flag*:       TTEntryFlag
    wasPV*:      bool
    bestMove*:   Move
    rawEval*:    int16

const EntriesPerCluster* = 3

type
  TTCluster* = object
    entries*: array[EntriesPerCluster, TTEntry]

var ttGeneration*: uint8 = 0

proc newTTGeneration*() =
  ttGeneration.inc

var transpositionTable*: ptr UncheckedArray[TTCluster]
var ttSize*: int  # number of clusters

proc initTT*(sizeMB: int) =
  let numClusters = (sizeMB * 1024 * 1024) div sizeof(TTCluster)

  ttSize = numClusters
  if transpositionTable != nil:
    deallocShared(transpositionTable)

  transpositionTable = cast[ptr UncheckedArray[TTCluster]](
    allocShared0(sizeof(TTCluster) * ttSize))

func ttIndex(key: ZobristKey, size: int): int {.inline.} =
  let k = key.uint64
  let s = size.uint64
  let kHi = k shr 32
  let kLo = k and 0xFFFFFFFF'u64
  let sHi = s shr 32
  let sLo = s and 0xFFFFFFFF'u64
  let hi = kHi * sHi + ((kHi * sLo) shr 32) + ((kLo * sHi) shr 32)
  int(hi)

proc storeTT*(board: Board, depth: int, score: int, originalAlpha: int,
              originalBeta: int, bestMove: Move, rawEval: int = 0,
              wasPV: bool = false) {.gcsafe.} =
  let clusterIdx = ttIndex(board.currentZobristKey, ttSize)
  let cluster = addr transpositionTable[clusterIdx]

  var flag = ExactScore
  if score <= originalAlpha:
    flag = UpperBound
  elif score >= originalBeta:
    flag = LowerBound

  var adjustedScore = score
  const MateThreshold = MateValue - MaxPly

  if score > MateThreshold:
    adjustedScore = score + board.gamePly
  elif score < -MateThreshold:
    adjustedScore = score - board.gamePly

  var replaceIdx = 0
  var minValue = high(int)
  var found = false
  var emptyIdx = -1

  for i in 0 ..< EntriesPerCluster:
    let e = cluster.entries[i]
    if e.flag != InvalidEntry and e.hash == uint16(board.currentZobristKey):
      replaceIdx = i
      found = true
      break
    if e.flag == InvalidEntry and emptyIdx < 0:
      emptyIdx = i
    let relativeAge = (256 + ttGeneration.int - e.generation.int) and 255
    let value = e.depth.int - relativeAge * 2
    if value < minValue:
      minValue = value
      replaceIdx = i

  if not found and emptyIdx >= 0:
    replaceIdx = emptyIdx

  let existingEntry = cluster.entries[replaceIdx]
  # Preserve wasPV flag once set for same-key entries
  let preserveWasPV = found and
    existingEntry.hash == uint16(board.currentZobristKey) and
    existingEntry.wasPV

  cluster.entries[replaceIdx] = TTEntry(
    hash:       uint16(board.currentZobristKey),
    depth:      depth.int8,
    generation: ttGeneration,
    score:      adjustedScore.int16,
    flag:       flag,
    wasPV:      wasPV or preserveWasPV,
    bestMove:   bestMove,
    rawEval:    rawEval.int16
  )

proc probeTT*(zobristKey: ZobristKey, depth: int, alpha: var int, beta: var int,
              gamePly: int): (bool, int, Move, int16, bool) {.gcsafe.} =
  let clusterIdx = ttIndex(zobristKey, ttSize)
  let cluster = addr transpositionTable[clusterIdx]

  for i in 0 ..< EntriesPerCluster:
    let e = cluster.entries[i]
    if e.hash == uint16(zobristKey):
      if e.depth >= depth.int8:
        var score = e.score.int
        const MateThreshold = MateValue - MaxPly

        if score > MateThreshold: score = score - gamePly
        elif score < -MateThreshold: score = score + gamePly

        if score > MateValue:  score = MateValue
        elif score < -MateValue: score = -MateValue

        if e.flag == ExactScore:
          return (true, score, e.bestMove, e.rawEval, e.wasPV)
        elif e.flag == LowerBound:
          if score >= beta:
            return (true, score, e.bestMove, e.rawEval, e.wasPV)
          alpha = max(alpha, score)
        elif e.flag == UpperBound:
          beta = min(beta, score)
        if alpha >= beta:
          return (true, score, e.bestMove, e.rawEval, e.wasPV)

      return (false, 0, e.bestMove, e.rawEval, e.wasPV)

  return (false, 0, Move(0), 0'i16, false)

proc getTTEntry*(zobristKey: ZobristKey): tuple[hit: bool, entry: TTEntry] {.gcsafe.} =
  let clusterIdx = ttIndex(zobristKey, ttSize)
  let cluster = addr transpositionTable[clusterIdx]

  for i in 0 ..< EntriesPerCluster:
    let e = cluster.entries[i]
    if e.hash == uint16(zobristKey):
      return (true, e)

  return (false, TTEntry())

proc getHashfull*(): int =
  var count = 0
  let sampleClusters = min(1000, ttSize)
  let totalSampled = sampleClusters * EntriesPerCluster

  for i in 0 ..< sampleClusters:
    for j in 0 ..< EntriesPerCluster:
      let e = transpositionTable[i].entries[j]
      if e.flag != InvalidEntry and e.generation == ttGeneration:
        count.inc

  if totalSampled == 0: return 0
  return (count * 1000) div totalSampled

proc prefetchTT*(key: ZobristKey) {.inline.} =
  if transpositionTable != nil:
    prefetch(addr transpositionTable[ttIndex(key, ttSize)], 0, 3)

proc clearTT*() =
  if transpositionTable != nil:
    zeroMem(transpositionTable, sizeof(TTCluster) * ttSize)
