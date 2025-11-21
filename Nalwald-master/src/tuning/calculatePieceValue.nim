import ../types, ../position, ../evaluation, ../bitboard, ../evalParameters, dataUtils

func getPieceValue(
    piece: Piece, evalParameters: EvalParameters, data: openArray[Entry]
): Value =
  var sum: int = 0
  var numPieceEvals: int = 0
  for entry in data:
    let position = entry.position
    let startEval = position.absoluteEvaluate(evalParameters)
    for square in position[piece]:
      let us = position.coloredPiece(square).color
      assert position.coloredPiece(square).piece == piece
      var newPosition = position
      newPosition.removePiece(us, piece, square)
      var diff = startEval - newPosition.absoluteEvaluate(evalParameters)
      if us == black:
        diff *= -1
      sum += diff.int
      numPieceEvals += 1
  (sum div numPieceEvals).Value

proc pieceValuesAsString*(
    evalParameters: EvalParameters, data: openArray[Entry]
): string =
  result = ""
  for piece in pawn .. queen:
    result &= $piece & ": " & $getPieceValue(piece, evalParameters, data) & ".Value, "

when isMainModule:
  var data: seq[Entry]
  data.loadDataBin "trainingSets/trainingSet_2023-12-28-11-23-21.bin"
  echo pieceValuesAsString(defaultEvalParameters, data)
