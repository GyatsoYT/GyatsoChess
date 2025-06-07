import types, bitboard, move, castling

export types, bitboard, move

type
  Position* = object
    pieces*: array[pawn .. king, Bitboard]
    colors*: array[white .. black, Bitboard]
    enPassantTarget*: Square
    rookSource*: array[white .. black, array[CastlingSide, Square]]
    us*: Color
    halfmovesPlayed*: int16
    halfmoveClock*: int8
    zobristKey*: ZobristKey
    pawnKey*: ZobristKey

func enemy*(position: Position): Color =
  position.us.opposite

func `[]`*(position: Position, piece: Piece): Bitboard {.inline.} =
  position.pieces[piece]

func `[]`*(position: var Position, piece: Piece): var Bitboard {.inline.} =
  position.pieces[piece]

func `[]=`*(position: var Position, piece: Piece, bitboard: Bitboard) {.inline.} =
  position.pieces[piece] = bitboard

func `[]`*(position: Position, color: Color): Bitboard {.inline.} =
  position.colors[color]

func `[]`*(position: var Position, color: Color): var Bitboard {.inline.} =
  position.colors[color]

func `[]=`*(position: var Position, color: Color, bitboard: Bitboard) {.inline.} =
  position.colors[color] = bitboard

func `[]`*(position: Position, piece: Piece, color: Color): Bitboard {.inline.} =
  position[color] and position[piece]

func `[]`*(position: Position, color: Color, piece: Piece): Bitboard {.inline.} =
  position[color] and position[piece]

func occupancy*(position: Position): Bitboard =
  position[white] or position[black]

func attackers*(position: Position, attacker: Color, target: Square): Bitboard =
  let occupancy = position.occupancy
  (
    (attackMaskBishop(target, occupancy) and (position[bishop] or position[queen])) or
    (attackMaskRook(target, occupancy) and (position[rook] or position[queen])) or
    (attackMaskKnight(target, occupancy) and position[knight]) or
    (attackMaskKing(target, occupancy) and position[king]) or
    (attackMaskPawnCapture(target, attacker.opposite) and position[pawn])
  ) and position[attacker]

func isAttacked*(position: Position, us: Color, target: Square): bool =
  not empty position.attackers(us.opposite, target)

func addPiece*(position: var Position, color: Color, piece: Piece, target: Square) {.inline.} =
  let bit = target.toBitboard
  position[piece] |= bit
  position[color] |= bit

func removePiece*(position: var Position, color: Color, piece: Piece, source: Square) {.inline.} =
  let bit = not source.toBitboard
  position[piece] &= bit
  position[color] &= bit

func movePiece*(position: var Position, color: Color, piece: Piece, source, target: Square) {.inline.} =
  position.removePiece(color, piece, source)
  position.addPiece(color, piece, target)

func castlingSide*(position: Position, move: Move): CastlingSide =
  if move.target == position.rookSource[position.us][queenside]:
    return queenside
  kingside

func doMove*(position: Position, move: Move): Position =
  result = position
  let
    target = move.target
    source = move.source
    moved = move.moved
    captured = move.captured
    promoted = move.promoted
    enPassantTarget = move.enPassantTarget
    us = result.us
    enemy = result.enemy

  # Update en passant target
  result.enPassantTarget = enPassantTarget

  # Handle king moves (clear castling rights)
  if moved == king:
    result.rookSource[us] = [noSquare, noSquare]

  # Handle rook moves (clear castling rights)
  for side in queenside .. kingside:
    if result.rookSource[us][side] == source:
      result.rookSource[us][side] = noSquare
    if result.rookSource[enemy][side] == target:
      result.rookSource[enemy][side] = noSquare

  # Handle en passant capture
  if move.capturedEnPassant:
    result.removePiece(enemy, pawn, attackMaskPawnQuiet(target, enemy).toSquare)
  # Handle normal capture
  elif captured != noPiece:
    result.removePiece(enemy, captured, target)

  # Handle castling
  if move.castled:
    let
      rookSource = target
      kingSource = source
      castlingSide = position.castlingSide(move)
      rookTarget = rookTarget[us][castlingSide]
      kingTarget = kingTarget[us][castlingSide]

    result.removePiece(us, king, kingSource)
    result.removePiece(us, rook, rookSource)

    result.addPiece(us, king, kingTarget)
    result.addPiece(us, rook, rookTarget)
  # Handle normal move or promotion
  else:
    if promoted != noPiece:
      result.removePiece(us, moved, source)
      result.addPiece(us, promoted, target)
    else:
      result.movePiece(us, moved, source, target)

  # Update halfmove counters
  result.halfmovesPlayed += 1
  result.halfmoveClock += 1
  if moved == pawn or captured != noPiece:
    result.halfmoveClock = 0

  # Switch side to move
  result.us = result.enemy

# Check if a move is legal
func isLegal*(position: Position, move: Move): bool =
  # Check if the move is valid
  if move.source == noSquare or move.target == noSquare:
    return false
  
  # Check if the piece belongs to the player
  let us = position.us
  if empty(position[us] and move.source.toBitboard):
    return false
  
  # Check if the moved piece is correct
  var foundPiece = false
  for piece in pawn .. king:
    if not empty(position[piece] and move.source.toBitboard):
      if piece != move.moved:
        return false
      foundPiece = true
      break
  
  if not foundPiece:
    return false
  
  # For castling moves
  if move.castled:
    # Check if castling is allowed
    let castlingSide = position.castlingSide(move)
    if position.rookSource[us][castlingSide] == noSquare:
      return false
    
    # Check if the path is clear
    let 
      kingSource = move.source
      rookSource = move.target
    
    if not empty(blockSensitive(us, castlingSide, kingSource, rookSource) and position.occupancy):
      return false
    
    # Check if the king is in check or would pass through check
    for checkSquare in checkSensitive[us][castlingSide][kingSource]:
      if position.isAttacked(us, checkSquare):
        return false
    
    return true
  
  # Make the move and check if our king is in check
  let newPosition = position.doMove(move)
  
  # Find our king in the new position
  let kingBB = newPosition[king] and newPosition[us.opposite]
  if kingBB == 0.Bitboard:
    return true  # No king (shouldn't happen in a real game)
  
  let kingSquare = firstOne(kingBB)
  
  # Check if our king is attacked after the move
  return not newPosition.isAttacked(us.opposite, kingSquare)