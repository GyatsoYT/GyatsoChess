import coretypes, board, move, movegen, evaluation, bitboard, tt, std/times,
    std/monotimes, std/atomics, see, tables, timeman,
    nnuetypes, nnue, history

var historyTable* {.threadvar.}: HistoryTables
var searchStack* {.threadvar.}: array[MaxPly + 4, StackEntry]
var nnueState* {.threadvar.}: NNUEState

# PV Table Implementation
type
  PVTable = array[MaxPly, array[MaxPly, Move]]

var pvTable {.threadvar.}: PVTable
var pvLength {.threadvar.}: array[MaxPly, int]

proc initPV(ply: int) {.inline.} =
  pvLength[ply] = ply

template updatePV(ply: int, m: Move) =
  pvTable[ply][ply] = m
  for i in (ply + 1) ..< pvLength[ply + 1]:
    pvTable[ply][i] = pvTable[ply + 1][i]
  pvLength[ply] = pvLength[ply + 1]

proc checkTime*(info: var SearchInfo) =
  if info.nodes mod 2048 == 0:
    # Sync node count to shared array FIRST
    if info.nodeCounts != nil:
      info.nodeCounts[info.threadID] = info.nodes

    # Then check stop flag
    if info.stopFlag != nil and info.stopFlag[].load(moRelaxed):
      return

    # Node limit check
    if info.nodeLimit > 0 and info.nodes >= info.nodeLimit:
      if info.stopFlag != nil:
        info.stopFlag[].store(true, moRelaxed)
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

proc qSearch*(board: var Board, alpha: int, beta: int, ply: int,
    info: var SearchInfo): int =
  info.nodes.inc
  if info.nodes mod 2048 == 0:
    checkTime(info)
  if info.stopFlag != nil and info.stopFlag[].load(moRelaxed):
    return 0

  if ply > info.selDepth:
    info.selDepth = ply

  var alpha = alpha
  let standPat = evaluate(board, nnueState)

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
  generatePseudoLegalCaptures(board, ml)

  let phase = getGamePhase(board)

  # Score moves
  for i in 0 ..< ml.count:
    ml.scores[i] = scoreMove(board, ml.moves[i], Move(0),
        searchStack, ply, phase, historyTable)

  for i in 0 ..< ml.count:
    let m = pickMove(ml, i)

    # SEE Pruning for bad captures
    if not m.isPromotion and see(board, m, phase) < 0:
      continue

    pushAccumulator(addr gNetwork, board, m, nnueState)
    if not board.makeMove(m):
      popAccumulator(nnueState)
      continue  # illegal move, skip
    prefetchTT(board.currentZobristKey)
    let score = -qSearch(board, -beta, -alpha, ply + 1, info)
    board.unmakeMove(m)
    popAccumulator(nnueState)

    if info.stopFlag != nil and info.stopFlag[].load(moRelaxed):
      return 0

    if score >= beta:
      return beta

    if score > alpha:
      alpha = score

  return alpha

proc negamax*(board: var Board, depth: int, alpha: int, beta: int, ply: int,
    info: var SearchInfo, totalExtensions: int = 0): int =

  initPV(ply)

  # Clear ply+1 killers at the start of each negamax call
  if ply + 1 < MaxPly:
    searchStack[ply + 1].killers[0] = 0
    searchStack[ply + 1].killers[1] = 0

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
  let (hit, ttScore, ttMove, _) = if excluded == Move(0):
      probeTT(board.currentZobristKey, depth, alpha, beta, board.gamePly)
    else:
      (false, 0, Move(0), 0'i16)

  if hit and ply > 1:
    return ttScore

  let (seHit, seEntry) = getTTEntry(board.currentZobristKey)

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

  let staticEval = if inCheck: UNKNOWN else: evaluate(board, nnueState)
  let phase = getGamePhase(board)
  searchStack[ply].evaluation = staticEval

  # Improving flag and delta (improvement) calculation
  var improving = false
  var improvement = 0
  if not inCheck and staticEval != UNKNOWN:
    if ply >= 2 and searchStack[ply - 2].evaluation != UNKNOWN:
      improvement = staticEval - searchStack[ply - 2].evaluation
      improving = improvement > 0
    elif ply >= 4 and searchStack[ply - 4].evaluation != UNKNOWN:
      improvement = staticEval - searchStack[ply - 4].evaluation
      improving = improvement > 0
    else:
      improving = true  # no data, assume improving

  # Reverse Futility Pruning
  if depth < 7 and ply > 0 and abs(beta) < MateValue and staticEval != UNKNOWN:
    let rfpMargin = 100 * depth - clamp(improvement div 2, -80, 80)
    if staticEval - rfpMargin >= beta:
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
        searchStack[ply].move = 0
        searchStack[ply].movedPiece = NoPiece
        pushNullMove(nnueState)
        board.makeNullMove()
        # Adaptive Null Move Pruning
        let R = 2 + (depth div 4)
        let score = -negamax(board, depth - R - 1, -beta, -beta + 1, ply + 1,
            info, totalExtensions)
        board.unmakeNullMove()
        popNullMove(nnueState)

        if info.stopFlag != nil and info.stopFlag[].load(moRelaxed):
          return 0

        if score >= beta:
          return beta

  # ProbCut Pruning
  if depth >= 5 and ply > 0 and not inCheck and abs(beta) < MateValue:
    let probCutDepth = depth - 4

    var ttAlpha = beta
    var ttBeta = beta + 1
    let (ttHit, ttScore, _, _) = probeTT(board.currentZobristKey, probCutDepth,
        ttAlpha, ttBeta, board.gamePly)

    if not (ttHit and ttScore >= beta):
      let probBeta = beta + 110 # Empirically tuned margin

      var tacticalMoves {.noinit.}: MoveList
      tacticalMoves.count = 0
      generatePseudoLegalCaptures(board, tacticalMoves)

      for i in 0 ..< tacticalMoves.count:
        tacticalMoves.scores[i] = scoreMove(board, tacticalMoves.moves[i], Move(
            0), searchStack, ply, phase, historyTable)

      for i in 0 ..< tacticalMoves.count:
        let m = pickMove(tacticalMoves, i)

        pushAccumulator(addr gNetwork, board, m, nnueState)
        if not board.makeMove(m):
          popAccumulator(nnueState)
          continue
        let score = -negamax(board, probCutDepth - 1, -probBeta, -probBeta + 1,
            ply + 1, info, totalExtensions)
        board.unmakeMove(m)
        popAccumulator(nnueState)

        if info.stopFlag != nil and info.stopFlag[].load(moRelaxed):
          return 0

        if score >= probBeta:
          return beta

  # Multi-Cut Pruning
  if depth >= 6 and ply > 0 and not inCheck and abs(beta) < MateValue:
    let isPV = (beta - alpha) > 1
    if not isPV:
      var mcMoves {.noinit.}: MoveList
      mcMoves.count = 0
      generatePseudoLegalCaptures(board, mcMoves)
      for i in 0 ..< mcMoves.count:
        mcMoves.scores[i] = scoreMove(board, mcMoves.moves[i], ttMove,
            searchStack, ply, phase, historyTable)

      var multiCutCount = 0
      let multiCutDepth = depth - 3
      let movesToTest = min(MultiCutM, mcMoves.count)

      for i in 0 ..< movesToTest:
        let m = pickMove(mcMoves, i)
        pushAccumulator(addr gNetwork, board, m, nnueState)
        if not board.makeMove(m):
          popAccumulator(nnueState)
          continue
        let score = -negamax(board, multiCutDepth, -beta, -beta + 1, ply + 1,
            info, totalExtensions)
        board.unmakeMove(m)
        popAccumulator(nnueState)

        if info.stopFlag != nil and info.stopFlag[].load(moRelaxed):
          return 0

        if score >= beta:
          multiCutCount.inc
          if multiCutCount >= MultiCutC:
            return beta # Multi-Cut pruning

  var maxEval = -Infinity
  var bestMove = Move(0)
  let originalAlpha = alpha

  # Track quiet moves tried (for history malus on cutoff)
  var quietsTried: array[MaxMoves, Move]
  var quietsTriedCount = 0

  var movesSearched = 0
  let isPVNode = (beta - alpha) > 1

  # Staged move picker
  let killerMove = if searchStack[ply].killers[0] != 0: Move(searchStack[ply].killers[0]) else: Move(0)
  var picker = initMovePicker(ttMove, killerMove, phase)

  while true:
    let m = picker.next(board, historyTable, searchStack, ply)
    if m == Move(0): break

    if m == excluded:
      continue

    let isQuiet = not m.isCapture and not m.isPromotion

    # Late Move Pruning (LMP) - skip quiet moves late in the move list at shallow depths
    if movesSearched > 0 and depth < 7 and not inCheck and not isPVNode and
        isQuiet and movesSearched >= LateMovePruning[depth] and
        staticEval >= alpha - 200:
      continue

    if movesSearched > 0 and depth < 7 and not inCheck and isQuiet:
      let margin = 100 * depth
      if staticEval + margin < alpha:
        continue

    # SEE Pruning for quiet moves (using StaticPruning table)
    if movesSearched > 0 and isQuiet and depth < MaxPly:
      if see(board, m, phase) < StaticPruning[0][depth]:
        continue

    # SEE Pruning for bad captures (using StaticPruning table)
    if movesSearched > 0 and m.isCapture and depth < MaxPly:
      if see(board, m, phase) < StaticPruning[1][depth]:
        continue

    # Track quiet moves tried (before making the move)
    if isQuiet:
      quietsTried[quietsTriedCount] = m
      quietsTriedCount.inc

    let movingPieceForStack = board.pieces[m.fromSquare]
    searchStack[ply].move = uint32(m)
    searchStack[ply].movedPiece = movingPieceForStack
    pushAccumulator(addr gNetwork, board, m, nnueState)
    if not board.makeMove(m):
      popAccumulator(nnueState)
      # Undo the quiet tracking if move was illegal
      if isQuiet and quietsTriedCount > 0:
        quietsTriedCount.dec
      continue

    prefetchTT(board.currentZobristKey)
    
    # Check Extension
    let opponent = board.sideToMove
    let opponentIsWhite = opponent == White
    let weAre = if opponentIsWhite: Black else: White
    let oppKingSq = bitScanForward(board.pieceBB[makePiece(opponent, King)])
    let givesCheck = isSquareAttacked(board, oppKingSq.Square, weAre)

    var extension = 0

    # Singular extension - only for TT move with proper conditions
    if m == ttMove and depth > 6 and excluded == Move(0) and not inCheck:
      if seHit and seEntry.depth >= (depth - 3).int8 and
          seEntry.flag == LowerBound and abs(ttScore) < MateValue:
        let singularBeta = ttScore - 3 * depth div 2
        let singularDepth = depth div 2 - 1
        let savedKiller0 = searchStack[ply].killers[0]
        let savedKiller1 = searchStack[ply].killers[1]
        let savedEval    = searchStack[ply].evaluation

        searchStack[ply].excluded = uint32(m)
        board.unmakeMove(m) # Unmake to search from current position
        popAccumulator(nnueState)
        let singularScore = negamax(board, singularDepth, singularBeta - 1,
            singularBeta, ply, info, totalExtensions)
        pushAccumulator(addr gNetwork, board, m, nnueState)
        discard board.makeMove(m) # Remake the move
        searchStack[ply].excluded = 0
        searchStack[ply].killers[0]  = savedKiller0
        searchStack[ply].killers[1]  = savedKiller1
        searchStack[ply].evaluation  = savedEval
        searchStack[ply].move        = uint32(m)
        searchStack[ply].movedPiece  = movingPieceForStack

        if info.stopFlag != nil and info.stopFlag[].load(moRelaxed):
          board.unmakeMove(m)
          popAccumulator(nnueState)
          return 0

        # Determine extension
        if singularScore < singularBeta:
          # Move is singular
          if singularScore < singularBeta - 50 and not isPVNode:
            extension = 2 # Double extension
          else:
            extension = 1 # Single extension
        elif singularBeta >= beta:
          board.unmakeMove(m)
          popAccumulator(nnueState)
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
          totalExtensions + extension)
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

        # History-based LMR adjustment: reduce less for good history, more for bad
        if isQuiet:
          let colorIdx = us.ord
          var histScore = historyTable.mainHistory[colorIdx][historyIndex(m)].int
          # Add continuation history if available
          if ply > 0 and searchStack[ply - 1].move != 0:
            let prevPiece = searchStack[ply - 1].movedPiece
            if prevPiece != NoPiece:
              let prevTo = Move(searchStack[ply - 1].move).toSquare.int
              let currPiece = board.pieces[m.fromSquare]
              histScore += historyTable.contHistory[prevPiece][prevTo][currPiece][m.toSquare.int].int
          reduction -= histScore div 8192

        # Extra reduction for quiet moves when not improving
        if isQuiet and not improving:
          reduction += 1

        # Ensure reduction is valid
        reduction = max(0, min(reduction, depth - 1))

      # Null Window Search with reduction
      score = -negamax(board, newDepth - reduction, -alpha - 1, -alpha, ply + 1,
          info, totalExtensions + extension)

      # Re-search if reduced and score raised alpha
      if reduction > 0 and score > alpha:
        score = -negamax(board, newDepth, -alpha - 1, -alpha, ply + 1, info,
            totalExtensions + extension)

      # PVS Re-search with full window
      if score > alpha and score < beta:
        score = -negamax(board, newDepth, -beta, -alpha, ply + 1, info,
            totalExtensions + extension)

    board.unmakeMove(m)
    popAccumulator(nnueState)
    movesSearched.inc

    if info.stopFlag != nil and info.stopFlag[].load(moRelaxed):
      return 0

    if score > maxEval:
      maxEval = score
      bestMove = m

    if maxEval > alpha:
      alpha = maxEval
      updatePV(ply, m) # Update PV if we improved alpha

    if alpha >= beta:
      # Beta Cutoff — update history for quiet best moves
      if ply > 0 and not m.isCapture and not m.isPromotion:
        let bonus = min(depth * depth + 2 * depth, 400)
        let malus = -bonus
        let colorIdx = us.ord
        # Bonus for the move that caused cutoff
        updateHistoryStat(historyTable.mainHistory[colorIdx][historyIndex(m)], bonus)
        # Malus for all quiets tried before the cutoff move
        for qi in 0 ..< quietsTriedCount - 1:  # -1 because bestMove is the last quiet added
          let qm = quietsTried[qi]
          updateHistoryStat(historyTable.mainHistory[colorIdx][historyIndex(qm)], malus)
        # 1-ply continuation history bonus/malus
        if searchStack[ply - 1].movedPiece != NoPiece:
          let prevPiece = searchStack[ply - 1].movedPiece
          let prevTo = Move(searchStack[ply - 1].move).toSquare.int
          let currPiece = board.pieces[m.fromSquare]
          updateHistoryStat(historyTable.contHistory[prevPiece][prevTo][currPiece][m.toSquare.int], bonus)
          for qi in 0 ..< quietsTriedCount - 1:
            let qm = quietsTried[qi]
            let qPiece = board.pieces[qm.fromSquare]
            updateHistoryStat(historyTable.contHistory[prevPiece][prevTo][qPiece][qm.toSquare.int], malus)
        # Update killers
        if searchStack[ply].killers[0] != uint32(m):
          searchStack[ply].killers[1] = searchStack[ply].killers[0]
          searchStack[ply].killers[0] = uint32(m)

      break

  # Checkmate / Stalemate detection
  if movesSearched == 0:
    if inCheck:
      return -MateValue + ply
    else:
      return 0

  # TT Store
  # Clamp score to avoid Infinity leaks
  var storeScore = maxEval
  if storeScore >= MateValue: storeScore = MateValue
  elif storeScore <= -MateValue: storeScore = -MateValue

  storeTT(board, depth, storeScore, originalAlpha, beta, bestMove, staticEval)

  return maxEval

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
    searchStack[i].move = 0
    searchStack[i].movedPiece = NoPiece

  searchStack[0].move = 0

  # Init history
  initHistory(historyTable)

  # Initialize NNUE accumulators from scratch for this position
  refreshState(addr gNetwork, board, nnueState)

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
    var alphaWindow = 20
    var betaWindow = 20
    var aspirationScore = bestScore

    var currentBestMove = Move(0)
    var currentBestScore = -Infinity
    var aspirationFails = 0 # Track aspiration failures
    var failHighCount = 0
    var searchDepth = depth

    # Aspiration window loop
    while true:
      var alpha = -Infinity
      var beta = Infinity

      if depth >= 3:
        alpha = max(-Infinity, aspirationScore - alphaWindow)
        beta = min(Infinity, aspirationScore + betaWindow)

      var ml: MoveList
      generateLegalMoves(board, ml)
      let phase = getGamePhase(board)

      if ml.count == 0:
        return (bestMove, bestScore)

      let (hit, ttScore, ttMove, _) = probeTT(board.currentZobristKey, depth,
          alpha, beta, board.gamePly)

      for i in 0 ..< ml.count:
        ml.scores[i] = scoreMove(board, ml.moves[i], ttMove,
            searchStack, 0, phase, historyTable)

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

        searchStack[0].move = uint32(m)
        searchStack[0].movedPiece = board.pieces[m.fromSquare]
        searchStack[1].move = uint32(m)
        pushAccumulator(addr gNetwork, board, m, nnueState)
        discard board.makeMove(m)

        var val = -Infinity
        if i == 0:
          val = -negamax(board, searchDepth - 1, -beta, -alpha, 1, info, 0)
        else:
          # Null window search
          val = -negamax(board, searchDepth - 1, -alpha - 1, -alpha, 1, info, 0)
          if val > alpha and val < beta:
            val = -negamax(board, searchDepth - 1, -beta, -alpha, 1, info, 0)

        board.unmakeMove(m)
        popAccumulator(nnueState)

        if info.stopFlag != nil and info.stopFlag[].load(moRelaxed):
          break

        if val > currentBestScore:
          currentBestScore = val
          currentBestMove = m

        if currentBestScore > alpha:
          alpha = currentBestScore
          # Ensure PV table is updated for the root
          updatePV(0, m)

        if currentBestScore >= beta:
          break

      if info.stopFlag != nil and info.stopFlag[].load(moRelaxed):
        break

      # Aspiration window logic
      if depth >= 3:
        let alphaStart = max(-Infinity, aspirationScore - alphaWindow)
        let betaStart = min(Infinity, aspirationScore + betaWindow)

        if currentBestScore <= alphaStart:
          alphaWindow = (alphaWindow * 3) div 2
          aspirationScore = currentBestScore
          aspirationFails += 1
          failHighCount = 0
          searchDepth = depth
          if threadID == 0 and info.allocatedTime != DurationZero:
            timeManager.keepSearching()
          continue
        elif currentBestScore >= betaStart:
          betaWindow = (betaWindow * 3) div 2
          aspirationScore = currentBestScore
          aspirationFails += 1
          inc failHighCount
          if failHighCount <= 2:
            searchDepth = depth - failHighCount
          else:
            searchDepth = depth  # too many failures, search full depth
          if threadID == 0 and info.allocatedTime != DurationZero:
            timeManager.keepSearching()
          continue

      # Within window or depth < 3
      searchDepth = depth
      failHighCount = 0
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

        # Construct PV string from PV table
        var pvLine = ""
        for i in 0 ..< pvLength[0]:
          pvLine.add(pvTable[0][i].toAlgebraic() & " ")

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

proc searchNodes*(board: var Board, nodes: int): (Move, int) =
  ## Standalone node-limited search for datagen.
  ## Calls iterativeDeepening directly — no threading, no UCI.
  var stopFlag: Atomic[bool]
  stopFlag.store(false, moRelaxed)

  var info: SearchInfo
  info.startTime = getMonoTime()
  info.allocatedTime = DurationZero
  info.depthLimit = 0
  info.nodeLimit = nodes.uint64
  info.stopFlag = addr stopFlag
  info.ponderFlag = nil
  info.nodeCounts = nil
  info.threadID = 0
  info.numThreads = 1
  info.nodes = 0
  info.selDepth = 0

  return iterativeDeepening(board, info, threadID = -1)
