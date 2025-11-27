
import coretypes, board, move, bitboard, lookups, utils, magicbitboards, evaluation

proc generatePawnMoves*(board: Board, ml: var MoveList) {.gcsafe.} =
  let us = board.sideToMove
  let them = if us == White: Black else: White
  let pawns = board.pieceBB[makePiece(us, Pawn)]
  let promotionRank = if us == White: 6 else: 1 # Rank before promotion
  let up = if us == White: 8 else: -8
  
  # Single Push
  var singlePush = if us == White: (pawns shl 8) else: (pawns shr 8)
  singlePush = singlePush and not board.allPiecesBB
  
  var bb = singlePush
  while bb != 0:
    let toSq = popBit(bb)
    let fromSq = (toSq.int - up).Square
    
    if rankOf(fromSq) == promotionRank:
      # Promotions
      ml.addMove(makeMove(fromSq, toSq, Queen, Promotion.int))
      ml.addMove(makeMove(fromSq, toSq, Rook, Promotion.int))
      ml.addMove(makeMove(fromSq, toSq, Bishop, Promotion.int))
      ml.addMove(makeMove(fromSq, toSq, Knight, Promotion.int))
    else:
      ml.addMove(makeMove(fromSq, toSq, NoPieceType, Quiet.int))

  # Double Push
  var doublePush = if us == White: (singlePush shl 8) else: (singlePush shr 8)
  # Filter by rank (must start from startRank)
  # For White, single push lands on rank 2 (index 2), double on rank 3. 
  # Wait, startRank is 1 (index 1). Single push lands on 2. Double push lands on 3.
  # We need to filter *sources* on startRank.
  # Easier: Filter doublePush destinations to be on rank 3 (White) or 4 (Black).
  let doublePushRankMask = if us == White: 0x00000000FF000000'u64 else: 0x000000FF00000000'u64
  doublePush = doublePush and doublePushRankMask and not board.allPiecesBB
  
  bb = doublePush
  while bb != 0:
    let toSq = popBit(bb)
    let fromSq = (toSq.int - 2 * up).Square
    ml.addMove(makeMove(fromSq, toSq, NoPieceType, DoublePawnPush.int))

  # Captures
  bb = pawns
  while bb != 0:
    let fromSq = popBit(bb)
    var attacks = pawnAttacks[us][fromSq] and board.occupiedBB[them]
    
    while attacks != 0:
      let toSq = popBit(attacks)
      if rankOf(fromSq) == promotionRank:
        # Capture Promotions
        ml.addMove(makeMove(fromSq, toSq, Queen, CapturePromotion.int))
        ml.addMove(makeMove(fromSq, toSq, Rook, CapturePromotion.int))
        ml.addMove(makeMove(fromSq, toSq, Bishop, CapturePromotion.int))
        ml.addMove(makeMove(fromSq, toSq, Knight, CapturePromotion.int))
      else:
        ml.addMove(makeMove(fromSq, toSq, NoPieceType, Capture.int))

  # En Passant
  if board.enPassantSquare != NoSquare:
    let epSq = board.enPassantSquare.Square
    # Find pawns that can attack epSq
    # We can use pawnAttacks[them][epSq] to find *our* pawns that attack *their* ep square?
    # No, pawnAttacks[c][s] gives squares attacked BY a pawn of color c on s.
    # We want to know if any of OUR pawns attack epSq.
    # This is equivalent to: if a pawn of OPPONENT color was on epSq, would it attack our pawn?
    # So we check pawnAttacks[them][epSq] and intersect with our pawns.
    
    var epAttackers = pawnAttacks[them][epSq] and pawns
    while epAttackers != 0:
      let fromSq = popBit(epAttackers)
      ml.addMove(makeMove(fromSq, epSq, NoPieceType, EpCapture.int))



proc generateKnightMoves*(board: Board, ml: var MoveList) {.gcsafe.} =
  let us = board.sideToMove
  var knights = board.pieceBB[makePiece(us, Knight)]
  let notUs = not board.occupiedBB[us]
  
  while knights != 0:
    let fromSq = popBit(knights)
    var moves = knightAttacks[fromSq] and notUs
    
    while moves != 0:
      let toSq = popBit(moves)
      let isCap = getBit(board.occupiedBB[if us == White: Black else: White], toSq)
      let flag = if isCap: Capture else: Quiet
      ml.addMove(makeMove(fromSq, toSq, NoPieceType, flag.int))

proc generateKingMoves*(board: Board, ml: var MoveList) {.gcsafe.} =
  let us = board.sideToMove
  let them = if us == White: Black else: White
  var king = board.pieceBB[makePiece(us, King)]
  let notUs = not board.occupiedBB[us]
  
  if king != 0:
    let fromSq = popBit(king)
    var moves = kingAttacks[fromSq] and notUs
    
    while moves != 0:
      let toSq = popBit(moves)
      let isCap = getBit(board.occupiedBB[them], toSq)
      let flag = if isCap: Capture else: Quiet
      ml.addMove(makeMove(fromSq, toSq, NoPieceType, flag.int))
      
    # Castling
    if us == White:
      # King Side (e1 -> g1)
      if (board.castlingRights and WhiteKingSide) != 0:
        if not getBit(board.allPiecesBB, squareFromCoords(0, 5)) and # f1
           not getBit(board.allPiecesBB, squareFromCoords(0, 6)):    # g1
             if not isSquareAttacked(board, squareFromCoords(0, 4), Black) and # e1
                not isSquareAttacked(board, squareFromCoords(0, 5), Black) and # f1
                not isSquareAttacked(board, squareFromCoords(0, 6), Black):    # g1
                  ml.addMove(makeMove(squareFromCoords(0, 4), squareFromCoords(0, 6), NoPieceType, KingCastle.int))
      
      # Queen Side (e1 -> c1)
      if (board.castlingRights and WhiteQueenSide) != 0:
        if not getBit(board.allPiecesBB, squareFromCoords(0, 3)) and # d1
           not getBit(board.allPiecesBB, squareFromCoords(0, 2)) and # c1
           not getBit(board.allPiecesBB, squareFromCoords(0, 1)):    # b1
             if not isSquareAttacked(board, squareFromCoords(0, 4), Black) and # e1
                not isSquareAttacked(board, squareFromCoords(0, 3), Black) and # d1
                not isSquareAttacked(board, squareFromCoords(0, 2), Black):    # c1
                  ml.addMove(makeMove(squareFromCoords(0, 4), squareFromCoords(0, 2), NoPieceType, QueenCastle.int))
    else:
      # King Side (e8 -> g8)
      if (board.castlingRights and BlackKingSide) != 0:
        if not getBit(board.allPiecesBB, squareFromCoords(7, 5)) and # f8
           not getBit(board.allPiecesBB, squareFromCoords(7, 6)):    # g8
             if not isSquareAttacked(board, squareFromCoords(7, 4), White) and # e8
                not isSquareAttacked(board, squareFromCoords(7, 5), White) and # f8
                not isSquareAttacked(board, squareFromCoords(7, 6), White):    # g8
                  ml.addMove(makeMove(squareFromCoords(7, 4), squareFromCoords(7, 6), NoPieceType, KingCastle.int))
                  
      # Queen Side (e8 -> c8)
      if (board.castlingRights and BlackQueenSide) != 0:
        if not getBit(board.allPiecesBB, squareFromCoords(7, 3)) and # d8
           not getBit(board.allPiecesBB, squareFromCoords(7, 2)) and # c8
           not getBit(board.allPiecesBB, squareFromCoords(7, 1)):    # b8
             if not isSquareAttacked(board, squareFromCoords(7, 4), White) and # e8
                not isSquareAttacked(board, squareFromCoords(7, 3), White) and # d8
                not isSquareAttacked(board, squareFromCoords(7, 2), White):    # c8
                  ml.addMove(makeMove(squareFromCoords(7, 4), squareFromCoords(7, 2), NoPieceType, QueenCastle.int))

proc generateSlidingMoves*(board: Board, ml: var MoveList) {.gcsafe.} =
  let us = board.sideToMove
  let them = if us == White: Black else: White
  let occupied = board.allPiecesBB
  let notUs = not board.occupiedBB[us]
  
  # Rooks & Queens (Orthogonal)
  var rooks = board.pieceBB[makePiece(us, Rook)] or board.pieceBB[makePiece(us, Queen)]
  while rooks != 0:
    let fromSq = popBit(rooks)
    var moves = getRookAttacks(fromSq, occupied) and notUs
    while moves != 0:
      let toSq = popBit(moves)
      let isCap = getBit(board.occupiedBB[them], toSq)
      let flag = if isCap: Capture else: Quiet
      ml.addMove(makeMove(fromSq, toSq, NoPieceType, flag.int))

  # Bishops & Queens (Diagonal)
  var bishops = board.pieceBB[makePiece(us, Bishop)] or board.pieceBB[makePiece(us, Queen)]
  while bishops != 0:
    let fromSq = popBit(bishops)
    var moves = getBishopAttacks(fromSq, occupied) and notUs
    while moves != 0:
      let toSq = popBit(moves)
      let isCap = getBit(board.occupiedBB[them], toSq)
      let flag = if isCap: Capture else: Quiet
      ml.addMove(makeMove(fromSq, toSq, NoPieceType, flag.int))

proc generatePseudoLegalMoves*(board: Board, ml: var MoveList) {.gcsafe.} =
  ml.clear()
  generatePawnMoves(board, ml)
  generateKnightMoves(board, ml)
  generateKingMoves(board, ml)
  generateSlidingMoves(board, ml)

proc generateLegalMoves*(board: var Board, ml: var MoveList) {.gcsafe.} =
  var pseudo: MoveList
  generatePseudoLegalMoves(board, pseudo)
  ml.clear()
  
  for i in 0 ..< pseudo.count:
    let m = pseudo.moves[i]
    if board.makeMove(m):
      ml.addMove(m)
      board.unmakeMove(m)

proc getPieceTypeAt(board: Board, sq: Square): PieceType =
  let p = board.pieces[sq]
  if p == NoPiece: return NoPieceType
  return pieceType(p)


proc getPieceValue(pt: PieceType): int =
  case pt
  of Pawn: PawnValue
  of Knight: KnightValue
  of Bishop: BishopValue
  of Rook: RookValue
  of Queen: QueenValue
  of King: KingValue
  else: 0

proc scoreMove*(board: Board, move: Move, ttMove: Move): int =
  if move == ttMove:
    return 20000 # Highest priority
    
  if move.isCapture:
    let victim = getPieceTypeAt(board, move.toSquare)
    # Find attacker
    let us = board.sideToMove
    let attacker = pieceType(board.pieces[move.fromSquare])

        
    if move.isEnPassant:
      return 105 # Pawn captures Pawn (100 + 10*1 - 1) approx
      
    let score = (getPieceValue(victim) * 10) - getPieceValue(attacker)
    return score + 1000 # Offset for captures
    
  if move.isPromotion:
    return getPieceValue(move.promotion) + 500
    
  return 0

proc pickMove*(ml: var MoveList, startIndex: int): Move =
  var bestIndex = startIndex
  var bestScore = -100000
  
  for i in startIndex ..< ml.count:
    if ml.scores[i] > bestScore:
      bestScore = ml.scores[i]
      bestIndex = i
      
  # Swap
  let tempMove = ml.moves[startIndex]
  ml.moves[startIndex] = ml.moves[bestIndex]
  ml.moves[bestIndex] = tempMove
  
  let tempScore = ml.scores[startIndex]
  ml.scores[startIndex] = ml.scores[bestIndex]
  ml.scores[bestIndex] = tempScore
  
  return ml.moves[startIndex]
