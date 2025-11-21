import evalParameters

func value*(piece: Piece): Value =
  const table = [pawn: 145.Value, knight: 471.Value, bishop: 511.Value, rook: 740.Value, queen: 1488.Value, king: valueCheckmate, noPiece: 0.Value]
  table[piece]
