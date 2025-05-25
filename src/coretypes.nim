type
  Color* = enum
    White, Black, NoColor

  PieceType* = enum
    Pawn, Knight, Bishop, Rook, Queen, King, NoPieceType

  # Piece encoding:
  # Empty = 0
  # White pieces: WP=1, WN=2, WB=3, WR=4, WQ=5, WK=6
  # Black pieces: BP=7, BN=8, BB=9, BR=10, BQ=11, BK=12
  Piece* = enum
    Empty, # ord = 0
    WP, WN, WB, WR, WQ, WK, # ord = 1..6
    BP, BN, BB, BR, BQ, BK  # ord = 7..12

  Square* = range[0..63] # Represents a square on the board, 0-63

const
  MaxMoves* = 256
  MaxPly* = 128

  numPieceTypesInternal = 6 # Pawn to King (Pawn.ord=0 to King.ord=5)

proc pieceColor*(p: Piece): Color {.inline.} =
  if p == Piece.Empty:
    return Color.NoColor
  # White pieces are WP (ord=1) to WK (ord=6)
  if ord(p) >= ord(Piece.WP) and ord(p) <= ord(Piece.WK):
    return Color.White
  # Black pieces are BP (ord=7) to BK (ord=12)
  elif ord(p) >= ord(Piece.BP) and ord(p) <= ord(Piece.BK):
    return Color.Black
  else:
    # This case should ideally not be reached if Piece enum is used correctly
    return Color.NoColor 

proc pieceType*(p: Piece): PieceType {.inline.} =
  if p == Piece.Empty:
    return PieceType.NoPieceType
  
  let pOrd = ord(p)
  # White pieces: ord(WP)=1 .. ord(WK)=6. Map to PieceType ord 0..5
  if pOrd >= ord(Piece.WP) and pOrd <= ord(Piece.WK):
    return PieceType(pOrd - ord(Piece.WP))
  # Black pieces: ord(BP)=7 .. ord(BK)=12. Map to PieceType ord 0..5
  elif pOrd >= ord(Piece.BP) and pOrd <= ord(Piece.BK):
    return PieceType(pOrd - ord(Piece.BP))
  else:
    # This case should ideally not be reached
    return PieceType.NoPieceType

proc makePiece*(c: Color, pt: PieceType): Piece {.inline.} =
  if c == Color.NoColor or pt == PieceType.NoPieceType:
    return Piece.Empty
  
  let ptOrd = ord(pt)
  # Ensure pt is one of Pawn..King
  if ptOrd < ord(PieceType.Pawn) or ptOrd > ord(PieceType.King):
    return Piece.Empty

  if c == Color.White:
    # ord(Piece.WP) is 1. ptOrd for Pawn is 0. So, Piece(0 + 1) = Piece(1) = WP.
    return Piece(ptOrd + ord(Piece.WP))
  elif c == Color.Black:
    # ord(Piece.BP) is 7. ptOrd for Pawn is 0. So, Piece(0 + 7) = Piece(7) = BP.
    return Piece(ptOrd + ord(Piece.BP))
  # c == NoColor is already handled by the first check
  # Defaulting to Empty for any other unexpected Color, though enum should prevent this.
  return Piece.Empty 