import move, position, movegen, see, evaluation, searchUtils

iterator treeSearchMoveIterator*(
    position: Position,
    tryFirstMove = noMove,
    historyTable: HistoryTable or tuple[] = (),
    killer = noMove,
    previous = noMove,
    doQuiets = true,
): Move =
  ## This iterator is optimized for speed and for good move ordering.
  ## It does not guarantee to list all legal moves and may include
  ## illegal moves that leave our own king in check.

  type OrderedMoveList[maxMoves: static int] = object
    moves: array[maxMoves, Move]
    movePriorities: array[maxMoves, float]
    numMoves: int

  template findBestMoves(moveList: var OrderedMoveList, minValue = float.low) =
    while true:
      var bestIndex = moveList.numMoves
      var bestValue = minValue
      for i in 0 ..< moveList.numMoves:
        if moveList.movePriorities[i] > bestValue:
          bestValue = moveList.movePriorities[i]
          bestIndex = i
      if bestIndex != moveList.numMoves:
        moveList.movePriorities[bestIndex] = float.low
        let move = moveList.moves[bestIndex]

        if move notin [tryFirstMove, killer]:
          yield move
      else:
        break

  # hash move
  if position.isPseudoLegal(tryFirstMove):
    yield tryFirstMove

  # init capture moves
  var captureList {.noinit.}: OrderedMoveList[64]
  captureList.numMoves = position.generateCaptures(captureList.moves)
  for i in 0 ..< captureList.numMoves:
    captureList.movePriorities[i] = position.see(captureList.moves[i]).float

  # mostly winning captures
  captureList.findBestMoves(minValue = -150.cp.float)

  # killers
  if doQuiets:
    if position.isPseudoLegal(killer) and killer != tryFirstMove:
      yield killer

  # quiet moves
  if doQuiets:
    var quietList {.noinit.}: OrderedMoveList[192]
    quietList.numMoves = position.generateQuiets(quietList.moves)
    for i in 0 ..< quietList.numMoves:
      quietList.movePriorities[i] =
        when historyTable is HistoryTable:
          historyTable.get(quietList.moves[i], previous, position.us)
        else:
          0.0

    quietList.findBestMoves()

  # losing captures
  captureList.findBestMoves()
