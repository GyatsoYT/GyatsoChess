import ../src/board, ../src/move, ../src/see, ../src/coretypes, ../src/utils, ../src/bitboard, ../src/lookups, ../src/magicbitboards, ../src/zobrist

# Initialize lookups
precomputeAttackTables()
initMagicBitboards()
initializeZobristKeys()

proc testSEE() =
  echo "Testing SEE..."
  
  var board: Board
  
  # Case 1: Simple Exchange (Pawn takes Pawn, protected by Pawn)
  # White Pawn on e4, Black Pawn on d5. Black Pawn protected by c6 pawn.
  # White to move. Capture d5.
  board = initializeBoard("rnbqkbnr/ppp1pppp/8/3p4/4P3/2P5/PP1P1PPP/RNBQKBNR w KQkq - 0 1")
  # e4xd5 (e4=3,4; d5=4,3)
  let m1 = makeMove(squareFromCoords(3, 4), squareFromCoords(4, 3), NoPieceType, Capture.int) 
  let score1 = see(board, m1)
  echo "Test 1 (Pawn takes Pawn protected by Pawn): ", score1, " (Expected: 0)"
  
  # Case 2: Bad Exchange (Knight takes Pawn protected by Pawn)
  # White Knight on f3, Black Pawn on e5 protected by d6 pawn.
  board = initializeBoard("rnbqkbnr/ppp2ppp/3p4/4p3/8/5N2/PPPPPPPP/RNBQKB1R w KQkq - 0 1")
  # Nf3xe5 (f3=2,5; e5=4,4)
  let m2 = makeMove(squareFromCoords(2, 5), squareFromCoords(4, 4), NoPieceType, Capture.int) 
  let score2 = see(board, m2)
  echo "Test 2 (Knight takes Pawn protected by Pawn): ", score2, " (Expected: -200 approx)"
  
  # Case 3: Hanging Piece (Queen takes Pawn)
  board = initializeBoard("rnbqkbnr/ppp2ppp/8/4p3/8/3Q4/PPPPPPPP/RNB1KBNR w KQkq - 0 1")
  # Qd3xe5 (d3=2,3; e5=4,4)
  let m3 = makeMove(squareFromCoords(2, 3), squareFromCoords(4, 4), NoPieceType, Capture.int) 
  let score3 = see(board, m3)
  echo "Test 3 (Queen takes undefended Pawn): ", score3, " (Expected: 100)"
  
  # Case 4: X-Ray (Rook behind Queen)
  # White Rook on d1, White Queen on d2. Black Pawn on d5 protected by Queen on d8.
  # White Queen takes d5. Black Queen takes d5. White Rook takes d5.
  # Gain: P(100) - Q(900) + Q(900) = 100.
  board = initializeBoard("3q4/8/8/3p4/8/8/3Q4/3R4 w - - 0 1")
  # d2=1,3; d5=4,3
  let m4 = makeMove(squareFromCoords(1, 3), squareFromCoords(4, 3), NoPieceType, Capture.int) 
  let score4 = see(board, m4)
  echo "Test 4 (X-Ray: QxP, QxQ, RxQ): ", score4, " (Expected: 100)"

testSEE()
