import
  types, bitboard, position, positionUtils, move, searchUtils, moveIterator, hashTable,
  evaluation, utils, see, searchParams

import std/[atomics, options, math]

static:
  doAssert pawn.value == 100.cp

func futilityReduction(value: Value): Ply =
  clampToType(value.toCp div futilityReductionDiv(), Ply)

func hashResultFutilityMargin(depthDifference: Ply): Value =
  depthDifference.Value * hashResultFutilityMarginMul().cp

func nullMoveReduction(depth: Ply): Ply =
  nullMoveDepthSub() + depth div nullMoveDepthDiv().Ply

func lmrReduction(depth: Ply, lmrMoveCounter: int): Ply =
  clampToType(
    lmrAddition() + ln(depth.float) * ln(lmrMoveCounter.float) / lmrDivisor(), Ply
  )

type SearchState* = object
  externalStopFlag*: ptr Atomic[bool]
  threadStop*: ptr Atomic[bool]
  hashTable*: ptr HashTable
  killerTable*: KillerTable
  historyTable*: HistoryTable
  corrHist*: CorrHistory
  gameHistory*: GameHistory
  countedNodes*: int
  maxNodes*: int
  stopTime*: Seconds
  skipMovesAtRoot*: seq[Move]
  evaluation*: proc(position: Position): Value {.noSideEffect.}

func shouldStop(state: SearchState): bool =
  if state.countedNodes >= state.maxNodes or
      ((state.countedNodes mod 2048) == 1107 and secondsSince1970() >= state.stopTime):
    state.externalStopFlag[].store(true)
  state.externalStopFlag[].load or state.threadStop[].load

func quiesce(
    position: Position,
    state: var SearchState,
    alpha, beta: Value,
    height: Ply,
    doPruning: static bool = true,
): Value =
  assert alpha < beta

  state.countedNodes += 1

  if height == Ply.high or position.insufficientMaterial:
    return 0.Value

  # TODO make this nicer, think about other eval uses
  let standPat =
    state.corrHist.getCorrEval(position, rawEval = state.evaluation(position))

  var
    alpha = alpha
    bestValue = standPat

  if standPat >= beta:
    return standPat
  if standPat > alpha:
    alpha = standPat

  for move in position.treeSearchMoveIterator(doQuiets = false):
    let newPosition = position.doMove(move)

    let seeEval = standPat + position.see(move)

    # delta pruning
    if seeEval + deltaMargin().cp < alpha and doPruning:
      # return instead of just continue, as later captures must have lower SEE value
      return bestValue

    if newPosition.inCheck(position.us):
      continue

    # fail-high delta pruning
    if seeEval - failHighDeltaMargin().cp >= beta and doPruning:
      return seeEval - failHighDeltaMargin().cp

    let value =
      -newPosition.quiesce(
        state, alpha = -beta, beta = -alpha, height + 1.Ply, doPruning = doPruning
      )

    if value > bestValue:
      bestValue = value
    if value >= beta:
      return bestValue
    if value > alpha:
      alpha = value

  bestValue

func materialQuiesce*(position: Position): Value =
  var state = SearchState(
    externalStopFlag: nil,
    hashTable: nil,
    gameHistory: newGameHistory(@[]),
    evaluation: material,
  )
  position.quiesce(
    state = state,
    alpha = -valueInfinity,
    beta = valueInfinity,
    height = 0.Ply,
    doPruning = false,
  )

func search(
    position: Position,
    state: var SearchState,
    alpha, beta: Value,
    depth, height: Ply,
    previous: Move,
): Value =
  assert alpha < beta

  state.countedNodes += 1

  if height > 0 and (
    height == Ply.high or position.insufficientMaterial or position.halfmoveClock >= 100 or
    state.gameHistory.checkForRepetitionAndAdd(position, height)
  ):
    return 0.Value

  let
    us = position.us
    inCheck = position.inCheck(us)
    hashResult = state.hashTable[].get(position.zobristKey)

  var
    alpha = alpha
    nodeType = allNode
    bestMove = noMove
    bestValue = -valueInfinity
    moveCounter = 0
    lmrMoveCounter = 0

  let depth = block:
    var depth = depth

    # check and passed pawn extension
    if (inCheck and depth <= 0) or previous.isPawnMoveToSecondRank:
      depth += 1.Ply

    # internal iterative reduction
    if hashResult.isEmpty and depth >= iirMinDepth():
      depth -= 1.Ply

    depth

  let beta = block:
    # update alpha, beta or return immediatly based on hash table result
    var beta = beta
    if height > 0 and not hashResult.isEmpty:
      let margin = hashResultFutilityMargin(depth - hashResult.depth)
      if hashResult.nodeType != upperBound:
        alpha = max(alpha, hashResult.value - margin)
      if hashResult.nodeType != lowerBound:
        beta = min(beta, hashResult.value + margin)

      if alpha >= beta:
        return alpha
    beta

  if depth <= 0:
    return position.quiesce(state, alpha = alpha, beta = beta, height)

  # get static eval of current position, but only when necessary
  lazyEval:
    rawEval = state.evaluation(position)
  lazyEval:
    staticEval = state.corrHist.getCorrEval(position, rawEval = rawEval)

  if alpha + 1 == beta and not inCheck and
      staticEval - rfpMarginMultiplier().cp * (depth - 1).Value >= beta:
    return staticEval

  # null move reduction
  if height > 0 and (hashResult.isEmpty or hashResult.nodeType == cutNode) and
      not inCheck and
      ((position[king] or position[pawn]) and position[us]) != position[us]:
    let newPosition = position.doNullMove
    let value =
      -newPosition.search(
        state,
        alpha = -beta,
        beta = -beta + 1.Value,
        depth = depth - nullMoveReduction(depth),
        height = height + 1.Ply,
        previous = noMove,
      )

    if value >= beta:
      return value

  # iterate over all moves and recursively search the new positions
  for move in position.treeSearchMoveIterator(
    hashResult.bestMove, state.historyTable, state.killerTable.get(height), previous
  ):
    if height == 0.Ply and move in state.skipMovesAtRoot:
      continue

    let newPosition = position.doMove(move)

    if newPosition.inCheck(us):
      continue
    moveCounter += 1

    let givingCheck = newPosition.inCheck(newPosition.us)

    var
      newDepth = depth
      newBeta = beta
      newAlpha = alpha

    if not givingCheck:
      # late move reduction
      if moveCounter >= minMoveCounterLmr() and not move.isTactical:
        newDepth -= lmrReduction(newDepth, lmrMoveCounter)
        lmrMoveCounter += 1

        if newDepth <= 0:
          break

      # futility reduction
      if moveCounter >= minMoveCounterFutility() and newDepth > 0:
        newDepth -= futilityReduction(alpha - staticEval - position.see(move))

        if newDepth <= 0:
          continue

    # first explore with null window
    if hashResult.bestMove != move:
      newBeta = alpha + 1
    elif hashResult.nodeType == cutNode:
      newAlpha = beta - 1

    # stop search if we exceeded maximum nodes or we got a stop signal from outside
    if state.shouldStop:
      break

    # search new position
    var value =
      -newPosition.search(
        state,
        alpha = -newBeta,
        beta = -newAlpha,
        depth = newDepth - 1.Ply,
        height = height + 1.Ply,
        previous = move,
      )

    # re-search with full window and full depth
    if (value > alpha and (newDepth < depth or newBeta < beta)) or
        (value < beta and newAlpha > alpha):
      newDepth = depth
      value =
        -newPosition.search(
          state,
          alpha = -beta,
          beta = -alpha,
          depth = depth - 1.Ply,
          height = height + 1.Ply,
          previous = move,
        )

    if value > bestValue:
      bestValue = value
      bestMove = move

    if value >= beta:
      nodeType = cutNode
      break

    if value > alpha:
      nodeType = pvNode
      alpha = value
    else:
      state.historyTable.update(
        move, previous = previous, us, newDepth, raisedAlpha = false
      )

  if moveCounter == 0:
    # checkmate
    if inCheck:
      bestValue = -(height.checkmateValue)
    # stalemate
    else:
      bestValue = 0.Value

  if bestMove != noMove and bestValue.abs < valueInfinity and not state.threadStop[].load:
    state.hashTable[].add(position.zobristKey, nodeType, bestValue, depth, bestMove)
    if nodeType != allNode:
      state.historyTable.update(
        bestMove, previous, position.us, depth, raisedAlpha = true
      )

      state.killerTable.update(height, bestMove)

    if not bestMove.isTactical:
      # TODO check if it's unnecessary to make staticEval in search fancy lazy, if it is called here anyway
      state.corrHist.update(
        position,
        rawEval = rawEval,
        searchEval = bestValue,
        nodeType = nodeType,
        depth = depth,
      )

  bestValue

func search*(position: Position, state: var SearchState, depth: Ply): Value =
  result = 0

  let hashResult = state.hashTable[].get(position.zobristKey)

  var
    estimatedValue = (if hashResult.isEmpty: 0.Value else: hashResult.value).float
    alphaOffset = aspirationWindowStartingOffset().cp.float
    betaOffset = aspirationWindowStartingOffset().cp.float

  # growing alpha beta window
  while not state.shouldStop:
    let
      alpha = max(estimatedValue - alphaOffset, -valueInfinity.float).Value
      beta = min(estimatedValue + betaOffset, valueInfinity.float).Value

    result = position.search(
      state, alpha = alpha, beta = beta, depth = depth, height = 0, previous = noMove
    )
    doAssert result.abs <= valueInfinity

    estimatedValue = result.float
    if result <= alpha:
      alphaOffset *= aspirationWindowMultiplier()
    elif result >= beta:
      betaOffset *= aspirationWindowMultiplier()
    else:
      break
