import coretypes
import bitboard
import board
import attacks

const seePieceValue*: array[PieceType, int] = [
  100,   # Pawn
  450,   # Knight
  450,   # Bishop
  650,   # Rook
  1250,  # Queen
  0,     # King
  0,     # NoPieceType
]

func seeValue*(pt: PieceType): int {.inline.} =
  seePieceValue[pt]

proc popLeastValuable(
  b:         Board,
  occ:       var Bitboard,
  attackers: Bitboard,
  us:        Color
): PieceType {.inline.} =
  const order = [Pawn, Knight, Bishop, Rook, Queen, King]
  for pt in order:
    let bb = attackers and b.pieces(pt, us)
    if not bb.isEmpty:
      occ = occ xor bb.lsb.bit
      return pt
  return NoPieceType

func captureGain(b: Board, m: Move): int {.inline.} =
  case m.moveType
  of Castling:
    return 0
  of EnPassant:
    return seeValue(Pawn)
  of Promotion:
    let captured = b.pieceOn(m.toSq)
    let gain = if captured != NoPiece: seeValue(captured.pieceType) else: 0
    let promoPt = case m.promoType
      of PromoKnight: Knight
      of PromoBishop: Bishop
      of PromoRook:   Rook
      of PromoQueen:  Queen
    return gain + seeValue(promoPt) - seeValue(Pawn)
  of Normal:
    let captured = b.pieceOn(m.toSq)
    return if captured != NoPiece: seeValue(captured.pieceType) else: 0

proc see*(b: Board, m: Move, threshold: int = 0): bool =
  if m.moveType == Castling:
    return threshold <= 0

  var score = captureGain(b, m) - threshold
  if score < 0:
    return false

  let movingPt =
    if m.moveType == Promotion:
      case m.promoType
      of PromoKnight: Knight
      of PromoBishop: Bishop
      of PromoRook:   Rook
      of PromoQueen:  Queen
    else:
      b.pieceOn(m.fromSq).pieceType

  score -= seeValue(movingPt)
  if score >= 0:
    return true

  let sq = m.toSq
  var occ = b.occupied xor m.fromSq.bit xor sq.bit

  if m.moveType == EnPassant:
    let capSq = sq + (if b.stm == White: -8 else: 8)
    occ = occ xor capSq.bit

  let diagSliders = b.pieces(Bishop, White) or b.pieces(Bishop, Black) or
                    b.pieces(Queen,  White) or b.pieces(Queen,  Black)
  let hvSliders   = b.pieces(Rook,  White) or b.pieces(Rook,  Black)  or
                    b.pieces(Queen,  White) or b.pieces(Queen,  Black)
  let whiteKingSq = b.kingSquare(White)
  let blackKingSq = b.kingSquare(Black)

  let whiteKingRay = rayBetween(whiteKingSq, sq) or sq.bit
  let blackKingRay = rayBetween(blackKingSq, sq) or sq.bit

  let allowed = not (b.pinHV or b.pinD12) or
                (b.pinHV and whiteKingRay) or
                (b.pinD12 and whiteKingRay) or
                (b.pinHV and blackKingRay) or
                (b.pinD12 and blackKingRay)

  var attackers = b.attackersTo(sq, occ) and allowed

  var us = b.stm.opposite

  while true:
    let ourAttackers = attackers and b.byColor[us.ord]
    if ourAttackers.isEmpty:
      break

    let nextPt = popLeastValuable(b, occ, ourAttackers, us)
    if nextPt == NoPieceType:
      break

    if nextPt in {Pawn, Bishop, Queen}:
      attackers = attackers or (getBishopAttacks(sq, occ) and diagSliders)
    if nextPt in {Rook, Queen}:
      attackers = attackers or (getRookAttacks(sq, occ) and hvSliders)

    attackers = attackers and occ

    attackers = attackers and allowed

    score = -score - 1 - seeValue(nextPt)
    us = us.opposite

    if score >= 0:
      if nextPt == King and not (attackers and b.byColor[us.ord]).isEmpty:
        us = us.opposite
      break

  return b.stm != us
