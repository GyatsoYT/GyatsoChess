import coretypes, board, move, bitboard, lookups, utils, magicbitboards, history

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
  let doublePushRankMask = if us == White: 0x00000000FF000000'u64 else: 0x000000FF00000000'u64
  doublePush = doublePush and doublePushRankMask and not board.allPiecesBB
  
  bb = doublePush
  while bb != 0:
    let toSq = popBit(bb)
    let fromSq = (toSq.int - 2 * up).Square
    ml.addMove(makeMove(fromSq, toSq, NoPieceType, DoublePawnPush.int))

  # Captures
  bb = pawns
  let themKing = board.pieceBB[makePiece(them, King)]
  let validTargets = board.occupiedBB[them] and not themKing
  
  while bb != 0:
    let fromSq = popBit(bb)
    var attacks = pawnAttacks[us][fromSq] and validTargets
    
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
    var epAttackers = pawnAttacks[them][epSq] and pawns
    while epAttackers != 0:
      let fromSq = popBit(epAttackers)
      ml.addMove(makeMove(fromSq, epSq, NoPieceType, EpCapture.int))



proc generateKnightMoves*(board: Board, ml: var MoveList) {.gcsafe.} =
  let us = board.sideToMove
  let them = if us == White: Black else: White
  var knights = board.pieceBB[makePiece(us, Knight)]
  let themKing = board.pieceBB[makePiece(them, King)]
  let notUs = not board.occupiedBB[us]
  
  while knights != 0:
    let fromSq = popBit(knights)
    var moves = knightAttacks[fromSq] and notUs and not themKing
    
    while moves != 0:
      let toSq = popBit(moves)
      let isCap = getBit(board.occupiedBB[them], toSq)
      let flag = if isCap: Capture else: Quiet
      ml.addMove(makeMove(fromSq, toSq, NoPieceType, flag.int))

proc generateKingMoves*(board: Board, ml: var MoveList) {.gcsafe.} =
  let us = board.sideToMove
  let them = if us == White: Black else: White
  var king = board.pieceBB[makePiece(us, King)]
  let themKing = board.pieceBB[makePiece(them, King)]
  let notUs = not board.occupiedBB[us]
  
  if king != 0:
    let fromSq = popBit(king)
    var moves = kingAttacks[fromSq] and notUs and not themKing
    
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
  let themKing = board.pieceBB[makePiece(them, King)]

  while rooks != 0:
    let fromSq = popBit(rooks)
    var moves = getRookAttacks(fromSq, occupied) and notUs and not themKing
    while moves != 0:
      let toSq = popBit(moves)
      let isCap = getBit(board.occupiedBB[them], toSq)
      let flag = if isCap: Capture else: Quiet
      ml.addMove(makeMove(fromSq, toSq, NoPieceType, flag.int))

  # Bishops & Queens (Diagonal)
  var bishops = board.pieceBB[makePiece(us, Bishop)] or board.pieceBB[makePiece(us, Queen)]
  while bishops != 0:
    let fromSq = popBit(bishops)
    var moves = getBishopAttacks(fromSq, occupied) and notUs and not themKing
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

proc generatePawnCaptures(board: Board, ml: var MoveList) {.gcsafe.} =
  let us = board.sideToMove
  let them = if us == White: Black else: White
  let pawns = board.pieceBB[makePiece(us, Pawn)]
  let promotionRank = if us == White: 6 else: 1
  
  # Captures
  var bb = pawns
  let validTargets = board.occupiedBB[them] and not board.pieceBB[makePiece(them, King)]
  
  while bb != 0:
    let fromSq = popBit(bb)
    var attacks = pawnAttacks[us][fromSq] and validTargets
    
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
        
  # Quiet Promotions
  var singlePush = if us == White: (pawns shl 8) else: (pawns shr 8)
  singlePush = singlePush and not board.allPiecesBB
  
  var bbProm = singlePush
  while bbProm != 0:
    let toSq = popBit(bbProm)
    let fromSq = (toSq.int - (if us == White: 8 else: -8)).Square
    if rankOf(fromSq) == promotionRank:
      ml.addMove(makeMove(fromSq, toSq, Queen, Promotion.int))
      ml.addMove(makeMove(fromSq, toSq, Rook, Promotion.int))
      ml.addMove(makeMove(fromSq, toSq, Bishop, Promotion.int))
      ml.addMove(makeMove(fromSq, toSq, Knight, Promotion.int))
        
  # En Passant
  if board.enPassantSquare != NoSquare:
    let epSq = board.enPassantSquare.Square
    var epAttackers = pawnAttacks[them][epSq] and pawns
    while epAttackers != 0:
      let fromSq = popBit(epAttackers)
      ml.addMove(makeMove(fromSq, epSq, NoPieceType, EpCapture.int))

proc generateKnightCaptures(board: Board, ml: var MoveList) {.gcsafe.} =
  let us = board.sideToMove
  var knights = board.pieceBB[makePiece(us, Knight)]
  let them = if us == White: Black else: White
  let themBB = board.occupiedBB[them] and not board.pieceBB[makePiece(them, King)]
  
  while knights != 0:
    let fromSq = popBit(knights)
    var moves = knightAttacks[fromSq] and themBB
    while moves != 0:
      let toSq = popBit(moves)
      ml.addMove(makeMove(fromSq, toSq, NoPieceType, Capture.int))

proc generateKingCaptures(board: Board, ml: var MoveList) {.gcsafe.} =
  let us = board.sideToMove
  let them = if us == White: Black else: White
  let themBB = board.occupiedBB[them] and not board.pieceBB[makePiece(them, King)]
  var king = board.pieceBB[makePiece(us, King)]
  
  if king != 0:
    let fromSq = popBit(king)
    var moves = kingAttacks[fromSq] and themBB
    while moves != 0:
      let toSq = popBit(moves)
      ml.addMove(makeMove(fromSq, toSq, NoPieceType, Capture.int))

proc generateSlidingCaptures(board: Board, ml: var MoveList) {.gcsafe.} =
  let us = board.sideToMove
  let them = if us == White: Black else: White
  let themBB = board.occupiedBB[them] and not board.pieceBB[makePiece(them, King)]
  let occupied = board.allPiecesBB
  
  # Rooks & Queens
  var rooks = board.pieceBB[makePiece(us, Rook)] or board.pieceBB[makePiece(us, Queen)]
  while rooks != 0:
    let fromSq = popBit(rooks)
    var moves = getRookAttacks(fromSq, occupied) and themBB
    while moves != 0:
      let toSq = popBit(moves)
      ml.addMove(makeMove(fromSq, toSq, NoPieceType, Capture.int))

  # Bishops & Queens
  var bishops = board.pieceBB[makePiece(us, Bishop)] or board.pieceBB[makePiece(us, Queen)]
  while bishops != 0:
    let fromSq = popBit(bishops)
    var moves = getBishopAttacks(fromSq, occupied) and themBB
    while moves != 0:
      let toSq = popBit(moves)
      let isCap = true # Captured piece known to be valid (not King)
      ml.addMove(makeMove(fromSq, toSq, NoPieceType, Capture.int))

proc generatePseudoLegalCaptures*(board: Board, ml: var MoveList) {.gcsafe.} =
  ml.clear()
  generatePawnCaptures(board, ml)
  generateKnightCaptures(board, ml)
  generateKingCaptures(board, ml)
  generateSlidingCaptures(board, ml)

proc generateLegalCaptures*(board: var Board, ml: var MoveList) {.gcsafe.} =
  var pseudo {.noinit.}: MoveList
  pseudo.count = 0
  generatePseudoLegalCaptures(board, pseudo)
  ml.clear()
  
  for i in 0 ..< pseudo.count:
    let m = pseudo.moves[i]
    if board.makeMove(m):
      ml.addMove(m)
      board.unmakeMove(m)


proc generateLegalMoves*(board: var Board, ml: var MoveList) {.gcsafe.} =
  var pseudo {.noinit.}: MoveList
  pseudo.count = 0
  generatePseudoLegalMoves(board, pseudo)
  ml.clear()
  
  for i in 0 ..< pseudo.count:
    let m = pseudo.moves[i]
    if board.makeMove(m):
      ml.addMove(m)
      board.unmakeMove(m)


proc getPieceValue(pt: PieceType): int =
  case pt
  of Pawn: PawnValueMG
  of Knight: KnightValueMG
  of Bishop: BishopValueMG
  of Rook: RookValueMG
  of Queen: QueenValueMG
  of King: KingValue
  else: 0

proc scoreMove*(board: Board, move: Move, ttMove: Move, 
                history: var HistoryTables, stack: openArray[StackEntry], ply: int,
                prevMove: Move, grandparentMove: Move): int32 {.inline.} =
  # TT move gets highest priority
  if move == ttMove:
    return 1_000_000'i32
  
  # Captures and promotions
  if move.isCapture or move.isPromotion:
    var score = 100_000'i32  # Base tactical score

    let tacHist = getTacticalHistory(history, move, board).int32
    score += (tacHist div 16)
    
    if move.isCapture:
      # MVV-LVA
      var victimVal = 0'i32
      if move.isEnPassant:
        victimVal = PawnValueMG.int32 # En Passant is always pawn capture
      else:
        let victim = pieceType(board.pieces[move.toSquare])
        victimVal = getPieceValue(victim).int32

      let attacker = pieceType(board.pieces[move.fromSquare])
      score += victimVal * 10'i32 - getPieceValue(attacker).int32
      
    if move.isPromotion:
      score += getPieceValue(move.promotion).int32 * 10'i32
    
    return score
  
  # Quiet moves
  var score: int32 = 0'i32
  
  # Killer moves (from search stack)
  # Ensure we respect array bounds and stack structure
  if stack[ply].killers[0] == uint32(move):
    return 90_000'i32
  if stack[ply].killers[1] == uint32(move):
    return 80_000'i32
  
  # Counter move
  if prevMove != Move(0):
      let counterMove = history.counterMoves[historyIndex(prevMove)]
      if move == counterMove:
        return 70_000'i32
  
  # Combined quiet history (main + counter + follow-up)
  score = getQuietHistory(history, move, board, prevMove, grandparentMove).int32
  
  return score

proc pickMove*(ml: var MoveList, startIndex: int): Move {.inline, noSideEffect.} =
  var bestIndex: int32 = startIndex.int32
  var bestScore: int32 = ml.scores[startIndex]
  let count = ml.count.int32
  
  for i in (startIndex.int32 + 1) ..< count:
    if ml.scores[i] > bestScore:
      bestScore = ml.scores[i]
      bestIndex = i
  

  let bestIdx = bestIndex.int
  swap(ml.moves[startIndex], ml.moves[bestIdx])
  swap(ml.scores[startIndex], ml.scores[bestIdx])
  
  return ml.moves[startIndex]
