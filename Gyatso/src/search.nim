import coretypes, board, move, movegen, evaluation, bitboard, tt, std/times, std/monotimes, std/atomics, see, zobrist

var killerMoves* {.threadvar.}: array[MaxPly, array[2, Move]]
var historyTable* {.threadvar.}: array[Color, array[Square, array[Square, int]]]

proc checkTime*(info: var SearchInfo) =
  if info.nodes mod 2048 == 0:
    # Sync node count to shared array FIRST
    if info.nodeCounts != nil:
      info.nodeCounts[info.threadID] = info.nodes
      
    # Then check stop flag
    if info.stopFlag != nil and info.stopFlag[].load(moRelaxed): 
      return
    
    # If pondering, don't check time - search infinitely until ponderhit or stop
    if info.ponderFlag != nil and info.ponderFlag[].load(moRelaxed):
      return
      
    let elapsed = getMonoTime() - info.startTime
    if info.allocatedTime != DurationZero and elapsed > info.allocatedTime:
      if info.stopFlag != nil:
        info.stopFlag[].store(true, moRelaxed)

const
  Infinity* = 30000
  MateValue* = 29000
  Contempt* = 20

proc qSearch(board: var Board, alpha: int, beta: int, ply: int, info: var SearchInfo): int =
  info.nodes.inc
  if info.nodes mod 2048 == 0:
    checkTime(info)
  if info.stopFlag != nil and info.stopFlag[].load(moRelaxed): 
    return 0

  var alpha = alpha
  let standPat = evaluate(board)
  
  if standPat >= beta:
    return beta
    
  # Delta Pruning
  const DeltaMargin = 975
  if standPat < alpha - DeltaMargin:
    return alpha

  if standPat > alpha:
    alpha = standPat
    
  var ml {.noinit.}: MoveList
  ml.count = 0
  generateLegalCaptures(board, ml)
  
  # Score moves
  for i in 0 ..< ml.count:
    ml.scores[i] = scoreMove(board, ml.moves[i], Move(0))
    
  for i in 0 ..< ml.count:
    let m = pickMove(ml, i)
    
    # SEE Pruning for bad captures
    if not m.isPromotion and see(board, m) < 0:
      continue
      
    discard board.makeMove(m)
    let score = -qSearch(board, -beta, -alpha, ply + 1, info)
    board.unmakeMove(m)
    
    if info.stopFlag != nil and info.stopFlag[].load(moRelaxed): 
      return 0
    
    if score >= beta:
      return beta
      
    if score > alpha:
      alpha = score
      
  return alpha

proc negamax*(board: var Board, depth: int, alpha: int, beta: int, ply: int, info: var SearchInfo, totalExtensions: int = 0): int =
  info.nodes.inc
  if info.nodes mod 2048 == 0:
    checkTime(info)
  if info.stopFlag != nil and info.stopFlag[].load(moRelaxed): 
    return 0

  var alpha = alpha
  var beta = beta
  
  # Draw Detection - contempt only makes sense if we're better
  if board.isRepetition() or board.halfMoveClock >= 100 or board.isInsufficientMaterial():
    return 0  # Always return 0 for draws (can be made dynamic based on position eval)

  # TT Probe
  let (hit, ttScore, ttMove) = probeTT(board.currentZobristKey, depth, alpha, beta, board.gamePly)
  if hit:
    return ttScore
  
  # Mate distance pruning
  # If we can already force a mate in X plies, don't search for longer mates
  let mateInPly = MateValue - ply
  if mateInPly < beta:
    beta = mateInPly
    if alpha >= mateInPly:
      return mateInPly

  # If opponent can force mate against us in X plies, don't bother with worse positions
  let matedInPly = -MateValue + ply + 1
  if matedInPly > alpha:
    alpha = matedInPly
    if beta <= matedInPly:
      return matedInPly

  if depth == 0:
    return qSearch(board, alpha, beta, ply, info)
    
  var ml: MoveList
  
  # Static Evaluation - compute ALWAYS, needed for pruning
  let staticEval = evaluate(board)
    
  # Reverse Futility Pruning
  if depth < 7 and ply > 0 and abs(beta) < MateValue and staticEval - (100 * depth) >= beta:
    return staticEval

  # Null Move Pruning
  if depth >= 3 and ply > 0 and staticEval >= beta:
    let us = board.sideToMove
    let them = if us == White: Black else: White
    let kingSq = bitScanForward(board.pieceBB[makePiece(us, King)])
    
    # Don't do null move if we're in check
    if not isSquareAttacked(board, kingSq.Square, them):
      # Check if we have non-pawn material (avoid zugzwang in pawn endgames)
      var hasNonPawnMaterial = false
      for pt in Knight .. Queen:
        if board.pieceBB[makePiece(us, pt)] != 0:
          hasNonPawnMaterial = true
          break
      
      if hasNonPawnMaterial:
        board.makeNullMove()
        let R = 2
        let score = -negamax(board, depth - R - 1, -beta, -beta + 1, ply + 1, info, totalExtensions)
        board.unmakeNullMove()
        
        if info.stopFlag != nil and info.stopFlag[].load(moRelaxed): 
          return 0
        
        if score >= beta:
          return beta
        
  generateLegalMoves(board, ml)
  
  if ml.count == 0:
    # Checkmate or Stalemate
    let us = board.sideToMove
    let them = if us == White: Black else: White
    let kingSq = bitScanForward(board.pieceBB[makePiece(us, King)])
    
    if isSquareAttacked(board, kingSq.Square, them):
      return -MateValue + ply
    else:
      return 0
      
  var maxEval = -Infinity
  var bestMove = Move(0)
  let originalAlpha = alpha
  
  # Check if we're in check (before making moves)
  let us = board.sideToMove
  let them = if us == White: Black else: White
  let ourKingSq = bitScanForward(board.pieceBB[makePiece(us, King)])
  let inCheck = isSquareAttacked(board, ourKingSq.Square, them)
  
  # Score Moves
  for i in 0 ..< ml.count:
    ml.scores[i] = scoreMove(board, ml.moves[i], ttMove)
    
    # Killer Moves & History Heuristic for quiet moves
    if ml.scores[i] == 0:
      if ml.moves[i] == killerMoves[ply][0]:
        ml.scores[i] = 80_000
      elif ml.moves[i] == killerMoves[ply][1]:
        ml.scores[i] = 70_000
      else:
        let m = ml.moves[i]
        let histScore = historyTable[board.sideToMove][m.fromSquare][m.toSquare]
        ml.scores[i] += min(histScore, 10_000)
  
  var movesSearched = 0
  
  for i in 0 ..< ml.count:
    let m = pickMove(ml, i)
    
    # Futility Pruning - prune quiet moves if eval is too low
    # Don't prune if in check or move gives check (approximation: captures/promotions might give check)
    if depth < 7 and not inCheck and not m.isCapture and not m.isPromotion:
       let margin = 100 * depth
       if staticEval + margin < alpha:
         continue
         
    discard board.makeMove(m)
    
    # Check Extension
    let opponent = board.sideToMove
    let opponentIsWhite = opponent == White
    let weAre = if opponentIsWhite: Black else: White
    let oppKingSq = bitScanForward(board.pieceBB[makePiece(opponent, King)])
    let givesCheck = isSquareAttacked(board, oppKingSq.Square, weAre)
    
    var extension = 0
    if givesCheck and totalExtensions < 16:
      extension = 1
      
    var newDepth = depth - 1 + extension
    if newDepth < 0: newDepth = 0

    var score = -Infinity
    
    if movesSearched == 0:
      # First move - Full Window
      score = -negamax(board, newDepth, -beta, -alpha, ply + 1, info, totalExtensions + extension)
    else:
      # Late Move Reductions
      var reduction = 0
      if depth >= 3 and movesSearched >= 4 and not m.isCapture and not m.isPromotion and not givesCheck and not inCheck:
        reduction = 1
        if movesSearched > 10: reduction += 1
        # Cap reduction
        if reduction > depth - 2: reduction = depth - 2
        if reduction < 0: reduction = 0
      
      # Null Window Search with reduction
      score = -negamax(board, newDepth - reduction, -alpha - 1, -alpha, ply + 1, info, totalExtensions + extension)
      
      # Re-search if reduced and score raised alpha
      if reduction > 0 and score > alpha:
         score = -negamax(board, newDepth, -alpha - 1, -alpha, ply + 1, info, totalExtensions + extension)
      
      # PVS Re-search with full window
      if score > alpha and score < beta:
        score = -negamax(board, newDepth, -beta, -alpha, ply + 1, info, totalExtensions + extension)
    
    board.unmakeMove(m)
    movesSearched.inc
    
    if info.stopFlag != nil and info.stopFlag[].load(moRelaxed): 
      return 0
    
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
        if historyTable[board.sideToMove][m.fromSquare][m.toSquare] > 20000:
           historyTable[board.sideToMove][m.fromSquare][m.toSquare] = 20000
           
      break 
  
  # TT Store
  storeTT(board, depth, maxEval, originalAlpha, beta, bestMove)
      
  return maxEval

proc getPV(board: Board, depth: int): string =
  var pv = ""
  var b = board
  var seenKeys: seq[ZobristKey] = @[]
  
  for i in 0 ..< depth:
    var alpha = -Infinity
    var beta = Infinity
    let (hit, _, move) = probeTT(b.currentZobristKey, 0, alpha, beta, b.gamePly)
    if move == Move(0):
      break
      
    # Verify move legality
    var ml: MoveList
    generateLegalMoves(b, ml)
    var isLegal = false
    for j in 0 ..< ml.count:
      if ml.moves[j] == move:
        isLegal = true
        break
    
    if not isLegal:
      break
      
    pv.add(move.toAlgebraic() & " ")
    discard b.makeMove(move)
    
    if b.halfMoveClock >= 100: break
    
    if b.isRepetition(): break
    if b.currentZobristKey in seenKeys: break
    seenKeys.add(b.currentZobristKey)
    
  return pv

proc iterativeDeepening*(board: var Board, info: var SearchInfo, threadID: int = 0): (Move, int) =
  info.startTime = getMonoTime()
  info.nodes = 0
  
  # Clear Killer Moves
  for i in 0 ..< MaxPly:
    killerMoves[i][0] = Move(0)
    killerMoves[i][1] = Move(0)
    
  # Decay history table instead of clearing (preserve knowledge across searches)
  for c in White .. Black:
    for f in 0.Square .. 63.Square:
      for t in 0.Square .. 63.Square:
        historyTable[c][f][t] = historyTable[c][f][t] div 4
  
  var bestMove = Move(0)
  var bestScore = -Infinity
  
  let maxDepth = if info.depthLimit > 0: info.depthLimit else: 64
  
  for depth in 1 .. maxDepth:
    if info.stopFlag != nil and info.stopFlag[].load(moRelaxed):
      break

    # Aspiration Windows
    var alphaWindow = 50
    var betaWindow = 50
    var aspirationScore = bestScore
    
    var currentBestMove = Move(0)
    var currentBestScore = -Infinity
    
    # Aspiration window loop
    while true:
      var alpha = -Infinity
      var beta = Infinity
      
      if depth >= 3:
        alpha = max(-Infinity, aspirationScore - alphaWindow)
        beta = min(Infinity, aspirationScore + betaWindow)
      
      # Generate and score moves fresh each aspiration attempt
      var ml: MoveList
      generateLegalMoves(board, ml)
      
      if ml.count == 0: 
        return (bestMove, bestScore)  # Game over
      
      # Get TT Move for ordering
      let (hit, ttScore, ttMove) = probeTT(board.currentZobristKey, depth, alpha, beta, board.gamePly)
      
      # Score Moves
      for i in 0 ..< ml.count:
        ml.scores[i] = scoreMove(board, ml.moves[i], ttMove)
        if ml.scores[i] == 0:
           let m = ml.moves[i]
           ml.scores[i] += min(historyTable[board.sideToMove][m.fromSquare][m.toSquare], 10_000)

      # Depth 1 fallback
      if depth == 1 and ml.count > 0:
         var bestStaticIdx = 0
         var bestStaticScore = ml.scores[0]
         for i in 1 ..< ml.count:
           if ml.scores[i] > bestStaticScore:
             bestStaticScore = ml.scores[i]
             bestStaticIdx = i
         bestMove = ml.moves[bestStaticIdx]

      currentBestMove = Move(0)
      currentBestScore = -Infinity
      
      # Search all moves
      for i in 0 ..< ml.count:
        let m = pickMove(ml, i)
        discard board.makeMove(m)
        
        var val = -Infinity
        if i == 0:
          val = -negamax(board, depth - 1, -beta, -alpha, 1, info)
        else:
          # Null window search
          val = -negamax(board, depth - 1, -alpha - 1, -alpha, 1, info)
          if val > alpha and val < beta:
            val = -negamax(board, depth - 1, -beta, -alpha, 1, info)
            
        board.unmakeMove(m)
        
        if info.stopFlag != nil and info.stopFlag[].load(moRelaxed): 
          break
        
        if val > currentBestScore:
          currentBestScore = val
          currentBestMove = m
          
        if currentBestScore > alpha:
          alpha = currentBestScore
          
        if currentBestScore >= beta:
           break
      
      # Check stop flag before aspiration logic
      if info.stopFlag != nil and info.stopFlag[].load(moRelaxed):
        break
        
      # Aspiration window logic
      if depth >= 3:
        let alphaStart = max(-Infinity, aspirationScore - alphaWindow)
        let betaStart = min(Infinity, aspirationScore + betaWindow)
        
        if currentBestScore <= alphaStart:
           # Fail low - widen alpha
           alphaWindow *= 2
           aspirationScore = currentBestScore
           continue
        elif currentBestScore >= betaStart:
           # Fail high - widen beta
           betaWindow *= 2
           aspirationScore = currentBestScore
           continue
      
      # Within window or depth < 3
      break
    
    # Check stop flag one last time before committing new bestMove for this depth
    if info.stopFlag != nil and info.stopFlag[].load(moRelaxed):
      break

    # Update best move/score if search completed successfully for this depth
    if currentBestMove != Move(0):
      bestMove = currentBestMove
      bestScore = currentBestScore
    
    if threadID == 0:
      # Safety: ensure we have a legal move
      if bestMove == Move(0):
        var ml: MoveList
        generateLegalMoves(board, ml)
        if ml.count > 0:
          bestMove = ml.moves[0]
          
      # Aggregate nodes from all threads
      var totalNodes = info.nodes
      if info.nodeCounts != nil:
        for i in 0 ..< info.numThreads:
          if i != threadID:
            totalNodes += info.nodeCounts[i]
            
      let elapsed = (getMonoTime() - info.startTime).inMilliseconds
      let nps = if elapsed > 0: (totalNodes.float / (elapsed.float / 1000.0)).int else: 0
      
      # Only print if not stopped
      if info.stopFlag == nil or not info.stopFlag[].load(moRelaxed):
        # Store TT Entry for Root Position
        storeTT(board, depth, bestScore, -Infinity, Infinity, bestMove)
        
        let pvLine = getPV(board, depth)
        
        # Format score for UCI output
        var scoreStr = ""
        if abs(bestScore) > 20000:
          # Mate score - convert to mate distance
          let mateDistance = (MateValue - abs(bestScore) + 1) div 2
          if bestScore > 0:
            scoreStr = "mate " & $mateDistance
          else:
            scoreStr = "mate -" & $mateDistance
        else:
          scoreStr = "cp " & $bestScore
        
        echo "info depth ", depth, " score ", scoreStr, " nodes ", totalNodes, " nps ", nps, " time ", elapsed, " pv ", pvLine
    
    # Decay History after each depth
    for c in White .. Black:
      for f in 0.Square .. 63.Square:
        for t in 0.Square .. 63.Square:
          historyTable[c][f][t] = historyTable[c][f][t] div 2
    
    # Stop if time expired
    if info.stopFlag != nil and info.stopFlag[].load(moRelaxed):
      break
    
  return (bestMove, bestScore)