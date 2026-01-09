import coretypes, bitboard, utils

type
  Direction* = enum
    North, NorthEast, East, SouthEast, South, SouthWest, West, NorthWest

var
  knightAttacks*: array[Square, Bitboard]
  kingAttacks*: array[Square, Bitboard]
  pawnAttacks*: array[Color, array[Square, Bitboard]]
  rayAttacks*: array[Square, array[Direction, Bitboard]]
  lineBetweenBB*: array[Square, array[Square, Bitboard]]

proc initRayAttacks() =
  for sqInt in 0..63:
    let sq = sqInt.Square
    let r = rankOf(sq)
    let f = fileOf(sq)
    
    # North
    for i in r+1..7: rayAttacks[sq][North].setBit(squareFromCoords(i, f))
    # South
    for i in countdown(r-1, 0): rayAttacks[sq][South].setBit(squareFromCoords(i, f))
    # East
    for i in f+1..7: rayAttacks[sq][East].setBit(squareFromCoords(r, i))
    # West
    for i in countdown(f-1, 0): rayAttacks[sq][West].setBit(squareFromCoords(r, i))
    
    # NorthEast
    var i = 1
    while r+i <= 7 and f+i <= 7:
      rayAttacks[sq][NorthEast].setBit(squareFromCoords(r+i, f+i))
      inc(i)
      
    # NorthWest
    i = 1
    while r+i <= 7 and f-i >= 0:
      rayAttacks[sq][NorthWest].setBit(squareFromCoords(r+i, f-i))
      inc(i)
      
    # SouthEast
    i = 1
    while r-i >= 0 and f+i <= 7:
      rayAttacks[sq][SouthEast].setBit(squareFromCoords(r-i, f+i))
      inc(i)
      
    # SouthWest
    i = 1
    while r-i >= 0 and f-i >= 0:
      rayAttacks[sq][SouthWest].setBit(squareFromCoords(r-i, f-i))
      inc(i)

proc initKnightAttacks() =
  let knightOffsets = [
    (2, 1), (2, -1), (-2, 1), (-2, -1),
    (1, 2), (1, -2), (-1, 2), (-1, -2)
  ]
  
  for sqInt in 0..63:
    let sq = sqInt.Square
    let r = rankOf(sq)
    let f = fileOf(sq)
    
    for offset in knightOffsets:
      let nr = r + offset[0]
      let nf = f + offset[1]
      if nr >= 0 and nr <= 7 and nf >= 0 and nf <= 7:
        knightAttacks[sq].setBit(squareFromCoords(nr, nf))

proc initKingAttacks() =
  let kingOffsets = [
    (1, 0), (1, 1), (0, 1), (-1, 1),
    (-1, 0), (-1, -1), (0, -1), (1, -1)
  ]
  
  for sqInt in 0..63:
    let sq = sqInt.Square
    let r = rankOf(sq)
    let f = fileOf(sq)
    
    for offset in kingOffsets:
      let nr = r + offset[0]
      let nf = f + offset[1]
      if nr >= 0 and nr <= 7 and nf >= 0 and nf <= 7:
        kingAttacks[sq].setBit(squareFromCoords(nr, nf))

proc initPawnAttacks() =
  # White pawns capture NorthEast and NorthWest
  for sqInt in 0..63:
    let sq = sqInt.Square
    let r = rankOf(sq)
    let f = fileOf(sq)
    
    if r < 7:
      if f < 7: pawnAttacks[White][sq].setBit(squareFromCoords(r+1, f+1))
      if f > 0: pawnAttacks[White][sq].setBit(squareFromCoords(r+1, f-1))
      
  # Black pawns capture SouthEast and SouthWest
  for sqInt in 0..63:
    let sq = sqInt.Square
    let r = rankOf(sq)
    let f = fileOf(sq)
    
    if r > 0:
      if f < 7: pawnAttacks[Black][sq].setBit(squareFromCoords(r-1, f+1))
      if f > 0: pawnAttacks[Black][sq].setBit(squareFromCoords(r-1, f-1))

proc initLineBetween() =
  for s1Int in 0..63:
    let s1 = s1Int.Square
    for s2Int in 0..63:
      let s2 = s2Int.Square
      if s1 == s2: continue
      
      let r1 = rankOf(s1); let f1 = fileOf(s1)
      let r2 = rankOf(s2); let f2 = fileOf(s2)
      
      var bb: Bitboard = 0
      
      # Same Rank
      if r1 == r2:
        let minF = min(f1, f2)
        let maxF = max(f1, f2)
        for f in minF+1 ..< maxF:
          bb.setBit(squareFromCoords(r1, f))
        lineBetweenBB[s1][s2] = bb
        
      # Same File
      elif f1 == f2:
        let minR = min(r1, r2)
        let maxR = max(r1, r2)
        for r in minR+1 ..< maxR:
          bb.setBit(squareFromCoords(r, f1))
        lineBetweenBB[s1][s2] = bb
        
      # Same Diagonal
      elif abs(r1 - r2) == abs(f1 - f2):
        let dr = if r2 > r1: 1 else: -1
        let df = if f2 > f1: 1 else: -1
        var r = r1 + dr
        var f = f1 + df
        while r != r2:
          bb.setBit(squareFromCoords(r, f))
          r += dr
          f += df
        lineBetweenBB[s1][s2] = bb

var
  FileMasks*: array[0..7, Bitboard]
  RankMasks*: array[0..7, Bitboard]
  IsolatedPawnMasks*: array[0..7, Bitboard]
  PassedPawnMasks*: array[Color, array[Square, Bitboard]]
  KingShieldMasks*: array[Color, array[Square, Bitboard]]
  KingAttackZoneMasks*: array[Square, Bitboard]

proc initEvaluationMasks() =
  # File and Rank Masks
  for r in 0..7:
    for f in 0..7:
      let sq = squareFromCoords(r, f)
      FileMasks[f].setBit(sq)
      RankMasks[r].setBit(sq)
      
  # Isolated Pawn Masks (adjacent files)
  for f in 0..7:
    if f > 0: IsolatedPawnMasks[f] = IsolatedPawnMasks[f] or FileMasks[f-1]
    if f < 7: IsolatedPawnMasks[f] = IsolatedPawnMasks[f] or FileMasks[f+1]
    
  # Passed Pawn Masks
  for sqInt in 0..63:
    let sq = sqInt.Square
    let r = rankOf(sq)
    let f = fileOf(sq)
    
    # White Passed Pawn: Files f-1, f, f+1, Ranks > r
    var whitePassed: Bitboard = 0
    for r2 in r+1..7:
      whitePassed.setBit(squareFromCoords(r2, f))
      if f > 0: whitePassed.setBit(squareFromCoords(r2, f-1))
      if f < 7: whitePassed.setBit(squareFromCoords(r2, f+1))
    PassedPawnMasks[White][sq] = whitePassed
    
    # Black Passed Pawn: Files f-1, f, f+1, Ranks < r
    var blackPassed: Bitboard = 0
    for r2 in countdown(r-1, 0):
      blackPassed.setBit(squareFromCoords(r2, f))
      if f > 0: blackPassed.setBit(squareFromCoords(r2, f-1))
      if f < 7: blackPassed.setBit(squareFromCoords(r2, f+1))
    PassedPawnMasks[Black][sq] = blackPassed

  for sqInt in 0..63:
    let sq = sqInt.Square
    let r = rankOf(sq)
    let f = fileOf(sq)
    
    # White Shield
    var whiteShield: Bitboard = 0
    if r < 7:
      # Rank + 1
      whiteShield.setBit(squareFromCoords(r+1, f))
      if f > 0: whiteShield.setBit(squareFromCoords(r+1, f-1))
      if f < 7: whiteShield.setBit(squareFromCoords(r+1, f+1))
      
      # Rank + 2
      if r < 6:
        whiteShield.setBit(squareFromCoords(r+2, f))
        if f > 0: whiteShield.setBit(squareFromCoords(r+2, f-1))
        if f < 7: whiteShield.setBit(squareFromCoords(r+2, f+1))
    KingShieldMasks[White][sq] = whiteShield
    
    # Black Shield
    var blackShield: Bitboard = 0
    if r > 0:
      # Rank - 1
      blackShield.setBit(squareFromCoords(r-1, f))
      if f > 0: blackShield.setBit(squareFromCoords(r-1, f-1))
      if f < 7: blackShield.setBit(squareFromCoords(r-1, f+1))
      
      # Rank - 2
      if r > 1:
        blackShield.setBit(squareFromCoords(r-2, f))
        if f > 0: blackShield.setBit(squareFromCoords(r-2, f-1))
        if f < 7: blackShield.setBit(squareFromCoords(r-2, f+1))
    KingShieldMasks[Black][sq] = blackShield

  for sqInt in 0..63:
    let sq = sqInt.Square
    let r = rankOf(sq)
    let f = fileOf(sq)
    
    var attackZone: Bitboard = 0
    for rOffset in -1..1:
      for fOffset in -1..1:
        let nr = r + rOffset
        let nf = f + fOffset
        if nr >= 0 and nr <= 7 and nf >= 0 and nf <= 7:
          attackZone.setBit(squareFromCoords(nr, nf))
    KingAttackZoneMasks[sq] = attackZone

proc precomputeAttackTables*() =
  initRayAttacks()
  initKnightAttacks()
  initKingAttacks()
  initPawnAttacks()
  initLineBetween()
  initEvaluationMasks()
