import coretypes
import board
import bitboard # For popcount


const
  PawnValue*   = 100
  KnightValue* = 300
  BishopValue* = 310 # Slightly more than knight
  RookValue*   = 500
  QueenValue*  = 900
  KingValue*   = 20000 # Large value representing game over importance

# Piece-Square Tables (PSTs) - values in centipawns
# Indexed by Square (0-63), from White's perspective (A1 = 0, H8 = 63)
# For Black, the square index will be mirrored (sq xor 56).

const pawnPST*: array[Square, int] = [
   0,  0,  0,  0,  0,  0,  0,  0,
   5, 10, 10,-20,-20, 10, 10,  5,
   5, -5,-10,  0,  0,-10, -5,  5,
   0,  0,  0, 20, 20,  0,  0,  0,
   5,  5, 10, 25, 25, 10,  5,  5,
  10, 10, 20, 30, 30, 20, 10, 10,
  50, 50, 50, 50, 50, 50, 50, 50,
   0,  0,  0,  0,  0,  0,  0,  0
]

const knightPST*: array[Square, int] = [
  -50,-40,-30,-30,-30,-30,-40,-50,
  -40,-20,  0,  5,  5,  0,-20,-40,
  -30,  5, 10, 15, 15, 10,  5,-30,
  -30,  0, 15, 20, 20, 15,  0,-30,
  -30,  5, 15, 20, 20, 15,  5,-30,
  -30,  0, 10, 15, 15, 10,  0,-30,
  -40,-20,  0,  0,  0,  0,-20,-40,
  -50,-40,-30,-30,-30,-30,-40,-50
]

const bishopPST*: array[Square, int] = [
  -20,-10,-10,-10,-10,-10,-10,-20,
  -10,  5,  0,  0,  0,  0,  5,-10,
  -10, 10, 10, 10, 10, 10, 10,-10,
  -10,  0, 10, 10, 10, 10,  0,-10,
  -10,  5,  5, 10, 10,  5,  5,-10,
  -10,  0,  5, 10, 10,  5,  0,-10,
  -10,  0,  0,  0,  0,  0,  0,-10,
  -20,-10,-10,-10,-10,-10,-10,-20
]

const rookPST*: array[Square, int] = [
   0,  0,  0,  5,  5,  0,  0,  0,
  -5,  0,  0,  0,  0,  0,  0, -5,
  -5,  0,  0,  0,  0,  0,  0, -5,
  -5,  0,  0,  0,  0,  0,  0, -5,
  -5,  0,  0,  0,  0,  0,  0, -5,
  -5,  0,  0,  0,  0,  0,  0, -5,
   5, 10, 10, 10, 10, 10, 10,  5,
   0,  0,  0,  0,  0,  0,  0,  0
]

const queenPST*: array[Square, int] = [
  -20,-10,-10, -5, -5,-10,-10,-20,
  -10,  0,  5,  0,  0,  0,  0,-10,
  -10,  5,  5,  5,  5,  5,  0,-10,
   0,  0,  5,  5,  5,  5,  0, -5,
  -5,  0,  5,  5,  5,  5,  0, -5,
  -10,  0,  5,  5,  5,  5,  0,-10,
  -10,  0,  0,  0,  0,  0,  0,-10,
  -20,-10,-10, -5, -5,-10,-10,-20
]

# King PST is often split into middlegame and endgame. For now, a single one.
const kingPST*: array[Square, int] = [
  # Middlegame King Safety - encourages castling
   20, 30, 10,  0,  0, 10, 30, 20,
   20, 20,  0,  0,  0,  0, 20, 20,
  -10,-20,-20,-20,-20,-20,-20,-10,
  -20,-30,-30,-40,-40,-30,-30,-20,
  -30,-40,-40,-50,-50,-40,-40,-30,
  -30,-40,-40,-50,-50,-40,-40,-30,
  -30,-40,-40,-50,-50,-40,-40,-30,
  -30,-40,-40,-50,-50,-40,-40,-30
]

proc mirroredSquare(sq: Square): Square {.inline.} =
  ## Mirrors a square vertically (flips the rank).
  ## E.g., a1 (sq 0, rank 0) becomes a8 (sq 56, rank 7).
  ## h8 (sq 63, rank 7) becomes h1 (sq 7, rank 0).
  return Square(sq xor 56)

proc evaluate*(boardState: Board): int =
  ## Calculates a score for the current board position from the perspective
  ## of the board.sideToMove, based on material count and piece-square tables.

  var whiteScore = 0
  var blackScore = 0

  # --- White's evaluation ---
  var bb = boardState.pieceBB[Piece.WP]
  while bb != 0:
    let sq = popBit(bb)
    whiteScore += PawnValue + pawnPST[sq]
  
  bb = boardState.pieceBB[Piece.WN]
  while bb != 0:
    let sq = popBit(bb)
    whiteScore += KnightValue + knightPST[sq]

  bb = boardState.pieceBB[Piece.WB]
  while bb != 0:
    let sq = popBit(bb)
    whiteScore += BishopValue + bishopPST[sq]

  bb = boardState.pieceBB[Piece.WR]
  while bb != 0:
    let sq = popBit(bb)
    whiteScore += RookValue + rookPST[sq]

  bb = boardState.pieceBB[Piece.WQ]
  while bb != 0:
    let sq = popBit(bb)
    whiteScore += QueenValue + queenPST[sq]
  
  # King material is large, PST for king is more about safety/position
  bb = boardState.pieceBB[Piece.WK]
  if bb != 0: # Should always be true for a valid board state
    let sq = popBit(bb) # Assuming only one king
    whiteScore += KingValue + kingPST[sq]


  # --- Black's evaluation ---
  bb = boardState.pieceBB[Piece.BP]
  while bb != 0:
    let sq = popBit(bb)
    blackScore += PawnValue + pawnPST[mirroredSquare(sq)]

  bb = boardState.pieceBB[Piece.BN]
  while bb != 0:
    let sq = popBit(bb)
    blackScore += KnightValue + knightPST[mirroredSquare(sq)]

  bb = boardState.pieceBB[Piece.BB]
  while bb != 0:
    let sq = popBit(bb)
    blackScore += BishopValue + bishopPST[mirroredSquare(sq)]

  bb = boardState.pieceBB[Piece.BR]
  while bb != 0:
    let sq = popBit(bb)
    blackScore += RookValue + rookPST[mirroredSquare(sq)]

  bb = boardState.pieceBB[Piece.BQ]
  while bb != 0:
    let sq = popBit(bb)
    blackScore += QueenValue + queenPST[mirroredSquare(sq)]
  
  bb = boardState.pieceBB[Piece.BK]
  if bb != 0: # Should always be true
    let sq = popBit(bb) # Assuming only one king
    blackScore += KingValue + kingPST[mirroredSquare(sq)]

  let totalScoreDifference = whiteScore - blackScore

  if boardState.sideToMove == Color.White:
    return totalScoreDifference
  else: # boardState.sideToMove == Color.Black
    return -totalScoreDifference 