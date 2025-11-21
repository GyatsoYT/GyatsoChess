
import coretypes, bitboard, zobrist, utils, lookups, magicbitboards, move
import std/strutils

const
  WhiteKingSide* = 1
  WhiteQueenSide* = 2
  BlackKingSide* = 4
  BlackQueenSide* = 8
  DefaultFen* = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
  NoSquare* = -1

type
  Board* = object
    pieceBB*: array[Piece, Bitboard]
    occupiedBB*: array[Color, Bitboard]
    allPiecesBB*: Bitboard
    sideToMove*: Color
    enPassantSquare*: int # Using int to allow NoSquare (-1)
    castlingRights*: int
    halfMoveClock*: int
    fullMoveNumber*: int
    currentZobristKey*: ZobristKey
    history*: seq[GameState]

  GameState* = object
    castlingRights*: int
    enPassantSquare*: int
    halfMoveClock*: int
    zobristKey*: ZobristKey
    capturedPiece*: Piece

proc clear(board: var Board) =
  for p in Piece: board.pieceBB[p] = 0
  for c in Color: board.occupiedBB[c] = 0
  board.allPiecesBB = 0
  board.sideToMove = White
  board.enPassantSquare = NoSquare
  board.castlingRights = 0
  board.halfMoveClock = 0
  board.fullMoveNumber = 1
  board.currentZobristKey = 0

proc updateOccupancies(board: var Board) =
  board.occupiedBB[White] = 0
  board.occupiedBB[Black] = 0
  
  for p in WhitePawn..WhiteKing:
    board.occupiedBB[White] = board.occupiedBB[White] or board.pieceBB[p]
    
  for p in BlackPawn..BlackKing:
    board.occupiedBB[Black] = board.occupiedBB[Black] or board.pieceBB[p]
    
  board.allPiecesBB = board.occupiedBB[White] or board.occupiedBB[Black]

proc generateZobristKey(board: Board): ZobristKey =
  var key: ZobristKey = 0
  
  # Pieces
  for p in Piece:
    if p == NoPiece: continue
    var bb = board.pieceBB[p]
    while bb != 0:
      let sq = popBit(bb)
      key = key xor zobristTable[p][sq]
      
  # Side to move
  if board.sideToMove == Black:
    key = key xor zobristSideToMove
    
  # Castling
  key = key xor zobristCastling[board.castlingRights]
  
  # En Passant
  if board.enPassantSquare != NoSquare:
    let file = fileOf(board.enPassantSquare.Square)
    key = key xor zobristEnPassant[file]
    
  return key

proc parseFen*(board: var Board, fen: string) =
  board.clear()
  
  var parts = fen.split(' ')
  
  # 1. Piece placement
  var rank = 7
  var file = 0
  for char in parts[0]:
    if char == '/':
      rank -= 1
      file = 0
    elif char.isDigit:
      file += char.ord - '0'.ord
    else:
      var pieceType = NoPieceType
      var color = NoColor
      
      case char
      of 'P': (pieceType, color) = (Pawn, White)
      of 'N': (pieceType, color) = (Knight, White)
      of 'B': (pieceType, color) = (Bishop, White)
      of 'R': (pieceType, color) = (Rook, White)
      of 'Q': (pieceType, color) = (Queen, White)
      of 'K': (pieceType, color) = (King, White)
      of 'p': (pieceType, color) = (Pawn, Black)
      of 'n': (pieceType, color) = (Knight, Black)
      of 'b': (pieceType, color) = (Bishop, Black)
      of 'r': (pieceType, color) = (Rook, Black)
      of 'q': (pieceType, color) = (Queen, Black)
      of 'k': (pieceType, color) = (King, Black)
      else: discard
      
      if pieceType != NoPieceType:
        let piece = makePiece(color, pieceType)
        let sq = squareFromCoords(rank, file)
        board.pieceBB[piece].setBit(sq)
        file += 1

  board.updateOccupancies()

  # 2. Side to move
  if parts.len > 1:
    board.sideToMove = if parts[1] == "w": White else: Black

  # 3. Castling rights
  if parts.len > 2:
    for char in parts[2]:
      case char
      of 'K': board.castlingRights = board.castlingRights or WhiteKingSide
      of 'Q': board.castlingRights = board.castlingRights or WhiteQueenSide
      of 'k': board.castlingRights = board.castlingRights or BlackKingSide
      of 'q': board.castlingRights = board.castlingRights or BlackQueenSide
      else: discard

  # 4. En passant
  if parts.len > 3 and parts[3] != "-":
    board.enPassantSquare = algebraicToSquare(parts[3]).int

  # 5. Halfmove clock
  if parts.len > 4:
    try:
      board.halfMoveClock = parseInt(parts[4])
    except ValueError:
      board.halfMoveClock = 0

  # 6. Fullmove number
  if parts.len > 5:
    try:
      board.fullMoveNumber = parseInt(parts[5])
    except ValueError:
      board.fullMoveNumber = 1

  board.currentZobristKey = board.generateZobristKey()

proc initializeBoard*(fen: string = DefaultFen): Board =
  result.parseFen(fen)

proc printBoard*(board: Board) =
  echo "  +---+---+---+---+---+---+---+---+"
  for r in countdown(7, 0):
    stdout.write(rankToChar(r))
    stdout.write(" |")
    for f in 0..7:
      let sq = squareFromCoords(r, f)
      var pieceChar = ' '
      for p in Piece:
        if p == NoPiece: continue
        if board.pieceBB[p].getBit(sq):
          pieceChar = case p
          of WhitePawn: 'P'
          of WhiteKnight: 'N'
          of WhiteBishop: 'B'
          of WhiteRook: 'R'
          of WhiteQueen: 'Q'
          of WhiteKing: 'K'
          of BlackPawn: 'p'
          of BlackKnight: 'n'
          of BlackBishop: 'b'
          of BlackRook: 'r'
          of BlackQueen: 'q'
          of BlackKing: 'k'
          else: ' '
          break
      stdout.write(" " & pieceChar & " |")
    echo "\n  +---+---+---+---+---+---+---+---+"
  echo "    a   b   c   d   e   f   g   h"
  echo "Side to move: ", if board.sideToMove == White: "White" else: "Black"
  echo "Castling: ", board.castlingRights
  echo "En Passant: ", if board.enPassantSquare != NoSquare: $board.enPassantSquare.Square else: "-"
  echo "Key: ", board.currentZobristKey.toHex

proc isSquareAttacked*(board: Board, sq: Square, attacker: Color): bool {.gcsafe.} =
  # Pawns
  let defender = if attacker == White: Black else: White
  if (pawnAttacks[defender][sq] and board.pieceBB[makePiece(attacker, Pawn)]) != 0: return true
  
  # Knights
  if (knightAttacks[sq] and board.pieceBB[makePiece(attacker, Knight)]) != 0: return true
  
  # King
  if (kingAttacks[sq] and board.pieceBB[makePiece(attacker, King)]) != 0: return true
  
  # Sliding Pieces (Rooks, Queens)
  let rookQueens = board.pieceBB[makePiece(attacker, Rook)] or board.pieceBB[makePiece(attacker, Queen)]
  if (getRookAttacks(sq, board.allPiecesBB) and rookQueens) != 0: return true
  
  # Sliding Pieces (Bishops, Queens)
  let bishopQueens = board.pieceBB[makePiece(attacker, Bishop)] or board.pieceBB[makePiece(attacker, Queen)]
  if (getBishopAttacks(sq, board.allPiecesBB) and bishopQueens) != 0: return true

  if (getBishopAttacks(sq, board.allPiecesBB) and bishopQueens) != 0: return true
  
proc hasSufficientMaterial*(board: Board, color: Color): bool =
  let nonPawn = board.pieceBB[makePiece(color, Knight)] or
                board.pieceBB[makePiece(color, Bishop)] or
                board.pieceBB[makePiece(color, Rook)] or
                board.pieceBB[makePiece(color, Queen)]
  return nonPawn != 0

proc makeNullMove*(board: var Board) =
  let state = GameState(
    castlingRights: board.castlingRights,
    enPassantSquare: board.enPassantSquare,
    halfMoveClock: board.halfMoveClock,
    zobristKey: board.currentZobristKey,
    capturedPiece: NoPiece
  )
  board.history.add(state)
  
  board.enPassantSquare = NoSquare
  board.sideToMove = if board.sideToMove == White: Black else: White
  
  # Update Zobrist Key (Incremental would be faster, but full regen is safer for now)
  board.currentZobristKey = board.generateZobristKey()

proc unmakeNullMove*(board: var Board) =
  let state = board.history.pop()
  board.castlingRights = state.castlingRights
  board.enPassantSquare = state.enPassantSquare
  board.halfMoveClock = state.halfMoveClock
  board.currentZobristKey = state.zobristKey
  board.sideToMove = if board.sideToMove == White: Black else: White

proc unmakeMove*(board: var Board, move: Move) =
  # Restore State
  let state = board.history.pop()
  board.castlingRights = state.castlingRights
  board.enPassantSquare = state.enPassantSquare
  board.halfMoveClock = state.halfMoveClock
  board.currentZobristKey = state.zobristKey
  # fullMoveNumber and sideToMove need manual reversal
  
  let us = if board.sideToMove == White: Black else: White # Side that moved
  let them = board.sideToMove # Side currently to move (before reversal)
  
  board.sideToMove = us
  if us == Black: dec(board.fullMoveNumber)
  
  let fromSq = move.fromSquare
  let toSq = move.toSquare
  let isCap = move.isCapture
  let isPromo = move.isPromotion
  let capturedPiece = state.capturedPiece
  
  # Identify moving piece (it's at toSq now, unless promo)
  var movingPiece = NoPiece
  if isPromo:
    movingPiece = makePiece(us, Pawn)
    # Remove promoted piece
    let promoPiece = makePiece(us, move.promotion)
    board.pieceBB[promoPiece].clearBit(toSq)
  else:
    # Find piece at toSq
    for p in makePiece(us, Pawn) .. makePiece(us, King):
      if board.pieceBB[p].getBit(toSq):
        movingPiece = p
        break
    board.pieceBB[movingPiece].clearBit(toSq)
    
  # Place moving piece back at source
  board.pieceBB[movingPiece].setBit(fromSq)
  
  # Restore Captured Piece
  if isCap:
    if move.isEnPassant:
      let capSq = if us == White: (toSq.int - 8).Square else: (toSq.int + 8).Square
      board.pieceBB[capturedPiece].setBit(capSq)
    else:
      board.pieceBB[capturedPiece].setBit(toSq)
      
  # Restore Castling Rook
  if move.isCastle:
    let flags = move.flags
    if us == White:
      if flags == KingCastle.int:
        board.pieceBB[WhiteRook].clearBit(squareFromCoords(0, 5)) # f1
        board.pieceBB[WhiteRook].setBit(squareFromCoords(0, 7))   # h1
      elif flags == QueenCastle.int:
        board.pieceBB[WhiteRook].clearBit(squareFromCoords(0, 3)) # d1
        board.pieceBB[WhiteRook].setBit(squareFromCoords(0, 0))   # a1
    else:
      if flags == KingCastle.int:
        board.pieceBB[BlackRook].clearBit(squareFromCoords(7, 5)) # f8
        board.pieceBB[BlackRook].setBit(squareFromCoords(7, 7))   # h8
      elif flags == QueenCastle.int:
        board.pieceBB[BlackRook].clearBit(squareFromCoords(7, 3)) # d8
        board.pieceBB[BlackRook].setBit(squareFromCoords(7, 0))   # a8
        
  board.updateOccupancies()

proc makeMove*(board: var Board, move: Move): bool =
  let us = board.sideToMove
  let them = if us == White: Black else: White
  let fromSq = move.fromSquare
  let toSq = move.toSquare
  let flags = move.flags
  let isCap = move.isCapture
  let isPromo = move.isPromotion
  
  # Identify moving piece
  var movingPiece = NoPiece
  for p in makePiece(us, Pawn) .. makePiece(us, King):
    if board.pieceBB[p].getBit(fromSq):
      movingPiece = p
      break
      
  # Identify captured piece
  var capturedPiece = NoPiece
  if isCap:
    if move.isEnPassant:
      capturedPiece = makePiece(them, Pawn)
    else:
      for p in makePiece(them, Pawn) .. makePiece(them, King):
        if board.pieceBB[p].getBit(toSq):
          capturedPiece = p
          break

  # Save state
  let state = GameState(
    castlingRights: board.castlingRights,
    enPassantSquare: board.enPassantSquare,
    halfMoveClock: board.halfMoveClock,
    zobristKey: board.currentZobristKey,
    capturedPiece: capturedPiece
  )
  board.history.add(state)
  
  # Update Bitboards
  # Remove moving piece from source
  board.pieceBB[movingPiece].clearBit(fromSq)
  
  # Handle Captures
  if isCap:
    if move.isEnPassant:
      let capSq = if us == White: (toSq.int - 8).Square else: (toSq.int + 8).Square
      board.pieceBB[capturedPiece].clearBit(capSq)
    else:
      board.pieceBB[capturedPiece].clearBit(toSq)
      
      # Update Castling Rights if Rook captured
      if capturedPiece == makePiece(them, Rook):
        if toSq == squareFromCoords(0, 0): board.castlingRights = board.castlingRights and not WhiteQueenSide
        elif toSq == squareFromCoords(0, 7): board.castlingRights = board.castlingRights and not WhiteKingSide
        elif toSq == squareFromCoords(7, 0): board.castlingRights = board.castlingRights and not BlackQueenSide
        elif toSq == squareFromCoords(7, 7): board.castlingRights = board.castlingRights and not BlackKingSide

  # Place moving piece at destination
  if isPromo:
    let promoPiece = makePiece(us, move.promotion)
    board.pieceBB[promoPiece].setBit(toSq)
  else:
    board.pieceBB[movingPiece].setBit(toSq)
    
  # Handle Castling Move (Move Rook)
  if move.isCastle:
    if us == White:
      if flags == KingCastle.int: # O-O
        board.pieceBB[WhiteRook].clearBit(squareFromCoords(0, 7)) # h1
        board.pieceBB[WhiteRook].setBit(squareFromCoords(0, 5))   # f1
      elif flags == QueenCastle.int: # O-O-O
        board.pieceBB[WhiteRook].clearBit(squareFromCoords(0, 0)) # a1
        board.pieceBB[WhiteRook].setBit(squareFromCoords(0, 3))   # d1
    else:
      if flags == KingCastle.int: # O-O
        board.pieceBB[BlackRook].clearBit(squareFromCoords(7, 7)) # h8
        board.pieceBB[BlackRook].setBit(squareFromCoords(7, 5))   # f8
      elif flags == QueenCastle.int: # O-O-O
        board.pieceBB[BlackRook].clearBit(squareFromCoords(7, 0)) # a8
        board.pieceBB[BlackRook].setBit(squareFromCoords(7, 3))   # d8

  # Update Castling Rights (if King or Rook moves)
  if movingPiece == makePiece(us, King):
    if us == White:
      board.castlingRights = board.castlingRights and not (WhiteKingSide or WhiteQueenSide)
    else:
      board.castlingRights = board.castlingRights and not (BlackKingSide or BlackQueenSide)
  elif movingPiece == makePiece(us, Rook):
    if us == White:
      if fromSq == squareFromCoords(0, 0): board.castlingRights = board.castlingRights and not WhiteQueenSide
      elif fromSq == squareFromCoords(0, 7): board.castlingRights = board.castlingRights and not WhiteKingSide
    else:
      if fromSq == squareFromCoords(7, 0): board.castlingRights = board.castlingRights and not BlackQueenSide
      elif fromSq == squareFromCoords(7, 7): board.castlingRights = board.castlingRights and not BlackKingSide

  # Update En Passant
  if flags == DoublePawnPush.int:
    let up = if us == White: 8 else: -8
    board.enPassantSquare = fromSq.int + up
  else:
    board.enPassantSquare = NoSquare
    
  # Update HalfMove Clock
  if pieceType(movingPiece) == Pawn or isCap:
    board.halfMoveClock = 0
  else:
    inc(board.halfMoveClock)
    
  # Update FullMove Number
  if us == Black:
    inc(board.fullMoveNumber)
    
  # Update Side to Move
  board.sideToMove = them
  
  # Update Occupancies
  board.updateOccupancies()
  
  # Update Zobrist Key (Full regen for correctness first)
  board.currentZobristKey = board.generateZobristKey()
  
  # Check Legality (King in check?)
  # Note: sideToMove is now 'them', so we check if 'us' King is attacked by 'them'
  let kingSq = bitScanForward(board.pieceBB[makePiece(us, King)])
  if board.isSquareAttacked(kingSq.Square, them):
    board.unmakeMove(move)
    return false
    
  return true


