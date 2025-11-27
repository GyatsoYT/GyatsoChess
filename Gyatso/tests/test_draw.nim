import ../src/board, ../src/coretypes, ../src/search, ../src/move, ../src/utils, ../src/bitboard, ../src/zobrist, ../src/lookups, ../src/magicbitboards
import std/unittest

# Initialize lookups
precomputeAttackTables()
initMagicBitboards()
initializeZobristKeys()

# Helper
func sq(s: string): Square = algebraicToSquare(s)

suite "Draw Detection Tests":
  
  test "Insufficient Material":
    var board: Board
    
    # K vs K
    board = initializeBoard("8/8/8/8/8/8/8/4K3 w - - 0 1")
    board.pieceBB[BlackKing] = 1.Bitboard shl 60 # Place black king somewhere
    board.updateOccupancies()
    check board.isInsufficientMaterial() == true
    
    # K+N vs K
    board = initializeBoard("8/8/8/8/8/8/8/4K3 w - - 0 1")
    board.pieceBB[BlackKing] = 1.Bitboard shl 60
    board.pieceBB[WhiteKnight] = 1.Bitboard shl 10
    board.updateOccupancies()
    check board.isInsufficientMaterial() == true
    
    # K+B vs K
    board = initializeBoard("8/8/8/8/8/8/8/4K3 w - - 0 1")
    board.pieceBB[BlackKing] = 1.Bitboard shl 60
    board.pieceBB[WhiteBishop] = 1.Bitboard shl 10
    board.updateOccupancies()
    check board.isInsufficientMaterial() == true
    
    # KB vs KB (same color)
    board = initializeBoard("8/8/8/8/8/8/8/4K3 w - - 0 1")
    board.pieceBB[BlackKing] = 1.Bitboard shl 60
    # White Bishop on a1 (dark)
    board.pieceBB[WhiteBishop] = 1.Bitboard shl 0 
    # Black Bishop on h8 (dark)
    board.pieceBB[BlackBishop] = 1.Bitboard shl 63
    board.updateOccupancies()
    check board.isInsufficientMaterial() == true
    
    # KB vs KB (diff color)
    board = initializeBoard("8/8/8/8/8/8/8/4K3 w - - 0 1")
    board.pieceBB[BlackKing] = 1.Bitboard shl 60
    # White Bishop on a1 (dark)
    board.pieceBB[WhiteBishop] = 1.Bitboard shl 0 
    # Black Bishop on h1 (light)
    board.pieceBB[BlackBishop] = 1.Bitboard shl 7
    board.updateOccupancies()
    check board.isInsufficientMaterial() == false
    
    # K+R vs K (Sufficient)
    board = initializeBoard("8/8/8/8/8/8/8/4K3 w - - 0 1")
    board.pieceBB[BlackKing] = 1.Bitboard shl 60
    board.pieceBB[WhiteRook] = 1.Bitboard shl 10
    board.updateOccupancies()
    check board.isInsufficientMaterial() == false

  test "Repetition Detection":
    var board = initializeBoard(DefaultFen)
    
    # Move 1: e4 e5
    discard board.makeMove(makeMove(sq("e2"), sq("e4"), NoPieceType, DoublePawnPush.int))
    discard board.makeMove(makeMove(sq("e7"), sq("e5"), NoPieceType, DoublePawnPush.int))
    
    # Move 2: Nf3 Nc6
    discard board.makeMove(makeMove(sq("g1"), sq("f3")))
    discard board.makeMove(makeMove(sq("b8"), sq("c6")))
    
    # Start repetition sequence
    # Ng1 Nb8 Nf3 Nc6 (Repeat 1)
    
    # 1. Ng1
    discard board.makeMove(makeMove(sq("f3"), sq("g1")))
    check board.isRepetition() == false
    
    # 1... Nb8
    discard board.makeMove(makeMove(sq("c6"), sq("b8")))
    check board.isRepetition() == false
    
    # 2. Nf3 (Position repeated once? No, needs 3 fold for draw, but we detect any repetition for search avoidance)
    # Our logic detects ANY repetition from history.
    # Current position: White to move.
    # Previous occurrence: After 1. e4 e5 2. Nf3 Nc6
    # Let's trace:
    # Start: Pos A
    # e4 e5: Pos B
    # Nf3 Nc6: Pos C (White to move)
    # Ng1 Nb8: Pos B (White to move) -> Wait, e4 e5 is played. Pieces are back.
    # Actually:
    # Start
    # 1. e4 e5
    # 2. Nf3 Nc6 -> Position X
    # 3. Ng1 Nb8 -> Position Y (almost start, but e4 e5 played)
    # 4. Nf3 Nc6 -> Position X again.
    
    discard board.makeMove(makeMove(sq("g1"), sq("f3")))
    # Now we are at Position X again.
    # History should contain Position X from move 2.
    check board.isRepetition() == true
    
  test "Search Contempt":
    var board = initializeBoard(DefaultFen)
    var info: SearchInfo
    
    # Force a repetition state
    # 1. Nf3 Nf6 2. Ng1 Ng8 3. Nf3
    discard board.makeMove(makeMove(sq("g1"), sq("f3")))
    discard board.makeMove(makeMove(sq("g8"), sq("f6")))
    discard board.makeMove(makeMove(sq("f3"), sq("g1")))
    discard board.makeMove(makeMove(sq("f6"), sq("g8")))
    
    # Now playing Nf3 repeats position
    discard board.makeMove(makeMove(sq("g1"), sq("f3")))
    
    # We are now at a repeated position.
    # If we call negamax with depth 1, it should detect repetition immediately?
    # Wait, isRepetition checks if CURRENT position is in history.
    # Yes, we just made the move that repeated.
    
    check board.isRepetition() == true
    
    # Call negamax
    # ply should be > 0 for Contempt
    let score = negamax(board, 1, -Infinity, Infinity, 1, info)
    check score == Contempt
    
    # At root (ply 0)
    let rootScore = negamax(board, 1, -Infinity, Infinity, 0, info)
    check rootScore == 0

