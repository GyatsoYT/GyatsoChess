import coretypes, zobrist, move, board
import std/locks

type
  TTEntryFlag* = enum
    InvalidEntry, # 0, so allocShared0 sets this by default
    ExactScore,
    LowerBound,
    UpperBound

  TTEntry* = object
    zobristKey*: ZobristKey
    depth*: int8
    score*: int16
    flag*: TTEntryFlag
    bestMove*: Move

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
  
  # Initialize locks
  for i in 0 ..< NumTTLocks:
    initLock(ttLocks[i])

proc ttIndex(key: ZobristKey): int {.inline.} =
  int(key mod ttSize.uint64)

proc storeTT*(board: Board, depth: int, score: int, originalAlpha: int, originalBeta: int, bestMove: Move, plyFromRoot: int) {.gcsafe.} =
  let index = ttIndex(board.currentZobristKey)
  let lockIdx = index mod NumTTLocks
  
  var flag = ExactScore
  if score <= originalAlpha:
    flag = UpperBound
  elif score >= originalBeta:
    flag = LowerBound
    
  var adjustedScore = score
  if abs(score) > 20000: # Mate score threshold (KingValue)
    if score > 0:
      adjustedScore += plyFromRoot
    else:
      adjustedScore -= plyFromRoot
      
  # Replacement strategy: Always replace for now (simplest)
  # Could add depth check: if entry.depth <= depth or entry.flag == InvalidEntry
  
  acquire(ttLocks[lockIdx])
  transpositionTable[index] = TTEntry(
    zobristKey: board.currentZobristKey,
    depth: depth.int8,
    score: adjustedScore.int16,
    flag: flag,
    bestMove: bestMove
  )
  release(ttLocks[lockIdx])

proc probeTT*(zobristKey: ZobristKey, depth: int, alpha: var int, beta: var int, plyFromRoot: int): (bool, int, Move) {.gcsafe.} =
  let index = ttIndex(zobristKey)
  let lockIdx = index mod NumTTLocks
  
  acquire(ttLocks[lockIdx])
  let entry = transpositionTable[index]
  release(ttLocks[lockIdx])
  
  if entry.zobristKey == zobristKey:
    if entry.depth >= depth.int8:
      var score = entry.score.int
      
      if abs(score) > 20000:
        if score > 0:
          score -= plyFromRoot
        else:
          score += plyFromRoot
          
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
        
    return (false, 0, entry.bestMove) # Return move even if false? Useful for ordering.
    
  return (false, 0, Move(0))
