import position, bitboard, move, types, castling

func addMove(
    moves: var openArray[Move],
    index: var int,
    source, target, enPassantTarget: Square,
    moved, captured, promoted: Piece,
    castled, capturedEnPassant: bool,
) =
  if moves.len > index:
    moves[index].create(
      source, target, enPassantTarget, moved, captured, promoted, castled,
      capturedEnPassant,
    )
    index += 1

func generateCaptures(
    position: Position, piece: Piece, moves: var openArray[Move]
): int =
  result = 0
  for source in position[position.us] and position[piece]:
    for target in piece.attackMask(source, position.occupancy) and
        position[position.enemy]:
      for captured in pawn .. king:
        if not empty(position[captured] and target.toBitboard):
          moves.addMove(
            result,
            source = source,
            target = target,
            enPassantTarget = noSquare,
            moved = piece,
            captured = captured,
            promoted = noPiece,
            castled = false,
            capturedEnPassant = false,
          )
          break

func generateQuiets(position: Position, piece: Piece, moves: var openArray[Move]): int =
  let occupancy = position.occupancy
  result = 0
  for source in position[position.us] and position[piece]:
    for target in piece.attackMask(source, occupancy) and not occupancy:
      moves.addMove(
        result,
        source = source,
        target = target,
        enPassantTarget = noSquare,
        moved = piece,
        captured = noPiece,
        promoted = noPiece,
        castled = false,
        capturedEnPassant = false,
      )

func left(b: Bitboard): Bitboard =
  b shr 1
func right(b: Bitboard): Bitboard =
  b shl 1
func up(b: Bitboard, c: Color): Bitboard =
  if c == white:
    b shl 8
  else:
    b shr 8

func pawnLeftAttack(pawns: Bitboard, color: Color): Bitboard =
  (pawns and not files[a1]).up(color).left
func pawnRightAttack(pawns: Bitboard, color: Color): Bitboard =
  (pawns and not files[h1]).up(color).right

const firstPawnPushRank = [
  white: homeRank[white].up(white).up(white), black: homeRank[black].up(black).up(black)
]

func generatePawnCaptures(position: Position, moves: var openArray[Move]): int =
  result = 0

  proc addPromotions(
      moves: var openArray[Move],
      source, target: Square,
      counter: var int,
      captured = noPiece,
  ) =
    for promoted in knight .. queen:
      moves.addMove(
        counter,
        source = source,
        target = target,
        enPassantTarget = noSquare,
        moved = pawn,
        captured = captured,
        promoted = promoted,
        castled = false,
        capturedEnPassant = false,
      )

  let
    us = position.us
    enemy = position.enemy
    potentialTargets = position[enemy] or position.enPassantTarget.toBitboard
  for (targets, dir) in [
    (position[pawn, us].pawnLeftAttack(us) and potentialTargets, 1),
    (position[pawn, us].pawnRightAttack(us) and potentialTargets, -1),
  ]:
    for target in targets:
      let source = (target.int + dir).Square.up(enemy)
      var
        captured = noPiece
        capturedEnPassant = false

      for piece in pawn .. king:
        if not empty(position[enemy, piece] and target.toBitboard):
          captured = piece
          break

      if captured == noPiece:
        capturedEnPassant = true
        captured = pawn

      if target notin a2 .. h7:
        moves.addPromotions(source, target, result, captured)
      else:
        moves.addMove(
          result,
          source = source,
          target = target,
          enPassantTarget = noSquare,
          moved = pawn,
          captured = captured,
          promoted = noPiece,
          castled = false,
          capturedEnPassant = capturedEnPassant,
        )

  # quiet promotions
  for target in position[pawn, us].up(us) and homeRank[enemy] and not position.occupancy:
    let source = target.up(enemy)
    moves.addPromotions(source, target, result)

func generatePawnQuiets(position: Position, moves: var openArray[Move]): int =
  result = 0

  let
    us = position.us
    enemy = position.enemy
    occupancy = position.occupancy

  let targets = position[pawn, us].up(us) and not (occupancy or homeRank[enemy])
  for target in targets:
    let source = target.up(enemy)
    moves.addMove(
      result,
      source = source,
      target = target,
      enPassantTarget = noSquare,
      moved = pawn,
      captured = noPiece,
      promoted = noPiece,
      castled = false,
      capturedEnPassant = false,
    )

  let doubleTargets = (targets and firstPawnPushRank[us]).up(us) and not occupancy
  for target in doubleTargets:
    let
      enPassantTarget = target.up(enemy)
      source = enPassantTarget.up(enemy)
    moves.addMove(
      result,
      source = source,
      target = target,
      enPassantTarget = enPassantTarget,
      moved = pawn,
      captured = noPiece,
      promoted = noPiece,
      castled = false,
      capturedEnPassant = false,
    )

func generateCastlingMoves(position: Position, moves: var openArray[Move]): int =
  let
    us = position.us
    occupancy = position.occupancy
    kingSource = (position[us] and position[king]).toSquare

  result = 0
  for (castlingSide, rookSource) in position.rookSource[us].pairs:
    # castling is still allowed
    if rookSource == noSquare:
      continue

    # all necessary squares are empty
    if not empty(blockSensitive(us, castlingSide, kingSource, rookSource) and occupancy):
      continue

    # king will never be in check
    var kingInCheck = false
    for checkSquare in checkSensitive[us][castlingSide][kingSource]:
      if position.isAttacked(us, checkSquare):
        kingInCheck = true
        break
    if kingInCheck:
      continue

    moves.addMove(
      result,
      source = kingSource,
      target = rookSource,
      enPassantTarget = noSquare,
      moved = king,
      captured = noPiece,
      promoted = noPiece,
      castled = true,
      capturedEnPassant = false,
    )

func generateCaptures*(position: Position, moves: var openArray[Move]): int =
  ## Generates pseudo-legal capture moves and writes the into the `moves` array, starting from index 0.
  ## This function will silently stop generating moves if the `moves` array fills up.
  result = position.generatePawnCaptures(moves)
  for piece in knight .. king:
    result += position.generateCaptures(piece, moves.toOpenArray(result, moves.len - 1))

func generateQuiets*(position: Position, moves: var openArray[Move]): int =
  ## Generates pseudo-legal quiet moves and writes the into the `moves` array, starting from index 0.
  ## This function will silently stop generating moves if the `moves` array fills up.
  result = position.generatePawnQuiets(moves)
  result += position.generateCastlingMoves(moves.toOpenArray(result, moves.len - 1))
  for piece in knight .. king:
    result += position.generateQuiets(piece, moves.toOpenArray(result, moves.len - 1))

func generateMoves*(position: Position, moves: var openArray[Move]): int =
  ## Generates pseudo-legal moves and writes the into the `moves` array, starting from index 0.
  ## This function will silently stop generating moves if the `moves` array fills up.
  result = position.generateCaptures(moves)
  result += position.generateQuiets(moves.toOpenArray(result, moves.len - 1))
