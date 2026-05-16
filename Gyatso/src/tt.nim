import coretypes, zobrist, move, board

type
  TTEntryFlag* = enum
    InvalidEntry,
    ExactScore,
    LowerBound,
    UpperBound

  TTEntry* = object
    hash*: uint16
    depth*: int8
    generation*: uint8 # TT Ageing
    score*: int16
    flag*: TTEntryFlag
    bestMove*: Move
    rawEval*: int16

var ttGeneration*: uint8 = 0

proc newTTGeneration*() =
  ttGeneration.inc

var transpositionTable*: ptr UncheckedArray[TTEntry]
var ttSize*: int

proc initTT*(sizeMB: int) =
  let entrySize = sizeof(TTEntry)
  let numEntries = (sizeMB * 1024 * 1024) div entrySize
  
  ttSize = numEntries
  if transpositionTable != nil:
    deallocShared(transpositionTable)
    
  transpositionTable = cast[ptr UncheckedArray[TTEntry]](allocShared0(sizeof(TTEntry) * ttSize))
  zeroMem(transpositionTable, sizeof(TTEntry) * ttSize)

func ttIndex(key: ZobristKey, size: int): int {.inline.} =
  let k = key.uint64
  let s = size.uint64
  let kHi = k shr 32
  let kLo = k and 0xFFFFFFFF'u64
  let sHi = s shr 32
  let sLo = s and 0xFFFFFFFF'u64
  let hi = kHi * sHi + ((kHi * sLo) shr 32) + ((kLo * sHi) shr 32)
  int(hi)

proc storeTT*(board: Board, depth: int, score: int, originalAlpha: int, originalBeta: int, bestMove: Move, rawEval: int = 0) {.gcsafe.} =
  let index = ttIndex(board.currentZobristKey, ttSize)
  
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
  
  let existingEntry = transpositionTable[index]
  
  var replace = false
  
  if existingEntry.generation != ttGeneration:
    replace = true
  else:
    if depth >= existingEntry.depth or existingEntry.flag == InvalidEntry:
      replace = true
      
  if replace or existingEntry.hash != uint16(board.currentZobristKey):
    transpositionTable[index] = TTEntry(
      hash: uint16(board.currentZobristKey),
      depth: depth.int8,
      generation: ttGeneration,
      score: adjustedScore.int16,
      flag: flag,
      bestMove: bestMove,
      rawEval: rawEval.int16
    )

proc probeTT*(zobristKey: ZobristKey, depth: int, alpha: var int, beta: var int, gamePly: int): (bool, int, Move, int16) {.gcsafe.} =
  let index = ttIndex(zobristKey, ttSize)
  let entry = transpositionTable[index]
  
  if entry.hash == uint16(zobristKey):
    if entry.depth >= depth.int8:
      var score = entry.score.int
      const MateThreshold = MateValue - MaxPly
      
      if score > MateThreshold:
        score = score - gamePly
      elif score < -MateThreshold:
        score = score + gamePly
      
      if score > MateValue: score = MateValue
      elif score < -MateValue: score = -MateValue
      
          
      if entry.flag == ExactScore:
        return (true, score, entry.bestMove, entry.rawEval)
      elif entry.flag == LowerBound:
        if score >= beta:
          return (true, score, entry.bestMove, entry.rawEval)
        alpha = max(alpha, score)
      elif entry.flag == UpperBound:
        beta = min(beta, score)
        
      if alpha >= beta:
        return (true, score, entry.bestMove, entry.rawEval)
        
    return (false, 0, entry.bestMove, entry.rawEval) 
    
  return (false, 0, Move(0), 0'i16)

proc getTTEntry*(zobristKey: ZobristKey): tuple[hit: bool, entry: TTEntry] {.gcsafe.} =
  let index = ttIndex(zobristKey, ttSize)
  let entry = transpositionTable[index]
  
  if entry.hash == uint16(zobristKey):
    return (true, entry)
  else:
    return (false, entry)

proc getHashfull*(): int =
  var count = 0
  let sampleSize = min(1000, ttSize)
  
  for i in 0 ..< sampleSize:
    if transpositionTable[i].flag != InvalidEntry and transpositionTable[i].generation == ttGeneration:
      count.inc
      
  if sampleSize == 0: return 0
  return (count * 1000) div sampleSize
