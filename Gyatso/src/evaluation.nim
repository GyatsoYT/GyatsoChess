import coretypes, bitboard, board

const
  PhaseTotal* = 24
  PhaseKnight* = 1
  PhaseBishop* = 1
  PhaseRook* = 2
  PhaseQueen* = 4

proc getGamePhase*(board: Board): int =
  var phase = PhaseTotal
  phase -= countBits(board.pieceBB[WhiteKnight]) * PhaseKnight
  phase -= countBits(board.pieceBB[BlackKnight]) * PhaseKnight
  phase -= countBits(board.pieceBB[WhiteBishop]) * PhaseBishop
  phase -= countBits(board.pieceBB[BlackBishop]) * PhaseBishop
  phase -= countBits(board.pieceBB[WhiteRook]) * PhaseRook
  phase -= countBits(board.pieceBB[BlackRook]) * PhaseRook
  phase -= countBits(board.pieceBB[WhiteQueen]) * PhaseQueen
  phase -= countBits(board.pieceBB[BlackQueen]) * PhaseQueen
  return max(0, phase)

when defined(hce):
  import lookups, magicbitboards, utils, endgame

  const
    PawnPST_MG: array[Square, int] = [
         0,   0,   0,   0,   0,   0,   0,   0,
        -9,  -8,  -4,  -2,   0,  21,  22,  -7,
       -10,  -7,   2,   5,  18,   9,  12,  -4,
        -7,  -7,   8,  17,  20,  21,   5,  -4,
        -1,   2,  11,  22,  33,  38,  10,   0,
         4,  30,  45,  41,  52,  98,  57,  14,
        49,  34,  28,  20,  21,  41, -12, -24,
         0,   0,   0,   0,   0,   0,   0,   0,
    ]
    PawnPST_EG: array[Square, int] = [
         0,   0,   0,   0,   0,   0,   0,   0,
        33,  30,  34,  35,  40,  39,  22,  11,
        31,  26,  24,  21,  26,  28,  18,  16,
        38,  38,  19,  13,  13,  18,  23,  22,
        58,  49,  34,  11,  15,  20,  39,  39,
        79,  74,  52,  24,  25,  41,  63,  67,
        29,  39,  32,  19,  22,  27,  51,  38,
         0,   0,   0,   0,   0,   0,   0,   0,
    ]
    KnightPST_MG: array[Square, int] = [
       -52, -33, -27, -25, -19, -21, -28, -51,
       -45, -43, -25,  -3,  -6, -13, -25, -22,
       -41, -13,  -6,   1,   6,   5,  -4, -18,
       -12,   7,  15,  22,  29,  20,  34,   2,
        -5,  16,  31,  44,  31,  48,  24,  13,
       -29,  -2,  26,  38,  58,  66,  36,  -2,
       -45, -38,   2,  28,  31,  45, -40, -29,
      -161, -50, -51, -30, -18, -62, -49, -97,
    ]
    KnightPST_EG: array[Square, int] = [
       -47, -36, -28,  -6,  -6, -12, -21, -45,
       -21,  -5, -30, -14,  -9, -30,  -4,  -7,
       -40, -26,  -8,  11,  10, -11, -21, -29,
       -13,  -6,  23,  32,  30,  24,  -2,  -2,
       -14,  -2,  25,  40,  39,  21,   4,  -6,
       -26, -12,  23,  19,   8,  19, -17, -23,
       -25, -11, -26,  -2, -10, -37, -17, -28,
       -89, -38, -10, -16, -10, -13, -33, -89,
    ]
    BishopPST_MG: array[Square, int] = [
        13,   3,  -1,  -4,  -8,   0,  -1,  11,
         8,  14,  14,   6,  13,  13,  31,  14,
        -7,  12,  10,  16,  13,  16,  13,  12,
       -12,   0,  13,  25,  29,   5,   7,  -8,
       -19,  14,  11,  46,  27,  20,   7,  -3,
        -1,  12,  28,  20,  40,  45,  42,  15,
       -55, -27, -18, -27, -24,   7, -31, -28,
       -34, -31, -39, -51, -42, -57, -12, -35,
    ]
    BishopPST_EG: array[Square, int] = [
       -22,  -9,  -6, -11,  -6,   0,  -6, -26,
       -19, -24, -18,  -6,  -7, -15, -16, -37,
       -11,  -3,   1,   3,   9,   0,  -5,  -9,
       -11,  -1,   9,   8,   7,  11,  -1, -11,
         2,  11,   7,   8,  15,   8,  16,   1,
         4,  12,   8,   3,   0,  15,   7,   5,
         6,  14,   9,   5,   5,   0,  10,  -3,
         7,   7,  -1,   7,   3,  -5,  -4,  -1,
    ]
    RookPST_MG: array[Square, int] = [
       -16,  -7,   0,   9,   9,  10,  10,  -6,
       -67, -27, -21, -15, -14,  -1,   4, -55,
       -38, -19, -28, -22, -20, -15,  12, -17,
       -30, -24, -27, -17, -17, -17,   6, -12,
       -14,   4,   8,  31,  25,  28,  36,  24,
       -10,  36,  20,  42,  65,  62,  85,  31,
         2,  -6,  19,  36,  33,  43,  19,  29,
        22,  14,   0,   2,   7,  16,  23,  31,
    ]
    RookPST_EG: array[Square, int] = [
        -7,  -7,  -5, -16, -17,  -3, -14, -21,
       -11, -19, -15, -20, -21, -27, -31, -16,
       -16,  -6,  -7, -11, -11, -12, -18, -25,
         1,  14,  14,   7,   6,   6,   0,  -4,
        17,  11,  15,   5,   2,   0,  -2,   3,
        22,   5,  14,   0,  -8,   0, -11,   7,
        26,  31,  25,  22,  23,  12,  21,  17,
        37,  43,  48,  43,  42,  45,  44,  42,
    ]
    QueenPST_MG: array[Square, int] = [
         3,  15,  21,  28,  27,  15,  18,   2,
        -5,  10,  19,  18,  20,  26,  23,  -9,
        -5,  11,  11,   4,   9,   7,  21,   8,
        -6,   6,   2,   0,   1,   6,  18,  15,
        -5,   1,   0,  -1,   2,   8,  25,  21,
       -18,  -8, -10,   3,  -2,  15,  26,  -8,
       -25, -56, -19, -27, -57,  -4, -48,  -8,
       -10,   5,  11,  18,   6,  14,  11,  17,
    ]
    QueenPST_EG: array[Square, int] = [
       -44, -61, -63, -46, -63, -67, -49, -44,
       -35, -45, -66, -38, -44, -80, -76, -25,
       -28, -23,  -2, -12, -10,  10, -11, -16,
        -7,   9,  11,  45,  44,  44,  25,  36,
        -5,  22,  13,  53,  66,  61,  57,  41,
         3,  -3,  24,  36,  50,  32,  18,  33,
        16,  46,  35,  52,  69,  27,  39,  25,
        15,  33,  40,  47,  38,  32,  29,  26,
    ]
    KingPST_MG: array[Square, int] = [
       -29, -16, -45, -77, -59,-106, -21, -11,
       -10, -34, -50,-107, -85, -84, -28, -18,
       -49, -28, -30, -58, -43, -34, -36, -69,
       -39, -20, -16, -56, -37, -21,  -6, -73,
       -23, -17, -18, -41, -37, -16, -13, -39,
       -10,   1,  -6, -12, -14,   0,   0, -13,
        13,  29,   7,   4,   4,  10,  26,  13,
        16,  27,   9,   1,   1,  11,  29,  16,
    ]
    KingPST_EG: array[Square, int] = [
       -93, -51, -27, -44, -58, -15, -51,-111,
       -34, -12,  -1,  11,   8,  11, -14, -43,
       -35, -12,   3,  19,  17,  10,  -6, -25,
       -42,  -1,  19,  34,  31,  22,   2, -28,
       -20,  17,  32,  36,  36,  32,  24, -14,
       -20,  29,  33,  24,  23,  42,  38, -13,
       -54,   6,   8,  -1,   2,  17,  27, -41,
       -86, -52, -43, -29, -34, -28, -36, -74,
    ]

    PawnPST_MG_Black: array[Square, int] = block:
      var arr: array[Square, int]
      for sq in 0..63: arr[sq] = PawnPST_MG[(sq xor 56)]
      arr
    PawnPST_EG_Black: array[Square, int] = block:
      var arr: array[Square, int]
      for sq in 0..63: arr[sq] = PawnPST_EG[(sq xor 56)]
      arr
    KnightPST_MG_Black: array[Square, int] = block:
      var arr: array[Square, int]
      for sq in 0..63: arr[sq] = KnightPST_MG[(sq xor 56)]
      arr
    KnightPST_EG_Black: array[Square, int] = block:
      var arr: array[Square, int]
      for sq in 0..63: arr[sq] = KnightPST_EG[(sq xor 56)]
      arr
    BishopPST_MG_Black: array[Square, int] = block:
      var arr: array[Square, int]
      for sq in 0..63: arr[sq] = BishopPST_MG[(sq xor 56)]
      arr
    BishopPST_EG_Black: array[Square, int] = block:
      var arr: array[Square, int]
      for sq in 0..63: arr[sq] = BishopPST_EG[(sq xor 56)]
      arr
    RookPST_MG_Black: array[Square, int] = block:
      var arr: array[Square, int]
      for sq in 0..63: arr[sq] = RookPST_MG[(sq xor 56)]
      arr
    RookPST_EG_Black: array[Square, int] = block:
      var arr: array[Square, int]
      for sq in 0..63: arr[sq] = RookPST_EG[(sq xor 56)]
      arr
    QueenPST_MG_Black: array[Square, int] = block:
      var arr: array[Square, int]
      for sq in 0..63: arr[sq] = QueenPST_MG[(sq xor 56)]
      arr
    QueenPST_EG_Black: array[Square, int] = block:
      var arr: array[Square, int]
      for sq in 0..63: arr[sq] = QueenPST_EG[(sq xor 56)]
      arr
    KingPST_MG_Black: array[Square, int] = block:
      var arr: array[Square, int]
      for sq in 0..63: arr[sq] = KingPST_MG[(sq xor 56)]
      arr
    KingPST_EG_Black: array[Square, int] = block:
      var arr: array[Square, int]
      for sq in 0..63: arr[sq] = KingPST_EG[(sq xor 56)]
      arr

    DoubledPawnPenalty = -8
    IsolatedPawnPenalty = -16
    PassedPawnBonus: array[0..7, int] = [0, 24, 27, 41, 73, 133, 222, 0]
    PassedPawnBonusMG*: array[0..7, int] = [0, -10, -17, 0, 33, 81, 114, 0]
    BlockadePenaltyMG* = -4
    BlockadePenaltyEG* = -49
    RookBehindPasserMG* = 4
    RookBehindPasserEG* = 17
    BishopPairBonus = 39
    RookOnOpenFileBonus = 25
    RookOnSemiOpenFileBonus = 15

    KnightMobilityMG*: array[9, int] = [-38, -18, -11, -6, 0, 3, 10, 20, 35]
    KnightMobilityEG*: array[9, int] = [-104, -48, 0, 26, 44, 64, 65, 56, 30]
    BishopMobilityMG*: array[14, int] = [-25, -19, -10, -4, 2, 7, 10, 9, 11, 17, 21, 47, 54, 53]
    BishopMobilityEG*: array[14, int] = [-104, -46, -15, 8, 27, 46, 58, 63, 73, 67, 68, 52, 87, 41]
    RookMobilityMG*: array[15, int] = [-23, -16, -12, -9, -9, -3, 0, 6, 12, 16, 18, 23, 26, 25, 95]
    RookMobilityEG*: array[15, int] = [-42, -12, 1, 14, 29, 35, 43, 42, 46, 53, 57, 60, 64, 55, 17]
    QueenMobilityMG*: array[28, int] = [-65, -45, -27, -18, -13, -10, -6, -4, 0, 4, 7, 12, 16, 17, 17, 14, 9, 6, 9, 23, 33, 39, 35, 31, 19, 16, 12, 11]
    QueenMobilityEG*: array[28, int] = [-35, -63, -75, -74, -61, -43, -20, -1, 10, 18, 29, 33, 35, 43, 53, 62, 73, 75, 75, 69, 67, 65, 62, 56, 41, 35, 28, 27]

    ShieldPawnBonus = 21
    ShieldPawnAdvancedPenalty = -3
    AttackWeightQueen = 4
    AttackWeightRook = 3
    AttackWeightBishop = 2
    AttackWeightKnight = 2

    SafetyTable*: array[100, int] = [0, 0, 2, 6, 10, 16, 24, 32, 42, 54, 66, 80, 96, 112, 130, 150, 170, 192, 216, 240, 266, 294, 322, 352, 384, 416, 450, 486, 522, 560, 600, 640, 682, 726, 770, 816, 864, 912, 962, 1014, 1066, 1120, 1176, 1232, 1290, 1350, 1410, 1472, 1536, 1600, 1666, 1734, 1802, 1872, 1944, 2016, 2090, 2166, 2242, 2320, 2400, 2480, 2562, 2646, 2730, 2816, 2904, 2992, 3082, 3174, 3266, 3360, 3456, 3552, 3650, 3750, 3850, 3952, 4056, 4160, 4266, 4374, 4482, 4592, 4704, 4816, 4930, 5046, 5162, 5280, 5400, 5520, 5642, 5766, 5890, 6016, 6144, 6272, 6402, 6534]

    PawnThreatsMG*: array[5, int] = [10, 50, 52, 48, 42]
    PawnThreatsEG*: array[5, int] = [-28, 66, 88, 27, 21]
    KnightThreatsMG*: array[5, int] = [-10, 7, 21, 42, 29]
    KnightThreatsEG*: array[5, int] = [2, 49, 43, 21, 23]
    BishopThreatsMG*: array[5, int] = [-5, 17, 1, 37, 29]
    BishopThreatsEG*: array[5, int] = [0, 47, 58, 28, 110]
    RookThreatsMG*: array[5, int] = [-10, 2, 4, 10, 40]
    RookThreatsEG*: array[5, int] = [5, 17, 18, 27, 34]
    QueenThreatsMG*: array[5, int] = [-6, 1, -1, -7, 8]
    QueenThreatsEG*: array[5, int] = [4, 0, 21, 13, 2]

    HangingPieceBonusMG* = 10
    HangingPieceBonusEG* = 17
    KnightNearOurRookBonus = 2
    BishopNearEnemyKingBonus = -2
    RookOnSameFileBonus = 12
    QueenNearEnemyKingBonus = 55

    PassedOurKingDistanceMG*: array[24, int] = [29, 55, -15, 0, 0, 0, 37, 51, 11, -40, 0, 0, 22, 0, -15, -13, 12, 0, 11, -9, -30, -13, -3, 24]
    PassedOurKingDistanceEG*: array[24, int] = [58, -2, -62, 0, 0, 0, 36, 0, 0, -45, 0, 0, 35, 14, 5, -14, -41, 0, 27, 17, 12, -2, -15, -29]
    PassedTheirKingDistanceMG*: array[24, int] = [-9, 17, 31, 0, 0, 0, 1, 37, 25, -21, 0, 0, -6, 21, 15, 3, -31, 0, -48, -5, 4, 23, 21, -30]
    PassedTheirKingDistanceEG*: array[24, int] = [-123, 6, 112, 0, 0, 0, -96, -23, 11, 99, 0, 0, -51, -27, -2, 21, 62, 0, -23, -15, 0, 1, 8, 39]

    TempoBonus = 19

  proc evaluatePieceRelativePositions(board: Board): int =
    var whiteScore = 0
    var blackScore = 0

    if board.pieceBB[BlackKing] != 0:
      let enemyKingSq = bitScanForward(board.pieceBB[BlackKing]).Square
      let roughEnemyKingFile = (enemyKingSq.int mod 8) div 2
      let roughEnemyKingRank = (enemyKingSq.int div 8) div 4

      var zoneAllInBonus = 0
      if roughEnemyKingFile == 1 or roughEnemyKingFile == 2: zoneAllInBonus += 5
      if roughEnemyKingRank == 0: zoneAllInBonus += 5

      var bb = board.pieceBB[WhiteKnight]
      while bb != 0:
        let sq = popBit(bb)
        var friends = board.pieceBB[WhiteRook]
        while friends != 0:
          let fsq = popBit(friends)
          if distance(sq, fsq) <= 2:
            whiteScore += KnightNearOurRookBonus

      bb = board.pieceBB[WhiteBishop]
      while bb != 0:
        let sq = popBit(bb)
        if distance(sq, enemyKingSq) <= 2:
          whiteScore += BishopNearEnemyKingBonus + zoneAllInBonus

      bb = board.pieceBB[WhiteRook]
      while bb != 0:
        let sq = popBit(bb)
        let f = fileOf(sq)
        if (FileMasks[f] and (board.pieceBB[WhiteQueen] or (board.pieceBB[WhiteRook] and not (1'u64 shl sq)))) != 0:
          whiteScore += RookOnSameFileBonus

      bb = board.pieceBB[WhiteQueen]
      while bb != 0:
        let sq = popBit(bb)
        if distance(sq, enemyKingSq) <= 2:
          whiteScore += QueenNearEnemyKingBonus + zoneAllInBonus

    if board.pieceBB[WhiteKing] != 0:
      let enemyKingSq = bitScanForward(board.pieceBB[WhiteKing]).Square
      let roughEnemyKingFile = (enemyKingSq.int mod 8) div 2
      let roughEnemyKingRank = (enemyKingSq.int div 8) div 4

      var zoneAllInBonus = 0
      if roughEnemyKingFile == 1 or roughEnemyKingFile == 2: zoneAllInBonus += 5
      if roughEnemyKingRank == 1: zoneAllInBonus += 5

      var bb = board.pieceBB[BlackKnight]
      while bb != 0:
        let sq = popBit(bb)
        var friends = board.pieceBB[BlackRook]
        while friends != 0:
          let fsq = popBit(friends)
          if distance(sq, fsq) <= 2:
            blackScore += KnightNearOurRookBonus

      bb = board.pieceBB[BlackBishop]
      while bb != 0:
        let sq = popBit(bb)
        if distance(sq, enemyKingSq) <= 2:
          blackScore += BishopNearEnemyKingBonus + zoneAllInBonus

      bb = board.pieceBB[BlackRook]
      while bb != 0:
        let sq = popBit(bb)
        let f = fileOf(sq)
        if (FileMasks[f] and (board.pieceBB[BlackQueen] or (board.pieceBB[BlackRook] and not (1'u64 shl sq)))) != 0:
          blackScore += RookOnSameFileBonus

      bb = board.pieceBB[BlackQueen]
      while bb != 0:
        let sq = popBit(bb)
        if distance(sq, enemyKingSq) <= 2:
          blackScore += QueenNearEnemyKingBonus + zoneAllInBonus

    return whiteScore - blackScore

  proc evaluatePawnStructure(board: Board, mgWhite, egWhite, mgBlack, egBlack: var int) =
    var bb = board.pieceBB[WhitePawn]
    while bb != 0:
      let sq = popBit(bb)
      let f = fileOf(sq)
      let r = rankOf(sq)

      if (FileMasks[f] and board.pieceBB[WhitePawn] and not (1'u64 shl sq)) != 0:
        mgWhite += DoubledPawnPenalty
        egWhite += DoubledPawnPenalty

      if (IsolatedPawnMasks[f] and board.pieceBB[WhitePawn]) == 0:
        mgWhite += IsolatedPawnPenalty
        egWhite += IsolatedPawnPenalty

      if (PassedPawnMasks[White][sq] and board.pieceBB[BlackPawn]) == 0:
        mgWhite += PassedPawnBonusMG[r]
        egWhite += PassedPawnBonus[r]

        let aheadSq = sq + 8
        if aheadSq <= 63:
          let occupant = board.pieces[aheadSq]
          if occupant != NoPiece and pieceColor(occupant) == Black:
            mgWhite += BlockadePenaltyMG
            egWhite += BlockadePenaltyEG

        let rooksBehind = board.pieceBB[WhiteRook] and FileMasks[f]
        if rooksBehind != 0:
          var rooks = rooksBehind
          while rooks != 0:
            let rookSq = popBit(rooks)
            if rankOf(rookSq) < r:
              mgWhite += RookBehindPasserMG
              egWhite += RookBehindPasserEG
              break

    bb = board.pieceBB[BlackPawn]
    while bb != 0:
      let sq = popBit(bb)
      let f = fileOf(sq)
      let r = rankOf(sq)
      let relativeRank = 7 - r

      if (FileMasks[f] and board.pieceBB[BlackPawn] and not (1'u64 shl sq)) != 0:
        mgBlack += DoubledPawnPenalty
        egBlack += DoubledPawnPenalty

      if (IsolatedPawnMasks[f] and board.pieceBB[BlackPawn]) == 0:
        mgBlack += IsolatedPawnPenalty
        egBlack += IsolatedPawnPenalty

      if (PassedPawnMasks[Black][sq] and board.pieceBB[WhitePawn]) == 0:
        mgBlack += PassedPawnBonusMG[relativeRank]
        egBlack += PassedPawnBonus[relativeRank]

        let aheadSq = sq - 8
        if aheadSq >= 0:
          let occupant = board.pieces[aheadSq]
          if occupant != NoPiece and pieceColor(occupant) == White:
            mgBlack += BlockadePenaltyMG
            egBlack += BlockadePenaltyEG

        let rooksBehind = board.pieceBB[BlackRook] and FileMasks[f]
        if rooksBehind != 0:
          var rooks = rooksBehind
          while rooks != 0:
            let rookSq = popBit(rooks)
            if rankOf(rookSq) > r:
              mgBlack += RookBehindPasserMG
              egBlack += RookBehindPasserEG
              break

  proc evaluatePassedPawnKingDistance(board: Board, mgWhite, egWhite, mgBlack, egBlack: var int) =
    if board.pieceBB[WhiteKing] == 0 or board.pieceBB[BlackKing] == 0:
      return

    let whiteKingSq = bitScanForward(board.pieceBB[WhiteKing]).Square
    let blackKingSq = bitScanForward(board.pieceBB[BlackKing]).Square

    var bb = board.pieceBB[WhitePawn]
    while bb != 0:
      let sq = popBit(bb)
      let r = rankOf(sq)
      if (PassedPawnMasks[White][sq] and board.pieceBB[BlackPawn]) == 0:
        let queeningDistance = 7 - r
        if queeningDistance <= 4 and queeningDistance >= 1:
          let ourKingDist = manhattanDistance(whiteKingSq, sq)
          let theirKingDist = manhattanDistance(blackKingSq, sq)
          let ourIndex = (queeningDistance - 1) * 6 + min(queeningDistance + 2, ourKingDist) - 1
          let theirIndex = (queeningDistance - 1) * 6 + min(queeningDistance + 2, theirKingDist) - 1
          mgWhite += PassedOurKingDistanceMG[ourIndex]
          egWhite += PassedOurKingDistanceEG[ourIndex]
          mgWhite += PassedTheirKingDistanceMG[theirIndex]
          egWhite += PassedTheirKingDistanceEG[theirIndex]

    bb = board.pieceBB[BlackPawn]
    while bb != 0:
      let sq = popBit(bb)
      let r = rankOf(sq)
      let relativeRank = 7 - r
      if (PassedPawnMasks[Black][sq] and board.pieceBB[WhitePawn]) == 0:
        let queeningDistance = 7 - relativeRank
        if queeningDistance <= 4 and queeningDistance >= 1:
          let ourKingDist = manhattanDistance(blackKingSq, sq)
          let theirKingDist = manhattanDistance(whiteKingSq, sq)
          let ourIndex = (queeningDistance - 1) * 6 + min(queeningDistance + 2, ourKingDist) - 1
          let theirIndex = (queeningDistance - 1) * 6 + min(queeningDistance + 2, theirKingDist) - 1
          mgBlack += PassedOurKingDistanceMG[ourIndex]
          egBlack += PassedOurKingDistanceEG[ourIndex]
          mgBlack += PassedTheirKingDistanceMG[theirIndex]
          egBlack += PassedTheirKingDistanceEG[theirIndex]

  template getVictimIndex(pt: PieceType): int =
    case pt
    of Pawn: 0
    of Knight: 1
    of Bishop: 2
    of Rook: 3
    of Queen: 4
    else: -1

  proc evaluateThreats(board: Board, us: Color,
                       attackedByPawn, attackedByKnight, attackedByBishop,
                       attackedByRook, attackedByQueen, attackedByUs,
                       attackedByThem: Bitboard): tuple[mg, eg: int] {.inline.} =
    let them = if us == White: Black else: White
    let theirPieces = board.occupiedBB[them]
    var mgScore = 0
    var egScore = 0

    var threats = theirPieces and attackedByPawn
    while threats != 0:
      let sq = popBit(threats)
      let victim = pieceType(board.pieces[sq])
      let idx = getVictimIndex(victim)
      if idx >= 0:
        mgScore += PawnThreatsMG[idx]
        egScore += PawnThreatsEG[idx]

    threats = theirPieces and attackedByKnight
    while threats != 0:
      let sq = popBit(threats)
      let victim = pieceType(board.pieces[sq])
      let idx = getVictimIndex(victim)
      if idx >= 0:
        mgScore += KnightThreatsMG[idx]
        egScore += KnightThreatsEG[idx]

    threats = theirPieces and attackedByBishop
    while threats != 0:
      let sq = popBit(threats)
      let victim = pieceType(board.pieces[sq])
      let idx = getVictimIndex(victim)
      if idx >= 0:
        mgScore += BishopThreatsMG[idx]
        egScore += BishopThreatsEG[idx]

    threats = theirPieces and attackedByRook
    while threats != 0:
      let sq = popBit(threats)
      let victim = pieceType(board.pieces[sq])
      let idx = getVictimIndex(victim)
      if idx >= 0:
        mgScore += RookThreatsMG[idx]
        egScore += RookThreatsEG[idx]

    threats = theirPieces and attackedByQueen
    while threats != 0:
      let sq = popBit(threats)
      let victim = pieceType(board.pieces[sq])
      let idx = getVictimIndex(victim)
      if idx >= 0:
        mgScore += QueenThreatsMG[idx]
        egScore += QueenThreatsEG[idx]

    let hangingPawns = (theirPieces and board.pieceBB[makePiece(them, Pawn)]) and
        attackedByUs and (not attackedByThem)
    let hangingCount = countBits(hangingPawns)
    mgScore += hangingCount * HangingPieceBonusMG
    egScore += hangingCount * HangingPieceBonusEG

    return (mgScore, egScore)

  proc evaluate*(board: Board): int =
    var mgWhite = 0
    var egWhite = 0
    var mgBlack = 0
    var egBlack = 0
    var gamePhase = 0

    let whiteNonPawnMat = (board.occupiedBB[White] xor board.pieceBB[WhiteKing] xor board.pieceBB[WhitePawn]) != 0
    let blackNonPawnMat = (board.occupiedBB[Black] xor board.pieceBB[BlackKing] xor board.pieceBB[BlackPawn]) != 0
    let whiteWraps = (board.occupiedBB[White] xor board.pieceBB[WhiteKing]) == 0
    let blackWraps = (board.occupiedBB[Black] xor board.pieceBB[BlackKing]) == 0

    if whiteNonPawnMat and blackWraps:
      return mopUpEvaluation(board)
    if blackNonPawnMat and whiteWraps:
      return mopUpEvaluation(board)

    var whiteKingZone: Bitboard = 0
    var blackKingZone: Bitboard = 0

    var whitePawnAttacks: Bitboard = 0
    var whiteKnightAttacks: Bitboard = 0
    var whiteBishopAttacks: Bitboard = 0
    var whiteRookAttacks: Bitboard = 0
    var whiteQueenAttacks: Bitboard = 0

    var blackPawnAttacks: Bitboard = 0
    var blackKnightAttacks: Bitboard = 0
    var blackBishopAttacks: Bitboard = 0
    var blackRookAttacks: Bitboard = 0
    var blackQueenAttacks: Bitboard = 0

    if board.pieceBB[WhiteKing] != 0:
      let ksq = bitScanForward(board.pieceBB[WhiteKing])
      whiteKingZone = KingAttackZoneMasks[ksq.Square]
      mgWhite += KingValue + KingPST_MG[ksq.Square]
      egWhite += KingValue + KingPST_EG[ksq.Square]

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

      let shieldMask = KingShieldMasks[Black][ksq.Square]
      var shieldPawns = shieldMask and board.pieceBB[BlackPawn]
      while shieldPawns != 0:
        let psq = popBit(shieldPawns)
        var bonus = ShieldPawnBonus
        if rankOf(psq) < rankOf(ksq.Square) - 1: bonus += ShieldPawnAdvancedPenalty
        mgBlack += bonus

    var whiteAttackUnits = 0
    var blackAttackUnits = 0
    var whiteAttackerCount = 0
    var blackAttackerCount = 0

    let whiteOccupied = board.occupiedBB[White]
    let blackOccupied = board.occupiedBB[Black]
    let allPieces = board.allPiecesBB

    var bb = board.pieceBB[WhitePawn]
    while bb != 0:
      let sq = popBit(bb)
      mgWhite += PawnValueMG + PawnPST_MG[sq]
      egWhite += PawnValueEG + PawnPST_EG[sq]
      whitePawnAttacks = whitePawnAttacks or pawnAttacks[White][sq]

    bb = board.pieceBB[BlackPawn]
    while bb != 0:
      let sq = popBit(bb)
      mgBlack += PawnValueMG + PawnPST_MG_Black[sq]
      egBlack += PawnValueEG + PawnPST_EG_Black[sq]
      blackPawnAttacks = blackPawnAttacks or pawnAttacks[Black][sq]

    bb = board.pieceBB[WhiteKnight]
    while bb != 0:
      let sq = popBit(bb)
      mgWhite += KnightValueMG + KnightPST_MG[sq]
      egWhite += KnightValueEG + KnightPST_EG[sq]
      gamePhase += PhaseKnight
      let attacks = knightAttacks[sq]
      whiteKnightAttacks = whiteKnightAttacks or attacks
      let safeMob = min(countBits(attacks and not whiteOccupied and not blackPawnAttacks), 8)
      mgWhite += KnightMobilityMG[safeMob]
      egWhite += KnightMobilityEG[safeMob]
      if (attacks and blackKingZone) != 0:
        whiteAttackUnits += countBits(attacks and blackKingZone) * AttackWeightKnight
        whiteAttackerCount += 1

    bb = board.pieceBB[WhiteBishop]
    while bb != 0:
      let sq = popBit(bb)
      mgWhite += BishopValueMG + BishopPST_MG[sq]
      egWhite += BishopValueEG + BishopPST_EG[sq]
      gamePhase += PhaseBishop
      let attacks = getBishopAttacks(sq, allPieces)
      whiteBishopAttacks = whiteBishopAttacks or attacks
      let safeMob = min(countBits(attacks and not whiteOccupied and not blackPawnAttacks), 13)
      mgWhite += BishopMobilityMG[safeMob]
      egWhite += BishopMobilityEG[safeMob]
      if (attacks and blackKingZone) != 0:
        whiteAttackUnits += countBits(attacks and blackKingZone) * AttackWeightBishop
        whiteAttackerCount += 1

    if (board.pieceBB[WhiteBishop] and (board.pieceBB[WhiteBishop] - 1)) != 0:
      mgWhite += BishopPairBonus
      egWhite += BishopPairBonus

    bb = board.pieceBB[WhiteRook]
    while bb != 0:
      let sq = popBit(bb)
      mgWhite += RookValueMG + RookPST_MG[sq]
      egWhite += RookValueEG + RookPST_EG[sq]
      gamePhase += PhaseRook
      let attacks = getRookAttacks(sq, allPieces)
      whiteRookAttacks = whiteRookAttacks or attacks
      let safeMob = min(countBits(attacks and not whiteOccupied and not blackPawnAttacks), 14)
      mgWhite += RookMobilityMG[safeMob]
      egWhite += RookMobilityEG[safeMob]
      if (attacks and blackKingZone) != 0:
        whiteAttackUnits += countBits(attacks and blackKingZone) * AttackWeightRook
        whiteAttackerCount += 1
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

    bb = board.pieceBB[WhiteQueen]
    while bb != 0:
      let sq = popBit(bb)
      mgWhite += QueenValueMG + QueenPST_MG[sq]
      egWhite += QueenValueEG + QueenPST_EG[sq]
      gamePhase += PhaseQueen
      let attacks = getQueenAttacks(sq, allPieces)
      whiteQueenAttacks = whiteQueenAttacks or attacks
      let safeMob = min(countBits(attacks and not whiteOccupied and not blackPawnAttacks), 27)
      mgWhite += QueenMobilityMG[safeMob]
      egWhite += QueenMobilityEG[safeMob]
      if (attacks and blackKingZone) != 0:
        whiteAttackUnits += countBits(attacks and blackKingZone) * AttackWeightQueen
        whiteAttackerCount += 1

    bb = board.pieceBB[BlackKnight]
    while bb != 0:
      let sq = popBit(bb)
      mgBlack += KnightValueMG + KnightPST_MG_Black[sq]
      egBlack += KnightValueEG + KnightPST_EG_Black[sq]
      gamePhase += PhaseKnight
      let attacks = knightAttacks[sq]
      blackKnightAttacks = blackKnightAttacks or attacks
      let safeMob = min(countBits(attacks and not blackOccupied and not whitePawnAttacks), 8)
      mgBlack += KnightMobilityMG[safeMob]
      egBlack += KnightMobilityEG[safeMob]
      if (attacks and whiteKingZone) != 0:
        blackAttackUnits += countBits(attacks and whiteKingZone) * AttackWeightKnight
        blackAttackerCount += 1

    bb = board.pieceBB[BlackBishop]
    while bb != 0:
      let sq = popBit(bb)
      mgBlack += BishopValueMG + BishopPST_MG_Black[sq]
      egBlack += BishopValueEG + BishopPST_EG_Black[sq]
      gamePhase += PhaseBishop
      let attacks = getBishopAttacks(sq, allPieces)
      blackBishopAttacks = blackBishopAttacks or attacks
      let safeMob = min(countBits(attacks and not blackOccupied and not whitePawnAttacks), 13)
      mgBlack += BishopMobilityMG[safeMob]
      egBlack += BishopMobilityEG[safeMob]
      if (attacks and whiteKingZone) != 0:
        blackAttackUnits += countBits(attacks and whiteKingZone) * AttackWeightBishop
        blackAttackerCount += 1

    if (board.pieceBB[BlackBishop] and (board.pieceBB[BlackBishop] - 1)) != 0:
      mgBlack += BishopPairBonus
      egBlack += BishopPairBonus

    bb = board.pieceBB[BlackRook]
    while bb != 0:
      let sq = popBit(bb)
      mgBlack += RookValueMG + RookPST_MG_Black[sq]
      egBlack += RookValueEG + RookPST_EG_Black[sq]
      gamePhase += PhaseRook
      let attacks = getRookAttacks(sq, allPieces)
      blackRookAttacks = blackRookAttacks or attacks
      let safeMob = min(countBits(attacks and not blackOccupied and not whitePawnAttacks), 14)
      mgBlack += RookMobilityMG[safeMob]
      egBlack += RookMobilityEG[safeMob]
      if (attacks and whiteKingZone) != 0:
        blackAttackUnits += countBits(attacks and whiteKingZone) * AttackWeightRook
        blackAttackerCount += 1
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

    bb = board.pieceBB[BlackQueen]
    while bb != 0:
      let sq = popBit(bb)
      mgBlack += QueenValueMG + QueenPST_MG_Black[sq]
      egBlack += QueenValueEG + QueenPST_EG_Black[sq]
      gamePhase += PhaseQueen
      let attacks = getQueenAttacks(sq, allPieces)
      blackQueenAttacks = blackQueenAttacks or attacks
      let safeMob = min(countBits(attacks and not blackOccupied and not whitePawnAttacks), 27)
      mgBlack += QueenMobilityMG[safeMob]
      egBlack += QueenMobilityEG[safeMob]
      if (attacks and whiteKingZone) != 0:
        blackAttackUnits += countBits(attacks and whiteKingZone) * AttackWeightQueen
        blackAttackerCount += 1

    let whiteAttacksAll = whitePawnAttacks or whiteKnightAttacks or whiteBishopAttacks or whiteRookAttacks or whiteQueenAttacks
    let blackAttacksAll = blackPawnAttacks or blackKnightAttacks or blackBishopAttacks or blackRookAttacks or blackQueenAttacks

    let (wThreatsMg, wThreatsEg) = evaluateThreats(board, White,
        whitePawnAttacks, whiteKnightAttacks, whiteBishopAttacks,
        whiteRookAttacks, whiteQueenAttacks, whiteAttacksAll, blackAttacksAll)
    mgWhite += wThreatsMg
    egWhite += wThreatsEg

    let (bThreatsMg, bThreatsEg) = evaluateThreats(board, Black,
        blackPawnAttacks, blackKnightAttacks, blackBishopAttacks,
        blackRookAttacks, blackQueenAttacks, blackAttacksAll, whiteAttacksAll)
    mgBlack += bThreatsMg
    egBlack += bThreatsEg

    if blackAttackerCount >= 2:
      if blackAttackUnits > 100: blackAttackUnits = 100
      mgWhite -= SafetyTable[blackAttackUnits]

    if whiteAttackerCount >= 2:
      if whiteAttackUnits > 100: whiteAttackUnits = 100
      mgBlack -= SafetyTable[whiteAttackUnits]

    evaluatePawnStructure(board, mgWhite, egWhite, mgBlack, egBlack)
    evaluatePassedPawnKingDistance(board, mgWhite, egWhite, mgBlack, egBlack)

    if gamePhase > PhaseTotal: gamePhase = PhaseTotal
    let mgPhase = gamePhase
    let egPhase = PhaseTotal - mgPhase

    let whiteScore = (mgWhite * mgPhase + egWhite * egPhase) div PhaseTotal
    let blackScore = (mgBlack * mgPhase + egBlack * egPhase) div PhaseTotal

    var finalScore = 0
    if board.sideToMove == White:
      finalScore = (whiteScore - blackScore) + TempoBonus
    else:
      finalScore = (blackScore - whiteScore) + TempoBonus

    const MaxEval = MateValue - MaxPly - 100
    if finalScore > MaxEval: finalScore = MaxEval
    elif finalScore < -MaxEval: finalScore = -MaxEval

    let relScore = evaluatePieceRelativePositions(board)
    if board.sideToMove == White:
      finalScore += relScore
    else:
      finalScore -= relScore

    return finalScore

else:
  import nnuetypes, nnue

  var gNetwork*: NNUENetwork

  proc initNNUE*(path: string = "") =
    if path.len == 0:
      gNetwork = loadNetworkFromEmbedded()
    else:
      gNetwork = loadNetwork(path)

  proc evaluate*(board: Board, state: var NNUEState): int {.inline.} =
    return nnueEvaluate(addr gNetwork, board, state)