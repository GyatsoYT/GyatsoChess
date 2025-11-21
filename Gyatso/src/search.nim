import coretypes, board, move, movegen, evaluation, bitboard, tt, std/times, std/monotimes

type
  TimeLimit* = object
    startTime*: MonoTime
    allocatedTime*: Duration
    depthLimit*: int
    nodes*: uint64
    stopFlag*: ptr bool

var searchTimeLimit*: TimeLimit

proc checkTime*() =
  if searchTimeLimit.stopFlag != nil and searchTimeLimit.stopFlag[]: return
  if searchTimeLimit.nodes mod 2048 == 0:
    let elapsed = getMonoTime() - searchTimeLimit.startTime
    if elapsed > searchTimeLimit.allocatedTime and searchTimeLimit.allocatedTime != DurationZero:
      if searchTimeLimit.stopFlag != nil:
        searchTimeLimit.stopFlag[] = true

const
  Infinity* = 30000
  MateValue* = 29000 # Slightly less than Infinity to allow for mate distance logic

proc qSearch(board: var Board, alpha: int, beta: int, ply: int): int =
  searchTimeLimit.nodes.inc
  if searchTimeLimit.nodes mod 2048 == 0:
    checkTime()
  if searchTimeLimit.stopFlag != nil and searchTimeLimit.stopFlag[]: return 0

  var alpha = alpha
  let standPat = evaluate(board)
  
  if standPat >= beta:
    return beta
    
  if standPat > alpha:
    alpha = standPat
    
  var ml: MoveList
  generateLegalMoves(board, ml)
  
  # Score Moves (only captures/promotions relevant, but we score all for simplicity of reuse)
  # Optimization: Could have a specialized generateCaptures
  
  # We need a dummy move for scoring (no TT move in QSearch usually, or passed from negamax?)
  # For now, Move(0)
  for i in 0 ..< ml.count:
    ml.scores[i] = scoreMove(board, ml.moves[i], Move(0))
    
  for i in 0 ..< ml.count:
    let m = pickMove(ml, i)
    
    # Only consider captures and promotions
    if not m.isCapture and not m.isPromotion:
      continue
      
    discard board.makeMove(m)
    let score = -qSearch(board, -beta, -alpha, ply + 1)
    board.unmakeMove(m)
    
    if searchTimeLimit.stopFlag != nil and searchTimeLimit.stopFlag[]: return 0
    
    if score >= beta:
      return beta
      
    if score > alpha:
      alpha = score
      
  return alpha

proc negamax(board: var Board, depth: int, alpha: int, beta: int, ply: int): int =
  searchTimeLimit.nodes.inc
  if searchTimeLimit.nodes mod 2048 == 0:
    checkTime()
  if searchTimeLimit.stopFlag != nil and searchTimeLimit.stopFlag[]: return 0

  var alpha = alpha
  var beta = beta
  
  # TT Probe
  let (hit, ttScore, ttMove) = probeTT(board.currentZobristKey, depth, alpha, beta, ply)
  if hit:
    return ttScore

  if depth == 0:
    return qSearch(board, alpha, beta, ply)
    
  var ml: MoveList
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
  
  for i in 0 ..< ml.count:
    let m = pickMove(ml, i)
    discard board.makeMove(m)
    let eval = -negamax(board, depth - 1, -beta, -alpha, ply + 1)
    board.unmakeMove(m)
    
    if eval > maxEval:
      maxEval = eval
      bestMove = m
      
    if maxEval > alpha:
      alpha = maxEval
      
    if alpha >= beta:
      break # Beta Cutoff
  
  # TT Store
  storeTT(board, depth, maxEval, originalAlpha, beta, bestMove, ply)
      
  return maxEval

proc iterativeDeepening*(board: var Board, timeLimit: TimeLimit): (Move, int) =
  searchTimeLimit = timeLimit
  searchTimeLimit.startTime = getMonoTime()
  searchTimeLimit.nodes = 0
  # stopFlag is managed by caller
  
  var bestMove = Move(0)
  var bestScore = -Infinity
  
  # If depth limit is 0, set it to max
  let maxDepth = if timeLimit.depthLimit > 0: timeLimit.depthLimit else: 64
  
  for depth in 1 .. maxDepth:
    var alpha = -Infinity
    var beta = Infinity
    
    # Root search logic inside ID loop
    var ml: MoveList
    generateLegalMoves(board, ml)
    if ml.count == 0: break # Game over
    
    var currentBestMove = Move(0)
    var currentBestScore = -Infinity
    
    # Get TT Move for ordering
    # Get TT Move for ordering
    let (hit, ttScore, ttMove) = probeTT(board.currentZobristKey, depth, alpha, beta, 0)
    
    # Score Moves
    for i in 0 ..< ml.count:
      ml.scores[i] = scoreMove(board, ml.moves[i], ttMove)
    
    for i in 0 ..< ml.count:
      let m = pickMove(ml, i)
      discard board.makeMove(m)
      let score = -negamax(board, depth - 1, -beta, -alpha, 1)
      board.unmakeMove(m)
      
      if searchTimeLimit.stopFlag != nil and searchTimeLimit.stopFlag[]: break
      
      if score > currentBestScore:
        currentBestScore = score
        currentBestMove = m
        
      if currentBestScore > alpha:
        alpha = currentBestScore
        
    if searchTimeLimit.stopFlag != nil and searchTimeLimit.stopFlag[]:
      break
      
    bestMove = currentBestMove
    bestScore = currentBestScore
    
    let elapsed = (getMonoTime() - searchTimeLimit.startTime).inMilliseconds
    let nps = if elapsed > 0: (searchTimeLimit.nodes.float / (elapsed.float / 1000.0)).int else: 0
    
    echo "info depth ", depth, " score cp ", bestScore, " nodes ", searchTimeLimit.nodes, " nps ", nps, " time ", elapsed, " pv ", bestMove.toAlgebraic()
    
    # Check if we used up too much time (soft limit check could go here)
    
  return (bestMove, bestScore)
