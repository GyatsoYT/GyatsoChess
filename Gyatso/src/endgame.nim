import coretypes, bitboard, board, utils

const
  TB_WIN* = 300

var
  DISTANCE*: array[Square, array[Square, int]]

proc initEndgame*() =
  for s1 in Square(0)..Square(63):
    for s2 in Square(0)..Square(63):
      let f1 = fileOf(s1)
      let r1 = rankOf(s1)
      let f2 = fileOf(s2)
      let r2 = rankOf(s2)
      
      DISTANCE[s1][s2] = abs(f1 - f2) + abs(r1 - r2)

# Run initialization at startup
initEndgame()

proc mopUpEvaluation*(board: Board): int =
  var score = 0
  
  var strongSide = NoColor
  var weakSide = NoColor

  let whitePieces = board.occupiedBB[White] xor board.pieceBB[WhiteKing]
  let blackPieces = board.occupiedBB[Black] xor board.pieceBB[BlackKing]
  
  if whitePieces != 0 and blackPieces == 0:
    strongSide = White
    weakSide = Black
  elif blackPieces != 0 and whitePieces == 0:
    strongSide = Black
    weakSide = White
  else:
    return 0
    
  let strongPawns = board.pieceBB[makePiece(strongSide, Pawn)]
  let strongKnights = board.pieceBB[makePiece(strongSide, Knight)]
  let strongBishops = board.pieceBB[makePiece(strongSide, Bishop)]
  let strongRooks = board.pieceBB[makePiece(strongSide, Rook)]
  let strongQueens = board.pieceBB[makePiece(strongSide, Queen)]
  
  if strongRooks != 0 or strongQueens != 0:
    score += TB_WIN
  
  score += countBits(strongPawns) * PawnValueEG
  score += countBits(strongKnights) * KnightValueEG
  score += countBits(strongBishops) * BishopValueEG
  score += countBits(strongRooks) * RookValueEG
  score += countBits(strongQueens) * QueenValueEG
  
  var pbb = strongPawns
  while pbb != 0:
    let sq = popBit(pbb)
    let r = rankOf(sq)
    let promRank = if strongSide == White: r else: 7 - r
    score += 6 * (promRank * promRank)
    
  let weakKingSq = bitScanForward(board.pieceBB[makePiece(weakSide, King)]).Square
  let strongKingSq = bitScanForward(board.pieceBB[makePiece(strongSide, King)]).Square
  
  let kingDistance = DISTANCE[strongKingSq][weakKingSq]
  
  var corners: seq[Square]
  if strongBishops == 0:
    corners = @[Square(0), Square(7), Square(56), Square(63)]
  else:
    var useDark = false
    var useLight = false
    var bbb = strongBishops
    while bbb != 0:
      let sq = popBit(bbb)
      if ((fileOf(sq) + rankOf(sq)) mod 2) == 0:
        useDark = true 
      else:
        useLight = true
        
    if useDark:
      corners.add(Square(0))
      corners.add(Square(63))
    if useLight:
      corners.add(Square(7))
      corners.add(Square(56))
      
  var cornerDistance = 1000
  for c in corners:
    let dist = DISTANCE[weakKingSq][c]
    if dist < cornerDistance:
      cornerDistance = dist
      
  score += 3 * (14 - kingDistance) + 2 * (6 - cornerDistance)
  
  if board.sideToMove == strongSide:
    return score
  else:
    return -score
