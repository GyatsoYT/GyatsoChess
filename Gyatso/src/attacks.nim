import coretypes
import bitboard

# BMI2 intrinsics
when defined(bmi2):
  {.passC: "-mbmi2".}
  func pext(a, mask: uint64): uint64
    {.importc: "_pext_u64", header: "immintrin.h", noSideEffect.}
  func pdep(a, mask: uint64): uint64
    {.importc: "_pdep_u64", header: "immintrin.h", noSideEffect.}

const knightAttacks*: array[64, Bitboard] = block:
  var tbl: array[64, Bitboard]
  for sq in 0..63:
    let r = sq div 8
    let f = sq mod 8
    var bb = Bitboard(0)
    let moves = [
      (-2, -1), (-2, 1), (-1, -2), (-1, 2),
      (1, -2), (1, 2), (2, -1), (2, 1)
    ]
    for m in moves:
      let nr = r + m[0]
      let nf = f + m[1]
      if nr >= 0 and nr <= 7 and nf >= 0 and nf <= 7:
        bb = bb or makeSquare(nr, nf).bit
    tbl[sq] = bb
  tbl

const kingAttacks*: array[64, Bitboard] = block:
  var tbl: array[64, Bitboard]
  for sq in 0..63:
    let r = sq div 8
    let f = sq mod 8
    var bb = Bitboard(0)
    let moves = [
      (-1, -1), (-1, 0), (-1, 1),
      (0, -1),           (0, 1),
      (1, -1),  (1, 0),  (1, 1)
    ]
    for m in moves:
      let nr = r + m[0]
      let nf = f + m[1]
      if nr >= 0 and nr <= 7 and nf >= 0 and nf <= 7:
        bb = bb or makeSquare(nr, nf).bit
    tbl[sq] = bb
  tbl

# pawnAttacks[White.ord][sq] = squares attacked by white pawn on sq
# pawnAttacks[Black.ord][sq] = squares attacked by black pawn on sq
const pawnAttacks*: array[2, array[64, Bitboard]] = block:
  var tbl: array[2, array[64, Bitboard]]
  for sq in 0..63:
    let bb = Square(sq).bit
    # White pawns (White = 0)
    let wAttacks = ((bb and not FileA) shl 7) or ((bb and not FileH) shl 9)
    tbl[0][sq] = wAttacks

    # Black pawns (Black = 1)
    let bAttacks = ((bb and not FileH) shr 7) or ((bb and not FileA) shr 9)
    tbl[1][sq] = bAttacks
  tbl

const diagonals*: array[64, Bitboard] = block:
  var tbl: array[64, Bitboard]
  for sq in 0..63:
    let r = sq div 8
    let f = sq mod 8
    var bb = Bitboard(0)
    for nr in 0..7:
      for nf in 0..7:
        if nr - nf == r - f:
          bb = bb or makeSquare(nr, nf).bit
    tbl[sq] = bb
  tbl

const antiDiagonals*: array[64, Bitboard] = block:
  var tbl: array[64, Bitboard]
  for sq in 0..63:
    let r = sq div 8
    let f = sq mod 8
    var bb = Bitboard(0)
    for nr in 0..7:
      for nf in 0..7:
        if nr + nf == r + f:
          bb = bb or makeSquare(nr, nf).bit
    tbl[sq] = bb
  tbl

const fileMasks*: array[64, Bitboard] = block:
  var tbl: array[64, Bitboard]
  for sq in 0..63:
    let f = sq mod 8
    tbl[sq] = fileMask(f)
  tbl

const rankMasks*: array[64, Bitboard] = block:
  var tbl: array[64, Bitboard]
  for sq in 0..63:
    let r = sq div 8
    tbl[sq] = rankMask(r)
  tbl

func getKnightAttacks*(sq: Square): Bitboard {.inline.} =
  knightAttacks[sq.int]

func getKingAttacks*(sq: Square): Bitboard {.inline.} =
  kingAttacks[sq.int]

func getPawnAttacks*(sq: Square, color: Color): Bitboard {.inline.} =
  pawnAttacks[color.ord][sq.int]

# Magic Bitboard
type MagicEntry* = object
  mask*:   Bitboard
  magic*:  uint64
  shift*:  int
  offset*: int

const rookShifts: array[64, int] = [
  52, 53, 53, 53, 53, 53, 53, 52,
  53, 54, 54, 54, 54, 54, 54, 53,
  53, 54, 54, 54, 54, 54, 54, 53,
  53, 54, 54, 54, 54, 54, 54, 53,
  53, 54, 54, 54, 54, 54, 54, 53,
  53, 54, 54, 54, 54, 54, 54, 53,
  53, 54, 54, 54, 54, 54, 54, 53,
  52, 53, 53, 53, 53, 53, 53, 52,
]

const bishopShifts: array[64, int] = [
  59, 60, 59, 59, 59, 59, 60, 58,
  60, 60, 59, 59, 59, 59, 60, 60,
  59, 59, 57, 57, 57, 57, 59, 59,
  59, 59, 57, 55, 55, 57, 59, 59,
  59, 59, 57, 55, 55, 57, 59, 59,
  59, 59, 57, 57, 57, 57, 59, 60,
  60, 60, 59, 59, 59, 59, 60, 60,
  59, 60, 59, 59, 59, 59, 60, 58,
]

const rookMagicNums: array[64, uint64] = [
  0x2080002040068490'u64, 0x06C0021001200C40'u64, 0x288009300280A000'u64, 0x0100089521003000'u64,
  0x6100040801003082'u64, 0x65FFEBC5FFEEE7F0'u64, 0x0400080C10219112'u64, 0x0200014434060003'u64,
  0x96CD8008C00379D9'u64, 0x2A06002101FF81CF'u64, 0x7BCA0020802E0641'u64, 0xDAE2FFEFFD0020BA'u64,
  0x62E20005E0D200AA'u64, 0x2302000830DA0044'u64, 0xE81C002CE40A3028'u64, 0xC829FFFAFD8BBC06'u64,
  0x12C57E800740089D'u64, 0xA574FDFFE13A81FD'u64, 0xF331B1FFE0BF79FE'u64, 0x0000A1003001010A'u64,
  0x7CD4E2000600264F'u64, 0x0299010004000228'u64, 0xA36CEBFFAE0FA825'u64, 0x9A87E9FFF4408405'u64,
  0x0BAEC0007FF8EB82'u64, 0xF81909BDFFE18205'u64, 0x0391AF45001FFF01'u64, 0xD000900100290021'u64,
  0x2058480080040080'u64, 0x6DCDFFA2002C38D0'u64, 0xC709C80C00951002'u64, 0xB70EE5420008FF84'u64,
  0x6E254003897FFCE6'u64, 0xD91D21FE7E003901'u64, 0xA0D1EFFF857FE001'u64, 0x7C45FFC022001893'u64,
  0x8180818800800400'u64, 0x2146001CB20018B0'u64, 0x843C20E7DBFF8FEE'u64, 0x09283C127A00083F'u64,
  0x01465F8CC0078000'u64, 0xA30A50075FFD3FFF'u64, 0x39593D8231FE0020'u64, 0x8129FE58405E000F'u64,
  0x1140850008010011'u64, 0x2302000830DA0044'u64, 0xD706971819F400B0'u64, 0xA0B2A3BC86E20004'u64,
  0x10FFF67AD3B88200'u64, 0x10FFF67AD3B88200'u64, 0x5076D15DBDF97E00'u64, 0xD861C0D1FFC8DE00'u64,
  0x5CA002003B305E00'u64, 0x84FFFFCF19605740'u64, 0xD26F0FA80A28AC00'u64, 0x342F7E87013BFA00'u64,
  0x63BB9E8FBF01FE7A'u64, 0x260ADF40007B9101'u64, 0x2013CEFF6000BEF7'u64, 0x13AD6200060EBFE6'u64,
  0x2D4DFFFF28F4D9FA'u64, 0x766200004B3A92F6'u64, 0xB6AE6FF7FE8A070C'u64, 0xD065F4839BFC4B02'u64,
]

const bishopMagicNums: array[64, uint64] = [
  0x69906270549A3405'u64, 0xE846197A0E88067F'u64, 0x54D7C7FB06DE5827'u64, 0xF4380209C8E966FE'u64,
  0xDF33F39ECD91FCF6'u64, 0xC580F3DFFCC85DB4'u64, 0xC6A89809B600286C'u64, 0xC1DE00D4289BFFC0'u64,
  0x7BDA249AC632C811'u64, 0x83534631B40CA406'u64, 0x6EA35817F035775C'u64, 0x6DB23BEF4DF5645E'u64,
  0x5555D3FB9F934CD3'u64, 0xE6766DFD0FC609F8'u64, 0xFC2EB0C6C58C8021'u64, 0x6786D25EACCFDF72'u64,
  0x86E8324A02CA8AEF'u64, 0xF91A13391D2D97F1'u64, 0x131810CFFD99BE90'u64, 0x8537F35C05EFA08B'u64,
  0x5D598243FF5FD71A'u64, 0x1D09FFBF00FAD72B'u64, 0xD16A319977FC05FD'u64, 0x8D6601E599347F90'u64,
  0x4404409F5EC1F3DB'u64, 0x25A7EC287E0BB817'u64, 0x22F9F7FF5AF54401'u64, 0x00200302080070E0'u64,
  0x3D1900D006FFC014'u64, 0x3958E700A5FEBEFB'u64, 0xD48AA0E6BBFC0214'u64, 0x56BBF68FC6CD5C13'u64,
  0xD4CFE69F216FF3C9'u64, 0xE46CEF960C704413'u64, 0x7985CEB00428057B'u64, 0x4900220082080080'u64,
  0x028422C010040100'u64, 0x119377F9FFF6BEEB'u64, 0x2787B8DA98AC0221'u64, 0xCF340AB7795DFC80'u64,
  0x5F4D27A008D84FE9'u64, 0x4339FF0FE25ED893'u64, 0x88F477A178045010'u64, 0x7B293EDFD1015806'u64,
  0x1F61DFF2047F5BFF'u64, 0xE2E1B97D1A009100'u64, 0x9C9F7BCC878F1A08'u64, 0xABFFCA859DA3CDFE'u64,
  0x1CD806CBB423E49B'u64, 0x5EE7FB86BD527D9B'u64, 0xBB0A8BC1EAB02192'u64, 0xB75E295A3FCE452C'u64,
  0x911D2E51E6060430'u64, 0x133E017175D1FB87'u64, 0xD7C00065234350D1'u64, 0x220029F586970AD8'u64,
  0xA6F001938E193FDB'u64, 0xDF725BF4FA4505B6'u64, 0xE5DE50FA3FDC8C72'u64, 0x3CE77ED6760FC3D0'u64,
  0x4CAD71659E41C408'u64, 0xE6766DFD0FC609F8'u64, 0x45D7FEA873649EA8'u64, 0xA8806CA2E576C9E4'u64,
]

proc slidingAttacksSlow(sq: Square, occ: Bitboard, dirs: openArray[(int, int)]): Bitboard =
  result = Bitboard(0)
  let r0 = sq.int div 8
  let f0 = sq.int mod 8
  for d in dirs:
    var r = r0 + d[0]
    var f = f0 + d[1]
    while r >= 0 and r <= 7 and f >= 0 and f <= 7:
      let target = makeSquare(r, f).bit
      result = result or target
      if (occ and target) != Bitboard(0):
        break
      r += d[0]
      f += d[1]

proc rookAttacksSlow(sq: Square, occ: Bitboard): Bitboard {.inline.} =
  slidingAttacksSlow(sq, occ, [(1,0),(-1,0),(0,1),(0,-1)])

proc bishopAttacksSlow(sq: Square, occ: Bitboard): Bitboard {.inline.} =
  slidingAttacksSlow(sq, occ, [(1,1),(1,-1),(-1,1),(-1,-1)])

iterator subsets(mask: Bitboard): Bitboard {.inline.} =
  var sub = Bitboard(0)
  while true:
    yield sub
    if sub == mask: break
    sub = (sub - mask) and mask

proc computeRookNegMask(sq: Square): Bitboard =
  result = AllSquares
  let r0 = sq.int div 8
  let f0 = sq.int mod 8
  for d in [(1,0),(-1,0),(0,1),(0,-1)]:
    var r = r0 + d[0]
    var f = f0 + d[1]
    while r >= 0 and r <= 7 and f >= 0 and f <= 7:
      let nextR = r + d[0]
      let nextF = f + d[1]
      if nextR >= 0 and nextR <= 7 and nextF >= 0 and nextF <= 7:
        result = result and not makeSquare(r, f).bit  # mark as relevant
      r = nextR
      f = nextF

proc computeBishopNegMask(sq: Square): Bitboard =
  result = AllSquares
  let r0 = sq.int div 8
  let f0 = sq.int mod 8
  for d in [(1,1),(1,-1),(-1,1),(-1,-1)]:
    var r = r0 + d[0]
    var f = f0 + d[1]
    while r >= 0 and r <= 7 and f >= 0 and f <= 7:
      let nextR = r + d[0]
      let nextF = f + d[1]
      if nextR >= 0 and nextR <= 7 and nextF >= 0 and nextF <= 7:
        result = result and not makeSquare(r, f).bit
      r = nextR
      f = nextF

const rookTableSize = block:
  var total = 0
  for sq in 0..63:
    total += 1 shl (64 - rookShifts[sq])
  total

const bishopTableSize = block:
  var total = 0
  for sq in 0..63:
    total += 1 shl (64 - bishopShifts[sq])
  total

var rookMagics*:   array[64, MagicEntry]
var bishopMagics*: array[64, MagicEntry]

var gRookAttackTable:   ptr UncheckedArray[Bitboard]
var gBishopAttackTable: ptr UncheckedArray[Bitboard]

var rookAttacks*   {.threadvar.}: ptr UncheckedArray[Bitboard]
var bishopAttacks* {.threadvar.}: ptr UncheckedArray[Bitboard]

proc initThreadAttacks*() {.inline.} =
  rookAttacks   = gRookAttackTable
  bishopAttacks = gBishopAttackTable

var rayBetweenTable: array[64, array[64, Bitboard]]
var rayPastTable:    array[64, array[64, Bitboard]]

proc initRays() =
  for a in 0..63:
    for b in 0..63:
      if a == b: continue
      let sb = Square(b)
      let ar = a div 8; let af = a mod 8
      let br = b div 8; let bf = b mod 8
      let dr = br - ar; let df = bf - af
      # Check if on same rank, file, diagonal, or antidiagonal
      if ar == br or af == bf or
         (dr == df) or (dr == -df):
        let stepR = if dr == 0: 0 elif dr > 0: 1 else: -1
        let stepF = if df == 0: 0 elif df > 0: 1 else: -1
        var between = Bitboard(0)
        var past    = Bitboard(0)
        var r = ar + stepR
        var f = af + stepF
        var reachedB = false
        while r >= 0 and r <= 7 and f >= 0 and f <= 7:
          let sq = makeSquare(r, f)
          if sq == sb:
            reachedB = true
          elif not reachedB:
            between = between or sq.bit
          else:
            past = past or sq.bit
          r += stepR
          f += stepF
        rayBetweenTable[a][b] = between
        rayPastTable[a][b]    = past

proc initMagics*() =
  # Allocate shared attack tables
  gRookAttackTable   = cast[ptr UncheckedArray[Bitboard]](
    allocShared0(rookTableSize * sizeof(Bitboard)))
  gBishopAttackTable = cast[ptr UncheckedArray[Bitboard]](
    allocShared0(bishopTableSize * sizeof(Bitboard)))

  # Build rook magic entries and fill table
  var rookOffset = 0
  for sq in 0..63:
    let s = Square(sq)
    let negMask = computeRookNegMask(s)
    rookMagics[sq] = MagicEntry(
      mask:   negMask,
      magic:  rookMagicNums[sq],
      shift:  rookShifts[sq],
      offset: rookOffset
    )
    let relMask = not negMask and not s.bit
    for occ in subsets(relMask):
      let attacks = rookAttacksSlow(s, occ)
      let idx = system.int((occ.uint64 or negMask.uint64) * rookMagicNums[sq] shr rookShifts[sq])
      gRookAttackTable[rookOffset + idx] = attacks
    rookOffset += 1 shl (64 - rookShifts[sq])

  # Build bishop magic entries and fill table
  var bishopOffset = 0
  for sq in 0..63:
    let s = Square(sq)
    let negMask = computeBishopNegMask(s)
    bishopMagics[sq] = MagicEntry(
      mask:   negMask,
      magic:  bishopMagicNums[sq],
      shift:  bishopShifts[sq],
      offset: bishopOffset
    )
    let relMask = not negMask and not s.bit
    for occ in subsets(relMask):
      let attacks = bishopAttacksSlow(s, occ)
      let idx = system.int((occ.uint64 or negMask.uint64) * bishopMagicNums[sq] shr bishopShifts[sq])
      gBishopAttackTable[bishopOffset + idx] = attacks
    bishopOffset += 1 shl (64 - bishopShifts[sq])

  # Set thread-local pointers for the main thread
  initThreadAttacks()

# Magic lookups
proc getRookAttacksMagic(sq: Square, occ: Bitboard): Bitboard {.inline.} =
  let e = rookMagics[sq.int]
  rookAttacks[e.offset + system.int((occ.uint64 or e.mask.uint64) * e.magic shr e.shift)]

proc getBishopAttacksMagic(sq: Square, occ: Bitboard): Bitboard {.inline.} =
  let e = bishopMagics[sq.int]
  bishopAttacks[e.offset + system.int((occ.uint64 or e.mask.uint64) * e.magic shr e.shift)]

# BMI2 data structures and tables
type
  RookBmi2Entry = object
    srcMask: Bitboard
    dstMask: Bitboard
    offset:  int

  BishopBmi2Entry = object
    mask:   Bitboard
    offset: int

# Per-square metadata arrays
var rookBmi2*:   array[64, RookBmi2Entry]
var bishopBmi2*: array[64, BishopBmi2Entry]

# Flat attack storage
var gRookBmi2Table*:   ptr UncheckedArray[uint16]
var gBishopBmi2Table*: ptr UncheckedArray[Bitboard]

proc initBmi2*() =
  var rookTableSizeBmi2   = 0
  var bishopTableSizeBmi2 = 0

  for sq in 0..63:
    var src = Bitboard(0)
    var dst = Bitboard(0)
    let r0 = sq div 8
    let f0 = sq mod 8
    for d in [(1,0),(-1,0),(0,1),(0,-1)]:
      var r = r0 + d[0]
      var f = f0 + d[1]
      while r >= 0 and r <= 7 and f >= 0 and f <= 7:
        let target = makeSquare(r, f).bit
        dst = dst or target
        let nr = r + d[0]; let nf = f + d[1]
        if nr >= 0 and nr <= 7 and nf >= 0 and nf <= 7:
          src = src or target
        r += d[0]; f += d[1]
    rookBmi2[sq] = RookBmi2Entry(
      srcMask: src,
      dstMask: dst,
      offset:  rookTableSizeBmi2
    )
    rookTableSizeBmi2 += 1 shl src.popcount()

    var bmask = Bitboard(0)
    for d in [(1,1),(1,-1),(-1,1),(-1,-1)]:
      var r = r0 + d[0]
      var f = f0 + d[1]
      while r >= 0 and r <= 7 and f >= 0 and f <= 7:
        let target = makeSquare(r, f).bit
        let nr = r + d[0]; let nf = f + d[1]
        if nr >= 0 and nr <= 7 and nf >= 0 and nf <= 7:
          bmask = bmask or target
        r += d[0]; f += d[1]
    bishopBmi2[sq] = BishopBmi2Entry(
      mask:   bmask,
      offset: bishopTableSizeBmi2
    )
    bishopTableSizeBmi2 += 1 shl bmask.popcount()

  gRookBmi2Table = cast[ptr UncheckedArray[uint16]](
    allocShared0(rookTableSizeBmi2 * sizeof(uint16)))
  gBishopBmi2Table = cast[ptr UncheckedArray[Bitboard]](
    allocShared0(bishopTableSizeBmi2 * sizeof(Bitboard)))

  when defined(bmi2):
    for sq in 0..63:
      let s   = Square(sq)
      let e   = rookBmi2[sq]
      let cnt = e.srcMask.popcount()
      let entries = 1 shl cnt
      for i in 0 ..< entries:
        let occ        = Bitboard(pdep(cast[uint64](i), e.srcMask.uint64))
        let attacks    = rookAttacksSlow(s, occ)
        let compressed = pext(attacks.uint64, e.dstMask.uint64)
        gRookBmi2Table[e.offset + i] = cast[uint16](compressed)

    for sq in 0..63:
      let s   = Square(sq)
      let e   = bishopBmi2[sq]
      let cnt = e.mask.popcount()
      let entries = 1 shl cnt
      for i in 0 ..< entries:
        let occ = Bitboard(pdep(cast[uint64](i), e.mask.uint64))
        gBishopBmi2Table[e.offset + i] = bishopAttacksSlow(s, occ)

when defined(bmi2):
  proc getRookAttacksBmi2(sq: Square, occ: Bitboard): Bitboard {.inline.} =
    let e   = rookBmi2[sq.int]
    let idx = pext(occ.uint64, e.srcMask.uint64)
    Bitboard(pdep(cast[uint64](gRookBmi2Table[e.offset + system.int(idx)]), e.dstMask.uint64))

  proc getBishopAttacksBmi2(sq: Square, occ: Bitboard): Bitboard {.inline.} =
    let e   = bishopBmi2[sq.int]
    let idx = pext(occ.uint64, e.mask.uint64)
    gBishopBmi2Table[e.offset + system.int(idx)]

proc getRookAttacks*(sq: Square, occ: Bitboard): Bitboard {.inline.} =
  when defined(bmi2): getRookAttacksBmi2(sq, occ)
  else:               getRookAttacksMagic(sq, occ)

proc getBishopAttacks*(sq: Square, occ: Bitboard): Bitboard {.inline.} =
  when defined(bmi2): getBishopAttacksBmi2(sq, occ)
  else:               getBishopAttacksMagic(sq, occ)

proc getQueenAttacks*(sq: Square, occ: Bitboard): Bitboard {.inline.} =
  getRookAttacks(sq, occ) or getBishopAttacks(sq, occ)

proc initAttacks*() =
  initRays()
  when defined(bmi2): initBmi2()
  else:               initMagics()

proc rayBetween*(a, b: Square): Bitboard {.inline.} =
  rayBetweenTable[a.int][b.int]

proc rayPast*(king, piece: Square): Bitboard {.inline.} =
  rayPastTable[king.int][piece.int]

