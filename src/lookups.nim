import bitboard, coretypes, utils

type
  Direction* = enum
    North, NorthEast, East, SouthEast, South, SouthWest, West, NorthWest

var
  knightAttacks*: array[Square, Bitboard]
  kingAttacks*: array[Square, Bitboard]
  pawnAttacks*: array[Color, array[Square, Bitboard]]
  pawnPushes*: array[Color, array[Square, Bitboard]]
  pawnDoublePushes*: array[Color, array[Square, Bitboard]]
  rayAttacks*: array[Square, array[Direction, Bitboard]]
  lineBetweenBB*: array[Square, array[Square, Bitboard]]

proc precomputeAttackTables*() =
  # Knight attacks
  for sVal in 0..63:
    let s = Square(sVal)
    knightAttacks[s] = 0'u64
    let r = rankOf(s)
    let f = fileOf(s)
    const knightMoves = [
      ( 2,  1), ( 2, -1), (-2,  1), (-2, -1),
      ( 1,  2), ( 1, -2), (-1,  2), (-1, -2)
    ]
    for move in knightMoves:
      let nr = r + move[0]
      let nf = f + move[1]
      if nr >= 0 and nr <= 7 and nf >= 0 and nf <= 7:
        setBit(knightAttacks[s], squareFromCoords(nr, nf))

  # King attacks
  for sVal in 0..63:
    let s = Square(sVal)
    kingAttacks[s] = 0'u64
    let r = rankOf(s)
    let f = fileOf(s)
    const kingMoves = [
      ( 1,  0), ( 1,  1), ( 1, -1), ( 0,  1),
      ( 0, -1), (-1,  0), (-1,  1), (-1, -1)
    ]
    for move in kingMoves:
      let nr = r + move[0]
      let nf = f + move[1]
      if nr >= 0 and nr <= 7 and nf >= 0 and nf <= 7:
        setBit(kingAttacks[s], squareFromCoords(nr, nf))

  # Pawn attacks, pushes, and double pushes
  for cVal in ord(Color.White)..ord(Color.Black):
    let c = Color(cVal)
    for sVal in 0..63:
      let s = Square(sVal)
      pawnAttacks[c][s] = 0'u64
      pawnPushes[c][s] = 0'u64
      pawnDoublePushes[c][s] = 0'u64
      let r = rankOf(s)
      let f = fileOf(s)
      if c == Color.White:
        if r < 7:
          if f > 0: setBit(pawnAttacks[c][s], squareFromCoords(r + 1, f - 1))
          if f < 7: setBit(pawnAttacks[c][s], squareFromCoords(r + 1, f + 1))
        if r < 7: setBit(pawnPushes[c][s], squareFromCoords(r + 1, f))
        if r == 1: setBit(pawnDoublePushes[c][s], squareFromCoords(r + 2, f))
      else: # c == Color.Black
        if r > 0:
          if f > 0: setBit(pawnAttacks[c][s], squareFromCoords(r - 1, f - 1))
          if f < 7: setBit(pawnAttacks[c][s], squareFromCoords(r - 1, f + 1))
        if r > 0: setBit(pawnPushes[c][s], squareFromCoords(r - 1, f))
        if r == 6: setBit(pawnDoublePushes[c][s], squareFromCoords(r - 2, f))

  # Ray attacks
  const dirDeltas = [
    ( 1,  0), # North
    ( 1,  1), # NorthEast
    ( 0,  1), # East
    (-1,  1), # SouthEast
    (-1,  0), # South
    (-1, -1), # SouthWest
    ( 0, -1), # West
    ( 1, -1)  # NorthWest
  ]
  for sVal in 0..63:
    let s = Square(sVal)
    for dirVal in ord(Direction.North)..ord(Direction.NorthWest):
      let dir = Direction(dirVal)
      rayAttacks[s][dir] = 0'u64
      var r = rankOf(s)
      var f = fileOf(s)
      let dr = dirDeltas[ord(dir)][0]
      let df = dirDeltas[ord(dir)][1]
      while true:
        r += dr
        f += df
        if r >= 0 and r <= 7 and f >= 0 and f <= 7:
          setBit(rayAttacks[s][dir], squareFromCoords(r,f))
        else:
          break

  # Line between squares
  for s1Val in 0..63:
    let s1 = Square(s1Val)
    for s2Val in 0..63:
      let s2 = Square(s2Val)
      lineBetweenBB[s1][s2] = 0'u64
      if s1 == s2: continue

      let r1 = rankOf(s1)
      let f1 = fileOf(s1)
      let r2 = rankOf(s2)
      let f2 = fileOf(s2)

      let deltaR = r1 - r2
      let deltaF = f1 - f2

      let drStep = if r2 > r1: 1 elif r2 < r1: -1 else: 0
      let dfStep = if f2 > f1: 1 elif f2 < f1: -1 else: 0

      # Not aligned or adjacent (no squares *between* adjacent squares)
      if (drStep == 0 and dfStep == 0) or 
         (abs(deltaR) != abs(deltaF) and drStep != 0 and dfStep != 0) or # Not diagonal
         (drStep == 0 and abs(deltaF) <= 1) or # Horizontal adjacent or same
         (dfStep == 0 and abs(deltaR) <= 1) or # Vertical adjacent or same
         (abs(deltaR) <= 1 and abs(deltaF) <= 1): # Diagonal adjacent or same
        continue
      
      # If they are on the same line/diagonal (and not adjacent)
      if (drStep == 0) or (dfStep == 0) or (abs(deltaR) == abs(deltaF)):
        var curR = r1 + drStep
        var curF = f1 + dfStep
        while curR != r2 or curF != f2:
          if curR >= 0 and curR <= 7 and curF >= 0 and curF <= 7:
             setBit(lineBetweenBB[s1][s2], squareFromCoords(curR, curF))
          else: 
            break 
          curR += drStep
          curF += dfStep 