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
    pieces*: array[Square, Piece] # Mailbox representation
    sideToMove*: Color

    enPassantSquare*: int 
    castlingRights*: int
    halfMoveClock*: int
    fullMoveNumber*: int
    gamePly*: int 
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
  for s in 0..63: board.pieces[s.Square] = NoPiece
  for c in Color: board.occupiedBB[c] = 0

  board.allPiecesBB = 0
  board.sideToMove = White
  board.enPassantSquare = NoSquare
  board.castlingRights = 0
  board.halfMoveClock = 0
  board.fullMoveNumber = 1
  board.gamePly = 0
  board.currentZobristKey = 0

proc updateOccupancies*(board: var Board) =
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
        board.pieces[sq] = piece
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

  # Calculate gamePly from fullMoveNumber and sideToMove
  board.gamePly = (board.fullMoveNumber - 1) * 2 + (if board.sideToMove == Black: 1 else: 0)

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
  
proc hasSufficientMaterial*(board: Board, color: Color): bool =
  let nonPawn = board.pieceBB[makePiece(color, Knight)] or
                board.pieceBB[makePiece(color, Bishop)] or
                board.pieceBB[makePiece(color, Rook)] or
                board.pieceBB[makePiece(color, Queen)]
  return nonPawn != 0

proc isInsufficientMaterial*(board: Board): bool =
  # If there are any pawns, rooks, or queens, it's not insufficient material
  if (board.pieceBB[WhitePawn] or board.pieceBB[BlackPawn] or
      board.pieceBB[WhiteRook] or board.pieceBB[BlackRook] or
      board.pieceBB[WhiteQueen] or board.pieceBB[BlackQueen]) != 0:
    return false

  # Count minors
  let whiteKnights = countSetBits(board.pieceBB[WhiteKnight])
  let blackKnights = countSetBits(board.pieceBB[BlackKnight])
  let whiteBishops = countSetBits(board.pieceBB[WhiteBishop])
  let blackBishops = countSetBits(board.pieceBB[BlackBishop])
  
  let whiteMinors = whiteKnights + whiteBishops
  let blackMinors = blackKnights + blackBishops
  let totalMinors = whiteMinors + blackMinors

  # K vs K
  if totalMinors == 0: return true
  
  # K+N vs K or K+B vs K (one minor total)
  if totalMinors == 1: return true
  
  # KB vs KB (same color bishops)
  if totalMinors == 2 and whiteBishops == 1 and blackBishops == 1:
    let wbSq = bitScanForward(board.pieceBB[WhiteBishop])
    let bbSq = bitScanForward(board.pieceBB[BlackBishop])
    let wbColor = (rankOf(wbSq.Square) + fileOf(wbSq.Square)) mod 2
    let bbColor = (rankOf(bbSq.Square) + fileOf(bbSq.Square)) mod 2
    if wbColor == bbColor: return true
    
  return false

proc isRepetition*(board: Board): bool =
  
  if board.halfMoveClock < 4: return false
  
  let currentKey = board.currentZobristKey
  let historyLen = board.history.len
  let startIdx = historyLen - 2
  let endIdx = historyLen - board.halfMoveClock
  
  var i = startIdx
  while i >= endIdx and i >= 0:
    if board.history[i].zobristKey == currentKey:
      return true
    i -= 2
    
  return false

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
  let state = board.history.pop()
  board.castlingRights = state.castlingRights
  board.enPassantSquare = state.enPassantSquare
  board.halfMoveClock = state.halfMoveClock
  board.currentZobristKey = state.zobristKey
  
  let us = if board.sideToMove == White: Black else: White 
  let them = board.sideToMove 
  
  board.sideToMove = us
  if us == Black: dec(board.fullMoveNumber)
  dec(board.gamePly)
  
  let fromSq = move.fromSquare
  let toSq = move.toSquare
  let isCap = move.isCapture
  let isPromo = move.isPromotion
  let capturedPiece = state.capturedPiece
  
  var movingPiece = NoPiece
  if isPromo:
    movingPiece = makePiece(us, Pawn)
    let promoPiece = makePiece(us, move.promotion)
    board.pieceBB[promoPiece].clearBit(toSq)
    board.pieces[toSq] = NoPiece
  else:
    movingPiece = board.pieces[toSq]
    board.pieceBB[movingPiece].clearBit(toSq)
    board.pieces[toSq] = NoPiece
    
  board.pieceBB[movingPiece].setBit(fromSq)
  board.pieces[fromSq] = movingPiece
  
  # Restore Captured Piece
  if isCap:
    if move.isEnPassant:
      let capSq = if us == White: (toSq.int - 8).Square else: (toSq.int + 8).Square
      board.pieceBB[capturedPiece].setBit(capSq)
      board.pieces[capSq] = capturedPiece
    else:
      board.pieceBB[capturedPiece].setBit(toSq)
      board.pieces[toSq] = capturedPiece
      
  # Restore Castling Rook
  if move.isCastle:
    let flags = move.flags
    if us == White:
      if flags == KingCastle.int:
        board.pieceBB[WhiteRook].clearBit(squareFromCoords(0, 5)) # f1
        board.pieces[squareFromCoords(0, 5)] = NoPiece
        board.pieceBB[WhiteRook].setBit(squareFromCoords(0, 7))   # h1
        board.pieces[squareFromCoords(0, 7)] = WhiteRook
        
        # Incremental Update: Move Rook in occupiedBB and allPiecesBB
        board.occupiedBB[White].clearBit(squareFromCoords(0, 5))
        board.occupiedBB[White].setBit(squareFromCoords(0, 7))
        board.allPiecesBB.clearBit(squareFromCoords(0, 5))
        board.allPiecesBB.setBit(squareFromCoords(0, 7))

      elif flags == QueenCastle.int:
        board.pieceBB[WhiteRook].clearBit(squareFromCoords(0, 3)) # d1
        board.pieces[squareFromCoords(0, 3)] = NoPiece
        board.pieceBB[WhiteRook].setBit(squareFromCoords(0, 0))   # a1
        board.pieces[squareFromCoords(0, 0)] = WhiteRook
        
        # Incremental Update
        board.occupiedBB[White].clearBit(squareFromCoords(0, 3))
        board.occupiedBB[White].setBit(squareFromCoords(0, 0))
        board.allPiecesBB.clearBit(squareFromCoords(0, 3))
        board.allPiecesBB.setBit(squareFromCoords(0, 0))

    else:
      if flags == KingCastle.int:
        board.pieceBB[BlackRook].clearBit(squareFromCoords(7, 5)) # f8
        board.pieces[squareFromCoords(7, 5)] = NoPiece
        board.pieceBB[BlackRook].setBit(squareFromCoords(7, 7))   # h8
        board.pieces[squareFromCoords(7, 7)] = BlackRook

        # Incremental Update
        board.occupiedBB[Black].clearBit(squareFromCoords(7, 5))
        board.occupiedBB[Black].setBit(squareFromCoords(7, 7))
        board.allPiecesBB.clearBit(squareFromCoords(7, 5))
        board.allPiecesBB.setBit(squareFromCoords(7, 7))

      elif flags == QueenCastle.int:
        board.pieceBB[BlackRook].clearBit(squareFromCoords(7, 3)) # d8
        board.pieces[squareFromCoords(7, 3)] = NoPiece
        board.pieceBB[BlackRook].setBit(squareFromCoords(7, 0))   # a8
        board.pieces[squareFromCoords(7, 0)] = BlackRook

        # Incremental Update
        board.occupiedBB[Black].clearBit(squareFromCoords(7, 3))
        board.occupiedBB[Black].setBit(squareFromCoords(7, 0))
        board.allPiecesBB.clearBit(squareFromCoords(7, 3))
        board.allPiecesBB.setBit(squareFromCoords(7, 0))

  
  if isPromo:
    board.occupiedBB[us].clearBit(toSq)
    board.occupiedBB[us].setBit(fromSq)
    board.allPiecesBB.clearBit(toSq)
    board.allPiecesBB.setBit(fromSq)
  else:
    board.occupiedBB[us].clearBit(toSq)
    board.occupiedBB[us].setBit(fromSq)
    board.allPiecesBB.clearBit(toSq)
    board.allPiecesBB.setBit(fromSq)
    
  # Restore Captured
  if isCap:
    if move.isEnPassant:
      let capSq = if us == White: (toSq.int - 8).Square else: (toSq.int + 8).Square
      # Add captured pawn back to them
      board.occupiedBB[them].setBit(capSq)
      board.allPiecesBB.setBit(capSq)
    else:
      board.occupiedBB[them].setBit(toSq)
      board.allPiecesBB.setBit(toSq)

proc makeMove*(board: var Board, move: Move): bool =
  let us = board.sideToMove
  let them = if us == White: Black else: White
  let fromSq = move.fromSquare
  let toSq = move.toSquare
  let flags = move.flags
  let isCap = move.isCapture
  let isPromo = move.isPromotion
  
  # Identify moving piece
  let movingPiece = board.pieces[fromSq]
  
  # Identify captured piece
  var capturedPiece = NoPiece
  if isCap:
    if move.isEnPassant:
      capturedPiece = makePiece(them, Pawn)
    else:
      capturedPiece = board.pieces[toSq]

  # Save state
  let state = GameState(
    castlingRights: board.castlingRights,
    enPassantSquare: board.enPassantSquare,
    halfMoveClock: board.halfMoveClock,
    zobristKey: board.currentZobristKey,
    capturedPiece: capturedPiece
  )
  board.history.add(state)
  
  # Incremental Zobrist Update
  var key = board.currentZobristKey
  
  # Remove moving piece from source
  key = key xor zobristTable[movingPiece][fromSq]
  board.pieceBB[movingPiece].clearBit(fromSq)
  board.pieces[fromSq] = NoPiece
  
  # Handle Captures
  if isCap:
    if move.isEnPassant:
      let capSq = if us == White: (toSq.int - 8).Square else: (toSq.int + 8).Square
      key = key xor zobristTable[capturedPiece][capSq]
      board.pieceBB[capturedPiece].clearBit(capSq)
      board.pieces[capSq] = NoPiece
    else:
      key = key xor zobristTable[capturedPiece][toSq]
      board.pieceBB[capturedPiece].clearBit(toSq)
      # pieces[toSq] will be overwritten by moving piece later
      
  # INCREMENTAL UPDATES
  
  # 1. Moving Piece: Remove from Source
  board.occupiedBB[us].clearBit(fromSq)
  board.allPiecesBB.clearBit(fromSq)
  
  # 2. Handle Captures: Remove from Them
  if isCap:
    if move.isEnPassant:
      let capSq = if us == White: (toSq.int - 8).Square else: (toSq.int + 8).Square
      board.occupiedBB[them].clearBit(capSq)
      board.allPiecesBB.clearBit(capSq)
    else:
      board.occupiedBB[them].clearBit(toSq)
      board.allPiecesBB.clearBit(toSq)
      
      # Update Castling Rights if Rook captured
      if capturedPiece == makePiece(them, Rook):
        if toSq == squareFromCoords(0, 0): board.castlingRights = board.castlingRights and not WhiteQueenSide
        elif toSq == squareFromCoords(0, 7): board.castlingRights = board.castlingRights and not WhiteKingSide
        elif toSq == squareFromCoords(7, 0): board.castlingRights = board.castlingRights and not BlackQueenSide
        elif toSq == squareFromCoords(7, 7): board.castlingRights = board.castlingRights and not BlackKingSide

  # 3. Place moving piece at destination (Pawn or Promo)
  if isPromo:
    let promoPiece = makePiece(us, move.promotion)
    key = key xor zobristTable[promoPiece][toSq]
    board.pieceBB[promoPiece].setBit(toSq)
    board.pieces[toSq] = promoPiece
  else:
    key = key xor zobristTable[movingPiece][toSq]
    board.pieceBB[movingPiece].setBit(toSq)
    board.pieces[toSq] = movingPiece

  board.occupiedBB[us].setBit(toSq)
  board.allPiecesBB.setBit(toSq)

  if move.isCastle:
    if us == White:
      if flags == KingCastle.int: # O-O
        # Move Rook from h1 to f1
        key = key xor zobristTable[WhiteRook][squareFromCoords(0, 7)]
        key = key xor zobristTable[WhiteRook][squareFromCoords(0, 5)]
        board.pieceBB[WhiteRook].clearBit(squareFromCoords(0, 7))
        board.pieces[squareFromCoords(0, 7)] = NoPiece
        board.pieceBB[WhiteRook].setBit(squareFromCoords(0, 5))
        board.pieces[squareFromCoords(0, 5)] = WhiteRook
        
        # Incremental
        board.occupiedBB[White].clearBit(squareFromCoords(0, 7))
        board.occupiedBB[White].setBit(squareFromCoords(0, 5))
        board.allPiecesBB.clearBit(squareFromCoords(0, 7))
        board.allPiecesBB.setBit(squareFromCoords(0, 5))
        
      elif flags == QueenCastle.int: # O-O-O
        # Move Rook from a1 to d1
        key = key xor zobristTable[WhiteRook][squareFromCoords(0, 0)]
        key = key xor zobristTable[WhiteRook][squareFromCoords(0, 3)]
        board.pieceBB[WhiteRook].clearBit(squareFromCoords(0, 0))
        board.pieces[squareFromCoords(0, 0)] = NoPiece
        board.pieceBB[WhiteRook].setBit(squareFromCoords(0, 3))
        board.pieces[squareFromCoords(0, 3)] = WhiteRook

        # Incremental
        board.occupiedBB[White].clearBit(squareFromCoords(0, 0))
        board.occupiedBB[White].setBit(squareFromCoords(0, 3))
        board.allPiecesBB.clearBit(squareFromCoords(0, 0))
        board.allPiecesBB.setBit(squareFromCoords(0, 3))

    else:
      if flags == KingCastle.int: # O-O
        # Move Rook from h8 to f8
        key = key xor zobristTable[BlackRook][squareFromCoords(7, 7)]
        key = key xor zobristTable[BlackRook][squareFromCoords(7, 5)]
        board.pieceBB[BlackRook].clearBit(squareFromCoords(7, 7))
        board.pieces[squareFromCoords(7, 7)] = NoPiece
        board.pieceBB[BlackRook].setBit(squareFromCoords(7, 5))
        board.pieces[squareFromCoords(7, 5)] = BlackRook

        # Incremental
        board.occupiedBB[Black].clearBit(squareFromCoords(7, 7))
        board.occupiedBB[Black].setBit(squareFromCoords(7, 5))
        board.allPiecesBB.clearBit(squareFromCoords(7, 7))
        board.allPiecesBB.setBit(squareFromCoords(7, 5))

      elif flags == QueenCastle.int: # O-O-O
        # Move Rook from a8 to d8
        key = key xor zobristTable[BlackRook][squareFromCoords(7, 0)]
        key = key xor zobristTable[BlackRook][squareFromCoords(7, 3)]
        board.pieceBB[BlackRook].clearBit(squareFromCoords(7, 0))
        board.pieces[squareFromCoords(7, 0)] = NoPiece
        board.pieceBB[BlackRook].setBit(squareFromCoords(7, 3))
        board.pieces[squareFromCoords(7, 3)] = BlackRook

        # Incremental
        board.occupiedBB[Black].clearBit(squareFromCoords(7, 0))
        board.occupiedBB[Black].setBit(squareFromCoords(7, 3))
        board.allPiecesBB.clearBit(squareFromCoords(7, 0))
        board.allPiecesBB.setBit(squareFromCoords(7, 3))

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
  if board.enPassantSquare != NoSquare:
    let file = fileOf(board.enPassantSquare.Square)
    key = key xor zobristEnPassant[file] # Remove old EP key
    
  if flags == DoublePawnPush.int:
    let up = if us == White: 8 else: -8
    board.enPassantSquare = fromSq.int + up
    let file = fileOf(board.enPassantSquare.Square)
    key = key xor zobristEnPassant[file] # Add new EP key
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
  
  # Update GamePly
  inc(board.gamePly)
    
  # Update Side to Move
  board.sideToMove = them
  key = key xor zobristSideToMove
  
  # Update Castling Rights Key
  key = key xor zobristCastling[state.castlingRights] # Remove old
  key = key xor zobristCastling[board.castlingRights] # Add new
  
  # Update Zobrist Key
  board.currentZobristKey = key

  let kingSq = bitScanForward(board.pieceBB[makePiece(us, King)])
  if board.isSquareAttacked(kingSq.Square, them):
    board.unmakeMove(move)
    return false
    
  return true


