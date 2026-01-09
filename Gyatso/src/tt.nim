import coretypes, zobrist, move, board
import std/locks

type
  TTEntryFlag* = enum
    InvalidEntry,
    ExactScore,
    LowerBound,
    UpperBound

  TTEntry* = object
    zobristKey*: ZobristKey
    depth*: int8
    generation*: uint8 # TT Ageing
    score*: int16
    flag*: TTEntryFlag
    bestMove*: Move

var ttGeneration*: uint8 = 0

proc newTTGeneration*() =
  ttGeneration.inc

var transpositionTable*: ptr UncheckedArray[TTEntry]
var ttSize*: int

const NumTTLocks = 8192
var ttLocks: array[NumTTLocks, Lock]

proc initTT*(sizeMB: int) =
  let entrySize = sizeof(TTEntry)
  let numEntries = (sizeMB * 1024 * 1024) div entrySize
  
  ttSize = numEntries
  if transpositionTable != nil:
    deallocShared(transpositionTable)
    
  transpositionTable = cast[ptr UncheckedArray[TTEntry]](allocShared0(sizeof(TTEntry) * ttSize))
  zeroMem(transpositionTable, sizeof(TTEntry) * ttSize)
  
  for i in 0 ..< NumTTLocks:
    initLock(ttLocks[i])

template ttIndex(key: ZobristKey): int =
  int(key mod ttSize.uint64)

proc storeTT*(board: Board, depth: int, score: int, originalAlpha: int, originalBeta: int, bestMove: Move) {.gcsafe.} =
  let index = ttIndex(board.currentZobristKey)
  let lockIdx = index mod NumTTLocks
  
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
  
      
  acquire(ttLocks[lockIdx])
  let existingEntry = transpositionTable[index]
  
  var replace = false
  
  if existingEntry.generation != ttGeneration:
    replace = true
  else:
    if depth >= existingEntry.depth or existingEntry.flag == InvalidEntry:
      replace = true
      
  if replace or existingEntry.zobristKey != board.currentZobristKey:
    transpositionTable[index] = TTEntry(
      zobristKey: board.currentZobristKey,
      depth: depth.int8,
      generation: ttGeneration,
      score: adjustedScore.int16,
      flag: flag,
      bestMove: bestMove
    )
  release(ttLocks[lockIdx])

proc probeTT*(zobristKey: ZobristKey, depth: int, alpha: var int, beta: var int, gamePly: int): (bool, int, Move) {.gcsafe.} =
  let index = ttIndex(zobristKey)
  let lockIdx = index mod NumTTLocks
  
  acquire(ttLocks[lockIdx])
  let entry = transpositionTable[index]
  release(ttLocks[lockIdx])
  
  if entry.zobristKey == zobristKey:
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
        return (true, score, entry.bestMove)
      elif entry.flag == LowerBound:
        if score >= beta:
          return (true, score, entry.bestMove)
        alpha = max(alpha, score)
      elif entry.flag == UpperBound:
        beta = min(beta, score)
        
      if alpha >= beta:
        return (true, score, entry.bestMove)
        
    return (false, 0, entry.bestMove) 
    
  return (false, 0, Move(0))

proc getTTEntry*(zobristKey: ZobristKey): tuple[hit: bool, entry: TTEntry] {.gcsafe.} =
  let index = ttIndex(zobristKey)
  let lockIdx = index mod NumTTLocks
  
  acquire(ttLocks[lockIdx])
  let entry = transpositionTable[index]
  release(ttLocks[lockIdx])
  
  if entry.zobristKey == zobristKey:
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

