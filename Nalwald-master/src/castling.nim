import types, bitboard

type CastlingSide* = enum
  queenside
  kingside

func connectOnFile(a, b: Square): Bitboard =
  result = 0.Bitboard
  if not empty(ranks[a] and ranks[b]):
    var currentSquare = min(a, b)
    while true:
      result = result or currentSquare.toBitboard
      if currentSquare == max(a, b):
        break
      inc currentSquare

func blockSensitive(
    target: array[white .. black, array[CastlingSide, Square]]
): array[white .. black, array[CastlingSide, array[a1 .. h8, Bitboard]]] =
  result = default(array[white .. black, array[CastlingSide, array[a1 .. h8, Bitboard]]])

  for us in white .. black:
    for castlingSide in queenside .. kingside:
      for source in a1 .. h8:
        result[us][castlingSide][source] =
          connectOnFile(source, target[us][castlingSide])

const
  kingTarget* =
    [white: [queenside: c1, kingside: g1], black: [queenside: c8, kingside: g8]]
  rookTarget* =
    [white: [queenside: d1, kingside: f1], black: [queenside: d8, kingside: f8]]
  classicalRookSource* =
    [white: [queenside: a1, kingside: h1], black: [queenside: a8, kingside: h8]]
  classicalKingSource* = [white: e1, black: e8]
  blockSensitiveRook = blockSensitive(rookTarget)
  blockSensitiveKing = blockSensitive(kingTarget)

func blockSensitive*(
    us: Color, castlingSide: CastlingSide, kingSource, rookSource: Square
): Bitboard =
  (
    blockSensitiveKing[us][castlingSide][kingSource] or
    blockSensitiveRook[us][castlingSide][rookSource]
  ) and not (kingSource.toBitboard or rookSource.toBitboard)

const checkSensitive* = block:
  var checkSensitive:
    array[white .. black, array[CastlingSide, array[a1 .. h8, seq[Square]]]]

  for us in white .. black:
    for castlingSide in queenside .. kingside:
      for kingSource in a1 .. h8:
        let b =
          blockSensitiveKing[us][castlingSide][kingSource] and
          # I don't need to check if the king will be in check after the move is done
          (kingSource.toBitboard or not kingTarget[us][castlingSide].toBitboard)
        for square in b:
          checkSensitive[us][castlingSide][kingSource].add(square)

  checkSensitive
