import position, positionUtils, types, timeManagedSearch, hashTable, move, evaluation

import std/[tables]

type
  Game* {.requiresInit.} = object
    hashTable: ref HashTable
    positionHistory: seq[Position]
    evals: Table[Position, Value] = initTable[Position, Value]()
    maxNodes: int
    earlyResignMargin: Value
    earlyAdjudicationMinConsistentPly: int
    minAdjudicationGameLenPly: int
    evaluation: proc(position: Position): Value {.noSideEffect.}

  GameStatus* = enum
    running
    fiftyMoveRule
    threefoldRepetition
    stalemate
    checkmateWhite
    checkmateBlack

func gameStatus*(positionHistory: openArray[Position]): GameStatus =
  doAssert positionHistory.len >= 1
  let position = positionHistory[^1]
  if position.legalMoves.len == 0:
    if position.inCheck(position.us):
      return (if position.enemy == black: checkmateBlack else: checkmateWhite)
    else:
      return stalemate
  if position.halfmoveClock >= 100:
    return fiftyMoveRule
  var repetitions = 0
  for p in positionHistory:
    if p.zobristKey == position.zobristKey:
      repetitions += 1
  doAssert repetitions in 1 .. 3
  if repetitions == 3:
    return threefoldRepetition
  running

func getPositionHistory*(game: Game): seq[(Position, Value)] =
  result = @[]
  for position in game.positionHistory:
    let value =
      if position in game.evals:
        game.evals[position]
      else:
        valueInfinity
    result.add (position, value)

proc makeNextMove(game: var Game): (GameStatus, Value, Move) =
  doAssert game.positionHistory.len >= 1
  if game.positionHistory.gameStatus != running:
    return (game.positionHistory.gameStatus, 0.Value, noMove)

  let
    position = game.positionHistory[^1]
    pvSeq = timeManagedSearch(
      SearchInfo(
        positionHistory: game.positionHistory,
        hashTable: addr game.hashTable[],
        evaluation: game.evaluation,
        maxNodes: game.maxNodes,
      )
    )
  doAssert pvSeq.len >= 1
  let
    pv = pvSeq[0].pv
    value = pvSeq[0].value
    absoluteValue =
      if position.us == white:
        value
      else:
        -value
  doAssert pv.len >= 1
  doAssert pv[0] != noMove
  doAssert position notin game.evals

  game.evals[position] = absoluteValue
  game.positionHistory.add position.doMove pv[0]

  (game.positionHistory.gameStatus, absoluteValue, pv[0])

func newGame*(
    startingPosition: Position,
    maxNodes = 20_000,
    earlyResignMargin = 800.cp,
    earlyAdjudicationMinConsistentPly = 8,
    minAdjudicationGameLenPly = 30,
    hashTable: ref HashTable = nil,
    evaluation: proc(position: Position): Value {.noSideEffect.} = perspectiveEvaluate,
): Game =
  result = Game(
    hashTable: hashTable,
    positionHistory: @[startingPosition],
    maxNodes: maxNodes,
    earlyResignMargin: earlyResignMargin,
    earlyAdjudicationMinConsistentPly: earlyAdjudicationMinConsistentPly,
    minAdjudicationGameLenPly: minAdjudicationGameLenPly,
    evaluation: evaluation,
  )
  if result.hashTable == nil:
    {.warning[ProveInit]: off.}:
      result.hashTable = new HashTable
    result.hashTable[] = newHashTable(len = maxNodes * 2)

proc playGame*(game: var Game, suppressOutput = true): float =
  doAssert game.positionHistory.len >= 1, "Need a starting position"

  template echoSuppressed(x: typed) =
    if not suppressOutput:
      echo $x

  echoSuppressed "-----------------------------"
  echoSuppressed "starting position:"
  echoSuppressed game.positionHistory[0]

  var
    drawPlies = 0
    whiteResignPlies = 0
    blackResignPlies = 0

  while true:
    var (gameStatus, value, move) = game.makeNextMove()
    if value == 0.Value:
      drawPlies += 1
    else:
      drawPlies = 0

    if value >= game.earlyResignMargin:
      blackResignPlies += 1
    else:
      blackResignPlies = 0
    if -value >= game.earlyResignMargin:
      whiteResignPlies += 1
    else:
      whiteResignPlies = 0

    echoSuppressed "Move: " & $move
    echoSuppressed game.positionHistory[^1]
    echoSuppressed "Value: " & $value
    if gameStatus != running:
      echoSuppressed gameStatus

    if gameStatus != running:
      case gameStatus
      of stalemate, fiftyMoveRule, threefoldRepetition:
        return 0.5
      of checkmateWhite:
        return 1.0
      of checkmateBlack:
        return 0.0
      else:
        doAssert false, $gameStatus

    if game.positionHistory.len >= game.minAdjudicationGameLenPly:
      if drawPlies >= game.earlyAdjudicationMinConsistentPly:
        echoSuppressed "Adjudicated draw"
        return 0.5
      if whiteResignPlies >= game.earlyAdjudicationMinConsistentPly:
        echoSuppressed "White resigned"
        return 0.0
      if blackResignPlies >= game.earlyAdjudicationMinConsistentPly:
        echoSuppressed "Black resigned"
        return 1.0
