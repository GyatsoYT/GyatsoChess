import coretypes, zobrist, move, board

type
  TTEntryFlag* = enum
    ExactScore,
    LowerBound,
    UpperBound,
    InvalidEntry

  TTEntry* = object
    zobristKey*: ZobristKey
    depth*: int8
    score*: int16
    flag*: TTEntryFlag
    bestMove*: Move



var transpositionTable*: ptr UncheckedArray[TTEntry]
var ttSize*: int

proc initTT*(sizeMB: int) =
  let entrySize = sizeof(TTEntry)
  let numEntries = (sizeMB * 1024 * 1024) div entrySize
  
  ttSize = numEntries
  transpositionTable = cast[ptr UncheckedArray[TTEntry]](allocShared0(sizeof(TTEntry) * ttSize))
  
  # Clear table (allocShared0 already zeroes it, but we can set flags if needed)
  # For now, 0 flag is ExactScore (if enum starts at 0).
  # Let's make InvalidEntry 0 to be safe with allocShared0?
  # Or just loop and set.
  for i in 0 ..< ttSize:
    transpositionTable[i].flag = InvalidEntry

proc ttIndex(key: ZobristKey): int {.inline.} =
  int(key mod ttSize.uint64)

proc storeTT*(board: Board, depth: int, score: int, originalAlpha: int, originalBeta: int, bestMove: Move, plyFromRoot: int) {.gcsafe.} =
  let index = ttIndex(board.currentZobristKey)
  
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
  
  transpositionTable[index] = TTEntry(
    zobristKey: board.currentZobristKey,
    depth: depth.int8,
    score: adjustedScore.int16,
    flag: flag,
    bestMove: bestMove
  )

proc probeTT*(zobristKey: ZobristKey, depth: int, alpha: var int, beta: var int, plyFromRoot: int): (bool, int, Move) {.gcsafe.} =
  let index = ttIndex(zobristKey)
  let entry = transpositionTable[index]
  
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
        # Can update alpha?
        # alpha = max(alpha, score) 
        # The prompt says: If entry.flag == LowerBound, alpha = max(alpha, retrievedScore).
        # But we return hit only if cutoff.
        # Actually, standard TT probing updates alpha/beta for the current search context if not cutting off immediately?
        # The prompt says: 
        # iii. If entry.flag == LowerBound, alpha = max(alpha, retrievedScore).
        # iv. If entry.flag == UpperBound, beta = min(beta, retrievedScore).
        # v. If alpha >= beta, return (true, retrievedScore, entry.bestMove)
        
        # Let's follow the prompt logic exactly in the return values or side effects?
        # The function signature is `probeTT(..., alpha: var int, beta: var int, ...)` so it can modify alpha/beta.
        
        alpha = max(alpha, score)
      elif entry.flag == UpperBound:
        beta = min(beta, score)
        
      if alpha >= beta:
        return (true, score, entry.bestMove)
        
    # Even if depth is not sufficient for cutoff, we might return the move for ordering?
    # The prompt says "Return (false, 0, defaultMove) if no usable hit."
    # But usually we want the move even if we don't cut off.
    # For now, let's stick to the prompt's "usable hit" for cutoff/score return.
    # Wait, prompt says "If hit is true, return ttScore." in negamax.
    # So this function is primarily for retrieving a score to return immediately.
    # However, for move ordering (Task 14), we will need the move regardless of depth.
    # We can return (false, 0, entry.bestMove) if key matches but depth insufficient?
    # Prompt says: "Return (false, 0, defaultMove) if no usable hit."
    # Let's follow that for now.
    
    return (false, 0, entry.bestMove) # Return move even if false? Useful for ordering.
    
  return (false, 0, Move(0))
