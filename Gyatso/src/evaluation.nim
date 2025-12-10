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
  
  # Phase Constants
  PhaseTotal = 24
  PhaseKnight = 1
  PhaseBishop = 1
  PhaseRook = 2
  PhaseQueen = 4

  # Piece-Square Tables (Middlegame and Endgame)
  
  # Pawns
  PawnPST_MG: array[Square, int] = [
      0,  0,  0,  0,  0,  0,  0,  0,
     50, 50, 50, 50, 50, 50, 50, 50,
     10, 10, 20, 30, 30, 20, 10, 10,
      5,  5, 10, 25, 25, 10,  5,  5,
      0,  0,  0, 20, 20,  0,  0,  0,
      5, -5,-10,  0,  0,-10, -5,  5,
      5, 10, 10,-20,-20, 10, 10,  5,
      0,  0,  0,  0,  0,  0,  0,  0
  ]
  
  PawnPST_EG: array[Square, int] = [
      0,  0,  0,  0,  0,  0,  0,  0,
     80, 80, 80, 80, 80, 80, 80, 80,
     50, 50, 50, 50, 50, 50, 50, 50,
     30, 30, 30, 30, 30, 30, 30, 30,
     20, 20, 20, 20, 20, 20, 20, 20,
     10, 10, 10, 10, 10, 10, 10, 10,
     10, 10, 10, 10, 10, 10, 10, 10,
      0,  0,  0,  0,  0,  0,  0,  0
  ]

  # Knights (Mainly centralized)
  KnightPST_MG: array[Square, int] = [
    -50,-40,-30,-30,-30,-30,-40,-50,
    -40,-20,  0,  0,  0,  0,-20,-40,
    -30,  0, 10, 15, 15, 10,  0,-30,
    -30,  5, 15, 20, 20, 15,  5,-30,
    -30,  0, 15, 20, 20, 15,  0,-30,
    -30,  5, 10, 15, 15, 10,  5,-30,
    -40,-20,  0,  5,  5,  0,-20,-40,
    -50,-40,-30,-30,-30,-30,-40,-50
  ]
  
  KnightPST_EG: array[Square, int] = [
    -50,-40,-30,-30,-30,-30,-40,-50,
    -40,-20,  0,  0,  0,  0,-20,-40,
    -30,  0, 10, 15, 15, 10,  0,-30,
    -30,  5, 15, 20, 20, 15,  5,-30,
    -30,  0, 15, 20, 20, 15,  0,-30,
    -30,  5, 10, 15, 15, 10,  5,-30,
    -40,-20,  0,  5,  5,  0,-20,-40,
    -50,-40,-30,-30,-30,-30,-40,-50
  ]

  # Bishops
  BishopPST_MG: array[Square, int] = [
    -20,-10,-10,-10,-10,-10,-10,-20,
    -10,  0,  0,  0,  0,  0,  0,-10,
    -10,  0,  5, 10, 10,  5,  0,-10,
    -10,  5,  5, 10, 10,  5,  5,-10,
    -10,  0, 10, 10, 10, 10,  0,-10,
    -10, 10, 10, 10, 10, 10, 10,-10,
    -10,  5,  0,  0,  0,  0,  5,-10,
    -20,-10,-10,-10,-10,-10,-10,-20
  ]
  
  BishopPST_EG: array[Square, int] = [
    -20,-10,-10,-10,-10,-10,-10,-20,
    -10,  0,  0,  0,  0,  0,  0,-10,
    -10,  0,  5, 10, 10,  5,  0,-10,
    -10,  5,  5, 10, 10,  5,  5,-10,
    -10,  0, 10, 10, 10, 10,  0,-10,
    -10, 10, 10, 10, 10, 10, 10,-10,
    -10,  5,  0,  0,  0,  0,  5,-10,
    -20,-10,-10,-10,-10,-10,-10,-20
  ]

  # Rooks
  RookPST_MG: array[Square, int] = [
      0,  0,  0,  0,  0,  0,  0,  0,
      5, 10, 10, 10, 10, 10, 10,  5,
     -5,  0,  0,  0,  0,  0,  0, -5,
     -5,  0,  0,  0,  0,  0,  0, -5,
     -5,  0,  0,  0,  0,  0,  0, -5,
     -5,  0,  0,  0,  0,  0,  0, -5,
     -5,  0,  0,  0,  0,  0,  0, -5,
      0,  0,  0,  5,  5,  0,  0,  0
  ]
  
  RookPST_EG: array[Square, int] = [
      0,  0,  0,  0,  0,  0,  0,  0,
      5, 10, 10, 10, 10, 10, 10,  5,
     -5,  0,  0,  0,  0,  0,  0, -5,
     -5,  0,  0,  0,  0,  0,  0, -5,
     -5,  0,  0,  0,  0,  0,  0, -5,
     -5,  0,  0,  0,  0,  0,  0, -5,
     -5,  0,  0,  0,  0,  0,  0, -5,
      0,  0,  0,  5,  5,  0,  0,  0
  ]

  # Queens
  QueenPST_MG: array[Square, int] = [
    -20,-10,-10, -5, -5,-10,-10,-20,
    -10,  0,  0,  0,  0,  0,  0,-10,
    -10,  0,  5,  5,  5,  5,  0,-10,
     -5,  0,  5,  5,  5,  5,  0, -5,
      0,  0,  5,  5,  5,  5,  0, -5,
    -10,  5,  5,  5,  5,  5,  0,-10,
    -10,  0,  5,  0,  0,  0,  0,-10,
    -20,-10,-10, -5, -5,-10,-10,-20
  ]
  
  QueenPST_EG: array[Square, int] = [
    -20,-10,-10, -5, -5,-10,-10,-20,
    -10,  0,  0,  0,  0,  0,  0,-10,
    -10,  0,  5,  5,  5,  5,  0,-10,
     -5,  0,  5,  5,  5,  5,  0, -5,
      0,  0,  5,  5,  5,  5,  0, -5,
    -10,  5,  5,  5,  5,  5,  0,-10,
    -10,  0,  5,  0,  0,  0,  0,-10,
    -20,-10,-10, -5, -5,-10,-10,-20
  ]

  # King
  KingPST_MG: array[Square, int] = [
    -30,-40,-40,-50,-50,-40,-40,-30,
    -30,-40,-40,-50,-50,-40,-40,-30,
    -30,-40,-40,-50,-50,-40,-40,-30,
    -30,-40,-40,-50,-50,-40,-40,-30,
    -20,-30,-30,-40,-40,-30,-30,-20,
    -10,-20,-20,-20,-20,-20,-20,-10,
     20, 20,  0,  0,  0,  0, 20, 20,
     20, 30, 10,  0,  0, 10, 30, 20
  ]
  
  KingPST_EG: array[Square, int] = [
    -50,-40,-30,-20,-20,-30,-40,-50,
    -30,-20,-10,  0,  0,-10,-20,-30,
    -30,-10, 20, 30, 30, 20,-10,-30,
    -30,-10, 30, 40, 40, 30,-10,-30,
    -30,-10, 30, 40, 40, 30,-10,-30,
    -30,-10, 20, 30, 30, 20,-10,-30,
    -30,-30,  0,  0,  0,  0,-30,-30,
    -50,-30,-30,-30,-30,-30,-30,-50
  ]

  
  # Evaluation Constants
  DoubledPawnPenalty = -10
  IsolatedPawnPenalty = -10
  PassedPawnBonus: array[0..7, int] = [0, 5, 10, 20, 35, 60, 100, 0] # Bonus by rank
  TempoBonus = 15
  
  BishopPairBonus = 40
  RookOnOpenFileBonus = 25
  RookOnSemiOpenFileBonus = 12
  
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

proc evaluatePawnStructure(board: Board, mgWhite, egWhite, mgBlack, egBlack: var int) =
  # White Pawns
  var bb = board.pieceBB[WhitePawn]
  while bb != 0:
    let sq = popBit(bb)
    let f = fileOf(sq)
    let r = rankOf(sq)
    
    # Doubled Pawns
    if (FileMasks[f] and board.pieceBB[WhitePawn] and not (1'u64 shl sq)) != 0:
      mgWhite += DoubledPawnPenalty
      egWhite += DoubledPawnPenalty
      
    # Isolated Pawns
    if (IsolatedPawnMasks[f] and board.pieceBB[WhitePawn]) == 0:
      mgWhite += IsolatedPawnPenalty
      egWhite += IsolatedPawnPenalty
      
    # Passed Pawns (Endgame Bonus)
    if (PassedPawnMasks[White][sq] and board.pieceBB[BlackPawn]) == 0:
      egWhite += PassedPawnBonus[r]
      
  # Black Pawns
  bb = board.pieceBB[BlackPawn]
  while bb != 0:
    let sq = popBit(bb)
    let f = fileOf(sq)
    let r = rankOf(sq) 
    let relativeRank = 7 - r
    
    # Doubled Pawns
    if (FileMasks[f] and board.pieceBB[BlackPawn] and not (1'u64 shl sq)) != 0:
      mgBlack += DoubledPawnPenalty
      egBlack += DoubledPawnPenalty
      
    # Isolated Pawns
    if (IsolatedPawnMasks[f] and board.pieceBB[BlackPawn]) == 0:
      mgBlack += IsolatedPawnPenalty
      egBlack += IsolatedPawnPenalty
      
    # Passed Pawns (Endgame Bonus)
    if (PassedPawnMasks[Black][sq] and board.pieceBB[WhitePawn]) == 0:
      egBlack += PassedPawnBonus[relativeRank]



proc evaluate*(board: Board): int =
  var mgWhite = 0
  var egWhite = 0
  var mgBlack = 0
  var egBlack = 0
  var gamePhase = 0
  
  # 1. King Zones & Pawn Shield (Pre-calculation for Safety)
  var whiteKingZone: Bitboard = 0
  var blackKingZone: Bitboard = 0
  
  if board.pieceBB[WhiteKing] != 0:
    let ksq = bitScanForward(board.pieceBB[WhiteKing])
    whiteKingZone = KingAttackZoneMasks[ksq.Square]
    mgWhite += KingValue + KingPST_MG[ksq.Square]
    egWhite += KingValue + KingPST_EG[ksq.Square]
    
    # Pawn Shield (MG only)
    let shieldMask = KingShieldMasks[White][ksq.Square]
    var shieldPawns = shieldMask and board.pieceBB[WhitePawn]
    while shieldPawns != 0:
      let psq = popBit(shieldPawns)
      var bonus = ShieldPawnBonus
      if rankOf(psq) > rankOf(ksq.Square) + 1: bonus += ShieldPawnAdvancedPenalty
      mgWhite += bonus

  if board.pieceBB[BlackKing] != 0:
    let ksq = bitScanForward(board.pieceBB[BlackKing])
    blackKingZone = KingAttackZoneMasks[ksq.Square]
    mgBlack += KingValue + KingPST_MG[mirrorSquare(ksq.Square)]
    egBlack += KingValue + KingPST_EG[mirrorSquare(ksq.Square)]
    
    # Pawn Shield (MG only)
    let shieldMask = KingShieldMasks[Black][ksq.Square]
    var shieldPawns = shieldMask and board.pieceBB[BlackPawn]
    while shieldPawns != 0:
      let psq = popBit(shieldPawns)
      var bonus = ShieldPawnBonus
      if rankOf(psq) < rankOf(ksq.Square) - 1: bonus += ShieldPawnAdvancedPenalty
      mgBlack += bonus

  # Attack Units for King Safety
  var whiteAttackUnits = 0 # Attacks BY White against Black King
  var blackAttackUnits = 0 # Attacks BY Black against White King
  
  let whiteOccupied = board.occupiedBB[White]
  let blackOccupied = board.occupiedBB[Black]
  let allPieces = board.allPiecesBB
  
  # 2. Piece Loop (Material, PST, Mobility, King Safety, Phase)
  
  # --- WHITE PIECES ---
  
  # Pawns
  var bb = board.pieceBB[WhitePawn]
  while bb != 0:
    let sq = popBit(bb)
    mgWhite += PawnValue + PawnPST_MG[sq]
    egWhite += PawnValue + PawnPST_EG[sq]
    
  # Knights
  bb = board.pieceBB[WhiteKnight]
  while bb != 0:
    let sq = popBit(bb)
    mgWhite += KnightValue + KnightPST_MG[sq]
    egWhite += KnightValue + KnightPST_EG[sq]
    gamePhase += PhaseKnight
    
    let attacks = knightAttacks[sq]
    # Mobility (Both)
    let mob = countBits(attacks and not whiteOccupied) * MobilityBonusKnight
    mgWhite += mob
    egWhite += mob
    
    # King Safety (Attacking Black King)
    if (attacks and blackKingZone) != 0:
      whiteAttackUnits += countBits(attacks and blackKingZone) * AttackWeightKnight

  # Bishops
  bb = board.pieceBB[WhiteBishop]
  while bb != 0:
    let sq = popBit(bb)
    mgWhite += BishopValue + BishopPST_MG[sq]
    egWhite += BishopValue + BishopPST_EG[sq]
    gamePhase += PhaseBishop
    
    let attacks = getBishopAttacks(sq, allPieces)
    let mob = countBits(attacks and not whiteOccupied) * MobilityBonusBishop
    mgWhite += mob
    egWhite += mob
    
    if (attacks and blackKingZone) != 0:
      whiteAttackUnits += countBits(attacks and blackKingZone) * AttackWeightBishop
      
  if (board.pieceBB[WhiteBishop] and (board.pieceBB[WhiteBishop] - 1)) != 0:
    mgWhite += BishopPairBonus
    egWhite += BishopPairBonus

  # Rooks
  bb = board.pieceBB[WhiteRook]
  while bb != 0:
    let sq = popBit(bb)
    mgWhite += RookValue + RookPST_MG[sq]
    egWhite += RookValue + RookPST_EG[sq]
    gamePhase += PhaseRook
    
    let attacks = getRookAttacks(sq, allPieces)
    let mob = countBits(attacks and not whiteOccupied) * MobilityBonusRook
    mgWhite += mob
    egWhite += mob
    
    if (attacks and blackKingZone) != 0:
      whiteAttackUnits += countBits(attacks and blackKingZone) * AttackWeightRook

    # Rook on Open/Semi-Open File
    let f = fileOf(sq)
    let fileMask = FileMasks[f]
    let whitePawnsOnFile = (board.pieceBB[WhitePawn] and fileMask) != 0
    let blackPawnsOnFile = (board.pieceBB[BlackPawn] and fileMask) != 0
    
    if not whitePawnsOnFile:
      if not blackPawnsOnFile:
        mgWhite += RookOnOpenFileBonus
        egWhite += RookOnOpenFileBonus
      else:
        mgWhite += RookOnSemiOpenFileBonus
        egWhite += RookOnSemiOpenFileBonus

  # Queens
  bb = board.pieceBB[WhiteQueen]
  while bb != 0:
    let sq = popBit(bb)
    mgWhite += QueenValue + QueenPST_MG[sq]
    egWhite += QueenValue + QueenPST_EG[sq]
    gamePhase += PhaseQueen
    
    let attacks = getQueenAttacks(sq, allPieces)
    let mob = countBits(attacks and not whiteOccupied) * MobilityBonusQueen
    mgWhite += mob
    egWhite += mob
    
    if (attacks and blackKingZone) != 0:
      whiteAttackUnits += countBits(attacks and blackKingZone) * AttackWeightQueen

  # --- BLACK PIECES ---
  
  # Pawns
  bb = board.pieceBB[BlackPawn]
  while bb != 0:
    let sq = popBit(bb)
    mgBlack += PawnValue + PawnPST_MG[mirrorSquare(sq)]
    egBlack += PawnValue + PawnPST_EG[mirrorSquare(sq)]
    
  # Knights
  bb = board.pieceBB[BlackKnight]
  while bb != 0:
    let sq = popBit(bb)
    mgBlack += KnightValue + KnightPST_MG[mirrorSquare(sq)]
    egBlack += KnightValue + KnightPST_EG[mirrorSquare(sq)]
    gamePhase += PhaseKnight
    
    let attacks = knightAttacks[sq]
    let mob = countBits(attacks and not blackOccupied) * MobilityBonusKnight
    mgBlack += mob
    egBlack += mob
    
    if (attacks and whiteKingZone) != 0:
      blackAttackUnits += countBits(attacks and whiteKingZone) * AttackWeightKnight

  # Bishops
  bb = board.pieceBB[BlackBishop]
  while bb != 0:
    let sq = popBit(bb)
    mgBlack += BishopValue + BishopPST_MG[mirrorSquare(sq)]
    egBlack += BishopValue + BishopPST_EG[mirrorSquare(sq)]
    gamePhase += PhaseBishop
    
    let attacks = getBishopAttacks(sq, allPieces)
    let mob = countBits(attacks and not blackOccupied) * MobilityBonusBishop
    mgBlack += mob
    egBlack += mob
    
    if (attacks and whiteKingZone) != 0:
      blackAttackUnits += countBits(attacks and whiteKingZone) * AttackWeightBishop

  if (board.pieceBB[BlackBishop] and (board.pieceBB[BlackBishop] - 1)) != 0:
    mgBlack += BishopPairBonus
    egBlack += BishopPairBonus

  # Rooks
  bb = board.pieceBB[BlackRook]
  while bb != 0:
    let sq = popBit(bb)
    mgBlack += RookValue + RookPST_MG[mirrorSquare(sq)]
    egBlack += RookValue + RookPST_EG[mirrorSquare(sq)]
    gamePhase += PhaseRook
    
    let attacks = getRookAttacks(sq, allPieces)
    let mob = countBits(attacks and not blackOccupied) * MobilityBonusRook
    mgBlack += mob
    egBlack += mob
    
    if (attacks and whiteKingZone) != 0:
      blackAttackUnits += countBits(attacks and whiteKingZone) * AttackWeightRook

    # Rook on Open/Semi-Open File
    let f = fileOf(sq)
    let fileMask = FileMasks[f]
    let whitePawnsOnFile = (board.pieceBB[WhitePawn] and fileMask) != 0
    let blackPawnsOnFile = (board.pieceBB[BlackPawn] and fileMask) != 0
    
    if not blackPawnsOnFile:
      if not whitePawnsOnFile:
        mgBlack += RookOnOpenFileBonus
        egBlack += RookOnOpenFileBonus
      else:
        mgBlack += RookOnSemiOpenFileBonus
        egBlack += RookOnSemiOpenFileBonus

  # Queens
  bb = board.pieceBB[BlackQueen]
  while bb != 0:
    let sq = popBit(bb)
    mgBlack += QueenValue + QueenPST_MG[mirrorSquare(sq)]
    egBlack += QueenValue + QueenPST_EG[mirrorSquare(sq)]
    gamePhase += PhaseQueen
    
    let attacks = getQueenAttacks(sq, allPieces)
    let mob = countBits(attacks and not blackOccupied) * MobilityBonusQueen
    mgBlack += mob
    egBlack += mob
    
    if (attacks and whiteKingZone) != 0:
      blackAttackUnits += countBits(attacks and whiteKingZone) * AttackWeightQueen

  # 3. Apply King Safety Penalties (MG Only)
  if blackAttackUnits > 100: blackAttackUnits = 100
  mgWhite -= SafetyTable[blackAttackUnits]
  
  if whiteAttackUnits > 100: whiteAttackUnits = 100
  mgBlack -= SafetyTable[whiteAttackUnits]

  # 4. Pawn Structure
  evaluatePawnStructure(board, mgWhite, egWhite, mgBlack, egBlack)
    
  # 5. Tapered Interpolation
  if gamePhase > PhaseTotal: gamePhase = PhaseTotal
  let mgPhase = gamePhase
  let egPhase = PhaseTotal - mgPhase
  
  let whiteScore = (mgWhite * mgPhase + egWhite * egPhase) div PhaseTotal
  let blackScore = (mgBlack * mgPhase + egBlack * egPhase) div PhaseTotal
  
  # Return score from perspective of side to move
  if board.sideToMove == White:
    return (whiteScore - blackScore) + TempoBonus
  else:
    return (blackScore - whiteScore) + TempoBonus

