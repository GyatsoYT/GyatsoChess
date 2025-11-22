import coretypes, bitboard, board, lookups, magicbitboards, utils

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
  
  # Evaluation Constants
  DoubledPawnPenalty = -10
  IsolatedPawnPenalty = -10
  PassedPawnBonus: array[0..7, int] = [0, 5, 10, 20, 35, 60, 100, 0] # Bonus by rank
  
  MobilityBonusKnight = 4
  MobilityBonusBishop = 3
  MobilityBonusRook = 2
  MobilityBonusQueen = 1

# Helper to mirror square for Black (flip rank)
# Square 0 (a1) -> 56 (a8)
# Square 7 (h1) -> 63 (h8)
# Formula: sq xor 56
func mirrorSquare(sq: Square): Square {.inline.} =
  (sq.int xor 56).Square

proc evaluatePawnStructure(board: Board, whiteScore, blackScore: var int) =
  # White Pawns
  var bb = board.pieceBB[WhitePawn]
  while bb != 0:
    let sq = popBit(bb)
    let f = fileOf(sq)
    let r = rankOf(sq)
    
    # Doubled Pawns
    if (FileMasks[f] and board.pieceBB[WhitePawn] and not (1'u64 shl sq)) != 0:
      whiteScore += DoubledPawnPenalty
      
    # Isolated Pawns
    if (IsolatedPawnMasks[f] and board.pieceBB[WhitePawn]) == 0:
      whiteScore += IsolatedPawnPenalty
      
    # Passed Pawns
    if (PassedPawnMasks[White][sq] and board.pieceBB[BlackPawn]) == 0:
      whiteScore += PassedPawnBonus[r]
      
  # Black Pawns
  bb = board.pieceBB[BlackPawn]
  while bb != 0:
    let sq = popBit(bb)
    let f = fileOf(sq)
    let r = rankOf(sq) # 0-7, but for black passed pawn bonus we want relative rank
    let relativeRank = 7 - r
    
    # Doubled Pawns
    if (FileMasks[f] and board.pieceBB[BlackPawn] and not (1'u64 shl sq)) != 0:
      blackScore += DoubledPawnPenalty
      
    # Isolated Pawns
    if (IsolatedPawnMasks[f] and board.pieceBB[BlackPawn]) == 0:
      blackScore += IsolatedPawnPenalty
      
    # Passed Pawns
    if (PassedPawnMasks[Black][sq] and board.pieceBB[WhitePawn]) == 0:
      blackScore += PassedPawnBonus[relativeRank]

proc evaluateMobility(board: Board, whiteScore, blackScore: var int) =
  let whiteOccupied = board.occupiedBB[White]
  let blackOccupied = board.occupiedBB[Black]
  let allPieces = board.allPiecesBB
  
  # White Mobility
  # Knights
  var bb = board.pieceBB[WhiteKnight]
  while bb != 0:
    let sq = popBit(bb)
    let attacks = knightAttacks[sq] and not whiteOccupied
    whiteScore += countBits(attacks) * MobilityBonusKnight
    
  # Bishops
  bb = board.pieceBB[WhiteBishop]
  while bb != 0:
    let sq = popBit(bb)
    let attacks = getBishopAttacks(sq, allPieces) and not whiteOccupied
    whiteScore += countBits(attacks) * MobilityBonusBishop
    
  # Rooks
  bb = board.pieceBB[WhiteRook]
  while bb != 0:
    let sq = popBit(bb)
    let attacks = getRookAttacks(sq, allPieces) and not whiteOccupied
    whiteScore += countBits(attacks) * MobilityBonusRook
    
  # Queens
  bb = board.pieceBB[WhiteQueen]
  while bb != 0:
    let sq = popBit(bb)
    let attacks = getQueenAttacks(sq, allPieces) and not whiteOccupied
    whiteScore += countBits(attacks) * MobilityBonusQueen
    
  # Black Mobility
  # Knights
  bb = board.pieceBB[BlackKnight]
  while bb != 0:
    let sq = popBit(bb)
    let attacks = knightAttacks[sq] and not blackOccupied
    blackScore += countBits(attacks) * MobilityBonusKnight
    
  # Bishops
  bb = board.pieceBB[BlackBishop]
  while bb != 0:
    let sq = popBit(bb)
    let attacks = getBishopAttacks(sq, allPieces) and not blackOccupied
    blackScore += countBits(attacks) * MobilityBonusBishop
    
  # Rooks
  bb = board.pieceBB[BlackRook]
  while bb != 0:
    let sq = popBit(bb)
    let attacks = getRookAttacks(sq, allPieces) and not blackOccupied
    blackScore += countBits(attacks) * MobilityBonusRook
    
  # Queens
  bb = board.pieceBB[BlackQueen]
  while bb != 0:
    let sq = popBit(bb)
    let attacks = getQueenAttacks(sq, allPieces) and not blackOccupied
    blackScore += countBits(attacks) * MobilityBonusQueen

const
  # King Safety Constants
  ShieldPawnBonus = 15
  ShieldPawnAdvancedPenalty = -10 # Penalty for pawn being far (Rank+2 instead of Rank+1)
  
  AttackWeightQueen = 4
  AttackWeightRook = 3
  AttackWeightBishop = 2
  AttackWeightKnight = 2
  
  # Safety Table (Non-linear penalty based on attack units)
  # Index is attack units (0..99). Value is penalty in cp.
  # Formula approx: (units^2) / 1.5
  SafetyTable: array[0..100, int] = [
    0, 0, 1, 2, 3, 5, 7, 9, 12, 15,
    18, 22, 26, 30, 35, 40, 45, 50, 56, 62,
    68, 75, 82, 89, 97, 105, 113, 122, 131, 140,
    150, 160, 170, 181, 192, 204, 216, 228, 241, 254,
    267, 281, 295, 309, 324, 339, 355, 371, 387, 404,
    421, 439, 457, 475, 494, 513, 533, 553, 574, 595,
    617, 639, 661, 684, 708, 732, 757, 782, 808, 834,
    861, 888, 916, 944, 973, 1002, 1032, 1062, 1093, 1124,
    1156, 1188, 1221, 1254, 1288, 1322, 1357, 1392, 1428, 1464,
    1501, 1538, 1576, 1614, 1653, 1692, 1732, 1772, 1813, 1854, 1896
  ]

proc evaluateKingSafety(board: Board, whiteScore, blackScore: var int) =
  var whiteKingBB = board.pieceBB[WhiteKing]
  var blackKingBB = board.pieceBB[BlackKing]
  
  if whiteKingBB != 0:
    let ksq = popBit(whiteKingBB)
    
    # Pawn Shield
    # Check pawns in shield zone
    let shieldMask = KingShieldMasks[White][ksq]
    var shieldPawns = shieldMask and board.pieceBB[WhitePawn]
    while shieldPawns != 0:
      let psq = popBit(shieldPawns)
      var bonus = ShieldPawnBonus
      # If pawn is on Rank+2 (relative to king), apply penalty
      if rankOf(psq) > rankOf(ksq) + 1:
        bonus += ShieldPawnAdvancedPenalty
      whiteScore += bonus
      
    # King Attack Zone
    let attackZone = KingAttackZoneMasks[ksq]
    var attackUnits = 0
    
    # Enemy pieces attacking the zone
    # Knights
    var bb = board.pieceBB[BlackKnight]
    while bb != 0:
      let sq = popBit(bb)
      let attacks = knightAttacks[sq] and attackZone
      attackUnits += countBits(attacks) * AttackWeightKnight
      
    # Bishops
    bb = board.pieceBB[BlackBishop]
    while bb != 0:
      let sq = popBit(bb)
      let attacks = getBishopAttacks(sq, board.allPiecesBB) and attackZone
      attackUnits += countBits(attacks) * AttackWeightBishop
      
    # Rooks
    bb = board.pieceBB[BlackRook]
    while bb != 0:
      let sq = popBit(bb)
      let attacks = getRookAttacks(sq, board.allPiecesBB) and attackZone
      attackUnits += countBits(attacks) * AttackWeightRook
      
    # Queens
    bb = board.pieceBB[BlackQueen]
    while bb != 0:
      let sq = popBit(bb)
      let attacks = getQueenAttacks(sq, board.allPiecesBB) and attackZone
      attackUnits += countBits(attacks) * AttackWeightQueen
      
    if attackUnits > 100: attackUnits = 100
    whiteScore -= SafetyTable[attackUnits]

  if blackKingBB != 0:
    let ksq = popBit(blackKingBB)
    
    # Pawn Shield
    let shieldMask = KingShieldMasks[Black][ksq]
    var shieldPawns = shieldMask and board.pieceBB[BlackPawn]
    while shieldPawns != 0:
      let psq = popBit(shieldPawns)
      var bonus = ShieldPawnBonus
      # If pawn is on Rank-2 (relative to king), apply penalty
      if rankOf(psq) < rankOf(ksq) - 1:
        bonus += ShieldPawnAdvancedPenalty
      blackScore += bonus
      
    # King Attack Zone
    let attackZone = KingAttackZoneMasks[ksq]
    var attackUnits = 0
    
    # Enemy pieces attacking the zone
    # Knights
    var bb = board.pieceBB[WhiteKnight]
    while bb != 0:
      let sq = popBit(bb)
      let attacks = knightAttacks[sq] and attackZone
      attackUnits += countBits(attacks) * AttackWeightKnight
      
    # Bishops
    bb = board.pieceBB[WhiteBishop]
    while bb != 0:
      let sq = popBit(bb)
      let attacks = getBishopAttacks(sq, board.allPiecesBB) and attackZone
      attackUnits += countBits(attacks) * AttackWeightBishop
      
    # Rooks
    bb = board.pieceBB[WhiteRook]
    while bb != 0:
      let sq = popBit(bb)
      let attacks = getRookAttacks(sq, board.allPiecesBB) and attackZone
      attackUnits += countBits(attacks) * AttackWeightRook
      
    # Queens
    bb = board.pieceBB[WhiteQueen]
    while bb != 0:
      let sq = popBit(bb)
      let attacks = getQueenAttacks(sq, board.allPiecesBB) and attackZone
      attackUnits += countBits(attacks) * AttackWeightQueen
      
    if attackUnits > 100: attackUnits = 100
    blackScore -= SafetyTable[attackUnits]

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
    
  # Pawn Structure
  evaluatePawnStructure(board, whiteScore, blackScore)
  
  # Mobility
  evaluateMobility(board, whiteScore, blackScore)
  
  # King Safety
  evaluateKingSafety(board, whiteScore, blackScore)
    
  # Return score from perspective of side to move
  if board.sideToMove == White:
    return whiteScore - blackScore
  else:
    return blackScore - whiteScore
