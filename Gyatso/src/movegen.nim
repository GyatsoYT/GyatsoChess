import coretypes, board, move, bitboard, lookups, utils, magicbitboards,
    see, history

const
  MaxBadCaptures* = 64

type
  GenStage* = enum
    StageHash, StageGenCaps, StageGoodCaps,
    StageKiller, StageGenQuiets, StageQuiets,
    StageBadCaps, StageDone

  BadCapList* = object
    moves*: array[MaxBadCaptures, Move]
    scores*: array[MaxBadCaptures, int32]
    count*: int

  MovePicker* = object
    stage*: GenStage
    ttMove*: Move
    killerMove*: Move
    moves*: MoveList
    badCaps*: BadCapList
    idx*: int
    phase*: int

proc pickBadCap*(bl: var BadCapList, startIndex: int): Move {.inline.} =
  var bestIndex: int32 = startIndex.int32
  var bestScore: int32 = bl.scores[startIndex]
  for i in (startIndex.int32 + 1) ..< bl.count.int32:
    if bl.scores[i] > bestScore:
      bestScore = bl.scores[i]
      bestIndex = i
  let bestIdx = bestIndex.int
  swap(bl.moves[startIndex], bl.moves[bestIdx])
  swap(bl.scores[startIndex], bl.scores[bestIdx])
  return bl.moves[startIndex]

proc initMovePicker*(ttMove: Move, killer: Move, phase: int): MovePicker =
  result.stage = StageHash
  result.ttMove = ttMove
  result.killerMove = killer
  result.moves.count = 0
  result.badCaps.count = 0
  result.idx = 0
  result.phase = phase

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
          not getBit(board.allPiecesBB, squareFromCoords(0, 6)): # g1
            if not isSquareAttacked(board, squareFromCoords(0, 4), Black) and # e1
              not isSquareAttacked(board, squareFromCoords(0, 5), Black) and # f1
              not isSquareAttacked(board, squareFromCoords(0, 6), Black): # g1
                ml.addMove(makeMove(squareFromCoords(0, 4), squareFromCoords(0,
                    6), NoPieceType, KingCastle.int))

      # Queen Side (e1 -> c1)
      if (board.castlingRights and WhiteQueenSide) != 0:
        if not getBit(board.allPiecesBB, squareFromCoords(0, 3)) and # d1
          not getBit(board.allPiecesBB, squareFromCoords(0, 2)) and # c1
          not getBit(board.allPiecesBB, squareFromCoords(0, 1)): # b1
            if not isSquareAttacked(board, squareFromCoords(0, 4), Black) and # e1
              not isSquareAttacked(board, squareFromCoords(0, 3), Black) and # d1
              not isSquareAttacked(board, squareFromCoords(0, 2), Black): # c1
                ml.addMove(makeMove(squareFromCoords(0, 4), squareFromCoords(0,
                    2), NoPieceType, QueenCastle.int))
    else:
      # King Side (e8 -> g8)
      if (board.castlingRights and BlackKingSide) != 0:
        if not getBit(board.allPiecesBB, squareFromCoords(7, 5)) and # f8
          not getBit(board.allPiecesBB, squareFromCoords(7, 6)): # g8
            if not isSquareAttacked(board, squareFromCoords(7, 4), White) and # e8
              not isSquareAttacked(board, squareFromCoords(7, 5), White) and # f8
              not isSquareAttacked(board, squareFromCoords(7, 6), White): # g8
                ml.addMove(makeMove(squareFromCoords(7, 4), squareFromCoords(7,
                    6), NoPieceType, KingCastle.int))

      # Queen Side (e8 -> c8)
      if (board.castlingRights and BlackQueenSide) != 0:
        if not getBit(board.allPiecesBB, squareFromCoords(7, 3)) and # d8
          not getBit(board.allPiecesBB, squareFromCoords(7, 2)) and # c8
          not getBit(board.allPiecesBB, squareFromCoords(7, 1)): # b8
            if not isSquareAttacked(board, squareFromCoords(7, 4), White) and # e8
              not isSquareAttacked(board, squareFromCoords(7, 3), White) and # d8
              not isSquareAttacked(board, squareFromCoords(7, 2), White): # c8
                ml.addMove(makeMove(squareFromCoords(7, 4), squareFromCoords(7,
                    2), NoPieceType, QueenCastle.int))

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
  var bishops = board.pieceBB[makePiece(us, Bishop)] or board.pieceBB[makePiece(
      us, Queen)]
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
  let validTargets = board.occupiedBB[them] and not board.pieceBB[makePiece(
      them, King)]

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
  var bishops = board.pieceBB[makePiece(us, Bishop)] or board.pieceBB[makePiece(
      us, Queen)]
  while bishops != 0:
    let fromSq = popBit(bishops)
    var moves = getBishopAttacks(fromSq, occupied) and themBB
    while moves != 0:
      let toSq = popBit(moves)
      #let isCap = true # Captured piece known to be valid (not King)
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


proc scoreMove*(board: Board, move: Move, ttMove: Move, stack: openArray[StackEntry],
                ply: int, phase: int, history: HistoryTables): int32 {.inline.} =
  # TT move gets highest priority
  if move == ttMove:
    return 2_000_000'i32

  # Captures and promotions
  if move.isCapture or move.isPromotion:
    var baseScore = 1_000_000'i32

    # MVV-LVA / Promotion Score
    if move.isCapture:
      var victimVal = 0
      if move.isEnPassant:
        victimVal = getPieceValue(Pawn, phase)
      else:
        let victim = pieceType(board.pieces[move.toSquare])
        victimVal = getPieceValue(victim, phase)

      let attacker = pieceType(board.pieces[move.fromSquare])
      baseScore += (victimVal * 16 - getPieceValue(attacker, phase)).int32

    if move.isPromotion:
      baseScore += (getPieceValue(move.promotion, phase) * 10).int32

    # SEE Check
    let seeVal = see(board, move, phase).int32

    if seeVal >= 0:
      return baseScore
    else:
      return -50_000'i32 + seeVal

  # Quiet moves

  # Killers
  if stack[ply].killers[0] == uint32(move): return 195_000'i32

  # Combined quiet history score
  var score = history.mainHistory[board.sideToMove.ord][historyIndex(move)].int32

  # 1-ply continuation history
  if ply > 0 and stack[ply - 1].move != 0:
    let prevPiece = stack[ply - 1].movedPiece
    if prevPiece != NoPiece:
      let prevTo = Move(stack[ply - 1].move).toSquare.int
      let currPiece = board.pieces[move.fromSquare]
      score += history.contHistory[prevPiece][prevTo][currPiece][move.toSquare.int].int32

  return score

proc pickMove*(ml: var MoveList, startIndex: int): Move {.inline,
    noSideEffect.} =
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

proc generatePseudoLegalQuiets*(board: Board, ml: var MoveList) {.gcsafe.} =
  ## Generate all non-capture, non-promotion quiet moves.
  let us = board.sideToMove
  let them = if us == White: Black else: White
  let themKing = board.pieceBB[makePiece(them, King)]
  let empty = not board.allPiecesBB

  # Pawn Quiets (single push non-promotion + double push)
  let pawns = board.pieceBB[makePiece(us, Pawn)]
  let promotionRank = if us == White: 6 else: 1
  let up = if us == White: 8 else: -8

  var singlePush = if us == White: (pawns shl 8) else: (pawns shr 8)
  singlePush = singlePush and not board.allPiecesBB

  var bb = singlePush
  while bb != 0:
    let toSq = popBit(bb)
    let fromSq = (toSq.int - up).Square
    if rankOf(fromSq) != promotionRank:
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

  # Knight Quiets
  var knights = board.pieceBB[makePiece(us, Knight)]
  while knights != 0:
    let fromSq = popBit(knights)
    var moves = knightAttacks[fromSq] and empty and not themKing
    while moves != 0:
      let toSq = popBit(moves)
      ml.addMove(makeMove(fromSq, toSq, NoPieceType, Quiet.int))

  # King Quiets (including castling)
  var king = board.pieceBB[makePiece(us, King)]
  if king != 0:
    let fromSq = popBit(king)
    var moves = kingAttacks[fromSq] and empty and not themKing
    while moves != 0:
      let toSq = popBit(moves)
      ml.addMove(makeMove(fromSq, toSq, NoPieceType, Quiet.int))

    # Castling
    if us == White:
      if (board.castlingRights and WhiteKingSide) != 0:
        if not getBit(board.allPiecesBB, squareFromCoords(0, 5)) and
          not getBit(board.allPiecesBB, squareFromCoords(0, 6)):
            if not isSquareAttacked(board, squareFromCoords(0, 4), Black) and
              not isSquareAttacked(board, squareFromCoords(0, 5), Black) and
              not isSquareAttacked(board, squareFromCoords(0, 6), Black):
                ml.addMove(makeMove(squareFromCoords(0, 4), squareFromCoords(0,
                    6), NoPieceType, KingCastle.int))

      if (board.castlingRights and WhiteQueenSide) != 0:
        if not getBit(board.allPiecesBB, squareFromCoords(0, 3)) and
          not getBit(board.allPiecesBB, squareFromCoords(0, 2)) and
          not getBit(board.allPiecesBB, squareFromCoords(0, 1)):
            if not isSquareAttacked(board, squareFromCoords(0, 4), Black) and
              not isSquareAttacked(board, squareFromCoords(0, 3), Black) and
              not isSquareAttacked(board, squareFromCoords(0, 2), Black):
                ml.addMove(makeMove(squareFromCoords(0, 4), squareFromCoords(0,
                    2), NoPieceType, QueenCastle.int))
    else:
      if (board.castlingRights and BlackKingSide) != 0:
        if not getBit(board.allPiecesBB, squareFromCoords(7, 5)) and
          not getBit(board.allPiecesBB, squareFromCoords(7, 6)):
            if not isSquareAttacked(board, squareFromCoords(7, 4), White) and
              not isSquareAttacked(board, squareFromCoords(7, 5), White) and
              not isSquareAttacked(board, squareFromCoords(7, 6), White):
                ml.addMove(makeMove(squareFromCoords(7, 4), squareFromCoords(7,
                    6), NoPieceType, KingCastle.int))

      if (board.castlingRights and BlackQueenSide) != 0:
        if not getBit(board.allPiecesBB, squareFromCoords(7, 3)) and
          not getBit(board.allPiecesBB, squareFromCoords(7, 2)) and
          not getBit(board.allPiecesBB, squareFromCoords(7, 1)):
            if not isSquareAttacked(board, squareFromCoords(7, 4), White) and
              not isSquareAttacked(board, squareFromCoords(7, 3), White) and
              not isSquareAttacked(board, squareFromCoords(7, 2), White):
                ml.addMove(makeMove(squareFromCoords(7, 4), squareFromCoords(7,
                    2), NoPieceType, QueenCastle.int))

  # Sliding Piece Quiets
  let occupied = board.allPiecesBB

  # Rooks & Queens
  var rooks = board.pieceBB[makePiece(us, Rook)] or board.pieceBB[makePiece(us, Queen)]
  while rooks != 0:
    let fromSq = popBit(rooks)
    var moves = getRookAttacks(fromSq, occupied) and empty and not themKing
    while moves != 0:
      let toSq = popBit(moves)
      ml.addMove(makeMove(fromSq, toSq, NoPieceType, Quiet.int))

  # Bishops & Queens
  var bishops = board.pieceBB[makePiece(us, Bishop)] or board.pieceBB[makePiece(us, Queen)]
  while bishops != 0:
    let fromSq = popBit(bishops)
    var moves = getBishopAttacks(fromSq, occupied) and empty and not themKing
    while moves != 0:
      let toSq = popBit(moves)
      ml.addMove(makeMove(fromSq, toSq, NoPieceType, Quiet.int))

proc isPseudoLegal*(board: Board, m: Move): bool {.inline.} =
  ## Validate that a move is pseudolegal for the current position.
  if m == Move(0): return false
  let fromSq = m.fromSquare
  let toSq = m.toSquare
  let piece = board.pieces[fromSq]
  if piece == NoPiece: return false
  let us = board.sideToMove
  if pieceColor(piece) != us: return false
  let them = if us == White: Black else: White
  let toBB = 1'u64 shl toSq
  if (toBB and board.occupiedBB[us]) != 0: return false
  if (toBB and board.pieceBB[makePiece(them, King)]) != 0: return false
  if m.isCapture:
    if not m.isEnPassant:
      if (toBB and board.occupiedBB[them]) == 0: return false
  else:
    if not m.isCastle:
      if (toBB and board.allPiecesBB) != 0: return false
  let pt = pieceType(piece)
  case pt
  of Pawn:
    let up = if us == White: 8 else: -8
    if m.isCapture:
      if m.isEnPassant:
        return toSq.int == board.enPassantSquare and
               (pawnAttacks[us][fromSq] and toBB) != 0
      return (pawnAttacks[us][fromSq] and toBB) != 0
    else:
      if toSq.int - fromSq.int == up:
        return true
      elif toSq.int - fromSq.int == 2 * up:
        let midSq = (fromSq.int + up).Square
        return not getBit(board.allPiecesBB, midSq)
      else:
        return false
  of Knight:
    return (knightAttacks[fromSq] and toBB) != 0
  of Bishop:
    return (getBishopAttacks(fromSq, board.allPiecesBB) and toBB) != 0
  of Rook:
    return (getRookAttacks(fromSq, board.allPiecesBB) and toBB) != 0
  of Queen:
    return ((getBishopAttacks(fromSq, board.allPiecesBB) or
             getRookAttacks(fromSq, board.allPiecesBB)) and toBB) != 0
  of King:
    if m.isCastle:
      let flags = m.flags
      if us == White:
        if fromSq != squareFromCoords(0, 4): return false
        if flags == KingCastle.int:
          return (board.castlingRights and WhiteKingSide) != 0 and
                 not getBit(board.allPiecesBB, squareFromCoords(0, 5)) and
                 not getBit(board.allPiecesBB, squareFromCoords(0, 6)) and
                 not isSquareAttacked(board, squareFromCoords(0, 4), Black) and
                 not isSquareAttacked(board, squareFromCoords(0, 5), Black) and
                 not isSquareAttacked(board, squareFromCoords(0, 6), Black)
        elif flags == QueenCastle.int:
          return (board.castlingRights and WhiteQueenSide) != 0 and
                 not getBit(board.allPiecesBB, squareFromCoords(0, 3)) and
                 not getBit(board.allPiecesBB, squareFromCoords(0, 2)) and
                 not getBit(board.allPiecesBB, squareFromCoords(0, 1)) and
                 not isSquareAttacked(board, squareFromCoords(0, 4), Black) and
                 not isSquareAttacked(board, squareFromCoords(0, 3), Black) and
                 not isSquareAttacked(board, squareFromCoords(0, 2), Black)
        else: return false
      else:
        if fromSq != squareFromCoords(7, 4): return false
        if flags == KingCastle.int:
          return (board.castlingRights and BlackKingSide) != 0 and
                 not getBit(board.allPiecesBB, squareFromCoords(7, 5)) and
                 not getBit(board.allPiecesBB, squareFromCoords(7, 6)) and
                 not isSquareAttacked(board, squareFromCoords(7, 4), White) and
                 not isSquareAttacked(board, squareFromCoords(7, 5), White) and
                 not isSquareAttacked(board, squareFromCoords(7, 6), White)
        elif flags == QueenCastle.int:
          return (board.castlingRights and BlackQueenSide) != 0 and
                 not getBit(board.allPiecesBB, squareFromCoords(7, 3)) and
                 not getBit(board.allPiecesBB, squareFromCoords(7, 2)) and
                 not getBit(board.allPiecesBB, squareFromCoords(7, 1)) and
                 not isSquareAttacked(board, squareFromCoords(7, 4), White) and
                 not isSquareAttacked(board, squareFromCoords(7, 3), White) and
                 not isSquareAttacked(board, squareFromCoords(7, 2), White)
        else: return false
    return (kingAttacks[fromSq] and toBB) != 0
  else:
    return false

proc next*(mp: var MovePicker, board: Board, ht: HistoryTables,
           stack: openArray[StackEntry], ply: int): Move =
  while true:
    case mp.stage
    of StageHash:
      mp.stage = StageGenCaps
      if mp.ttMove != Move(0) and isPseudoLegal(board, mp.ttMove):
        return mp.ttMove

    of StageGenCaps:
      mp.stage = StageGoodCaps
      mp.idx = 0
      generatePseudoLegalCaptures(board, mp.moves)
      for i in 0 ..< mp.moves.count:
        mp.moves.scores[i] = scoreMove(board, mp.moves.moves[i], Move(0),
                                       stack, ply, mp.phase, ht)

    of StageGoodCaps:
      while mp.idx < mp.moves.count:
        let m = pickMove(mp.moves, mp.idx)
        inc mp.idx
        if m == mp.ttMove: continue
        let seeVal = see(board, m, mp.phase)
        if seeVal >= 0:
          return m
        else:
          # defer to bad captures stage
          if mp.badCaps.count < MaxBadCaptures:
            mp.badCaps.moves[mp.badCaps.count] = m
            mp.badCaps.scores[mp.badCaps.count] = seeVal.int32
            inc mp.badCaps.count
      mp.stage = StageKiller
      mp.idx = 0

    of StageKiller:
      mp.stage = StageGenQuiets
      let k = mp.killerMove
      if k != Move(0) and k != mp.ttMove and not k.isCapture and not k.isPromotion and isPseudoLegal(board, k):
        return k

    of StageGenQuiets:
      mp.stage = StageQuiets
      mp.idx = 0
      # Generate quiets directly into mp.moves
      mp.moves.count = 0
      generatePseudoLegalQuiets(board, mp.moves)
      # Remove duplicates
      var writeIdx = 0
      for i in 0 ..< mp.moves.count:
        let m = mp.moves.moves[i]
        if m == mp.ttMove or m == mp.killerMove: continue
        mp.moves.moves[writeIdx] = m
        mp.moves.scores[writeIdx] = scoreMove(board, m, Move(0),
                                               stack, ply, mp.phase, ht).int32
        inc writeIdx
      mp.moves.count = writeIdx

    of StageQuiets:
      while mp.idx < mp.moves.count:
        let m = pickMove(mp.moves, mp.idx)
        inc mp.idx
        return m
      mp.stage = StageBadCaps
      mp.idx = 0

    of StageBadCaps:
      while mp.idx < mp.badCaps.count:
        let m = pickBadCap(mp.badCaps, mp.idx)
        inc mp.idx
        if m == mp.ttMove: continue
        return m
      mp.stage = StageDone

    of StageDone:
      return Move(0)
