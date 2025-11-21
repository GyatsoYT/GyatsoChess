import coretypes, bitboard, board

const
  PawnValue* = 100
  KnightValue* = 300
  BishopValue* = 310
  RookValue* = 500
  QueenValue* = 900
  KingValue* = 20000

  # Piece-Square Tables
  # Tables are from White's perspective. Black's are mirrored.
  # Values are in centipawns.
  
  PawnPST: array[Square, int] = [
      0,  0,  0,  0,  0,  0,  0,  0,
     50, 50, 50, 50, 50, 50, 50, 50,
     10, 10, 20, 30, 30, 20, 10, 10,
      5,  5, 10, 25, 25, 10,  5,  5,
      0,  0,  0, 20, 20,  0,  0,  0,
      5, -5,-10,  0,  0,-10, -5,  5,
      5, 10, 10,-20,-20, 10, 10,  5,
      0,  0,  0,  0,  0,  0,  0,  0
  ]

  KnightPST: array[Square, int] = [
    -50,-40,-30,-30,-30,-30,-40,-50,
    -40,-20,  0,  0,  0,  0,-20,-40,
    -30,  0, 10, 15, 15, 10,  0,-30,
    -30,  5, 15, 20, 20, 15,  5,-30,
    -30,  0, 15, 20, 20, 15,  0,-30,
    -30,  5, 10, 15, 15, 10,  5,-30,
    -40,-20,  0,  5,  5,  0,-20,-40,
    -50,-40,-30,-30,-30,-30,-40,-50
  ]

  BishopPST: array[Square, int] = [
    -20,-10,-10,-10,-10,-10,-10,-20,
    -10,  0,  0,  0,  0,  0,  0,-10,
    -10,  0,  5, 10, 10,  5,  0,-10,
    -10,  5,  5, 10, 10,  5,  5,-10,
    -10,  0, 10, 10, 10, 10,  0,-10,
    -10, 10, 10, 10, 10, 10, 10,-10,
    -10,  5,  0,  0,  0,  0,  5,-10,
    -20,-10,-10,-10,-10,-10,-10,-20
  ]

  RookPST: array[Square, int] = [
      0,  0,  0,  0,  0,  0,  0,  0,
      5, 10, 10, 10, 10, 10, 10,  5,
     -5,  0,  0,  0,  0,  0,  0, -5,
     -5,  0,  0,  0,  0,  0,  0, -5,
     -5,  0,  0,  0,  0,  0,  0, -5,
     -5,  0,  0,  0,  0,  0,  0, -5,
     -5,  0,  0,  0,  0,  0,  0, -5,
      0,  0,  0,  5,  5,  0,  0,  0
  ]

  QueenPST: array[Square, int] = [
    -20,-10,-10, -5, -5,-10,-10,-20,
    -10,  0,  0,  0,  0,  0,  0,-10,
    -10,  0,  5,  5,  5,  5,  0,-10,
     -5,  0,  5,  5,  5,  5,  0, -5,
      0,  0,  5,  5,  5,  5,  0, -5,
    -10,  5,  5,  5,  5,  5,  0,-10,
    -10,  0,  5,  0,  0,  0,  0,-10,
    -20,-10,-10, -5, -5,-10,-10,-20
  ]

  # King Middle Game PST
  KingPST: array[Square, int] = [
    -30,-40,-40,-50,-50,-40,-40,-30,
    -30,-40,-40,-50,-50,-40,-40,-30,
    -30,-40,-40,-50,-50,-40,-40,-30,
    -30,-40,-40,-50,-50,-40,-40,-30,
    -20,-30,-30,-40,-40,-30,-30,-20,
    -10,-20,-20,-20,-20,-20,-20,-10,
     20, 20,  0,  0,  0,  0, 20, 20,
     20, 30, 10,  0,  0, 10, 30, 20
  ]

# Helper to mirror square for Black (flip rank)
# Square 0 (a1) -> 56 (a8)
# Square 7 (h1) -> 63 (h8)
# Formula: sq xor 56
func mirrorSquare(sq: Square): Square {.inline.} =
  (sq.int xor 56).Square

proc evaluate*(board: Board): int =
  var whiteScore = 0
  var blackScore = 0
  
  # Pawns
  var bb = board.pieceBB[WhitePawn]
  while bb != 0:
    let sq = popBit(bb)
    whiteScore += PawnValue + PawnPST[sq]
    
  bb = board.pieceBB[BlackPawn]
  while bb != 0:
    let sq = popBit(bb)
    blackScore += PawnValue + PawnPST[mirrorSquare(sq)]
    
  # Knights
  bb = board.pieceBB[WhiteKnight]
  while bb != 0:
    let sq = popBit(bb)
    whiteScore += KnightValue + KnightPST[sq]
    
  bb = board.pieceBB[BlackKnight]
  while bb != 0:
    let sq = popBit(bb)
    blackScore += KnightValue + KnightPST[mirrorSquare(sq)]
    
  # Bishops
  bb = board.pieceBB[WhiteBishop]
  while bb != 0:
    let sq = popBit(bb)
    whiteScore += BishopValue + BishopPST[sq]
    
  bb = board.pieceBB[BlackBishop]
  while bb != 0:
    let sq = popBit(bb)
    blackScore += BishopValue + BishopPST[mirrorSquare(sq)]
    
  # Rooks
  bb = board.pieceBB[WhiteRook]
  while bb != 0:
    let sq = popBit(bb)
    whiteScore += RookValue + RookPST[sq]
    
  bb = board.pieceBB[BlackRook]
  while bb != 0:
    let sq = popBit(bb)
    blackScore += RookValue + RookPST[mirrorSquare(sq)]
    
  # Queens
  bb = board.pieceBB[WhiteQueen]
  while bb != 0:
    let sq = popBit(bb)
    whiteScore += QueenValue + QueenPST[sq]
    
  bb = board.pieceBB[BlackQueen]
  while bb != 0:
    let sq = popBit(bb)
    blackScore += QueenValue + QueenPST[mirrorSquare(sq)]
    
  # Kings
  bb = board.pieceBB[WhiteKing]
  if bb != 0:
    let sq = popBit(bb)
    whiteScore += KingValue + KingPST[sq]
    
  bb = board.pieceBB[BlackKing]
  if bb != 0:
    let sq = popBit(bb)
    blackScore += KingValue + KingPST[mirrorSquare(sq)]
    
  # Return score from perspective of side to move
  if board.sideToMove == White:
    return whiteScore - blackScore
  else:
    return blackScore - whiteScore
