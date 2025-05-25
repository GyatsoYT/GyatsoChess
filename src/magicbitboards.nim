import coretypes, bitboard, utils, system, std/bitops

# Constants for mask generation
const
  FileABB = 0x0101010101010101'u64
  FileBBB = 0x0202020202020202'u64
  FileGBB = 0x4040404040404040'u64
  FileHBB = 0x8080808080808080'u64
  Rank1BB = 0x00000000000000FF'u64
  Rank2BB = 0x000000000000FF00'u64
  Rank7BB = 0x00FF000000000000'u64
  Rank8BB = 0xFF00000000000000'u64

type
  MagicEntryRook* = object
    mask*: Bitboard
    magic*: uint64
    attacks*: ptr UncheckedArray[Bitboard]
    shift*: int

var
  rookMagicsTable*: array[Square, MagicEntryRook]

# Precomputed magic numbers and shifts for rooks.
# Shifts are typically 64 - (number of relevant bits in the mask).
# These values are standard and widely used (e.g., from Stockfish/CPW).
const RookMagicNumbers: array[Square, uint64] = [
    0x0080001020400080'u64, 0x0040001000200040'u64, 0x0080081000200080'u64, 0x0080040800100080'u64,
    0x0080020400080080'u64, 0x0080010200040080'u64, 0x0080008001000200'u64, 0x0080002040800100'u64,
    0x0000800020400080'u64, 0x0000400020005000'u64, 0x0000801000200080'u64, 0x0000800800100080'u64,
    0x0000800400080080'u64, 0x0000800200040080'u64, 0x0000800100020080'u64, 0x0000800040800100'u64,
    0x0000208000400080'u64, 0x0000404000201000'u64, 0x0000808010002000'u64, 0x0000808008001000'u64,
    0x0000808004000800'u64, 0x0000808002000400'u64, 0x0000010100020004'u64, 0x0000020000408104'u64,
    0x0000208080004000'u64, 0x0000200040005000'u64, 0x0000100080200080'u64, 0x0000080080100080'u64,
    0x0000040080080080'u64, 0x0000020080040080'u64, 0x0000010080800200'u64, 0x0000800080004100'u64,
    0x0000204000800080'u64, 0x0000200040401000'u64, 0x0000100080802000'u64, 0x0000080080801000'u64,
    0x0000040080800800'u64, 0x0000020080800400'u64, 0x0000020001010004'u64, 0x0000800040800100'u64,
    0x0000204000808000'u64, 0x0000200040008080'u64, 0x0000100020008080'u64, 0x0000080010008080'u64,
    0x0000040008008080'u64, 0x0000020004008080'u64, 0x0000010002008080'u64, 0x0000004081020004'u64,
    0x0000204000800080'u64, 0x0000200040008080'u64, 0x0000100020008080'u64, 0x0000080010008080'u64,
    0x0000040008008080'u64, 0x0000020004008080'u64, 0x0000800100020080'u64, 0x0000800041000080'u64,
    0x00FFFCDDFCED714A'u64, 0x007FFCDDFCED714A'u64, 0x003FFFCDFFD88096'u64, 0x0000040810002101'u64,
    0x0001000204080011'u64, 0x0001000204000801'u64, 0x0001000082000401'u64, 0x0001FFFAABFAD1A2'u64
]

# const RookShifts: array[Square, int] = [ # These are (64 - relevant_bits) # REMOVED
#   52, 53, 54, 55, 55, 54, 53, 52,
#   53, 53, 54, 55, 55, 54, 53, 53,
#   54, 54, 54, 55, 55, 54, 54, 54,
#   55, 55, 55, 55, 55, 55, 55, 55,
#   55, 55, 55, 55, 55, 55, 55, 55,
#   54, 54, 54, 55, 55, 54, 54, 54,
#   53, 53, 54, 55, 55, 54, 53, 53,
#   52, 53, 54, 55, 55, 54, 53, 52
# ]


proc rookBlockerMask(sq: Square): Bitboard =
  result = 0'u64
  let r = rankOf(sq)
  let f = fileOf(sq)
  # North
  for i in 1..<7-r: setBit(result, squareFromCoords(r+i, f))
  # South
  for i in 1..<r:   setBit(result, squareFromCoords(r-i, f))
  # East
  for i in 1..<7-f: setBit(result, squareFromCoords(r, f+i))
  # West
  for i in 1..<f:   setBit(result, squareFromCoords(r, f-i))

proc calculateRookAttacksOnTheFly(sq: Square, occupied: Bitboard): Bitboard =
  result = 0'u64
  let r = rankOf(sq)
  let f = fileOf(sq)

  # North
  for nr in (r + 1)..7:
    let currentSq = squareFromCoords(nr, f)
    setBit(result, currentSq)
    if getBit(occupied, currentSq): break
  # South
  for nr in countdown(r - 1, 0):
    let currentSq = squareFromCoords(nr, f)
    setBit(result, currentSq)
    if getBit(occupied, currentSq): break
  # East
  for nf in (f + 1)..7:
    let currentSq = squareFromCoords(r, nf)
    setBit(result, currentSq)
    if getBit(occupied, currentSq): break
  # West
  for nf in countdown(f - 1, 0):
    let currentSq = squareFromCoords(r, nf)
    setBit(result, currentSq)
    if getBit(occupied, currentSq): break

proc initRookMagics*() =
  for sVal in 0..63:
    let sq = Square(sVal)
    let entry = addr rookMagicsTable[sq]
    
    entry.mask = rookBlockerMask(sq)
    entry.magic = RookMagicNumbers[sq]
    # entry.shift = RookShifts[sq] # Removed: Shift will be calculated dynamically

    let numMaskBits = popcount(entry.mask)
    entry.shift = 64 - numMaskBits
    
    let relevantBits = numMaskBits # Simplified: 64 - (64 - numMaskBits) = numMaskBits
    
    let attackTableSize = 1 shl relevantBits
    
    entry.attacks = cast[ptr UncheckedArray[Bitboard]](alloc0(attackTableSize * sizeof(Bitboard)))
    if entry.attacks == nil:
      quit("Error: Failed to allocate memory for rook magic attacks table for square " & $sq, 1)

    var tempMaskPop = entry.mask
    var maskSquares = newSeq[Square]()
    while tempMaskPop != 0:
      maskSquares.add(popBit(tempMaskPop))

    for i in 0 ..< attackTableSize:
      var currentOccupancy: Bitboard = 0
      for bitIdx in 0 ..< maskSquares.len:
        if (((i shr bitIdx) and 1) != 0):
          setBit(currentOccupancy, maskSquares[bitIdx])
      
      let attacks = calculateRookAttacksOnTheFly(sq, currentOccupancy)
      let magicIndex = ((currentOccupancy and entry.mask) * entry.magic) shr entry.shift
      
      if magicIndex.int >= attackTableSize:
          quit("Error: Magic index out of bounds for rook on square " & $sq & ". Index: " & $magicIndex & ", Table Size: " & $attackTableSize, 1)

      entry.attacks[magicIndex.int] = attacks

proc deinitRookMagics*() =
  for sVal in 0..63:
    let sq = Square(sVal)
    if rookMagicsTable[sq].attacks != nil:
      dealloc(rookMagicsTable[sq].attacks)
      rookMagicsTable[sq].attacks = nil

proc getRookAttacks*(sq: Square, occupied: Bitboard): Bitboard =
  let entry = rookMagicsTable[sq]
  let blockersOnMask = occupied and entry.mask
  let magicIndex = (blockersOnMask * entry.magic) shr entry.shift
  if entry.attacks == nil:
    quit("Error: Rook attacks table not initialized for square " & $sq, 1)
  return entry.attacks[magicIndex.int]

# It's good practice to call initRookMagics at engine startup
# and deinitRookMagics at shutdown. 

# --- Bishop Magic Bitboards ---

type
  MagicEntryBishop* = object
    mask*: Bitboard
    magic*: uint64
    attacks*: ptr UncheckedArray[Bitboard]
    shift*: int

var
  bishopMagicsTable*: array[Square, MagicEntryBishop]

# Precomputed magic numbers and shifts for bishops.
# These values are standard and widely used.
const BishopMagicNumbers: array[Square, uint64] = [
    0x0002020202020200'u64, 0x0002020202020000'u64, 0x0004010202000000'u64, 0x0004040080000000'u64,
    0x0001104000000000'u64, 0x0000821040000000'u64, 0x0000410410400000'u64, 0x0000104104104000'u64,
    0x0000040404040400'u64, 0x0000020202020200'u64, 0x0000040102020000'u64, 0x0000040400800000'u64,
    0x0000011040000000'u64, 0x0000008210400000'u64, 0x0000004104104000'u64, 0x0000002082082000'u64,
    0x0004000808080800'u64, 0x0002000404040400'u64, 0x0001000202020200'u64, 0x0000800802004000'u64,
    0x0000800400A00000'u64, 0x0000200100884000'u64, 0x0000400082082000'u64, 0x0000200041041000'u64,
    0x0002080010101000'u64, 0x0001040008080800'u64, 0x0000208004010400'u64, 0x0000404004010200'u64,
    0x0000840000802000'u64, 0x0000404002011000'u64, 0x0000808001041000'u64, 0x0000404000820800'u64,
    0x0001041000202000'u64, 0x0000820800101000'u64, 0x0000104400080800'u64, 0x0000020080080080'u64,
    0x0000404040040100'u64, 0x0000808100020100'u64, 0x0001010100020800'u64, 0x0000808080010400'u64,
    0x0000820820004000'u64, 0x0000410410002000'u64, 0x0000082088001000'u64, 0x0000002011000800'u64,
    0x0000080100400400'u64, 0x0001010101000200'u64, 0x0002020202000400'u64, 0x0001010101000200'u64,
    0x0000410410400000'u64, 0x0000208208200000'u64, 0x0000002084100000'u64, 0x0000000020880000'u64,
    0x0000001002020000'u64, 0x0000040408020000'u64, 0x0004040404040000'u64, 0x0002020202020000'u64,
    0x0000104104104000'u64, 0x0000002082082000'u64, 0x0000000020841000'u64, 0x0000000000208800'u64,
    0x0000000010020200'u64, 0x000000000404080200'u64, 0x0000040404040400'u64, 0x0002020202020200'u64
]

# const BishopShifts: array[Square, int] = [ # 64 - relevant_bits # REMOVED
#   58, 59, 59, 59, 59, 59, 59, 58,
#   59, 59, 59, 59, 59, 59, 59, 59,
#   59, 59, 57, 57, 57, 57, 59, 59,
#   59, 59, 57, 55, 55, 57, 59, 59,
#   59, 59, 57, 55, 55, 57, 59, 59,
#   59, 59, 57, 57, 57, 57, 59, 59,
#   59, 59, 59, 59, 59, 59, 59, 59,
#   58, 59, 59, 59, 59, 59, 59, 58
# ]

proc bishopBlockerMask(sq: Square): Bitboard =
  result = 0'u64
  let r = rankOf(sq)
  let f = fileOf(sq)
  # NorthEast
  var tr = r + 1; var tf = f + 1
  while tr < 7 and tf < 7: setBit(result, squareFromCoords(tr, tf)); tr += 1; tf += 1
  # SouthEast
  tr = r - 1; tf = f + 1
  while tr > 0 and tf < 7: setBit(result, squareFromCoords(tr, tf)); tr -= 1; tf += 1
  # SouthWest
  tr = r - 1; tf = f - 1
  while tr > 0 and tf > 0: setBit(result, squareFromCoords(tr, tf)); tr -= 1; tf -= 1
  # NorthWest
  tr = r + 1; tf = f - 1
  while tr < 7 and tf > 0: setBit(result, squareFromCoords(tr, tf)); tr += 1; tf -= 1

proc calculateBishopAttacksOnTheFly(sq: Square, occupied: Bitboard): Bitboard =
  result = 0'u64
  let r = rankOf(sq)
  let f = fileOf(sq)
  var tr, tf: int

  # NorthEast
  tr = r + 1; tf = f + 1
  while tr <= 7 and tf <= 7:
    let currentSq = squareFromCoords(tr, tf)
    setBit(result, currentSq)
    if getBit(occupied, currentSq): break
    tr += 1; tf += 1
  # SouthEast
  tr = r - 1; tf = f + 1
  while tr >= 0 and tf <= 7:
    let currentSq = squareFromCoords(tr, tf)
    setBit(result, currentSq)
    if getBit(occupied, currentSq): break
    tr -= 1; tf += 1
  # SouthWest
  tr = r - 1; tf = f - 1
  while tr >= 0 and tf >= 0:
    let currentSq = squareFromCoords(tr, tf)
    setBit(result, currentSq)
    if getBit(occupied, currentSq): break
    tr -= 1; tf -= 1
  # NorthWest
  tr = r + 1; tf = f - 1
  while tr <= 7 and tf >= 0:
    let currentSq = squareFromCoords(tr, tf)
    setBit(result, currentSq)
    if getBit(occupied, currentSq): break
    tr += 1; tf -= 1

proc initBishopMagics*() =
  for sVal in 0..63:
    let sq = Square(sVal)
    let entry = addr bishopMagicsTable[sq]

    entry.mask = bishopBlockerMask(sq)
    entry.magic = BishopMagicNumbers[sq]
    # entry.shift = BishopShifts[sq] # Removed: Shift will be calculated dynamically

    let numMaskBits = popcount(entry.mask)
    entry.shift = 64 - numMaskBits

    let relevantBits = numMaskBits # Simplified: 64 - (64 - numMaskBits) = numMaskBits

    let attackTableSize = 1 shl relevantBits

    entry.attacks = cast[ptr UncheckedArray[Bitboard]](alloc0(attackTableSize * sizeof(Bitboard)))
    if entry.attacks == nil:
      quit("Error: Failed to allocate memory for bishop magic attacks table for square " & $sq, 1)

    var tempMaskPop = entry.mask
    var maskSquares = newSeq[Square]()
    while tempMaskPop != 0:
      maskSquares.add(popBit(tempMaskPop))

    for i in 0 ..< attackTableSize:
      var currentOccupancy: Bitboard = 0
      for bitIdx in 0 ..< maskSquares.len:
        if (((i shr bitIdx) and 1) != 0):
          setBit(currentOccupancy, maskSquares[bitIdx])
      
      let attacks = calculateBishopAttacksOnTheFly(sq, currentOccupancy)
      let magicIndex = ((currentOccupancy * entry.magic) shr entry.shift)
      
      if magicIndex.int >= attackTableSize:
          quit("Error: Magic index out of bounds for bishop on square " & $sq & ". Index: " & $magicIndex & ", Table Size: " & $attackTableSize, 1)
      if entry.attacks[magicIndex.int] != 0'u64 and entry.attacks[magicIndex.int] != attacks:
        quit("Magic collision detected for bishop on square " & $sq & 
             " at index " & $magicIndex.int & ". Occupancy: " & $currentOccupancy &
             ". Original attacks: " & $entry.attacks[magicIndex.int] &
             ", New conflicting attacks: " & $attacks, 1)
      entry.attacks[magicIndex.int] = attacks

proc deinitBishopMagics*() =
  for sVal in 0..63:
    let sq = Square(sVal)
    if bishopMagicsTable[sq].attacks != nil:
      dealloc(bishopMagicsTable[sq].attacks)
      bishopMagicsTable[sq].attacks = nil

proc getBishopAttacks*(sq: Square, occupied: Bitboard): Bitboard =
  let entry = bishopMagicsTable[sq]
  let blockersOnMask = occupied and entry.mask
  let magicIndex = (blockersOnMask * entry.magic) shr entry.shift
  if entry.attacks == nil:
    quit("Error: Bishop attacks table not initialized for square " & $sq, 1)
  return entry.attacks[magicIndex.int]

proc getQueenAttacks*(sq: Square, occupied: Bitboard): Bitboard =
  ## Combines rook and bishop attacks for a queen on the given square.
  result = getRookAttacks(sq, occupied) or getBishopAttacks(sq, occupied)

# It's good practice to call initBishopMagics at engine startup
# and deinitBishopMagics at shutdown. 