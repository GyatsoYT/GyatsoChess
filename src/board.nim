import coretypes
import bitboard
import utils # For squareFromCoords, fileOf
import zobrist # For Zobrist keys and types
import strutils # For split, parseInt
import lookups
import magicbitboards
import move # For Move type and flags

const
  DefaultFen* = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"

  NoEnPassantSquareValue* = -1 # Must be outside Square's 0..63 range

  # Castling Rights Bitmasks
  WKC* = 1  # White King Side
  WQC* = 2  # White Queen Side
  BKC* = 4  # Black King Side
  BQC* = 8  # Black Queen Side
  
  AnyCastling* = WKC or WQC or BKC or BQC
  WhiteCastling* = WKC or WQC
  BlackCastling* = BKC or BQC

type
  Board* = object
    pieceBB*: array[Piece, Bitboard]        # Bitboards for each piece (WhitePawn, BlackKing, etc.)
    occupiedBB*: array[Color.White..Color.Black, Bitboard] # Bitboards for all pieces of a given color
    allPiecesBB*: Bitboard                  # Bitboard of all occupied squares

    sideToMove*: Color
    enPassantSquare*: int                  # Square index (0-63) or NoEnPassantSquareValue
    castlingRights*: int                   # Bitmask using WKC, WQC, BKC, BQC
    halfMoveClock*: int                    # For the fifty-move rule
    fullMoveNumber*: int                   # Incremented after Black's move
    currentZobristKey*: ZobristKey         # Current Zobrist key for the position

proc charToPiece(c: char): Piece =
  case c:
  of 'P': Piece.WP
  of 'N': Piece.WN
  of 'B': Piece.WB
  of 'R': Piece.WR
  of 'Q': Piece.WQ
  of 'K': Piece.WK
  of 'p': Piece.BP
  of 'n': Piece.BN
  of 'b': Piece.BB
  of 'r': Piece.BR
  of 'q': Piece.BQ
  of 'k': Piece.BK
  else: Piece.Empty

proc calculateZobristKey(board: Board): ZobristKey =
  ## Calculates the Zobrist key from scratch for the given board state.
  var key: ZobristKey = 0'u64

  # Piece keys
  for pType in Piece.WP..Piece.BK: # Iterate only actual pieces, not Empty
    var bbCopy = board.pieceBB[pType]
    while bbCopy != 0'u64:
      let sq = popBit(bbCopy)
      key = key xor zobristTable[pType][sq]
  
  # Side to move key
  if board.sideToMove == Color.Black:
    key = key xor zobristSideToMove

  # Castling rights key
  key = key xor zobristCastling[board.castlingRights and AnyCastling] # Mask to ensure 0-15

  # En passant key
  if board.enPassantSquare != NoEnPassantSquareValue and 
     board.enPassantSquare >= Square.low and board.enPassantSquare <= Square.high:
    let epFile = fileOf(Square(board.enPassantSquare))
    key = key xor zobristEnPassant[epFile]
  
  return key

proc setupBoardFromFen(board: var Board, fen: string) =
  # Clear board state
  for p in Piece: board.pieceBB[p] = 0'u64
  board.occupiedBB[White] = 0'u64
  board.occupiedBB[Black] = 0'u64
  board.allPiecesBB = 0'u64

  let parts = fen.split(' ')
  let piecePlacement = parts[0]
  
  var rank = 7 # FEN ranks are 8 to 1 (0-indexed: 7 to 0)
  var file = 0 # FEN files are a to h (0-indexed: 0 to 7)

  for c in piecePlacement:
    if c == '/':
      rank -= 1
      file = 0
    elif c.isDigit():
      file += parseInt($c)
    else:
      let piece = charToPiece(c)
      if piece != Piece.Empty:
        let sq = squareFromCoords(rank, file)
        setBit(board.pieceBB[piece], sq)
      file += 1
  
  # Update combined bitboards
  for p in Piece.WP..Piece.WK: board.occupiedBB[White] = board.occupiedBB[White] or board.pieceBB[p]
  for p in Piece.BP..Piece.BK: board.occupiedBB[Black] = board.occupiedBB[Black] or board.pieceBB[p]
  board.allPiecesBB = board.occupiedBB[White] or board.occupiedBB[Black]

  board.sideToMove = if parts[1] == "w": Color.White else: Color.Black
  
  board.castlingRights = 0
  if parts[2].contains('K'): board.castlingRights = board.castlingRights or WKC
  if parts[2].contains('Q'): board.castlingRights = board.castlingRights or WQC
  if parts[2].contains('k'): board.castlingRights = board.castlingRights or BKC
  if parts[2].contains('q'): board.castlingRights = board.castlingRights or BQC

  if parts[3] == "-":
    board.enPassantSquare = NoEnPassantSquareValue
  else:
    board.enPassantSquare = algebraicToSquare(parts[3])
  
  board.halfMoveClock = parseInt(parts[4])
  board.fullMoveNumber = parseInt(parts[5])

  board.currentZobristKey = calculateZobristKey(board)

proc initializeBoard*(fen: string = DefaultFen): Board =
  var board: Board
  let parts = fen.split(' ')
  setupBoardFromFen(board, fen)
  
  if fen != DefaultFen and parts[0] != "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR":
      echo "Warning: FEN string ", fen, " was parsed. Verify correctness for non-default FENs."
  return board

func opponentColorHelper*(color: Color): Color {.inline.} =
  ## Returns the opponent's color.
  if color == White: Black else: White

proc isSquareAttacked*(board: Board, sq: Square, attackerColor: Color): bool =
  ## Checks if the given square 'sq' is attacked by any piece of 'attackerColor'.

  # 1. Pawn attacks
  # pawnAttacks[opponentColorHelper(attackerColor)][sq] gives the squares from which an attackerColor pawn would attack sq.
  let pawnAttackOriginSquares = lookups.pawnAttacks[opponentColorHelper(attackerColor)][sq]
  let attackerPawns = board.pieceBB[makePiece(attackerColor, PieceType.Pawn)]
  if (pawnAttackOriginSquares and attackerPawns) != 0'u64:
    return true

  # 2. Knight attacks
  # knightAttacks[sq] gives all squares from which a knight can attack sq.
  let knightAttackOriginSquares = lookups.knightAttacks[sq]
  let attackerKnights = board.pieceBB[makePiece(attackerColor, PieceType.Knight)]
  if (knightAttackOriginSquares and attackerKnights) != 0'u64:
    return true

  # 3. King attacks
  # kingAttacks[sq] gives all squares from which a king can attack sq.
  let kingAttackOriginSquares = lookups.kingAttacks[sq]
  let attackerKing = board.pieceBB[makePiece(attackerColor, PieceType.King)]
  if (kingAttackOriginSquares and attackerKing) != 0'u64:
    return true

  # 4. Sliding attacks - Rooks and Queens
  let rookPiece = makePiece(attackerColor, PieceType.Rook)
  let queenPiece = makePiece(attackerColor, PieceType.Queen)
  let rookLikeAttackers = board.pieceBB[rookPiece] or board.pieceBB[queenPiece]
  if rookLikeAttackers != 0'u64: # Optimization: only check if there are such attackers
    let rookAttacksOnSq = magicbitboards.getRookAttacks(sq, board.allPiecesBB)
    if (rookAttacksOnSq and rookLikeAttackers) != 0'u64:
      return true

  # 5. Sliding attacks - Bishops and Queens
  let bishopPiece = makePiece(attackerColor, PieceType.Bishop)
  # queenPiece already defined and used for rookLikeAttackers, can reuse for bishopLikeAttackers
  let bishopLikeAttackers = board.pieceBB[bishopPiece] or board.pieceBB[queenPiece]
  if bishopLikeAttackers != 0'u64: # Optimization: only check if there are such attackers
    let bishopAttacksOnSq = magicbitboards.getBishopAttacks(sq, board.allPiecesBB)
    if (bishopAttacksOnSq and bishopLikeAttackers) != 0'u64:
      return true

  return false

proc pieceAt*(board: Board, sq: Square): Piece =
  ## Returns the piece on the given square.
  for pVal in ord(Piece.WP)..ord(Piece.BK): # Iterate through actual piece enum values
    let p = Piece(pVal)
    if getBit(board.pieceBB[p], sq):
      return p
  return Piece.Empty

proc makeMove*(board: var Board, move: Move): bool =
  ## Updates the board state according to the given move.
  ## Handles basic piece movement, captures, en passant, castling, promotions,
  ## and updates all relevant board state including Zobrist key.
  ## Returns true if the move is legal (king not left in check), false otherwise.

  let fromSq = move.fromSquare
  let toSq = move.toSquare
  let us = board.sideToMove       # Color of player making the move
  let them = opponentColorHelper(us)

  let pieceMoved = board.pieceAt(fromSq)
  let pieceMovedType = pieceType(pieceMoved)

  # Store state for Zobrist key changes and logic BEFORE modifications
  let oldEnPassantSquare = board.enPassantSquare
  let oldCastlingRights = board.castlingRights
  # board.halfMoveClock is updated directly
  # board.currentZobristKey is updated incrementally

  # 1. Update Zobrist key: XOR out pieceMoved from fromSq
  board.currentZobristKey = board.currentZobristKey xor zobristTable[pieceMoved][fromSq]

  # 2. Move pieceMoved on bitboards (clear from source square)
  clearBit(board.pieceBB[pieceMoved], fromSq)
  clearBit(board.occupiedBB[us], fromSq)

  var capturedPiece = Piece.Empty # Stores the actual piece type if a capture occurs
  
  let isCapture = (move.flags and FlagCapture) != 0

  if isCapture:
    if (move.flags and FlagEnPassant) != 0:
      # En Passant Capture: captured pawn is not on toSq.
      var capturedPawnSq: Square
      if us == White:
        capturedPawnSq = toSq - 8 # Black pawn is one rank below toSq (which is rank 5)
      else: # us == Black
        capturedPawnSq = toSq + 8 # White pawn is one rank above toSq (which is rank 2)
      
      capturedPiece = board.pieceAt(capturedPawnSq) # Should be opponent's pawn
      assert(pieceType(capturedPiece) == PieceType.Pawn, "En passant captured piece is not a pawn")
      assert(pieceColor(capturedPiece) == them, "En passant captured piece is wrong color")

      board.currentZobristKey = board.currentZobristKey xor zobristTable[capturedPiece][capturedPawnSq]
      clearBit(board.pieceBB[capturedPiece], capturedPawnSq)
      clearBit(board.occupiedBB[them], capturedPawnSq)
      clearBit(board.allPiecesBB, capturedPawnSq)
    else:
      # Normal Capture: captured piece is on toSq.
      capturedPiece = board.pieceAt(toSq)
      if capturedPiece != Piece.Empty: # Ensure there's a piece to capture (not for EP ghost square)
        assert(pieceColor(capturedPiece) == them, "Captured piece is not opponent's color")
        board.currentZobristKey = board.currentZobristKey xor zobristTable[capturedPiece][toSq]
        clearBit(board.pieceBB[capturedPiece], toSq)
        clearBit(board.occupiedBB[them], toSq)
  
  # 3. Half-move clock update
  if pieceMovedType == PieceType.Pawn or isCapture:
    board.halfMoveClock = 0
  else:
    board.halfMoveClock += 1

  # 4. En Passant Square generation/clearing
  # Clear old EP square Zobrist if it existed
  if oldEnPassantSquare != NoEnPassantSquareValue:
    board.currentZobristKey = board.currentZobristKey xor zobristEnPassant[fileOf(Square(oldEnPassantSquare))]
  
  board.enPassantSquare = NoEnPassantSquareValue # Default to no new EP square
  if pieceMovedType == PieceType.Pawn:
    if us == White and rankOf(fromSq) == 1 and rankOf(toSq) == 3: # White double push
      board.enPassantSquare = fromSq + 8 # Square behind pawn (rank 2)
    elif us == Black and rankOf(fromSq) == 6 and rankOf(toSq) == 4: # Black double push
      board.enPassantSquare = fromSq - 8 # Square behind pawn (rank 5)
    
  # Set new EP square Zobrist if it exists
  if board.enPassantSquare != NoEnPassantSquareValue:
    board.currentZobristKey = board.currentZobristKey xor zobristEnPassant[fileOf(Square(board.enPassantSquare))]

  # 5. Handle Promotions and determine the final piece to place on toSq
  var finalPieceToPlaceOnToSq = pieceMoved 
  if (move.flags and FlagPromotion) != 0:
    assert(pieceMovedType == PieceType.Pawn, "Promotion flag set but piece moved is not a pawn")
    let promotedType = move.promotionPiece
    assert(promotedType != PieceType.NoPieceType and promotedType != PieceType.Pawn and promotedType != PieceType.King, "Invalid promotion piece type")
    finalPieceToPlaceOnToSq = makePiece(us, promotedType)
    # The Zobrist key for the pawn at fromSq is already XORed out.
    # The Zobrist key for the promoted piece at toSq will be XORed in by the general logic below.
    # Bitboard pieceBB[pieceMoved] (pawn) at fromSq is cleared.
    # Bitboard pieceBB[finalPieceToPlaceOnToSq] (promoted piece) at toSq will be set.
    # OccupiedBB[us] is handled by general logic.
  
  # 6. Place the final piece (original or promoted) on the destination square bitboards
  setBit(board.pieceBB[finalPieceToPlaceOnToSq], toSq)
  setBit(board.occupiedBB[us], toSq) 

  # 7. Zobrist: XOR in the piece that landed on toSq
  board.currentZobristKey = board.currentZobristKey xor zobristTable[finalPieceToPlaceOnToSq][toSq]

  # 8. Handle Castling: move the corresponding rook
  if (move.flags and FlagCastle) != 0:
    assert(pieceMovedType == PieceType.King, "Castle flag set but piece moved is not a king")
    var rookFrom, rookTo: Square
    let rookPiece = makePiece(us, PieceType.Rook)
    
    if us == White:
      if toSq == Square(6): # G1, White King-side (E1->G1)
        rookFrom = Square(7) # H1
        rookTo = Square(5)   # F1
      else: # toSq == Square(2), C1, White Queen-side (E1->C1)
        assert(toSq == Square(2), "Invalid white castling toSq")
        rookFrom = Square(0) # A1
        rookTo = Square(3)   # D1
    else: # us == Black
      if toSq == Square(62): # G8, Black King-side (E8->G8)
        rookFrom = Square(63) # H8
        rookTo = Square(61)   # F8
      else: # toSq == Square(58), C8, Black Queen-side (E8->C8)
        assert(toSq == Square(58), "Invalid black castling toSq")
        rookFrom = Square(56) # A8
        rookTo = Square(59)   # D8
    
    # Update Zobrist for rook movement
    board.currentZobristKey = board.currentZobristKey xor zobristTable[rookPiece][rookFrom]
    board.currentZobristKey = board.currentZobristKey xor zobristTable[rookPiece][rookTo]

    # Update rook bitboards
    clearBit(board.pieceBB[rookPiece], rookFrom)
    clearBit(board.occupiedBB[us], rookFrom) # Rook is same color as king
    setBit(board.pieceBB[rookPiece], rookTo)
    setBit(board.occupiedBB[us], rookTo)

  # 9. Update Castling Rights
  var newCastlingRights = board.castlingRights
  
  # King moves
  if pieceMovedType == PieceType.King:
    if us == White: newCastlingRights = newCastlingRights and not WhiteCastling
    else: newCastlingRights = newCastlingRights and not BlackCastling
  
  # Rook moves (from its starting square)
  # For White
  if fromSq == Square(0): newCastlingRights = newCastlingRights and (not WQC) # A1 moved
  if fromSq == Square(7): newCastlingRights = newCastlingRights and (not WKC) # H1 moved
  # For Black
  if fromSq == Square(56): newCastlingRights = newCastlingRights and (not BQC) # A8 moved
  if fromSq == Square(63): newCastlingRights = newCastlingRights and (not BKC) # H8 moved

  # Rook captured on its starting square
  if capturedPiece != Piece.Empty:
    let capturedType = pieceType(capturedPiece)
    if capturedType == PieceType.Rook:
      if them == White: # Captured piece was White's
        if toSq == Square(0): newCastlingRights = newCastlingRights and (not WQC) # A1 captured
        if toSq == Square(7): newCastlingRights = newCastlingRights and (not WKC) # H1 captured
      else: # Captured piece was Black's
        if toSq == Square(56): newCastlingRights = newCastlingRights and (not BQC) # A8 captured
        if toSq == Square(63): newCastlingRights = newCastlingRights and (not BKC) # H8 captured
  
  if newCastlingRights != oldCastlingRights:
    board.currentZobristKey = board.currentZobristKey xor zobristCastling[oldCastlingRights]
    board.currentZobristKey = board.currentZobristKey xor zobristCastling[newCastlingRights]
    board.castlingRights = newCastlingRights

  # 10. Update board.allPiecesBB (after all piece movements)
  board.allPiecesBB = board.occupiedBB[White] or board.occupiedBB[Black]

  # 11. Switch Side to Move
  board.currentZobristKey = board.currentZobristKey xor zobristSideToMove
  board.sideToMove = them # 'them' was opponent of original 'us'

  # 12. Increment Full Move Number
  if board.sideToMove == White: # If it's now White's turn (i.e., Black just moved)
    board.fullMoveNumber += 1

  # 13. Legality Check: King of the player who made the move ('us') must not be in check by the new current player ('them')
  let kingToFind = makePiece(us, PieceType.King)
  var kingCurrentSq: Square
  
  if pieceMovedType == PieceType.King and finalPieceToPlaceOnToSq == kingToFind: # If the king itself moved
      kingCurrentSq = toSq
  else: # King didn't move, find its original square (which is still its current square)
      var kingBbCopy = board.pieceBB[kingToFind] # pieceBB is already updated for the current state
      assert(kingBbCopy != 0'u64, "King of side " & $us & " not found on board.")
      kingCurrentSq = popBit(kingBbCopy) # Modifies copy, board.pieceBB[kingToFind] is safe
                                       # This assumes only one king per side
  
  if board.isSquareAttacked(kingCurrentSq, board.sideToMove): # is king of 'us' attacked by new sideToMove ('them')
    # Move was illegal as it left the king in check.
    # In a full engine, unmakeMove would be called here if this is part of a search.
    # For now, per instructions, just return false.
    return false 

  return true # Move is considered legal

proc unmakeMove*(
  board: var Board, 
  move: Move, 
  originalCastlingRights: int, 
  originalEnPassantSquare: int, 
  originalHalfMoveClock: int, 
  originalZobristKey: ZobristKey
) =
  ## Reverts the board state to before the 'move' was made.
  ## This function must perfectly restore the state for search algorithms.
  ## Note on normal captures: For board.pieceBB, the specific type of a normally captured piece
  ## is not passed to this function. board.occupiedBB is restored. The Zobrist key,
  ## restored from originalZobristKey, correctly reflects the original state including the specific captured piece.

  let fromSq = move.fromSquare
  let toSq = move.toSquare

  # Determine colors based on the state *before* this unmake operation starts
  # (i.e., board.sideToMove is currently the player who *didn't* make the move being unmade)
  let colorWhoseTurnItWas = opponentColorHelper(board.sideToMove) # This is original 'us'
  let colorWhoWasOpponent = board.sideToMove                  # This is original 'them'

  # 1. Restore side to move & full move number
  board.sideToMove = colorWhoseTurnItWas
  if board.sideToMove == White: # If Black's move was unmade, it becomes White's turn. Full move number had been incremented.
    board.fullMoveNumber -= 1

  # 2. Restore simple state variables (castling, EP, halfmove clock)
  # Zobrist key for these changes is handled by restoring originalZobristKey globally at the end.
  board.castlingRights = originalCastlingRights
  board.enPassantSquare = originalEnPassantSquare 
  board.halfMoveClock = originalHalfMoveClock

  # 3. Unwind piece movement (from toSq back to fromSq) including promotion
  # Identify the piece currently on toSq (this is the piece that moved, possibly promoted)
  let pieceThatMovedToToSq = board.pieceAt(toSq) 

  # Clear this piece from toSq
  clearBit(board.pieceBB[pieceThatMovedToToSq], toSq)
  clearBit(board.occupiedBB[colorWhoseTurnItWas], toSq)

  # Determine the piece to place back on fromSq
  var pieceToRestoreOnFromSq: Piece
  if (move.flags and FlagPromotion) != 0:
    pieceToRestoreOnFromSq = makePiece(colorWhoseTurnItWas, PieceType.Pawn)
  else:
    pieceToRestoreOnFromSq = pieceThatMovedToToSq
  
  setBit(board.pieceBB[pieceToRestoreOnFromSq], fromSq)
  setBit(board.occupiedBB[colorWhoseTurnItWas], fromSq)

  # 4. Unwind captures
  if (move.flags and FlagCapture) != 0:
    if (move.flags and FlagEnPassant) != 0:
      let capturedPawn = makePiece(colorWhoWasOpponent, PieceType.Pawn)
      var epCapturedPawnSq: Square
      if colorWhoseTurnItWas == White: # White made the EP capture, took Black pawn
        epCapturedPawnSq = toSq - 8 # Black pawn was south of toSq (e.g. toSq=e6, pawn=e5)
      else: # Black made the EP capture, took White pawn
        epCapturedPawnSq = toSq + 8 # White pawn was north of toSq (e.g. toSq=c3, pawn=c4)
      
      setBit(board.pieceBB[capturedPawn], epCapturedPawnSq)
      setBit(board.occupiedBB[colorWhoWasOpponent], epCapturedPawnSq)
    else:
      # Normal capture: a piece of colorWhoWasOpponent was on toSq.
      # Restore the specific captured piece on its bitboard.
      if move.capturedPiece != Piece.Empty:
        setBit(board.pieceBB[move.capturedPiece], toSq)
      # Also restore it on the opponent's occupied bitboard.
      setBit(board.occupiedBB[colorWhoWasOpponent], toSq) # Mark toSq as occupied by opponent again

  # 5. Unwind castling rook movement
  if (move.flags and FlagCastle) != 0:
    let rook = makePiece(colorWhoseTurnItWas, PieceType.Rook)
    var rookOriginalSq, rookCurrentSq: Square 

    # Determine rook's current and original squares based on king's toSq
    if colorWhoseTurnItWas == White:
      if toSq == Square(6): # King moved E1->G1 (O-O), rook is on F1 (5), was H1 (7)
        rookCurrentSq = Square(5)
        rookOriginalSq = Square(7)
      else: # King moved E1->C1 (O-O-O), toSq == Square(2), rook is on D1 (3), was A1 (0)
        rookCurrentSq = Square(3)
        rookOriginalSq = Square(0)
    else: # colorWhoseTurnItWas == Black
      if toSq == Square(62): # King moved E8->G8 (o-o), rook is on F8 (61), was H8 (63)
        rookCurrentSq = Square(61)
        rookOriginalSq = Square(63)
      else: # King moved E8->C8 (o-o-o), toSq == Square(58), rook is on D8 (59), was A8 (56)
        rookCurrentSq = Square(59)
        rookOriginalSq = Square(56)
    
    # Move rook back: clear from current, set to original
    clearBit(board.pieceBB[rook], rookCurrentSq)
    clearBit(board.occupiedBB[colorWhoseTurnItWas], rookCurrentSq)
    setBit(board.pieceBB[rook], rookOriginalSq)
    setBit(board.occupiedBB[colorWhoseTurnItWas], rookOriginalSq)

  # 6. Update board.allPiecesBB (after all piece positions are restored)
  board.allPiecesBB = board.occupiedBB[White] or board.occupiedBB[Black]
  
  # 7. Restore Zobrist Key to its state before the move was made
  board.currentZobristKey = originalZobristKey
