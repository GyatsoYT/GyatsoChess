import types, move, position, positionUtils, evaluation, bitboard

template orderedPieces(): auto =
  (pawn, knight, bishop, rook, queen, king).fields

func checkAssumptions(): bool =
  var previousPiece = noPiece
  for piece in orderedPieces:
    var next = piece
    inc next
    if previousPiece != noPiece and piece.value <= previousPiece.value:
      return false
    previousPiece = piece
  true

static:
  doAssert checkAssumptions()

func see(position: var Position, target: Square, victim: Piece, us: Color): Value =
  let attackers = position.attackers(us, target)
  for piece in orderedPieces:
    let attack = position[piece, us] and attackers
    if not empty attack:
      position.removePiece(us, piece, attack.toSquare)

      var
        collected = victim.value
        newVictim = piece

      when piece == pawn:
        if target notin a2 .. h7:
          newVictim = queen
          collected += queen.value - pawn.value

      return max(0, collected - position.see(target, newVictim, us.opposite))
  0

func see*(position: Position, move: Move): Value =
  result = 0

  let
    us = position.us
    enemy = position.enemy
    source = move.source
    target = move.target
    moved = move.moved
    promoted = move.promoted

  var
    position = position
    currentVictim = moved

  position.removePiece(us, moved, source)

  if move.capturedEnPassant:
    position.removePiece(enemy, pawn, attackMaskPawnQuiet(target, enemy).toSquare)
    position.removePiece(us, pawn, source)
  elif promoted != noPiece:
    position.removePiece(us, moved, source)
    result = promoted.value - pawn.value
    currentVictim = promoted
  else:
    position.removePiece(us, moved, source)

  result += move.captured.value - position.see(target, currentVictim, enemy)
