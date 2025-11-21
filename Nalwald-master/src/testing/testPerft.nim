import
  ../position, ../types, ../searchUtils, ../hashTable, ../moveIterator, ../positionUtils

import std/[random, strformat]

type TestPerftState = object
  randomMoves: array[10000, Move]
  hashTable: ptr HashTable
  killerTable: KillerTable
  historyTable: HistoryTable
  randState = initRand(0)
  testPseudoLegality = false

func newTestPerftState*(hashTable: ptr HashTable): TestPerftState =
  TestPerftState(hashTable: hashTable, historyTable: newHistoryTable())

func testPerft(
    position: Position,
    state: var TestPerftState,
    depth: Ply,
    height: Ply,
    previous: Move,
): int =
  ## Returns number of nodes and also does a number of asserts on different systems
  result = 0

  if depth <= 0.Ply:
    return 1

  # Test for isPseudoLegal
  var claimedPseudoLegalMoves: seq[Move] = @[]
  if state.testPseudoLegality:
    for move in state.randomMoves:
      if position.isPseudoLegal move:
        claimedPseudoLegalMoves.add move

  let hashResult = state.hashTable[].get(position.zobristKey)

  var
    bestMove = noMove
    numLegalMoves = 0

  for move in position.treeSearchMoveIterator(
    hashResult.bestMove, state.historyTable, state.killerTable.get(height), previous
  ):
    # Test for isPseudoLegal
    if not position.isPseudoLegal(move):
      raise newException(
        CatchableError,
        fmt"Legal move not labeled as pseudo legal: {move} at position {position.fen}",
      )

    if state.testPseudoLegality:
      for claimedMove in claimedPseudoLegalMoves.mitems:
        if claimedMove == move:
          claimedMove = noMove
      state.randomMoves[state.randState.rand(0 ..< state.randomMoves.len)] = move

    let newPosition = position.doMove(move)

    # Test zobrist key incremental calculation
    if not newPosition.zobristKeysAreOk:
      raise newException(
        CatchableError,
        fmt"Incremental zobrist key calculation failed for move {move} at position {position.fen}",
      )

    if not newPosition.inCheck(position.us):
      numLegalMoves += 1
      result +=
        newPosition.testPerft(
          state, depth = depth - 1, height = height + 1, previous = move
        )

      if bestMove == noMove:
        bestMove = move
      elif state.randState.rand(1.0) < 0.1:
        bestMove = move

  # Test all the search utils
  let bestValue =
    if state.randState.rand(1.0) < 0.01:
      valueCheckmate * state.randState.rand(-1 .. 1).Value
    else:
      state.randState.rand(-valueCheckmate.int64 .. valueCheckmate.int64).Value

  let
    nodeTypeRandValue = state.randState.rand(1.0)
    nodeType =
      if nodeTypeRandValue < 0.45:
        allNode
      elif nodeTypeRandValue < 0.9:
        cutNode
      else:
        pvNode

  if numLegalMoves > 0:
    if bestMove == noMove:
      raise newException(
        CatchableError,
        fmt"Best move should be a legal move at the end of the move loop. {position.fen}",
      )
    state.hashTable[].add(position.zobristKey, nodeType, bestValue, depth, bestMove)
    state.historyTable.update(
      bestMove, previous, position.us, depth, raisedAlpha = nodeType != allNode
    )
    if nodeType == cutNode:
      state.killerTable.update(height, bestMove)

  # Test for isPseudoLegal
  if state.testPseudoLegality:
    for claimedMove in claimedPseudoLegalMoves:
      if claimedMove != noMove:
        raise newException(
          CatchableError,
          fmt"Move claimed to be legal, but it is not: {claimedMove} at position: {position.fen}",
        )

func runTestPerft*(
    position: Position,
    perftState: var TestPerftState,
    depth: Ply,
    testPseudoLegality: bool,
): int =
  perftState.testPseudoLegality = testPseudoLegality
  position.testPerft(perftState, depth = depth, height = 0.Ply, previous = noMove)
