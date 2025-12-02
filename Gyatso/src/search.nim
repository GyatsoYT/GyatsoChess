import coretypes, board, move, movegen, evaluation, bitboard, tt, std/times, std/monotimes, std/atomics, see



var killerMoves* {.threadvar.}: array[MaxPly, array[2, Move]]
var historyTable* {.threadvar.}: array[Color, array[Square, array[Square, int]]]

proc checkTime*(info: var SearchInfo) =
  if info.stopFlag != nil and info.stopFlag[].load(moRelaxed): return
  if info.nodes mod 2048 == 0:
    # Sync node count to shared array
    if info.nodeCounts != nil:
      info.nodeCounts[info.threadID] = info.nodes
      
    let elapsed = getMonoTime() - info.startTime
    if info.allocatedTime != DurationZero and elapsed > info.allocatedTime:
      if info.stopFlag != nil:
        info.stopFlag[].store(true, moRelaxed)





const
  Infinity* = 30000
  MateValue* = 29000 # Slightly less than Infinity to allow for mate distance logic
  Contempt* = 20 # Contempt factor for draw detection in search


proc qSearch(board: var Board, alpha: int, beta: int, ply: int, info: var SearchInfo): int =
  info.nodes.inc
  if info.nodes mod 2048 == 0:
    checkTime(info)
  if info.stopFlag != nil and info.stopFlag[].load(moRelaxed): return 0

  var alpha = alpha
  let standPat = evaluate(board)
  
  if standPat >= beta:
    return beta
    
  # Delta Pruning
  # If standing pat is far below alpha, we might not need to search captures
  # Safety margin: Queen Value + some buffer
  const DeltaMargin = 975
  if standPat < alpha - DeltaMargin:
    # If we are not promoting, we can't possibly raise alpha
    # But we need to be careful about promotions.
    # For now, let's just use it as a heuristic to return alpha if very bad.
    return alpha

  if standPat > alpha:
    alpha = standPat
    
  var ml {.noinit.}: MoveList
  ml.count = 0
  generateLegalCaptures(board, ml)

  
  # Score Moves (only captures/promotions relevant, but we score all for simplicity of reuse)
  # Optimization: Could have a specialized generateCaptures
  
  # We need a dummy move for scoring (no TT move in QSearch usually, or passed from negamax?)
  # For now, Move(0)
  for i in 0 ..< ml.count:
    ml.scores[i] = scoreMove(board, ml.moves[i], Move(0))
    
  for i in 0 ..< ml.count:
    let m = pickMove(ml, i)
    
    # SEE Pruning for Captures
    # If the capture loses material, don't search it in qSearch (unless very important?)
    # We skip bad captures.
    if not m.isPromotion and see(board, m) < 0:
      continue
      
    discard board.makeMove(m)
    let score = -qSearch(board, -beta, -alpha, ply + 1, info)
    board.unmakeMove(m)
    
    if info.stopFlag != nil and info.stopFlag[].load(moRelaxed): return 0
    
    if score >= beta:
      return beta
      
    if score > alpha:
      alpha = score
      
  return alpha

proc negamax*(board: var Board, depth: int, alpha: int, beta: int, ply: int, info: var SearchInfo, totalExtensions: int = 0): int =
  info.nodes.inc
  if info.nodes mod 2048 == 0:
    checkTime(info)
  if info.stopFlag != nil and info.stopFlag[].load(moRelaxed): return 0

  var alpha = alpha
  var beta = beta
  
  # Draw Detection
  # Check for Repetition, 50-Move Rule, and Insufficient Material
  # We check repetition first as it's most common in drawish endgames to avoid
  if board.isRepetition() or board.halfMoveClock >= 100 or board.isInsufficientMaterial():
    # At root, return 0 to avoid false mate lines
    if ply == 0: return 0
    # In search, return Contempt to avoid entering drawish lines when winning
    # Note: If we are losing, we might want to return -Contempt or 0, but for now fixed Contempt
    return Contempt

  # TT Probe
  let (hit, ttScore, ttMove) = probeTT(board.currentZobristKey, depth, alpha, beta, ply)
  if hit:
    return ttScore

  if depth == 0:
    return qSearch(board, alpha, beta, ply, info)
    
  var ml: MoveList
  
  # Static Evaluation for Pruning
  var staticEval = -Infinity
  if depth < 7:
    staticEval = evaluate(board)
    
  # Reverse Futility Pruning (Static Null Move Pruning)
  # If we are way above beta, we can prune.
  if depth < 7 and ply > 0 and abs(beta) < MateValue and staticEval - (100 * depth) >= beta:
    return staticEval

  # Null Move Pruning
  if depth >= 3 and (info.stopFlag == nil or not info.stopFlag[].load(moRelaxed)):
    let us = board.sideToMove
    let them = if us == White: Black else: White
    let kingSq = bitScanForward(board.pieceBB[makePiece(us, King)])
    
    # Only if static eval is good enough (>= beta) or we just try it?
    # Standard NMP: if staticEval >= beta (or close), try null move.
    # We use a relaxed condition or just try it.
    # Current implementation didn't check staticEval, which is risky.
    # Let's add staticEval check.
    if staticEval >= beta and not isSquareAttacked(board, kingSq.Square, them) and hasSufficientMaterial(board, us):
      board.makeNullMove()
      let R = 2
      let score = -negamax(board, depth - R - 1, -beta, -beta + 1, ply + 1, info, totalExtensions)
      board.unmakeNullMove()
      
      if info.stopFlag != nil and info.stopFlag[].load(moRelaxed): return 0
      
      if score >= beta:
        return beta
        
  generateLegalMoves(board, ml)
  
  if ml.count == 0:
    # Checkmate or Stalemate
    # We need to check if the King is currently attacked
    let us = board.sideToMove
    let them = if us == White: Black else: White
    let kingSq = bitScanForward(board.pieceBB[makePiece(us, King)])
    
    if isSquareAttacked(board, kingSq.Square, them):
      return -MateValue + ply # Prefer faster mates (higher score)
    else:
      return 0 # Stalemate
      
  var maxEval = -Infinity
  var bestMove = Move(0)
  let originalAlpha = alpha
  
  # Score Moves
  for i in 0 ..< ml.count:
    ml.scores[i] = scoreMove(board, ml.moves[i], ttMove)
    
    # Killer Moves & History Heuristic
    if ml.scores[i] == 0: # Only boost quiet moves (score 0 from scoreMove)
      if ml.moves[i] == killerMoves[ply][0]:
        ml.scores[i] = 80_000
      elif ml.moves[i] == killerMoves[ply][1]:
        ml.scores[i] = 70_000
      else:
        # History Heuristic
        let m = ml.moves[i]
        let histScore = historyTable[board.sideToMove][m.fromSquare][m.toSquare]
        # Cap history score
        ml.scores[i] += min(histScore, 10_000)
  
  var movesSearched = 0
  
  for i in 0 ..< ml.count:
    let m = pickMove(ml, i)
    
    # Futility Pruning (in loop)
    # Prune quiet moves if static eval is too low
    if depth < 7 and not m.isCapture and not m.isPromotion and not isSquareAttacked(board, bitScanForward(board.pieceBB[makePiece(board.sideToMove, King)]).Square, if board.sideToMove == White: Black else: White):
       let margin = 100 * depth
       if staticEval + margin < alpha:
         continue
         
    discard board.makeMove(m)
    
    # Check Extension
    let opponent = board.sideToMove
    let us = if opponent == White: Black else: White
    let kingSq = bitScanForward(board.pieceBB[makePiece(opponent, King)])
    let givesCheck = isSquareAttacked(board, kingSq.Square, us)
    
    var extension = 0
    if givesCheck and totalExtensions < 16:
      extension = 1
      
    var newDepth = depth - 1 + extension
    if newDepth <= 0: newDepth = 0 # Ensure we don't extend into negative if not intended, though 0 goes to qsearch

    var score = -Infinity
    
    if movesSearched == 0:
      # PVS: First move (PV move) - Full Window
      score = -negamax(board, newDepth, -beta, -alpha, ply + 1, info, totalExtensions + extension)
    else:
      # PVS: Late moves
      
      # LMR (Late Move Reductions)
      var reduction = 0
      if depth >= 3 and movesSearched >= 4 and not m.isCapture and not m.isPromotion and not givesCheck:
        let us = board.sideToMove
        let them = if us == White: Black else: White
        let kingSq = bitScanForward(board.pieceBB[makePiece(us, King)])
        # Don't reduce if in check
        if not isSquareAttacked(board, kingSq.Square, them):
          reduction = 1
          if movesSearched > 10: reduction += 1
          # Cap reduction?
          if reduction > depth - 2: reduction = depth - 2
          if reduction < 0: reduction = 0
      
      # Null Window Search (with LMR)
      # Note: If we extended, newDepth includes extension. If we reduced, we subtract from newDepth?
      # Usually LMR applies to the base depth.
      # But here we simplified newDepth. 
      # If reduced, we want (depth - 1 - reduction + extension).
      # So: newDepth - reduction.
      score = -negamax(board, newDepth - reduction, -alpha - 1, -alpha, ply + 1, info, totalExtensions + extension)
      
      # Re-search if LMR failed (score > alpha)
      if reduction > 0 and score > alpha:
         score = -negamax(board, newDepth, -alpha - 1, -alpha, ply + 1, info, totalExtensions + extension)
      
      # PVS Re-search (Full Window) if Null Window failed high
      if score > alpha and score < beta:
        score = -negamax(board, newDepth, -beta, -alpha, ply + 1, info, totalExtensions + extension)
    
    board.unmakeMove(m)
    movesSearched.inc
    
    if info.stopFlag != nil and info.stopFlag[].load(moRelaxed): return 0
    
    if score > maxEval:
      maxEval = score
      bestMove = m
      
    if maxEval > alpha:
      alpha = maxEval
      
    if alpha >= beta:
      # Beta Cutoff
      if not m.isCapture and not m.isPromotion:
        # Killer Move Heuristic
        if killerMoves[ply][0] != m:
          killerMoves[ply][1] = killerMoves[ply][0]
          killerMoves[ply][0] = m
          
        # History Heuristic Update
        let bonus = depth * depth
        historyTable[board.sideToMove][m.fromSquare][m.toSquare] += bonus
        # Cap?
        if historyTable[board.sideToMove][m.fromSquare][m.toSquare] > 20000:
           historyTable[board.sideToMove][m.fromSquare][m.toSquare] = 20000
           
      break 
  
  # TT Store
  storeTT(board, depth, maxEval, originalAlpha, beta, bestMove, ply)
      
  return maxEval

proc iterativeDeepening*(board: var Board, info: var SearchInfo, threadID: int = 0): (Move, int) =
  info.startTime = getMonoTime()
  info.nodes = 0
  # stopFlag is managed by caller
  
  # Clear Killer Moves & History Table
  for i in 0 ..< MaxPly:
    killerMoves[i][0] = Move(0)
    killerMoves[i][1] = Move(0)
    
  # We don't necessarily clear History Table every ID, but maybe decay it?
  # For now, let's clear it to be safe/simple, or decay.
  # Prompt says: "Periodically (e.g., at the end of each iterativeDeepeningSearch iteration or less frequently), decay all history scores"
  # Let's clear for now or decay at start of search.
  for c in White .. Black:
    for f in 0.Square .. 63.Square:
      for t in 0.Square .. 63.Square:
        historyTable[c][f][t] = 0
  
  var bestMove = Move(0)
  var bestScore = -Infinity
  
  # If depth limit is 0, set it to max
  let maxDepth = if info.depthLimit > 0: info.depthLimit else: 64
  
  for depth in 1 .. maxDepth:
    var alpha = -Infinity
    var beta = Infinity
    
    # Root search logic inside ID loop
    var ml: MoveList
    generateLegalMoves(board, ml)
    
    # Debug Logging
    # let f2 = open("debug.log", fmAppend)
    # f2.writeLine("Depth " & $depth & " Moves: " & $ml.count)
    # f2.close()
    
    if ml.count == 0: break # Game over
    
    var currentBestMove = Move(0)
    var currentBestScore = -Infinity
    
    # Get TT Move for ordering
    let (hit, ttScore, ttMove) = probeTT(board.currentZobristKey, depth, alpha, beta, 0)
    
    # Score Moves
    for i in 0 ..< ml.count:
      ml.scores[i] = scoreMove(board, ml.moves[i], ttMove)
      # Root moves history?
      if ml.scores[i] == 0:
         let m = ml.moves[i]
         ml.scores[i] += historyTable[board.sideToMove][m.fromSquare][m.toSquare]

    # Fallback for Depth 1: Select best static move to ensure we have a move if we timeout immediately
    if depth == 1 and ml.count > 0:
       var bestStaticIdx = 0
       var bestStaticScore = ml.scores[0]
       for i in 1 ..< ml.count:
         if ml.scores[i] > bestStaticScore:
           bestStaticScore = ml.scores[i]
           bestStaticIdx = i
       bestMove = ml.moves[bestStaticIdx]
       # echo "info string debug fallback selected ", bestMove.toAlgebraic()

    
    for i in 0 ..< ml.count:
      let m = pickMove(ml, i)
      discard board.makeMove(m)
      
      # Root PVS:
      var score = -Infinity
      if i == 0:
        score = -negamax(board, depth - 1, -beta, -alpha, 1, info)
      else:
        # Null window
        score = -negamax(board, depth - 1, -alpha - 1, -alpha, 1, info)
        if score > alpha:
          score = -negamax(board, depth - 1, -beta, -alpha, 1, info)
          
      board.unmakeMove(m)
      
      if info.stopFlag != nil and info.stopFlag[].load(moRelaxed): break
      
      if score > currentBestScore:
        currentBestScore = score
        currentBestMove = m
        
      if currentBestScore > alpha:
        alpha = currentBestScore
        
    if info.stopFlag != nil and info.stopFlag[].load(moRelaxed):
      break
      
    if currentBestMove != Move(0):
      bestMove = currentBestMove
      bestScore = currentBestScore
    
    if threadID == 0:
      # Final safety check: If bestMove is still Move(0) (should be impossible with fallback), pick first move
      if bestMove == Move(0) and ml.count > 0:
        bestMove = ml.moves[0]
        
      # Aggregate total nodes
      var totalNodes = info.nodes # Start with our own
      if info.nodeCounts != nil:
        # Sum other threads (skip ourselves if we want, but array has our old value)
        # Actually, info.nodeCounts[0] is our old value (synced every 2048).
        # info.nodes is our current value (more accurate).
        # So sum others.
        for i in 0 ..< info.numThreads:
          if i != threadID:
            totalNodes += info.nodeCounts[i]
            
      let elapsed = (getMonoTime() - info.startTime).inMilliseconds
      let nps = if elapsed > 0: (totalNodes.float / (elapsed.float / 1000.0)).int else: 0
      
      echo "info depth ", depth, " score cp ", bestScore, " nodes ", totalNodes, " nps ", nps, " time ", elapsed, " pv ", bestMove.toAlgebraic()
    
    # Decay History
    for c in White .. Black:
      for f in 0.Square .. 63.Square:
        for t in 0.Square .. 63.Square:
          historyTable[c][f][t] = historyTable[c][f][t] div 2
    
    # Check if we used up too much time (soft limit check could go here)
    
  return (bestMove, bestScore)

