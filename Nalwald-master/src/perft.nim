import position, positionUtils, move, movegen

func perft*(position: Position, depth: int, printRootMoveNodes = false): int64 =
  result = 0
  if depth <= 0:
    return 1
  var moves {.noinit.}: array[320, Move]
  let numMoves = position.generateMoves(moves)
  assert numMoves < 320
  for i in 0 ..< numMoves:
    template move(): Move =
      moves[i]

    let newPosition = position.doMove(move)
    if not newPosition.inCheck(position.us):
      let nodes = newPosition.perft(depth - 1)
      if printRootMoveNodes:
        debugEcho "    ", move, " ", nodes, " ", newPosition.fen
      result += nodes
