import coretypes, bitboard, board, lookups, magicbitboards, utils, endgame

const
  # Phase Constants
  PhaseTotal = 24
  PhaseKnight = 1
  PhaseBishop = 1
  PhaseRook = 2
  PhaseQueen = 4

  # Piece-Square Tables (Middlegame and Endgame)
  
  # Pawns
  PawnPST_MG: array[Square, int] = [
       0,   0,   0,   0,   0,   0,   0,   0,
     -24, -24, -21, -17, -16,   7,  10, -22,
     -21, -20,  -9,  -2,   8,  -0,   4, -14,
     -19, -13,   1,  11,  19,  17,   3, -14,
      -5,   6,  15,  37,  48,  44,  18,  -2,
       6,  38,  69,  69,  82, 115,  47,  17,
      51,  56,  38,  24,  17,  36,  15,   4,
       0,   0,   0,   0,   0,   0,   0,   0,
  ]

  PawnPST_EG: array[Square, int] = [
       0,   0,   0,   0,   0,   0,   0,   0,
      41,  35,  41,  37,  42,  43,  25,  18,
      35,  31,  27,  22,  29,  31,  21,  20,
      43,  40,  23,  16,  15,  21,  26,  26,
      61,  52,  36,  10,  14,  20,  38,  38,
      90,  76,  45,  10,   1,  26,  51,  59,
      64,  53,  35,   9,   2,   4,  33,  35,
       0,   0,   0,   0,   0,   0,   0,   0,
  ]

  KnightPST_MG: array[Square, int] = [
     -65, -44, -40, -37, -30, -30, -41, -68,
     -40, -42, -24,  -7, -13, -14, -30, -25,
     -45, -17,  -6,   8,  12,   3,  -8, -30,
     -21,   3,  14,  16,  27,  14,  25,  -9,
     -10,  11,  33,  45,  23,  49,  10,   7,
     -29,  12,  40,  58,  76,  70,  37, -20,
     -65, -33,  48,  18,  39,  45, -21, -34,
    -127, -43, -37, -31, -26, -58, -43, -75,
  ]

  KnightPST_EG: array[Square, int] = [
     -57, -56, -32, -22, -25, -29, -45, -54,
     -36, -22, -20, -11,  -8, -22, -25, -38,
     -37, -10,   1,  18,  15,  -3, -13, -37,
     -17,   8,  31,  39,  36,  31,  10,  -8,
     -15,  15,  33,  44,  51,  33,  28, -11,
     -28,   1,  26,  22,  12,  24,   0, -20,
     -38, -16, -15,  14,   2, -10, -24, -41,
     -85, -45, -25, -23, -21, -40, -40, -76,
  ]

  BishopPST_MG: array[Square, int] = [
       7,  -9, -13, -15, -19, -10, -11,   1,
      -1,  10,   6,  -6,   0,   4,  21,   4,
      -9,   8,   4,   4,   1,   6,   8,   7,
     -10,   0,   3,  21,  23,  -7,   3,  -8,
     -21,  13,   9,  40,  28,   7,  11,  -7,
      -8,  10,  43,  13,  36,  31,  29,  15,
     -45,  -8, -20, -10,  -6,  26, -12,  -7,
     -22, -23, -17, -27, -23, -25,  -9, -25,
  ]

  BishopPST_EG: array[Square, int] = [
     -23, -10, -27, -13,  -9, -13, -15, -24,
      -5, -27, -14,  -8,  -8, -15, -19, -22,
     -12,   2,   3,   8,  10,  -1,  -6,  -8,
      -2,   3,  17,   7,   4,  15,   2,  -2,
      10,  19,   9,  11,  14,  13,  17,   6,
      12,  16,   2,  10,   6,  18,  15,   2,
      -6,   7,  11,   0,   4,   1,   4, -18,
      -8, -10,  -6,  -1,  -2,  -8,  -5, -10,
  ]

  RookPST_MG: array[Square, int] = [
     -14,  -5,   3,  12,   9,   9,  10,  -4,
     -53, -22, -17,  -8,  -8,  -1,  -2, -48,
     -36, -16, -17, -10, -12, -14,   6, -16,
     -28, -17, -20,  -8, -10, -12,   3, -12,
     -10,   3,  16,  34,  22,  22,  16,  19,
       5,  26,  19,  36,  42,  33,  29,  16,
      10,  -4,  25,  33,  24,  26,  20,  17,
      18,  17,  11,  16,  16,  15,  14,  14,
  ]

  RookPST_EG: array[Square, int] = [
     -15, -13, -13, -22, -22, -10, -17, -31,
     -19, -21, -14, -24, -26, -28, -21, -17,
     -16,  -8, -14, -18, -17, -18, -15, -23,
       3,  10,  12,   3,   0,   3,   1,  -5,
      17,  14,  13,   8,   9,  11,  10,   7,
      18,  12,  18,   9,   8,  18,  13,  15,
      23,  30,  23,  25,  27,  21,  20,  21,
      29,  28,  27,  21,  23,  30,  35,  37,
  ]

  QueenPST_MG: array[Square, int] = [
      -1,   5,  18,  27,  18,   4,   3,  -7,
      -0,   9,  21,  20,  23,  24,  14,  -6,
      -2,  13,  12,   6,  11,  12,  17,   6,
      -1,   9,   2,  -0,   8,  14,  18,  16,
      -7,   2,  -5, -11,   5,   4,  27,  13,
     -11,  -6,   1,   2,  20,  16,  29, -15,
     -18, -56, -21, -15, -31,  22, -13,  17,
      -9,  -4,  -2,   3,   4,   4,  -5,   5,
  ]

  QueenPST_EG: array[Square, int] = [
     -15, -23, -34, -43, -24, -23, -17, -21,
     -10, -12, -35, -19, -27, -36, -25, -10,
     -14,  -9,   7,   1,   6,   9,   8,  -6,
       8,  12,  14,  38,  25,  22,  17,  14,
       0,  20,  10,  39,  35,  35,  33,  17,
     -10,   0,  12,  16,  32,  20,  18,   5,
       2,  17,  10,  16,  16,  34,  13,  -3,
     -10,   2,   5,  10,   8,  12,  -4,   4,
  ]

  KingPST_MG: array[Square, int] = [
     -39, -11, -45, -85, -60,-102, -15,  -3,
     -12, -27, -45,-108, -83, -73, -18, -10,
     -32, -28, -44, -62, -56, -39, -29, -54,
     -31, -29, -30, -49, -46, -42, -31, -49,
     -20, -21, -22, -36, -37, -26, -19, -26,
      -9,  -5, -14, -16, -20, -11,  -6,  -9,
      18,  28,   4,   2,   2,   7,  26,  18,
      20,  30,  10,   1,   2,  12,  30,  19,
  ]

  KingPST_EG: array[Square, int] = [
     -75, -58, -37, -37, -69, -30, -61,-127,
     -33, -16,  -2,  14,   7,   3, -25, -53,
     -39,  -7,  13,  29,  27,  11, -11, -29,
     -45,   5,  30,  43,  41,  30,  12, -27,
     -33,  15,  32,  37,  37,  37,  27, -12,
     -31,  19,  22,  13,  17,  38,  40,  -7,
     -41,  -8,  -3,  -6,  -4,  16,  10, -25,
     -63, -37, -38, -31, -31, -26, -32, -57,
  ]
  
  PawnPST_MG_Black: array[Square, int] = block:
    var arr: array[Square, int]
    for sq in 0..63:
      arr[sq] = PawnPST_MG[(sq xor 56)]
    arr
  
  PawnPST_EG_Black: array[Square, int] = block:
    var arr: array[Square, int]
    for sq in 0..63:
      arr[sq] = PawnPST_EG[(sq xor 56)]
    arr
  
  KnightPST_MG_Black: array[Square, int] = block:
    var arr: array[Square, int]
    for sq in 0..63:
      arr[sq] = KnightPST_MG[(sq xor 56)]
    arr
  
  KnightPST_EG_Black: array[Square, int] = block:
    var arr: array[Square, int]
    for sq in 0..63:
      arr[sq] = KnightPST_EG[(sq xor 56)]
    arr
  
  BishopPST_MG_Black: array[Square, int] = block:
    var arr: array[Square, int]
    for sq in 0..63:
      arr[sq] = BishopPST_MG[(sq xor 56)]
    arr
  
  BishopPST_EG_Black: array[Square, int] = block:
    var arr: array[Square, int]
    for sq in 0..63:
      arr[sq] = BishopPST_EG[(sq xor 56)]
    arr
  
  RookPST_MG_Black: array[Square, int] = block:
    var arr: array[Square, int]
    for sq in 0..63:
      arr[sq] = RookPST_MG[(sq xor 56)]
    arr
  
  RookPST_EG_Black: array[Square, int] = block:
    var arr: array[Square, int]
    for sq in 0..63:
      arr[sq] = RookPST_EG[(sq xor 56)]
    arr
  
  QueenPST_MG_Black: array[Square, int] = block:
    var arr: array[Square, int]
    for sq in 0..63:
      arr[sq] = QueenPST_MG[(sq xor 56)]
    arr
  
  QueenPST_EG_Black: array[Square, int] = block:
    var arr: array[Square, int]
    for sq in 0..63:
      arr[sq] = QueenPST_EG[(sq xor 56)]
    arr
  
  KingPST_MG_Black: array[Square, int] = block:
    var arr: array[Square, int]
    for sq in 0..63:
      arr[sq] = KingPST_MG[(sq xor 56)]
    arr
  
  KingPST_EG_Black: array[Square, int] = block:
    var arr: array[Square, int]
    for sq in 0..63:
      arr[sq] = KingPST_EG[(sq xor 56)]
    arr

  
  # Evaluation Constants
  DoubledPawnPenalty = -9
  IsolatedPawnPenalty = -16
  PassedPawnBonus: array[0..7, int] = [0, 15, 15, 43, 75, 143, 246, 0]

  BishopPairBonus = 42
  RookOnOpenFileBonus = 25
  RookOnSemiOpenFileBonus = 14

  MobilityBonusKnight = 0
  MobilityBonusBishop = 5
  MobilityBonusRook = 3
  MobilityBonusQueen = 2

  ShieldPawnBonus = 20
  ShieldPawnAdvancedPenalty = -2
  AttackWeightQueen = 4
  AttackWeightRook = 3
  AttackWeightBishop = 2
  AttackWeightKnight = 2

  TempoBonus = 12

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
  
  # --- Mop-up Evaluation Check ---
  # Check if one side has only a King and the other has pieces (excluding pawns initially)
  
  let whiteNonPawnMat = (board.occupiedBB[White] xor board.pieceBB[WhiteKing] xor board.pieceBB[WhitePawn]) != 0
  let blackNonPawnMat = (board.occupiedBB[Black] xor board.pieceBB[BlackKing] xor board.pieceBB[BlackPawn]) != 0
  
  let whiteWraps = (board.occupiedBB[White] xor board.pieceBB[WhiteKing]) == 0 # White has ONLY King
  let blackWraps = (board.occupiedBB[Black] xor board.pieceBB[BlackKing]) == 0 # Black has ONLY King

  # If White has pieces and Black is lone king
  if whiteNonPawnMat and blackWraps:
    return mopUpEvaluation(board)
    
  # If Black has pieces and White is lone king
  if blackNonPawnMat and whiteWraps:
    return mopUpEvaluation(board)
  # -------------------------------
  
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
    mgBlack += KingValue + KingPST_MG_Black[ksq.Square]
    egBlack += KingValue + KingPST_EG_Black[ksq.Square]
    
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
    mgWhite += PawnValueMG + PawnPST_MG[sq]
    egWhite += PawnValueEG + PawnPST_EG[sq]
    
  # Knights
  bb = board.pieceBB[WhiteKnight]
  while bb != 0:
    let sq = popBit(bb)
    mgWhite += KnightValueMG + KnightPST_MG[sq]
    egWhite += KnightValueEG + KnightPST_EG[sq]
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
    mgWhite += BishopValueMG + BishopPST_MG[sq]
    egWhite += BishopValueEG + BishopPST_EG[sq]
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
    mgWhite += RookValueMG + RookPST_MG[sq]
    egWhite += RookValueEG + RookPST_EG[sq]
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
    mgWhite += QueenValueMG + QueenPST_MG[sq]
    egWhite += QueenValueEG + QueenPST_EG[sq]
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
    mgBlack += PawnValueMG + PawnPST_MG_Black[sq]
    egBlack += PawnValueEG + PawnPST_EG_Black[sq]
    
  # Knights
  bb = board.pieceBB[BlackKnight]
  while bb != 0:
    let sq = popBit(bb)
    mgBlack += KnightValueMG + KnightPST_MG_Black[sq]
    egBlack += KnightValueEG + KnightPST_EG_Black[sq]
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
    mgBlack += BishopValueMG + BishopPST_MG_Black[sq]
    egBlack += BishopValueEG + BishopPST_EG_Black[sq]
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
    mgBlack += RookValueMG + RookPST_MG_Black[sq]
    egBlack += RookValueEG + RookPST_EG_Black[sq]
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
    mgBlack += QueenValueMG + QueenPST_MG_Black[sq]
    egBlack += QueenValueEG + QueenPST_EG_Black[sq]
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
  var finalScore = 0
  if board.sideToMove == White:
    finalScore = (whiteScore - blackScore) + TempoBonus
  else:
    finalScore = (blackScore - whiteScore) + TempoBonus
    
  const MaxEval = MateValue - MaxPly - 100
  
  if finalScore > MaxEval: finalScore = MaxEval
  elif finalScore < -MaxEval: finalScore = -MaxEval
  
  return finalScore

