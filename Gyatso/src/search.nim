import coretypes, board, move, movegen, evaluation, bitboard, tt, std/times,
    std/monotimes, std/atomics, see, zobrist, tables, history, timeman


var searchHistory* {.threadvar.}: HistoryTables
var searchStack* {.threadvar.}: array[MaxPly + 4, StackEntry]

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
  Contempt* = 20
  MultiCutM = 3 # Number of moves to test for Multi-Cut
  MultiCutC = 2 # Required cutoffs to trigger Multi-Cut pruning

proc qSearch(board: var Board, alpha: int, beta: int, ply: int,
    info: var SearchInfo): int =
  info.nodes.inc
  if info.nodes mod 2048 == 0:
    checkTime(info)
  if info.stopFlag != nil and info.stopFlag[].load(moRelaxed):
    return 0

  if ply > info.selDepth:
    info.selDepth = ply

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
    ml.scores[i] = scoreMove(board, ml.moves[i], Move(0), searchHistory,
        searchStack, ply, Move(0), Move(0))

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

proc negamax*(board: var Board, depth: int, alpha: int, beta: int, ply: int,
    info: var SearchInfo, totalExtensions: int = 0, prevMove: Move = Move(0)): int =

  info.nodes.inc
  if info.nodes mod 2048 == 0:
    checkTime(info)
  if info.stopFlag != nil and info.stopFlag[].load(moRelaxed):
    return 0

  if ply > info.selDepth:
    info.selDepth = ply

  var alpha = alpha
  var beta = beta
  var depth = depth # Make depth mutable for IIR

  if board.isRepetition() or board.halfMoveClock >= 100 or
      board.isInsufficientMaterial():
    return 0

  let excluded = Move(searchStack[ply].excluded)
  let (hit, ttScore, ttMove) = if excluded == Move(0):
      probeTT(board.currentZobristKey, depth, alpha, beta, board.gamePly)
    else:
      (false, 0, Move(0))

  if hit and ply > 1:
    return ttScore

  # Internal Iterative Reduction (IIR)
  let us = board.sideToMove
  let them = if us == White: Black else: White
  let kingSq = bitScanForward(board.pieceBB[makePiece(us, King)])
  let inCheck = isSquareAttacked(board, kingSq.Square, them)

  if depth > 3 and ttMove == Move(0) and not inCheck:
    depth -= 1

  # Mate distance pruning
  let mateInPly = MateValue - ply
  if mateInPly < beta:
    beta = mateInPly
    if alpha >= mateInPly:
      return mateInPly

  let matedInPly = -MateValue + ply + 1
  if matedInPly > alpha:
    alpha = matedInPly
    if beta <= matedInPly:
      return matedInPly

  if depth == 0:
    return qSearch(board, alpha, beta, ply, info)

  var ml: MoveList

  let staticEval = if inCheck: UNKNOWN else: evaluate(board)
  searchStack[ply].evaluation = staticEval

  let improving = (ply >= 2 and
                   searchStack[ply - 2].evaluation != UNKNOWN and
                   searchStack[ply].evaluation != UNKNOWN and
                   searchStack[ply].evaluation > searchStack[ply - 2].evaluation)

  # Reverse Futility Pruning
  if depth < 7 and ply > 0 and abs(beta) < MateValue and staticEval - (100 *
      depth) >= beta:
    return staticEval

  # Null Move Pruning (only when not in check and eval is known)
  if depth >= 3 and ply > 0 and staticEval != UNKNOWN and staticEval >= beta:
    if not inCheck:
      var hasNonPawnMaterial = false
      for pt in Knight .. Queen:
        if board.pieceBB[makePiece(us, pt)] != 0:
          hasNonPawnMaterial = true
          break

      if hasNonPawnMaterial:
        board.makeNullMove()
        # Adaptive Null Move Pruning
        let R = 2 + (depth div 6)
        let score = -negamax(board, depth - R - 1, -beta, -beta + 1, ply + 1,
            info, totalExtensions, Move(0))
        board.unmakeNullMove()

        if info.stopFlag != nil and info.stopFlag[].load(moRelaxed):
          return 0

        if score >= beta:
          return beta

  # ProbCut Pruning
  if depth >= 5 and ply > 0 and not inCheck and abs(beta) < MateValue:
    let probCutDepth = depth - 4

    var ttAlpha = beta
    var ttBeta = beta + 1
    let (ttHit, ttScore, _) = probeTT(board.currentZobristKey, probCutDepth,
        ttAlpha, ttBeta, board.gamePly)

    if not (ttHit and ttScore >= beta):
      let probBeta = beta + 110 # Empirically tuned margin

      var tacticalMoves {.noinit.}: MoveList
      tacticalMoves.count = 0
      generateLegalCaptures(board, tacticalMoves)

      for i in 0 ..< tacticalMoves.count:
        tacticalMoves.scores[i] = scoreMove(board, tacticalMoves.moves[i], Move(
            0), searchHistory, searchStack, ply, Move(0), Move(0))

      for i in 0 ..< tacticalMoves.count:
        let m = pickMove(tacticalMoves, i)

        discard board.makeMove(m)
        let score = -negamax(board, probCutDepth - 1, -probBeta, -probBeta + 1,
            ply + 1, info, totalExtensions, m)
        board.unmakeMove(m)

        if info.stopFlag != nil and info.stopFlag[].load(moRelaxed):
          return 0

        if score >= probBeta:
          return beta

  # Multi-Cut Pruning
  generateLegalMoves(board, ml)

  if ml.count == 0:
    if inCheck:
      return -MateValue + ply
    else:
      return 0

  var movesAlreadyScored = false

  # Apply Multi-Cut after move generation
  if depth >= 6 and ply > 0 and not inCheck and abs(beta) < MateValue and
      ml.count >= 4:
    let isPV = (beta - alpha) > 1
    if not isPV:
      # Score moves for Multi-Cut
      for i in 0 ..< ml.count:
        ml.scores[i] = scoreMove(board, ml.moves[i], ttMove, searchHistory,
            searchStack, ply, prevMove, if ply > 1: Move(searchStack[
            ply-2].move) else: Move(0))

      movesAlreadyScored = true

      var multiCutCount = 0
      let multiCutDepth = depth - 3
      let movesToTest = min(MultiCutM, ml.count)

      for i in 0 ..< movesToTest:
        let m = pickMove(ml, i)
        discard board.makeMove(m)
        let score = -negamax(board, multiCutDepth, -beta, -beta + 1, ply + 1,
            info, totalExtensions, m)
        board.unmakeMove(m)

        if info.stopFlag != nil and info.stopFlag[].load(moRelaxed):
          return 0

        if score >= beta:
          multiCutCount.inc
          if multiCutCount >= MultiCutC:
            return beta # Multi-Cut pruning

  var maxEval = -Infinity
  var bestMove = Move(0)
  let originalAlpha = alpha
  let grandParentMove = if ply > 1: Move(searchStack[ply-2].move) else: Move(0)

  # Score moves if not already scored by Multi-Cut
  if not movesAlreadyScored:
    for i in 0 ..< ml.count:
      ml.scores[i] = scoreMove(board, ml.moves[i], ttMove, searchHistory,
          searchStack, ply, prevMove, grandParentMove)

  var movesSearched = 0

  for i in 0 ..< ml.count:
    let m = pickMove(ml, i)

    if m == excluded:
      continue

    # Futility Pruning - prune quiet moves if eval is too low
    if movesSearched > 0 and depth < 7 and not inCheck and not m.isCapture and
        not m.isPromotion:
      let margin = 100 * depth
      if staticEval + margin < alpha:
        continue

    # SEE Pruning for quiet moves (using StaticPruning table)
    if movesSearched > 0 and not m.isCapture and not m.isPromotion and depth < MaxPly:
      if see(board, m) < StaticPruning[0][depth]:
        continue

    # SEE Pruning for bad captures (using StaticPruning table)
    if movesSearched > 0 and m.isCapture and depth < MaxPly:
      if see(board, m) < StaticPruning[1][depth]:
        continue

    searchStack[ply].move = uint32(m)
    discard board.makeMove(m)

    # Check Extension
    let opponent = board.sideToMove
    let opponentIsWhite = opponent == White
    let weAre = if opponentIsWhite: Black else: White
    let oppKingSq = bitScanForward(board.pieceBB[makePiece(opponent, King)])
    let givesCheck = isSquareAttacked(board, oppKingSq.Square, weAre)

    var extension = 0

    # Singular extension - only for TT move with proper conditions
    if m == ttMove and depth > 6 and excluded == Move(0) and not inCheck:
      let (ttHit, ttEntry) = getTTEntry(board.currentZobristKey)
      if ttHit and ttEntry.depth >= (depth - 3).int8 and ttEntry.flag ==
          LowerBound and abs(ttScore) < MateValue:
        let singularBeta = ttScore - 3 * depth div 2
        let singularDepth = depth div 2 - 1
        let isPV = (beta - alpha) > 1

        searchStack[ply].excluded = uint32(m)
        board.unmakeMove(m) # Unmake to search from current position
        let singularScore = negamax(board, singularDepth, singularBeta - 1,
            singularBeta, ply, info, totalExtensions, prevMove)
        discard board.makeMove(m) # Remake the move
        searchStack[ply].excluded = 0

        if info.stopFlag != nil and info.stopFlag[].load(moRelaxed):
          board.unmakeMove(m)
          return 0

        # Determine extension
        if singularScore < singularBeta:
          # Move is singular
          if singularScore < singularBeta - 50 and not isPV:
            extension = 2 # Double extension
          else:
            extension = 1 # Single extension
        elif singularBeta >= beta:
          board.unmakeMove(m)
          return singularBeta

    # Check extension
    if extension == 0 and givesCheck:
      extension = 1

    # Cap total extensions to prevent search explosion
    if totalExtensions + extension >= 16:
      extension = 0

    var newDepth = depth - 1 + extension
    if newDepth < 0: newDepth = 0

    var score = -Infinity

    if movesSearched == 0:
      # First move - Full Window
      score = -negamax(board, newDepth, -beta, -alpha, ply + 1, info,
          totalExtensions + extension, m)
    else:
      # Late Move Reductions using pre-computed LMR table
      var reduction = 0
      if depth >= 3 and movesSearched >= 1:
        # Base reduction from table
        let tableDepth = min(depth, MaxPly - 1)
        let tableIndex = min(movesSearched, 63)
        reduction = LMR[tableDepth][tableIndex]

        # Adjust reduction based on move characteristics
        if m.isCapture or m.isPromotion:
          reduction = reduction div 2 # Reduce less for tactical moves
        if givesCheck:
          reduction = max(0, reduction - 1)
        if inCheck:
          reduction = max(0, reduction - 1)

        # Ensure reduction is valid
        reduction = max(0, min(reduction, depth - 1))

      # Null Window Search with reduction
      score = -negamax(board, newDepth - reduction, -alpha - 1, -alpha, ply + 1,
          info, totalExtensions + extension, m)

      # Re-search if reduced and score raised alpha
      if reduction > 0 and score > alpha:
        score = -negamax(board, newDepth, -alpha - 1, -alpha, ply + 1, info,
            totalExtensions + extension, m)

      # PVS Re-search with full window
      if score > alpha and score < beta:
        score = -negamax(board, newDepth, -beta, -alpha, ply + 1, info,
            totalExtensions + extension, m)

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
        # Killer Move Heuristic Update
        let killer0 = Move(searchStack[ply].killers[0])
        if killer0 != m:
          searchStack[ply].killers[1] = uint32(killer0)
          searchStack[ply].killers[0] = uint32(m)

      # History Heuristic Update (Main, Counter, FollowUp, Tactical, CounterMoves)
      let grandParentMove = if ply > 1: Move(searchStack[
          ply-2].move) else: Move(0)

      updateHistories(searchHistory, board, ml, i, depth, prevMove, grandParentMove)

      break

  # TT Store
  # Clamp score to avoid Infinity leaks
  var storeScore = maxEval
  if storeScore >= MateValue: storeScore = MateValue
  elif storeScore <= -MateValue: storeScore = -MateValue

  storeTT(board, depth, storeScore, originalAlpha, beta, bestMove)

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

proc iterativeDeepening*(board: var Board, info: var SearchInfo,
    threadID: int = 0): (Move, int) =
  info.startTime = getMonoTime()
  info.startTime = getMonoTime()
  info.nodes = 0
  info.selDepth = 0

  # Clear killers in search stack and init evaluations
  for i in 0 ..< MaxPly + 4:
    searchStack[i].killers[0] = 0
    searchStack[i].killers[1] = 0
    searchStack[i].excluded = 0
    searchStack[i].excluded = 0
    searchStack[i].evaluation = UNKNOWN

  searchStack[0].move = 0

  initHistory(searchHistory)

  var bestMove = Move(0)
  var bestScore = -Infinity

  var timeManager: TimeManager
  if threadID == 0 and info.allocatedTime != DurationZero:
    let movesToGo = if info.movesToGo > 0: min(40, info.movesToGo) else: 30
    timeManager = initTimeManager(info.allocatedTime, info.allocatedTime,
        info.increment, movesToGo)

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
    var aspirationFails = 0 # Track aspiration failures

    # Aspiration window loop
    while true:
      var alpha = -Infinity
      var beta = Infinity

      if depth >= 3:
        alpha = max(-Infinity, aspirationScore - alphaWindow)
        beta = min(Infinity, aspirationScore + betaWindow)

      var ml: MoveList
      generateLegalMoves(board, ml)

      if ml.count == 0:
        return (bestMove, bestScore)

      let (hit, ttScore, ttMove) = probeTT(board.currentZobristKey, depth,
          alpha, beta, board.gamePly)

      for i in 0 ..< ml.count:
        ml.scores[i] = scoreMove(board, ml.moves[i], ttMove, searchHistory,
            searchStack, 0, Move(0), Move(0))

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

        searchStack[1].move = uint32(m)
        discard board.makeMove(m)

        var val = -Infinity
        if i == 0:
          val = -negamax(board, depth - 1, -beta, -alpha, 1, info, 0, Move(0))
        else:
          # Null window search
          val = -negamax(board, depth - 1, -alpha - 1, -alpha, 1, info, 0, Move(0))
          if val > alpha and val < beta:
            val = -negamax(board, depth - 1, -beta, -alpha, 1, info, 0, Move(0))

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

      if info.stopFlag != nil and info.stopFlag[].load(moRelaxed):
        break

      # Aspiration window logic
      if depth >= 3:
        let alphaStart = max(-Infinity, aspirationScore - alphaWindow)
        let betaStart = min(Infinity, aspirationScore + betaWindow)

        if currentBestScore <= alphaStart:
          alphaWindow *= 2
          aspirationScore = currentBestScore
          aspirationFails += 1
          if threadID == 0 and info.allocatedTime != DurationZero:
            timeManager.keepSearching()
          continue
        elif currentBestScore >= betaStart:
          betaWindow *= 2
          aspirationScore = currentBestScore
          aspirationFails += 1
          if threadID == 0 and info.allocatedTime != DurationZero:
            timeManager.keepSearching()
          continue

      # Within window or depth < 3
      break

    if info.stopFlag != nil and info.stopFlag[].load(moRelaxed):
      break

    if currentBestMove != Move(0):
      bestMove = currentBestMove
      bestScore = currentBestScore

    if threadID == 0 and info.allocatedTime != DurationZero and depth > 4:
      timeManager.updateStability(bestMove)
      timeManager.updateScoreOscillation(bestScore)

      if timeManager.shouldStopEarly():
        if info.stopFlag != nil:
          info.stopFlag[].store(true, moRelaxed)

    if threadID == 0:
      if bestMove == Move(0):
        var ml: MoveList
        generateLegalMoves(board, ml)
        if ml.count > 0:
          bestMove = ml.moves[0]

      var totalNodes = info.nodes
      if info.nodeCounts != nil:
        for i in 0 ..< info.numThreads:
          if i != threadID:
            totalNodes += info.nodeCounts[i]

      let elapsed = (getMonoTime() - info.startTime).inMilliseconds
      let nps = if elapsed > 0: (totalNodes.float / (elapsed.float /
          1000.0)).int else: 0

      if info.stopFlag == nil or not info.stopFlag[].load(moRelaxed):
        var rootScore = bestScore
        if rootScore >= MateValue: rootScore = MateValue
        elif rootScore <= -MateValue: rootScore = -MateValue

        storeTT(board, depth, rootScore, -Infinity, Infinity, bestMove)

        let pvLine = getPV(board, depth)

        var scoreStr = ""
        if abs(bestScore) > 20000 and abs(bestScore) <= MateValue:
          let safeScore = if bestScore > 0: min(bestScore, MateValue) else: max(
              bestScore, -MateValue)
          let mateDistance = (MateValue - abs(safeScore) + 1) div 2
          if bestScore > 0:
            scoreStr = "mate " & $mateDistance
          else:
            scoreStr = "mate -" & $mateDistance
        else:
          scoreStr = "cp " & $bestScore

        echo "info depth ", depth, " seldepth ", info.selDepth, " score ",
            scoreStr, " nodes ", totalNodes, " nps ", nps, " hashfull ",
            getHashfull(), " time ", elapsed, " pv ", pvLine

    if info.stopFlag != nil and info.stopFlag[].load(moRelaxed):
      break

  return (bestMove, bestScore)
