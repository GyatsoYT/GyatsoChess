# search.nim

import std/[algorithm, times, sequtils] 
import types, position, move, movegen, evaluation 

# --- Type Definitions ---
# Moved SearchResult to the top and export it
type
  SearchResult* = object # Exported for uci.nim
    bestMove*: Move
    score*: Value
    pv*: seq[Move]
    nodes*: uint64
  InfoCallback* = proc(depth: Ply, score: Value, iterNodes: uint64, totalTimeMs: int, pv: seq[Move])
  SearchStoppedError* = object of CatchableError # Inherit from CatchableError

const
  MaxSearchPly* = 64.Ply    # Max ply depth for search functions (not necessarily IDS depth)
                            # Explicitly .Ply to ensure type
  MaxMovesBuffer* = 320     # Max pseudo-legal moves buffer
  NodeCheckInterval = 2048  # Check time/nodes every N nodes

var
  nodesSearchedGlobal*: uint64    # Exported for uci.nim
  searchStopTimeEpochGlobal: float 
  searchMaxNodesGlobal: uint64   
  searchCancelledFlagGlobal*: bool # Exported for uci.nim 'stop'

# --- Move Ordering ---
proc getMoveOrderScore(m: Move): int =
  if m.isCapture:
    result = 2000 + pieceValues[m.captured].int - pieceValues[m.moved].int
  elif m.isPromotion:
    result = 1000 + pieceValues[m.promoted].int
  else:
    result = 0

proc sortMoves(moves: var openArray[Move]; count: int; pvMove: Move = noMove) =
  if count <= 1: return # No need to sort 0 or 1 elements

  proc cmpMoves(a, b: Move): int =
    if pvMove != noMove: 
      if a == pvMove: return -1
      if b == pvMove: return 1
    
    let scoreA = getMoveOrderScore(a)
    let scoreB = getMoveOrderScore(b)
    if scoreA > scoreB: return -1 
    if scoreA < scoreB: return 1
    return 0
  
  # Use system.sort for slices. moves[0 ..< count] creates a Slice.
  algorithm.sort(moves.toOpenArray(0, count-1), cmpMoves)

# --- Quiescence Search (QSearch) ---
proc qSearch(pos: Position, plyFromRoot: Ply, alphaOrig: Value, beta: Value, currentPV: var seq[Move]): Value =
  inc nodesSearchedGlobal
  currentPV = @[] 

  if (nodesSearchedGlobal mod NodeCheckInterval == 0):
    if searchCancelledFlagGlobal or 
       (epochTime() >= searchStopTimeEpochGlobal) or 
       (nodesSearchedGlobal >= searchMaxNodesGlobal):
      raise newException(SearchStoppedError, "QSearch: Time/nodes up or cancelled")

  var alpha = alphaOrig
  alpha = max(alpha, -valueInfinity + plyFromRoot.Value) 
  var currentBeta = min(beta, valueInfinity - (plyFromRoot.Value + 1.Ply).Value) # Ensure Ply arithmetic
  if alpha >= currentBeta:
    return alpha

  let standPatScore = evaluate(pos)

  if standPatScore >= currentBeta:
    return currentBeta 

  if standPatScore > alpha:
    alpha = standPatScore

  var moveList: array[MaxMovesBuffer, Move]
  let numMoves = generateCaptures(pos, moveList) 

  sortMoves(moveList, numMoves) 

  for i in 0 ..< numMoves:
    let m = moveList[i]
    
    if not pos.isLegal(m): 
      continue

    var childPV: seq[Move]
    let newPos = pos.doMove(m) 
    let score = -qSearch(newPos, plyFromRoot + 1.Ply, -currentBeta, -alpha, childPV) # Ensure Ply arithmetic

    if score >= currentBeta:
      return currentBeta 

    if score > alpha:
      alpha = score
      currentPV = @[m] & childPV 
  
  return alpha

# --- Negamax with Alpha-Beta Pruning ---
proc negamax(pos: Position, depth: Ply, plyFromRoot: Ply, alphaOrig: Value, beta: Value, currentPV: var seq[Move]): Value =
  inc nodesSearchedGlobal
  currentPV = @[] 

  if depth <= 0.Ply: # Explicitly check against Ply(0)
    return qSearch(pos, plyFromRoot, alphaOrig, beta, currentPV)

  if (nodesSearchedGlobal mod NodeCheckInterval == 0):
    if searchCancelledFlagGlobal or 
       (epochTime() >= searchStopTimeEpochGlobal) or 
       (nodesSearchedGlobal >= searchMaxNodesGlobal):
      raise newException(SearchStoppedError, "Negamax: Time/nodes up or cancelled")

  var alpha = alphaOrig
  alpha = max(alpha, -valueInfinity + plyFromRoot.Value)
  var currentBeta = min(beta, valueInfinity - (plyFromRoot.Value + 1.Ply).Value) # Ensure Ply arithmetic
  if alpha >= currentBeta:
    return alpha

  var moveList: array[MaxMovesBuffer, Move]
  let numMoves = generateMoves(pos, moveList) 
  sortMoves(moveList, numMoves)

  var bestScore = -valueInfinity
  var foundLegalMove = false

  for i in 0 ..< numMoves:
    let m = moveList[i]

    if not pos.isLegal(m):
      continue
    
    foundLegalMove = true
    var childPV: seq[Move]
    let newPos = pos.doMove(m)
    # Ensure Ply arithmetic for depth and plyFromRoot
    let score = -negamax(newPos, depth - 1.Ply, plyFromRoot + 1.Ply, -currentBeta, -alpha, childPV)

    if score > bestScore:
      bestScore = score
      currentPV = @[m] & childPV 

    if bestScore > alpha:
      alpha = bestScore
    
    if alpha >= currentBeta: 
      return currentBeta 
  
  if not foundLegalMove:
    let kingSq = firstOne(pos[king] and pos[pos.us])
    if kingSq != noSquare and pos.isAttacked(pos.us, kingSq): 
      return -checkmateValue(plyFromRoot) 
    else:
      return 0 # Stalemate
  
  return bestScore


# --- Iterative Deepening Search (IDS) ---
proc iterativeDeepening*(initialPos: Position, maxSearchDepthUci: Ply, timeForMoveSec: float, 
                         maxNodesAllowed: uint64, infoCb: InfoCallback): SearchResult =
  
  nodesSearchedGlobal = 0
  searchCancelledFlagGlobal = false 
  searchMaxNodesGlobal = if maxNodesAllowed == 0: high(uint64) else: maxNodesAllowed
  
  let searchStartTimeEpoch = epochTime()
  searchStopTimeEpochGlobal = searchStartTimeEpoch + timeForMoveSec

  var overallBestMove = noMove # from types.nim (via move.nim export)
  var overallBestScore = -valueInfinity
  var overallPV: seq[Move] = @[]
  
  let effectiveMaxDepth = min(maxSearchDepthUci, MaxSearchPly)

  for currentDepthIter in 1.Ply .. effectiveMaxDepth: # Changed var name to avoid confusion
    var iterationBestScore = -valueInfinity 
    var iterationBestMoveAtRoot = noMove
    var iterationPV: seq[Move] = @[] # PV for this specific iteration/depth
    
    var nodesAtIterationStart = nodesSearchedGlobal

    try:
      var rootAlpha = -valueInfinity
      var rootBeta = valueInfinity 

      var rootMoveList: array[MaxMovesBuffer, Move]
      let numRootMoves = generateMoves(initialPos, rootMoveList)

      var pvMoveForThisIteration = noMove
      if overallPV.len > 0:
        pvMoveForThisIteration = overallPV[0]
      
      sortMoves(rootMoveList, numRootMoves, pvMoveForThisIteration)

      for i in 0 ..< numRootMoves:
        let mRoot = rootMoveList[i]
        
        if not initialPos.isLegal(mRoot):
          continue

        var childPV: seq[Move]
        let newPos = initialPos.doMove(mRoot)
        
        # Explicit Ply type for subtractions/additions if direct arithmetic was problematic
        let depthForNegamax = currentDepthIter - 1.Ply 
        let plyFromRootForNegamax = 1.Ply 
        let currentMoveScore = -negamax(newPos, depthForNegamax, plyFromRootForNegamax, -rootBeta, -rootAlpha, childPV)
        
        if searchCancelledFlagGlobal or 
           (epochTime() >= searchStopTimeEpochGlobal) or 
           (nodesSearchedGlobal >= searchMaxNodesGlobal):
            if iterationBestMoveAtRoot != noMove: 
                overallBestMove = iterationBestMoveAtRoot
                overallBestScore = iterationBestScore 
                overallPV = iterationPV 
            raise newException(SearchStoppedError, "IDS: Interrupted mid-root-search")

        if currentMoveScore > rootAlpha:
          rootAlpha = currentMoveScore
          iterationBestMoveAtRoot = mRoot
          iterationPV = @[mRoot] & childPV # This is the PV for the current best root move at this depth

          # Update overall bests, as this is the best line found *so far* at any depth
          overallBestMove = iterationBestMoveAtRoot
          overallBestScore = rootAlpha # rootAlpha is the score for this iteration's best line
          overallPV = iterationPV      # Store the PV from this iteration
        
      iterationBestScore = rootAlpha 

      let timeTakenMs = ((epochTime() - searchStartTimeEpoch) * 1000.0).int
      if iterationBestMoveAtRoot != noMove: 
        # Pass currentDepthIter as Ply. Iteration nodes are nodes for this iteration only.
        infoCb(currentDepthIter, iterationBestScore, nodesSearchedGlobal - nodesAtIterationStart, timeTakenMs, overallPV) # Use overallPV for info string
      
      if searchCancelledFlagGlobal or 
         (epochTime() >= searchStopTimeEpochGlobal) or 
         (nodesSearchedGlobal >= searchMaxNodesGlobal):
        break 

      if abs(overallBestScore) >= valueCheckmate - effectiveMaxDepth.Value :
        break 
    except SearchStoppedError:
      break 
    
  return SearchResult(bestMove: overallBestMove, score: overallBestScore, pv: overallPV, nodes: nodesSearchedGlobal)