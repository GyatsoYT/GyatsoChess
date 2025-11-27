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
  TempoBonus = 15
  
  MobilityBonusKnight = 4
  MobilityBonusBishop = 3
  MobilityBonusRook = 2
  MobilityBonusQueen = 1

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

# Removed evaluateMobility and evaluateKingSafety as they are now inlined


proc evaluate*(board: Board): int =
  var whiteScore = 0
  var blackScore = 0
  
  # 1. King Zones & Pawn Shield (Pre-calculation)
  var whiteKingZone: Bitboard = 0
  var blackKingZone: Bitboard = 0
  
  if board.pieceBB[WhiteKing] != 0:
    let ksq = bitScanForward(board.pieceBB[WhiteKing])
    whiteKingZone = KingAttackZoneMasks[ksq.Square]
    whiteScore += KingValue + KingPST[ksq.Square]
    
    # Pawn Shield
    let shieldMask = KingShieldMasks[White][ksq.Square]
    var shieldPawns = shieldMask and board.pieceBB[WhitePawn]
    while shieldPawns != 0:
      let psq = popBit(shieldPawns)
      var bonus = ShieldPawnBonus
      if rankOf(psq) > rankOf(ksq.Square) + 1: bonus += ShieldPawnAdvancedPenalty
      whiteScore += bonus

  if board.pieceBB[BlackKing] != 0:
    let ksq = bitScanForward(board.pieceBB[BlackKing])
    blackKingZone = KingAttackZoneMasks[ksq.Square]
    blackScore += KingValue + KingPST[mirrorSquare(ksq.Square)]
    
    # Pawn Shield
    let shieldMask = KingShieldMasks[Black][ksq.Square]
    var shieldPawns = shieldMask and board.pieceBB[BlackPawn]
    while shieldPawns != 0:
      let psq = popBit(shieldPawns)
      var bonus = ShieldPawnBonus
      if rankOf(psq) < rankOf(ksq.Square) - 1: bonus += ShieldPawnAdvancedPenalty
      blackScore += bonus

  # Attack Units for King Safety
  var whiteAttackUnits = 0 # Attacks BY White against Black King
  var blackAttackUnits = 0 # Attacks BY Black against White King
  
  let whiteOccupied = board.occupiedBB[White]
  let blackOccupied = board.occupiedBB[Black]
  let allPieces = board.allPiecesBB
  
  # 2. Piece Loop (Material, PST, Mobility, King Safety)
  
  # --- WHITE PIECES ---
  
  # Pawns
  var bb = board.pieceBB[WhitePawn]
  while bb != 0:
    let sq = popBit(bb)
    whiteScore += PawnValue + PawnPST[sq]
    # Pawn structure (doubled/isolated/passed) handled separately or inline?
    # Keeping separate for now to avoid complexity explosion in this loop, 
    # as pawn structure relies on file masks, not attacks.
    
  # Knights
  bb = board.pieceBB[WhiteKnight]
  while bb != 0:
    let sq = popBit(bb)
    whiteScore += KnightValue + KnightPST[sq]
    
    let attacks = knightAttacks[sq]
    # Mobility
    whiteScore += countBits(attacks and not whiteOccupied) * MobilityBonusKnight
    # King Safety (Attacking Black King)
    if (attacks and blackKingZone) != 0:
      whiteAttackUnits += countBits(attacks and blackKingZone) * AttackWeightKnight

  # Bishops
  bb = board.pieceBB[WhiteBishop]
  while bb != 0:
    let sq = popBit(bb)
    whiteScore += BishopValue + BishopPST[sq]
    
    let attacks = getBishopAttacks(sq, allPieces)
    whiteScore += countBits(attacks and not whiteOccupied) * MobilityBonusBishop
    if (attacks and blackKingZone) != 0:
      whiteAttackUnits += countBits(attacks and blackKingZone) * AttackWeightBishop

  # Rooks
  bb = board.pieceBB[WhiteRook]
  while bb != 0:
    let sq = popBit(bb)
    whiteScore += RookValue + RookPST[sq]
    
    let attacks = getRookAttacks(sq, allPieces)
    whiteScore += countBits(attacks and not whiteOccupied) * MobilityBonusRook
    if (attacks and blackKingZone) != 0:
      whiteAttackUnits += countBits(attacks and blackKingZone) * AttackWeightRook

  # Queens
  bb = board.pieceBB[WhiteQueen]
  while bb != 0:
    let sq = popBit(bb)
    whiteScore += QueenValue + QueenPST[sq]
    
    let attacks = getQueenAttacks(sq, allPieces)
    whiteScore += countBits(attacks and not whiteOccupied) * MobilityBonusQueen
    if (attacks and blackKingZone) != 0:
      whiteAttackUnits += countBits(attacks and blackKingZone) * AttackWeightQueen

  # --- BLACK PIECES ---
  
  # Pawns
  bb = board.pieceBB[BlackPawn]
  while bb != 0:
    let sq = popBit(bb)
    blackScore += PawnValue + PawnPST[mirrorSquare(sq)]
    
  # Knights
  bb = board.pieceBB[BlackKnight]
  while bb != 0:
    let sq = popBit(bb)
    blackScore += KnightValue + KnightPST[mirrorSquare(sq)]
    
    let attacks = knightAttacks[sq]
    blackScore += countBits(attacks and not blackOccupied) * MobilityBonusKnight
    if (attacks and whiteKingZone) != 0:
      blackAttackUnits += countBits(attacks and whiteKingZone) * AttackWeightKnight

  # Bishops
  bb = board.pieceBB[BlackBishop]
  while bb != 0:
    let sq = popBit(bb)
    blackScore += BishopValue + BishopPST[mirrorSquare(sq)]
    
    let attacks = getBishopAttacks(sq, allPieces)
    blackScore += countBits(attacks and not blackOccupied) * MobilityBonusBishop
    if (attacks and whiteKingZone) != 0:
      blackAttackUnits += countBits(attacks and whiteKingZone) * AttackWeightBishop

  # Rooks
  bb = board.pieceBB[BlackRook]
  while bb != 0:
    let sq = popBit(bb)
    blackScore += RookValue + RookPST[mirrorSquare(sq)]
    
    let attacks = getRookAttacks(sq, allPieces)
    blackScore += countBits(attacks and not blackOccupied) * MobilityBonusRook
    if (attacks and whiteKingZone) != 0:
      blackAttackUnits += countBits(attacks and whiteKingZone) * AttackWeightRook

  # Queens
  bb = board.pieceBB[BlackQueen]
  while bb != 0:
    let sq = popBit(bb)
    blackScore += QueenValue + QueenPST[mirrorSquare(sq)]
    
    let attacks = getQueenAttacks(sq, allPieces)
    blackScore += countBits(attacks and not blackOccupied) * MobilityBonusQueen
    if (attacks and whiteKingZone) != 0:
      blackAttackUnits += countBits(attacks and whiteKingZone) * AttackWeightQueen

  # 3. Apply King Safety Penalties
  if blackAttackUnits > 100: blackAttackUnits = 100
  whiteScore -= SafetyTable[blackAttackUnits] # White penalized by Black attacks
  
  if whiteAttackUnits > 100: whiteAttackUnits = 100
  blackScore -= SafetyTable[whiteAttackUnits] # Black penalized by White attacks

  # 4. Pawn Structure (Still separate for now, but could be integrated)
  evaluatePawnStructure(board, whiteScore, blackScore)
    
  # Return score from perspective of side to move
  if board.sideToMove == White:
    return (whiteScore - blackScore) + TempoBonus
  else:
    return (blackScore - whiteScore) + TempoBonus

