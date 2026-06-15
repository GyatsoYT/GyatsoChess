import coretypes
import bitboard
import attacks
import board

# Internal helpers

func promotionRank(c: Color): Bitboard {.inline.} =
  if c == White: rankMask(7) else: rankMask(0)

func thirdRank(c: Color): Bitboard {.inline.} =
  if c == White: rankMask(2) else: rankMask(5)

func pawnPush(bb: Bitboard, c: Color): Bitboard {.inline.} =
  if c == White: bb shl 8 else: bb shr 8


func pawnAttackLeft(bb: Bitboard, c: Color): Bitboard {.inline.} =
  if c == White: (bb and not FileA) shl 7
  else:          (bb and not FileH) shr 7

func pawnAttackRight(bb: Bitboard, c: Color): Bitboard {.inline.} =
  if c == White: (bb and not FileH) shl 9
  else:          (bb and not FileA) shr 9

proc addPawnPromotions(ml: var MoveList, fromSq, toSq: Square) {.inline.} =
  ml.add(makePromo(fromSq, toSq, PromoQueen))
  ml.add(makePromo(fromSq, toSq, PromoRook))
  ml.add(makePromo(fromSq, toSq, PromoBishop))
  ml.add(makePromo(fromSq, toSq, PromoKnight))

proc generateKingMoves(b: Board, ml: var MoveList, targetMask: Bitboard) =
  let kingSq = b.kingSquare(b.stm)
  var targets = getKingAttacks(kingSq) and targetMask and not b.threats
  for toSq in targets:
    ml.add(makeMove(kingSq, toSq))

proc generateCastlingMoves(b: Board, ml: var MoveList) =
  let occ     = b.occupied
  let threats = b.threats
  let us      = b.stm

  if us == White:
    if b.castling.hasWK() and
       b.mailbox[H1.int] == WhiteRook and
       (occ and (F1.bit or G1.bit)).isEmpty() and
       (threats and (E1.bit or F1.bit or G1.bit)).isEmpty():
      ml.add(makeCastle(E1, G1))
    if b.castling.hasWQ() and
       b.mailbox[A1.int] == WhiteRook and
       (occ and (B1.bit or C1.bit or D1.bit)).isEmpty() and
       (threats and (E1.bit or D1.bit or C1.bit)).isEmpty():
      ml.add(makeCastle(E1, C1))
  else:
    if b.castling.hasBK() and
       b.mailbox[H8.int] == BlackRook and
       (occ and (F8.bit or G8.bit)).isEmpty() and
       (threats and (E8.bit or F8.bit or G8.bit)).isEmpty():
      ml.add(makeCastle(E8, G8))
    if b.castling.hasBQ() and
       b.mailbox[A8.int] == BlackRook and
       (occ and (B8.bit or C8.bit or D8.bit)).isEmpty() and
       (threats and (E8.bit or D8.bit or C8.bit)).isEmpty():
      ml.add(makeCastle(E8, C8))

proc generateKnightMoves(b: Board, ml: var MoveList, dstMask: Bitboard) =
  let ours = b.byColor[b.stm.ord]
  let pinned = b.pinHV or b.pinD12
  var knights = b.pieces(PieceType.Knight, b.stm) and not pinned
  for sq in knights:
    var targets = getKnightAttacks(sq) and not ours and dstMask
    for toSq in targets:
      ml.add(makeMove(sq, toSq))

proc generateSliderMoves(b: Board, ml: var MoveList, dstMask: Bitboard) =
  let us   = b.stm
  let occ  = b.occupied
  let ours = b.byColor[us.ord]

  let queens  = b.pieces(PieceType.Queen, us)
  let rookMovers   = queens or b.pieces(PieceType.Rook,   us)
  let bishopMovers = queens or b.pieces(PieceType.Bishop, us)

  var unpinnedRooks = rookMovers and not (b.pinHV or b.pinD12)
  for sq in unpinnedRooks:
    var targets = getRookAttacks(sq, occ) and not ours and dstMask
    for toSq in targets:
      ml.add(makeMove(sq, toSq))

  var pinnedHVRooks = rookMovers and b.pinHV and not b.pinD12
  for sq in pinnedHVRooks:
    var targets = getRookAttacks(sq, occ) and not ours and dstMask and b.pinHV
    for toSq in targets:
      ml.add(makeMove(sq, toSq))

  var unpinnedBishops = bishopMovers and not (b.pinHV or b.pinD12)
  for sq in unpinnedBishops:
    var targets = getBishopAttacks(sq, occ) and not ours and dstMask
    for toSq in targets:
      ml.add(makeMove(sq, toSq))

  var pinnedD12Bishops = bishopMovers and b.pinD12 and not b.pinHV
  for sq in pinnedD12Bishops:
    var targets = getBishopAttacks(sq, occ) and not ours and dstMask and b.pinD12
    for toSq in targets:
      ml.add(makeMove(sq, toSq))

proc isEpLegal(b: Board, fromSq, epSq: Square): bool {.inline.} =
  let us     = b.stm
  let them   = us.opposite()
  let kingSq = b.kingSquare(us)
  let capturedSq = if us == White: epSq + (-8) else: epSq + 8

  let occAfterEP = (b.occupied and not fromSq.bit and not capturedSq.bit) or epSq.bit
  
  let enemyHV  = b.pieces(PieceType.Rook, them) or b.pieces(PieceType.Queen, them)
  let enemyD12 = b.pieces(PieceType.Bishop, them) or b.pieces(PieceType.Queen, them)
  
  if not (getRookAttacks(kingSq, occAfterEP) and enemyHV).isEmpty():
    return false
  if not (getBishopAttacks(kingSq, occAfterEP) and enemyD12).isEmpty():
    return false
  return true

proc generatePawnMoves(b: Board, ml: var MoveList, dstMask: Bitboard) =
  let us    = b.stm
  let them  = us.opposite()
  let occ   = b.occupied
  let theirs = b.byColor[them.ord]
  let kingSq = b.kingSquare(us)

  let promoRank = promotionRank(us)
  let leftPinMask  = antiDiagonals[kingSq.int]
  let rightPinMask = diagonals[kingSq.int]

  let pawns = b.pieces(PieceType.Pawn, us)
  let horizontalPins = rankMask(kingSq.rank) and b.pinHV
  let pushablePawns  = pawns and not b.pinD12 and not horizontalPins

  let singlePush = pawnPush(pushablePawns, us) and not occ

  var singles = singlePush and dstMask and not promoRank
  for toSq in singles:
    let fromSq = if us == White: toSq + (-8) else: toSq + 8
    ml.add(makeMove(fromSq, toSq))

  var promoSingles = singlePush and dstMask and promoRank
  for toSq in promoSingles:
    let fromSq = if us == White: toSq + (-8) else: toSq + 8
    addPawnPromotions(ml, fromSq, toSq)

  let doublePush = pawnPush(singlePush and thirdRank(us), us) and not occ and dstMask
  for toSq in doublePush:
    let fromSq = if us == White: toSq + (-16) else: toSq + 16
    ml.add(makeMove(fromSq, toSq))

  let leftMovable  = (pawns and not b.pinHV and not b.pinD12) or
                     (pawns and leftPinMask and b.pinD12)
  let rightMovable = (pawns and not b.pinHV and not b.pinD12) or
                     (pawns and rightPinMask and b.pinD12)

  let leftCaptures  = pawnAttackLeft(leftMovable,  us) and theirs and dstMask
  let rightCaptures = pawnAttackRight(rightMovable, us) and theirs and dstMask

  for toSq in leftCaptures and not promoRank:
    let fromSq = if us == White: toSq + (-7) else: toSq + 7
    ml.add(makeMove(fromSq, toSq))

  for toSq in leftCaptures and promoRank:
    let fromSq = if us == White: toSq + (-7) else: toSq + 7
    addPawnPromotions(ml, fromSq, toSq)

  for toSq in rightCaptures and not promoRank:
    let fromSq = if us == White: toSq + (-9) else: toSq + 9
    ml.add(makeMove(fromSq, toSq))

  for toSq in rightCaptures and promoRank:
    let fromSq = if us == White: toSq + (-9) else: toSq + 9
    addPawnPromotions(ml, fromSq, toSq)

  if b.epSquare != NoSquare:
    let epSq = b.epSquare
    let epBit = epSq.bit

    let capturedSq = if us == White: epSq + (-8) else: epSq + 8
    let epInMask = not (dstMask and (epBit or capturedSq.bit)).isEmpty()

    if epInMask:
      let leftAttacker = pawnAttackLeft(leftMovable, us) and epBit
      if not leftAttacker.isEmpty():
        let fromSq = if us == White: epSq - 7 else: epSq + 7
        if isEpLegal(b, fromSq, epSq):
          ml.add(makeEnPassant(fromSq, epSq))

      let rightAttacker = pawnAttackRight(rightMovable, us) and epBit
      if not rightAttacker.isEmpty():
        let fromSq = if us == White: epSq - 9 else: epSq + 9
        if isEpLegal(b, fromSq, epSq):
          ml.add(makeEnPassant(fromSq, epSq))

proc generateMoves*(b: Board, ml: var MoveList) =
  ml.clear()
  let us     = b.stm
  let kingSq = b.kingSquare(us)
  let ours   = b.byColor[us.ord]

  generateKingMoves(b, ml, not ours)
  if b.checkers.moreThanOne(): return

  let dstMask: Bitboard =
    if b.checkers.isEmpty():
      AllSquares
    else:
      let checker = b.checkers.lsb()
      b.checkers or rayBetween(kingSq, checker)

  generatePawnMoves(b, ml, dstMask)
  generateKnightMoves(b, ml, dstMask)
  generateSliderMoves(b, ml, dstMask)

  if b.checkers.isEmpty():
    generateCastlingMoves(b, ml)

proc generateCaptures*(b: Board, ml: var MoveList) =
  ml.clear()
  let us     = b.stm
  let them   = us.opposite()
  let kingSq = b.kingSquare(us)
  let theirs = b.byColor[them.ord]
  let promos = not b.byColor[us.ord] and promotionRank(us)

  generateKingMoves(b, ml, theirs)
  if b.checkers.moreThanOne(): return

  let baseMask: Bitboard =
    if b.checkers.isEmpty():
      theirs or promos
    else:
      let checker = b.checkers.lsb()
      (b.checkers or rayBetween(kingSq, checker)) and (theirs or promos)

  generatePawnMoves(b, ml, baseMask)
  generateKnightMoves(b, ml, baseMask)
  generateSliderMoves(b, ml, baseMask)

