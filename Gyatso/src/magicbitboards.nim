import coretypes, bitboard, utils

type
  MagicEntry* = object
    mask*: Bitboard
    magic*: uint64
    shift*: int
    offset*: int

var rookMagics*: array[Square, MagicEntry]
var bishopMagics*: array[Square, MagicEntry]

var sharedRookAttackTable: ptr UncheckedArray[Bitboard]
var sharedBishopAttackTable: ptr UncheckedArray[Bitboard]

var rookAttackTable* {.threadvar.}: ptr UncheckedArray[Bitboard]
var bishopAttackTable* {.threadvar.}: ptr UncheckedArray[Bitboard]

var state: uint64 = 1804289383

proc randomU64(): uint64 =
  state = state xor (state shl 13)
  state = state xor (state shr 7)
  state = state xor (state shl 17)
  return state

proc randomU64FewBits(): uint64 =
  return randomU64() and randomU64() and randomU64()

proc getRookMask(sq: Square): Bitboard =
  var attacks: Bitboard = 0
  let r = rankOf(sq)
  let f = fileOf(sq)
  
  for r2 in r+1 .. 6: attacks.setBit(squareFromCoords(r2, f))
  for r2 in countdown(r-1, 1): attacks.setBit(squareFromCoords(r2, f))
  for f2 in f+1 .. 6: attacks.setBit(squareFromCoords(r, f2))
  for f2 in countdown(f-1, 1): attacks.setBit(squareFromCoords(r, f2))
  return attacks

proc getBishopMask(sq: Square): Bitboard =
  var attacks: Bitboard = 0
  let r = rankOf(sq)
  let f = fileOf(sq)
  
  var r2 = r + 1; var f2 = f + 1
  while r2 < 7 and f2 < 7: 
    attacks.setBit(squareFromCoords(r2, f2))
    inc(r2); inc(f2)
    
  r2 = r - 1; f2 = f + 1
  while r2 > 0 and f2 < 7:
    attacks.setBit(squareFromCoords(r2, f2))
    dec(r2); inc(f2)
    
  r2 = r + 1; f2 = f - 1
  while r2 < 7 and f2 > 0:
    attacks.setBit(squareFromCoords(r2, f2))
    inc(r2); dec(f2)
    
  r2 = r - 1; f2 = f - 1
  while r2 > 0 and f2 > 0:
    attacks.setBit(squareFromCoords(r2, f2))
    dec(r2); dec(f2)
    
  return attacks

proc indexToBitboard(index: int, mask: Bitboard): Bitboard =
  var bb: Bitboard = 0
  var m = mask
  var idx = index
  
  while m != 0:
    let sq = popBit(m)
    if (idx and 1) != 0:
      bb.setBit(sq)
    idx = idx shr 1
  return bb

proc rookAttacksSlow(sq: Square, occupancy: Bitboard): Bitboard =
  var attacks: Bitboard = 0
  let r = rankOf(sq)
  let f = fileOf(sq)
  
  for r2 in r+1 .. 7:
    attacks.setBit(squareFromCoords(r2, f))
    if occupancy.getBit(squareFromCoords(r2, f)): break
  for r2 in countdown(r-1, 0):
    attacks.setBit(squareFromCoords(r2, f))
    if occupancy.getBit(squareFromCoords(r2, f)): break
  for f2 in f+1 .. 7:
    attacks.setBit(squareFromCoords(r, f2))
    if occupancy.getBit(squareFromCoords(r, f2)): break
  for f2 in countdown(f-1, 0):
    attacks.setBit(squareFromCoords(r, f2))
    if occupancy.getBit(squareFromCoords(r, f2)): break
  return attacks

proc bishopAttacksSlow(sq: Square, occupancy: Bitboard): Bitboard =
  var attacks: Bitboard = 0
  let r = rankOf(sq)
  let f = fileOf(sq)
  
  var r2 = r + 1; var f2 = f + 1
  while r2 <= 7 and f2 <= 7:
    attacks.setBit(squareFromCoords(r2, f2))
    if occupancy.getBit(squareFromCoords(r2, f2)): break
    inc(r2); inc(f2)
    
  r2 = r - 1; f2 = f + 1
  while r2 >= 0 and f2 <= 7:
    attacks.setBit(squareFromCoords(r2, f2))
    if occupancy.getBit(squareFromCoords(r2, f2)): break
    dec(r2); inc(f2)
    
  r2 = r + 1; f2 = f - 1
  while r2 <= 7 and f2 >= 0:
    attacks.setBit(squareFromCoords(r2, f2))
    if occupancy.getBit(squareFromCoords(r2, f2)): break
    inc(r2); dec(f2)
    
  r2 = r - 1; f2 = f - 1
  while r2 >= 0 and f2 >= 0:
    attacks.setBit(squareFromCoords(r2, f2))
    if occupancy.getBit(squareFromCoords(r2, f2)): break
    dec(r2); dec(f2)
    
  return attacks

proc initMagicBitboards*() =
  # Initialize Rook Magics
  var currentOffset = 0
  sharedRookAttackTable = cast[ptr UncheckedArray[Bitboard]](allocShared0(sizeof(Bitboard) * 64 * 4096))
  rookAttackTable = sharedRookAttackTable # Set for main thread
  
  for sqInt in 0..63:
    let sq = sqInt.Square
    let mask = getRookMask(sq)
    let bits = countBits(mask)
    let permutations = 1 shl bits
    
    var occupancy: seq[Bitboard] = newSeq[Bitboard](permutations)
    var attacks: seq[Bitboard] = newSeq[Bitboard](permutations)
    
    for i in 0 ..< permutations:
      occupancy[i] = indexToBitboard(i, mask)
      attacks[i] = rookAttacksSlow(sq, occupancy[i])
      
    # Find Magic
    var found = false
    while not found:
      let magic = randomU64FewBits()
      if countBits((mask * magic) and 0xFF00000000000000'u64) < 6: continue
      
      var table: array[4096, Bitboard]
      var occupied: array[4096, bool]
      var fail = false
      
      let shift = 64 - bits
      
      for i in 0 ..< permutations:
        let idx = (occupancy[i] * magic) shr shift
        if occupied[idx]:
          if table[idx] != attacks[i]:
            fail = true
            break
        else:
          occupied[idx] = true
          table[idx] = attacks[i]
      
      if not fail:
        found = true
        rookMagics[sq].mask = mask
        rookMagics[sq].magic = magic
        rookMagics[sq].shift = shift
        rookMagics[sq].offset = currentOffset
        
        # Copy to global table
        for i in 0 ..< permutations:
          let idx = (occupancy[i] * magic) shr shift
          sharedRookAttackTable[currentOffset + idx.int] = attacks[i]
        
        currentOffset += (1 shl bits)
        
  # Initialize Bishop Magics
  currentOffset = 0
  sharedBishopAttackTable = cast[ptr UncheckedArray[Bitboard]](allocShared0(sizeof(Bitboard) * 64 * 512))
  bishopAttackTable = sharedBishopAttackTable # Set for main thread
  
  for sqInt in 0..63:
    let sq = sqInt.Square
    let mask = getBishopMask(sq)
    let bits = countBits(mask)
    let permutations = 1 shl bits
    
    var occupancy: seq[Bitboard] = newSeq[Bitboard](permutations)
    var attacks: seq[Bitboard] = newSeq[Bitboard](permutations)
    
    for i in 0 ..< permutations:
      occupancy[i] = indexToBitboard(i, mask)
      attacks[i] = bishopAttacksSlow(sq, occupancy[i])
      
    var found = false
    while not found:
      let magic = randomU64FewBits()
      if countBits((mask * magic) and 0xFF00000000000000'u64) < 6: continue
      
      var table: array[512, Bitboard]
      var occupied: array[512, bool]
      var fail = false
      
      let shift = 64 - bits
      
      for i in 0 ..< permutations:
        let idx = (occupancy[i] * magic) shr shift
        if occupied[idx]:
          if table[idx] != attacks[i]:
            fail = true
            break
        else:
          occupied[idx] = true
          table[idx] = attacks[i]
          
      if not fail:
        found = true
        bishopMagics[sq].mask = mask
        bishopMagics[sq].magic = magic
        bishopMagics[sq].shift = shift
        bishopMagics[sq].offset = currentOffset
        
        for i in 0 ..< permutations:
          let idx = (occupancy[i] * magic) shr shift
          sharedBishopAttackTable[currentOffset + idx.int] = attacks[i]
          
        currentOffset += (1 shl bits)

proc initThreadMagics*() =
  rookAttackTable = sharedRookAttackTable
  bishopAttackTable = sharedBishopAttackTable

proc getRookAttacks*(sq: Square, occ: Bitboard): Bitboard {.inline, gcsafe.} =
  let entry = rookMagics[sq]
  let idx = ((occ and entry.mask) * entry.magic) shr entry.shift
  return rookAttackTable[entry.offset + idx.int]

proc getBishopAttacks*(sq: Square, occ: Bitboard): Bitboard {.inline, gcsafe.} =
  let entry = bishopMagics[sq]
  let idx = ((occ and entry.mask) * entry.magic) shr entry.shift
  return bishopAttackTable[entry.offset + idx.int]

proc getQueenAttacks*(sq: Square, occ: Bitboard): Bitboard {.inline, gcsafe.} =
  return getRookAttacks(sq, occ) or getBishopAttacks(sq, occ)
