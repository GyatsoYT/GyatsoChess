import coretypes, bitboard, board, move, lookups, utils, magicbitboards

proc opponentColor(color: Color): Color {.inline.} =
  ## Returns the opponent's color.
  if color == White: Black else: White

proc generatePawnMoves*(board: Board, ml: var MoveList) =
  ## Generates all pseudo-legal pawn moves for the current side to move.
  ## Includes single pushes, double pushes, captures, promotions, and en passant.

  let us = board.sideToMove
  let them = opponentColor(us)
  
  # Get the Piece enum value for the current side's pawns (e.g., WP or BP)
  let ourPawnPieceEnum = makePiece(us, PieceType.Pawn)
  # Get the bitboard of all pawns for the current side
  let ourPawnsBB = board.pieceBB[ourPawnPieceEnum]

  # Define the piece types pawns can promote to
  const promotionTargets = [PieceType.Queen, PieceType.Rook, PieceType.Bishop, PieceType.Knight]

  var tempPawnsBB = ourPawnsBB # Mutable copy to iterate with popBit
  while tempPawnsBB != 0'u64:
    let fromSq = popBit(tempPawnsBB) # Current pawn's square
    let r = rankOf(fromSq)          # Current pawn's rank (0-7)
    let f = fileOf(fromSq)          # Current pawn's file (0-7)

    # 1. Single Pawn Pushes (including promotions)
    var toSqSingle: Square 
    var isValidSinglePushSquare = false # Flag to check if a single push destination square is on board

    if us == White:
      if r < 7: # White pawns not on the 8th rank (rank 7) can push
        toSqSingle = squareFromCoords(r + 1, f)
        isValidSinglePushSquare = true
    else: # us == Black
      if r > 0: # Black pawns not on the 1st rank (rank 0) can push
        toSqSingle = squareFromCoords(r - 1, f)
        isValidSinglePushSquare = true
            
    if isValidSinglePushSquare and not getBit(board.allPiecesBB, toSqSingle): # If dest square is on board and empty
      let destRank = rankOf(toSqSingle)
      # Check if this push results in a promotion
      let isPromotion = (us == White and destRank == 7) or (us == Black and destRank == 0)
      if isPromotion:
        for promoPt in promotionTargets:
          ml.addMove(fromSq, toSqSingle, promoPt)
      else:
        ml.addMove(fromSq, toSqSingle)

    # 2. Double Pawn Pushes
    if us == White:
      if r == 1: # White pawn on its starting rank (2nd rank, index 1)
        let oneStepSq = squareFromCoords(r + 1, f) # Square on rank 2 (index for 3rd rank)
        let twoStepsSq = squareFromCoords(r + 2, f) # Square on rank 3 (index for 4th rank)
        # Both squares must be empty for a double push
        if not getBit(board.allPiecesBB, oneStepSq) and not getBit(board.allPiecesBB, twoStepsSq):
          ml.addMove(fromSq, twoStepsSq)
    else: # us == Black
      if r == 6: # Black pawn on its starting rank (7th rank, index 6)
        let oneStepSq = squareFromCoords(r - 1, f) # Square on rank 5 (index for 6th rank)
        let twoStepsSq = squareFromCoords(r - 2, f) # Square on rank 4 (index for 5th rank)
        # Both squares must be empty for a double push
        if not getBit(board.allPiecesBB, oneStepSq) and not getBit(board.allPiecesBB, twoStepsSq):
          ml.addMove(fromSq, twoStepsSq)

    # 3. Pawn Captures (including promotion captures)
    let pawnAttackTargetsBB = lookups.pawnAttacks[us][fromSq] # Precomputed attack squares for this pawn
    var opponentPiecesOnAttackSquares = pawnAttackTargetsBB and board.occupiedBB[them] # Intersect with opponent's pieces
    
    while opponentPiecesOnAttackSquares != 0'u64:
      let toSqCapture = popBit(opponentPiecesOnAttackSquares) # Square where capture occurs
      let capturedToRank = rankOf(toSqCapture)
      # Check if this capture results in a promotion
      let isCapturePromotion = (us == White and capturedToRank == 7) or (us == Black and capturedToRank == 0)

      if isCapturePromotion:
        for promoPt in promotionTargets:
          ml.addMove(fromSq, toSqCapture, promoPt, FlagCapture, board.pieceAt(toSqCapture))
      else:
        ml.addMove(fromSq, toSqCapture, PieceType.NoPieceType, FlagCapture, board.pieceAt(toSqCapture))

    # 4. En Passant Captures
    if board.enPassantSquare != NoEnPassantSquareValue: # If an en passant square is set on the board
      let epTargetSq = Square(board.enPassantSquare) # The square the capturing pawn moves TO
      
      if getBit(lookups.pawnAttacks[us][fromSq], epTargetSq):
        let correctPawnRankForEpWhite = (us == White and r == 4) 
        let correctEpTargetRankForWhite = (us == White and rankOf(epTargetSq) == 5) 
        let correctPawnRankForEpBlack = (us == Black and r == 3) 
        let correctEpTargetRankForBlack = (us == Black and rankOf(epTargetSq) == 2) 

        if (correctPawnRankForEpWhite and correctEpTargetRankForWhite) or
           (correctPawnRankForEpBlack and correctEpTargetRankForBlack):
          # Determine the actual pawn being captured in EP
          var capturedEpPawnSq: Square
          if us == White: capturedEpPawnSq = epTargetSq - 8
          else: capturedEpPawnSq = epTargetSq + 8
          let capturedEpPawn = board.pieceAt(capturedEpPawnSq)
          ml.addMove(fromSq, epTargetSq, PieceType.NoPieceType, FlagEnPassant or FlagCapture, capturedEpPawn)

proc generateKnightMoves*(board: Board, ml: var MoveList) =
  ## Generates all pseudo-legal knight moves for the current side to move.
  let us = board.sideToMove
  let ourKnightPieceEnum = makePiece(us, PieceType.Knight)
  var ourKnightsBB = board.pieceBB[ourKnightPieceEnum]

  while ourKnightsBB != 0'u64:
    let fromSq = popBit(ourKnightsBB)
    var knightAttackTargetsBB = lookups.knightAttacks[fromSq]
    let validTargetsBB = knightAttackTargetsBB and not board.occupiedBB[us]
    
    var tempTargetsBB = validTargetsBB
    while tempTargetsBB != 0'u64:
      let toSq = popBit(tempTargetsBB)
      if getBit(board.occupiedBB[opponentColor(us)], toSq):
        ml.addMove(fromSq, toSq, PieceType.NoPieceType, FlagCapture, board.pieceAt(toSq))
      else:
        ml.addMove(fromSq, toSq)

proc generateKingMoves*(board: Board, ml: var MoveList) =
  ## Generates all pseudo-legal king moves for the current side to move (excluding castling).
  let us = board.sideToMove
  let ourKingPieceEnum = makePiece(us, PieceType.King)
  var ourKingBB = board.pieceBB[ourKingPieceEnum]

  if ourKingBB != 0'u64: 
    let fromSq = popBit(ourKingBB) 
    var kingAttackTargetsBB = lookups.kingAttacks[fromSq]
    let validTargetsBB = kingAttackTargetsBB and not board.occupiedBB[us]

    var tempTargetsBB = validTargetsBB
    while tempTargetsBB != 0'u64:
      let toSq = popBit(tempTargetsBB)
      if getBit(board.occupiedBB[opponentColor(us)], toSq):
        ml.addMove(fromSq, toSq, PieceType.NoPieceType, FlagCapture, board.pieceAt(toSq))
      else:
        ml.addMove(fromSq, toSq)
  # Castling moves are handled separately. 

proc generateSlidingMoves*(board: Board, ml: var MoveList) =
  ## Generates all pseudo-legal sliding piece moves (Rooks, Bishops, Queens).
  let us = board.sideToMove
  let them = opponentColor(us)

  # Generate moves for Rooks (using Magic Bitboards)
  let ourRookPieceEnum = makePiece(us, PieceType.Rook)
  var rooksBB = board.pieceBB[ourRookPieceEnum]
  while rooksBB != 0'u64:
    let fromSq = popBit(rooksBB)
    let attackTargetsBB = magicbitboards.getRookAttacks(fromSq, board.allPiecesBB)
    var validTargetsBB = attackTargetsBB and not board.occupiedBB[us]
    while validTargetsBB != 0'u64:
      let toSq = popBit(validTargetsBB)
      if getBit(board.occupiedBB[them], toSq):
        ml.addMove(fromSq, toSq, PieceType.NoPieceType, FlagCapture, board.pieceAt(toSq))
      else:
        ml.addMove(fromSq, toSq)

  # Generate moves for Bishops (using Magic Bitboards)
  let ourBishopPieceEnum = makePiece(us, PieceType.Bishop)
  var bishopsBB = board.pieceBB[ourBishopPieceEnum]
  while bishopsBB != 0'u64:
    let fromSq = popBit(bishopsBB)
    let attackTargetsBB = magicbitboards.getBishopAttacks(fromSq, board.allPiecesBB)
    var validTargetsBB = attackTargetsBB and not board.occupiedBB[us]
    while validTargetsBB != 0'u64:
      let toSq = popBit(validTargetsBB)
      if getBit(board.occupiedBB[them], toSq):
        ml.addMove(fromSq, toSq, PieceType.NoPieceType, FlagCapture, board.pieceAt(toSq))
      else:
        ml.addMove(fromSq, toSq)

  # Generate moves for Queens (using Magic Bitboards)
  let ourQueenPieceEnum = makePiece(us, PieceType.Queen)
  var queensBB = board.pieceBB[ourQueenPieceEnum]
  while queensBB != 0'u64:
    let fromSq = popBit(queensBB)
    let attackTargetsBB = magicbitboards.getQueenAttacks(fromSq, board.allPiecesBB)
    var validTargetsBB = attackTargetsBB and not board.occupiedBB[us]
    while validTargetsBB != 0'u64:
      let toSq = popBit(validTargetsBB)
      if getBit(board.occupiedBB[them], toSq):
        ml.addMove(fromSq, toSq, PieceType.NoPieceType, FlagCapture, board.pieceAt(toSq))
      else:
        ml.addMove(fromSq, toSq)

# Removed the old generateIterativePieceMoves and its calls as it's fully replaced.

# Constants for specific squares involved in castling.
# Using coretypes.Square type for clarity, though direct integers would also work.
const
  E1: Square = 4
  F1: Square = 5
  G1: Square = 6
  H1: Square = 7
  C1: Square = 2
  D1: Square = 3
  B1: Square = 1
  A1: Square = 0
  E8: Square = 60
  F8: Square = 61
  G8: Square = 62
  H8: Square = 63
  C8: Square = 58
  D8: Square = 59
  B8: Square = 57
  A8: Square = 56

proc generateCastlingMoves*(board: Board, ml: var MoveList) =
  ## Generates pseudo-legal castling moves.
  ## Does NOT currently check if the king passes through or lands on an attacked square.
  ## This check (isSquareAttacked) will be added later.
  let us = board.sideToMove

  if us == White:
    # White King-Side Castling (O-O)
    if (board.castlingRights and WKC) != 0: # Check if White King-Side castling right exists
      # Check if squares F1 and G1 are empty
      if (board.allPiecesBB and ((1'u64 shl F1) or (1'u64 shl G1))) == 0:
        if not board.isSquareAttacked(E1, Black) and 
           not board.isSquareAttacked(F1, Black) and 
           not board.isSquareAttacked(G1, Black):
          ml.addMove(E1, G1, PieceType.NoPieceType, FlagCastle)

    # White Queen-Side Castling (O-O-O)
    if (board.castlingRights and WQC) != 0: # Check if White Queen-Side castling right exists
      # Check if squares D1, C1, and B1 are empty
      if (board.allPiecesBB and ((1'u64 shl D1) or (1'u64 shl C1) or (1'u64 shl B1))) == 0:
        if not board.isSquareAttacked(E1, Black) and 
           not board.isSquareAttacked(D1, Black) and 
           not board.isSquareAttacked(C1, Black):
          ml.addMove(E1, C1, PieceType.NoPieceType, FlagCastle)
  else: # us == Black
    # Black King-Side Castling (o-o)
    if (board.castlingRights and BKC) != 0: # Check if Black King-Side castling right exists
      # Check if squares F8 and G8 are empty
      if (board.allPiecesBB and ((1'u64 shl F8) or (1'u64 shl G8))) == 0:
        if not board.isSquareAttacked(E8, White) and 
           not board.isSquareAttacked(F8, White) and 
           not board.isSquareAttacked(G8, White):
          ml.addMove(E8, G8, PieceType.NoPieceType, FlagCastle)

    # Black Queen-Side Castling (o-o-o)
    if (board.castlingRights and BQC) != 0: # Check if Black Queen-Side castling right exists
      # Check if squares D8, C8, and B8 are empty
      if (board.allPiecesBB and ((1'u64 shl D8) or (1'u64 shl C8) or (1'u64 shl B8))) == 0:
        if not board.isSquareAttacked(E8, White) and 
           not board.isSquareAttacked(D8, White) and 
           not board.isSquareAttacked(C8, White):
          ml.addMove(E8, C8, PieceType.NoPieceType, FlagCastle)

proc generatePseudoLegalMoves*(board: Board, ml: var MoveList) =
  ## Generates all pseudo-legal moves for the current side to move.
  ## This includes pawn, knight, king, sliding pieces (rooks, bishops, queens),
  ## and castling moves.
  ## The resulting list in 'ml' needs to be filtered for legality (king not in check).

  ml.count = 0 # Clear the move list

  generatePawnMoves(board, ml)
  generateKnightMoves(board, ml)
  generateKingMoves(board, ml)    # Generates king moves excluding castling
  generateSlidingMoves(board, ml) # Generates rook, bishop, queen moves
  generateCastlingMoves(board, ml) # Generates castling moves with attack checks

proc generateLegalMoves*(board: Board, ml: var MoveList) =
  ## Generates all strictly legal moves for the current side to move.
  ## It does this by generating pseudo-legal moves and then filtering them
  ## by making each move on a temporary board and checking if the king
  ## of the player who moved is left in check.

  var tempBoard = board # Create a copy of the board to make/unmake moves on
  var pseudoLegalMoves: MoveList
  
  # 1. Generate all pseudo-legal moves for the current position on the tempBoard
  generatePseudoLegalMoves(tempBoard, pseudoLegalMoves)
  
  # 2. Clear the output move list
  ml.count = 0
  
  # 3. Iterate through pseudo-legal moves and filter for legality
  for i in 0 ..< pseudoLegalMoves.count:
    let currentPseudoMove = pseudoLegalMoves.moves[i]
    
    # a. Store original state from tempBoard BEFORE making the move
    #    These are needed for unmakeMove.
    let originalCastlingRights = tempBoard.castlingRights
    let originalEnPassantSquare = tempBoard.enPassantSquare
    let originalHalfMoveClock = tempBoard.halfMoveClock
    let originalZobristKey = tempBoard.currentZobristKey
    
    # b. Call makeMove on tempBoard. 
    #    makeMove will update tempBoard and return true if the king of the player
    #    who made the move is NOT left in check.
    let isLegalRegardingSelfCheck = tempBoard.makeMove(currentPseudoMove)
    
    # c. If makeMove returns true, the move is legal regarding self-check.
    if isLegalRegardingSelfCheck:
      ml.addMove(
        currentPseudoMove.fromSquare, 
        currentPseudoMove.toSquare, 
        currentPseudoMove.promotionPiece, 
        currentPseudoMove.flags,
        currentPseudoMove.capturedPiece
      )
      
    # d. Call unmakeMove to restore tempBoard to its state BEFORE currentPseudoMove was made.
    #    This is crucial so the next pseudo-legal move is tested on the original state.
    tempBoard.unmakeMove(
      currentPseudoMove, 
      originalCastlingRights, 
      originalEnPassantSquare, 
      originalHalfMoveClock, 
      originalZobristKey
    )
    # After unmakeMove, tempBoard should be identical to its state at the start of this loop iteration.