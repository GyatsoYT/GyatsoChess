import std/[atomics, monotimes, times]

import coretypes
import bitboard
import board
import movegen
import evaluate
import nnuetypes
import perft
import tt
import moveorderer
import history
import searchparams
import see

var nnueState* {.threadvar.}: NNUEState

const Unknown* = high(int)
type
  SearchStackEntry* = object
    move*:       Move  
    staticEval*: int

  SearchStack* = array[MaxPly + 2, SearchStackEntry]

type SearchInfo* = object
  startTime*:  MonoTime
  allocMs*:    int64
  depthLimit*: int
  nodeLimit*:  uint64
  nodes*:      uint64
  selDepth*:   int
  stopFlag*:   ptr Atomic[bool]
  pvTable*:    array[MaxPly + 1, array[MaxPly + 1, Move]]
  pvLen*:      array[MaxPly + 1, int]
  silent*:     bool

proc shouldStop(info: var SearchInfo): bool {.inline.} =
  if info.stopFlag != nil and info.stopFlag[].load(moAcquire):
    return true
  if info.nodeLimit > 0 and info.nodes >= info.nodeLimit:
    if info.stopFlag != nil: info.stopFlag[].store(true, moRelease)
    return true
  if (getMonoTime() - info.startTime).inMilliseconds >= info.allocMs:
    if info.stopFlag != nil: info.stopFlag[].store(true, moRelease)
    return true
  return false

const StopCheckFreq = 2047'u64

proc checkStop(info: var SearchInfo): bool {.inline.} =
  if (info.nodes and StopCheckFreq) == 0:
    return shouldStop(info)
  return false

func hasNonPawnKingPiece(b: Board): bool {.inline.} =
  let us = b.stm
  let offset = us.ord * 6
  let nonPawnKing =
    b.byPiece[offset + Knight.ord] or
    b.byPiece[offset + Bishop.ord] or
    b.byPiece[offset + Rook.ord]   or
    b.byPiece[offset + Queen.ord]
  not nonPawnKing.isEmpty

proc qSearch*(b: var Board, alpha, beta, ply: int,
              info: var SearchInfo,
              stack: var SearchStack): int =
  if ply >= MaxPly:
    return evaluate(b, nnueState)

  inc info.nodes

  if checkStop(info):
    return 0

  if ply > info.selDepth:
    info.selDepth = ply

  # Draw detection in qsearch
  if b.isRepetition() or b.isFiftyMove():
    return 0

  let standPat = evaluate(b, nnueState)
  var bestScore = standPat

  if standPat >= beta:
    return standPat

  var curAlpha = max(alpha, standPat)

  var ml: MoveList
  generateCaptures(b, ml)
  sortMoves(b, ml, NullMove, ply)

  for idx in 0 ..< ml.len:
    let m = ml.moves[idx]
    stack[ply].move = m
    nnuePush(b, m, nnueState)
    b.makeMove(m)
    prefetchTT(cast[system.uint64](b.hash))
    let score = -qSearch(b, -beta, -curAlpha, ply + 1, info, stack)
    b.unmakeMove(m)
    nnuePop(nnueState)

    if info.stopFlag != nil and info.stopFlag[].load(moAcquire):
      return 0

    if score > bestScore:
      bestScore = score
      if score >= beta:
        return bestScore
      if score > curAlpha:
        curAlpha = score

  return bestScore

proc negamax*[pvNode: static bool](b: var Board, depth, alpha, beta, ply: int,
              info: var SearchInfo,
              stack: var SearchStack,
              skipNullMove: bool = false): int {.gcsafe.} =
  if ply >= MaxPly:
    return evaluate(b, nnueState)

  inc info.nodes

  if checkStop(info):
    return 0

  # Clear PV length for this ply — will be populated if we find a best move.
  info.pvLen[ply] = 0

  if ply > 0:
    if b.isRepetition() or b.isFiftyMove():
      return 0

  # Probe TT
  var ttMove = NullMove
  var ttScore = 0
  var ttDepth = 0
  var ttBound = 0'u8
  let hashVal = cast[system.uint64](b.hash)
  let hasTT = probeTT(hashVal, ply, ttMove, ttScore, ttDepth, ttBound)

  if hasTT and ttDepth >= depth and ply > 0:
    if ttBound == BoundExact:
      return ttScore
    elif ttBound == BoundAlpha and ttScore <= alpha:
      return ttScore
    elif ttBound == BoundBeta and ttScore >= beta:
      return ttScore

  let inCheck = not b.checkers.isEmpty

  # Internal Iterative Reduction (IIR)
  var depth = depth
  if depth >= IirMinDepth and ttMove == NullMove and not inCheck:
    dec depth

  if depth <= 0:
    return qSearch(b, alpha, beta, ply, info, stack)

  if inCheck:
    stack[ply].staticEval = Unknown
  elif stack[ply].staticEval == Unknown:
    stack[ply].staticEval = evaluate(b, nnueState)
  let staticEval = stack[ply].staticEval

  # Improving flag and delta (improvement) calculation
  var improving = false
  var improvement = 0
  if not inCheck and staticEval != Unknown:
    if ply >= 2 and stack[ply - 2].staticEval != Unknown:
      improvement = staticEval - stack[ply - 2].staticEval
      improving = improvement > 0
    elif ply >= 4 and stack[ply - 4].staticEval != Unknown:
      improvement = staticEval - stack[ply - 4].staticEval
      improving = improvement > 0
    else:
      improving = true  # no prior data — assume improving

  # Reverse Futility Pruning (RFP)
  if not pvNode and
     not inCheck and
     ply > 0 and
     depth <= RfpDepth and
     abs(beta) < MateThreshold:
    let rfpMargin = RfpLinearMargin * depth + RfpQuadraticMargin * depth * depth -
                    clamp(improvement div 2, -RfpImprovementClamp, RfpImprovementClamp)
    if staticEval - rfpMargin >= beta:
      return staticEval - rfpMargin

  # Null Move Pruning (NMP)
  if depth >= NmpMinDepth and
     ply   >= NmpMinPly and
     staticEval != Unknown and
     staticEval >= beta and
     (ply == 0 or stack[ply - 1].move != NullMove) and
     not inCheck and
     hasNonPawnKingPiece(b) and
     not skipNullMove:

    let R = NmpBaseR + depth div NmpDepthDiv   # 2 + depth/4

    stack[ply].move = NullMove
    stack[ply + 1].staticEval = Unknown
    nnuePushNull(nnueState)
    b.makeNullMove()

    let nullScore = -negamax[false](b, depth - R - 1, -beta, -beta + 1,
                             ply + 1, info, stack, skipNullMove = true)

    b.unmakeNullMove()
    nnuePopNull(nnueState)

    if info.stopFlag != nil and info.stopFlag[].load(moAcquire):
      return 0

    if nullScore >= beta:
      if depth > NmpVerificationDepth:
        stack[ply + 1].staticEval = Unknown
        let verScore = negamax[false](b, depth - R - 1, beta - 1, beta,
                               ply, info, stack, skipNullMove = true)
        if verScore < beta:
          discard
        else:
          return beta
      else:
        return beta

  var ml: MoveList
  generateMoves(b, ml)

  if ml.len == 0:
    return if not b.checkers.isEmpty: -MateValue + ply
           else: 0

  sortMoves(b, ml, ttMove, ply)

  var bestScore = -Infinity
  var curAlpha = alpha
  var bestMove = NullMove

  var triedQuiets: array[128, Move]
  var triedQuietsLen = 0
  var movesSearched = 0

  for idx in 0 ..< ml.len:
    let m = ml.moves[idx]

    # Futility Pruning
    if movesSearched > 0 and
       depth <= FpDepth and
       not inCheck and
       isQuietMove(b, m) and
       m != ttMove and
       m != killerMoves[ply][0] and
       m != killerMoves[ply][1] and
       curAlpha < MateThreshold:
      let fpMargin = FpMarginConst + FpMarginScale * depth
      if staticEval + fpMargin <= curAlpha:
        continue

    # Quiet SEE Pruning
    if movesSearched > 0 and
       not inCheck and
       isQuietMove(b, m) and
       abs(curAlpha) < MateThreshold and
       not see(b, m, StaticPruning[depth]):
      continue

    stack[ply].move = m
    stack[ply + 1].staticEval = Unknown
    nnuePush(b, m, nnueState)
    b.makeMove(m)
    prefetchTT(cast[system.uint64](b.hash))

    # Check Extension
    let givesCheck = not b.checkers.isEmpty
    let extension = if givesCheck and depth >= 1 and ply < MaxPly - 1: 1 else: 0
    let newDepth = depth - 1 + extension

    var score = -Infinity

    if movesSearched == 0:
      # First move — full window
      score = -negamax[pvNode](b, newDepth, -beta, -curAlpha, ply + 1, info, stack)
    else:
      # Late Move Reductions
      var reduction = 0
      if depth >= 3:
        let tableDepth = min(depth, MaxPly - 1)
        let tableIndex = min(movesSearched, 63)
        reduction = LMR[tableDepth][tableIndex]

      let reducedDepth = if reduction > 0: max(1, newDepth - reduction)
                         else: newDepth

      # Null-window search
      score = -negamax[false](b, reducedDepth, -curAlpha - 1, -curAlpha, ply + 1, info, stack)

      # Re-search at full depth if LMR raised alpha
      if reduction > 0 and score > curAlpha:
        score = -negamax[false](b, newDepth, -curAlpha - 1, -curAlpha, ply + 1, info, stack)

      # PVS re-search with full window
      if score > curAlpha and score < beta:
        score = -negamax[true](b, newDepth, -beta, -curAlpha, ply + 1, info, stack)

    b.unmakeMove(m)
    nnuePop(nnueState)

    if info.stopFlag != nil and info.stopFlag[].load(moAcquire):
      return 0

    inc movesSearched

    if score > bestScore:
      bestScore = score
      if score > curAlpha:
        curAlpha = score
        bestMove = m
        info.pvTable[ply][0] = m
        let childLen = info.pvLen[ply + 1]
        for k in 0 ..< childLen:
          info.pvTable[ply][k + 1] = info.pvTable[ply + 1][k]
        info.pvLen[ply] = childLen + 1
        if curAlpha >= beta:
          # Store killer if the cutoff move is quiet (not a capture/promotion)
          if isQuietMove(b, m):
            storeKiller(ply, m)
            let bonus = getBonus(depth)
            updateHistory(b, m, bonus)
            for i in 0 ..< triedQuietsLen:
              if triedQuiets[i] != m:
                updateHistory(b, triedQuiets[i], -getPenalty(depth))
          storeTT(hashVal, bestMove, bestScore.int16, depth.int8, BoundBeta, ply)
          return bestScore

    # Record tried quiet moves that did not cause a cutoff
    if isQuietMove(b, m):
      if triedQuietsLen < triedQuiets.len:
        triedQuiets[triedQuietsLen] = m
        inc triedQuietsLen

  let bound = if bestScore > alpha: BoundExact else: BoundAlpha
  if bestMove != NullMove and isQuietMove(b, bestMove):
    let bonus = getBonus(depth)
    updateHistory(b, bestMove, bonus)
    for i in 0 ..< triedQuietsLen:
      if triedQuiets[i] != bestMove:
        updateHistory(b, triedQuiets[i], -getPenalty(depth))
  storeTT(hashVal, bestMove, bestScore.int16, depth.int8, bound, ply)
  return bestScore

proc elapsedMs(info: SearchInfo): int64 {.inline.} =
  (getMonoTime() - info.startTime).inMilliseconds

proc printInfo(depth, selDepth, score: int, nodes: uint64,
               elapsed: int64, info: SearchInfo) =
  if info.silent: return
  let nps = if elapsed > 0: nodes * 1000 div cast[uint64](elapsed) else: nodes
  var line = "info depth " & $depth &
             " seldepth " & $selDepth &
             " score "
  if score >= MateThreshold:
    let mateIn = (MateValue - score + 1) div 2
    line &= "mate " & $mateIn
  elif score <= -MateThreshold:
    let mateIn = -(MateValue + score + 1) div 2
    line &= "mate " & $mateIn
  else:
    line &= "cp " & $score
  line &= " nodes " & $nodes &
          " nps " & $nps &
          " time " & $elapsed &
          " pv"
  for i in 0 ..< info.pvLen[0]:
    line &= " " & moveToAlgebraic(info.pvTable[0][i])
  echo line
  stdout.flushFile()

proc iterativeDeepening*(b: var Board, info: var SearchInfo): (Move, int) =
  # Age history table
  ageHistory()

  # Clear killer table for fresh search
  for i in 0 .. MaxPly:
    killerMoves[i][0] = NullMove
    killerMoves[i][1] = NullMove

  refreshNNUE(b, nnueState)

  let maxDepth = if info.depthLimit > 0: info.depthLimit else: MaxPly

  var bestMove  = NullMove
  var bestScore = -Infinity

  # Initialise the search stack for a fresh search
  var stack: SearchStack
  for i in 0 .. MaxPly + 1:
    stack[i].move       = NullMove
    stack[i].staticEval = Unknown

  # aspirationScore seeds the windows for depth >= AspMinDepth
  var aspirationScore = bestScore

  for depth in 1 .. maxDepth:
    info.selDepth = depth

    for k in 0 .. MaxPly:
      info.pvLen[k] = 0

    stack[0].staticEval = Unknown

    var alphaWindow  = AspInitAlpha
    var betaWindow   = AspInitBeta
    var aspRetries   = 0
    var failHighCount = 0
    var searchDepth  = depth

    var score = -Infinity

    while true:
      var alpha = -Infinity
      var beta  =  Infinity

      if depth >= AspMinDepth:
        alpha = max(-Infinity, aspirationScore - alphaWindow)
        beta  = min( Infinity, aspirationScore + betaWindow)

      for k in 0 .. MaxPly:
        info.pvLen[k] = 0
      stack[0].staticEval = Unknown

      score = negamax[true](b, searchDepth, alpha, beta, 0, info, stack)

      if info.stopFlag != nil and info.stopFlag[].load(moAcquire):
        break

      if depth < AspMinDepth or aspRetries >= AspMaxRetries:
        break

      if score <= alpha:
        alphaWindow  = (alphaWindow * AspWideNum) div AspWideDen
        aspirationScore = score
        inc aspRetries
        failHighCount = 0
        searchDepth   = depth
        continue

      elif score >= beta:
        betaWindow   = (betaWindow * AspWideNum) div AspWideDen
        aspirationScore = score
        inc aspRetries
        inc failHighCount
        if failHighCount <= AspFailHighMaxReduction:
          searchDepth = depth - failHighCount
        else:
          searchDepth = depth
        continue

      break

    let stopped = (info.stopFlag != nil and info.stopFlag[].load(moAcquire)) or
                  shouldStop(info)
    if stopped and depth > 1:
      break

    bestScore = score
    bestMove  = if info.pvLen[0] > 0: info.pvTable[0][0] else: NullMove

    aspirationScore = bestScore

    let elapsed = elapsedMs(info)
    printInfo(depth, info.selDepth, bestScore, info.nodes, elapsed, info)

    if stopped:
      break

  if bestMove == NullMove:
    if info.pvLen[0] > 0 and info.pvTable[0][0] != NullMove:
      bestMove = info.pvTable[0][0]
    else:
      var ml: MoveList
      generateMoves(b, ml)
      if ml.len > 0:
        bestMove = ml.moves[0]

  return (bestMove, bestScore)
