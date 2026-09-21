import coretypes
import board
import bitboard
type
  PackedBoard* {.packed.} = object
    occupied*:  uint64
    pieces*:    array[16, uint8]
    stmEp*:     uint8
    halfmove*:  uint8
    fullmove*:  uint16
    score*:     int16
    wdl*:       uint8
    extra*:     uint8

static:
  doAssert sizeof(PackedBoard) == 32, "PackedBoard must be exactly 32 bytes"
type
  ViriBuffer* = object
    buf*: seq[byte]

proc reset*(vb: var ViriBuffer) {.inline.} =
  if vb.buf.len == 0:
    vb.buf = newSeqOfCap[byte](32 + 512 * 4 + 4)
  else:
    vb.buf.setLen(0)

proc rookHasCastlingRights*(b: Board; sq: Square; color: Color): bool {.inline.} =
  if color == White:
    return b.castlingRooks.wk == sq or b.castlingRooks.wq == sq
  else:
    return b.castlingRooks.bk == sq or b.castlingRooks.bq == sq

proc writeBoard*(vb: var ViriBuffer; b: Board;
                 halfmoveClock: int = -1; fullmoveCounter: int = -1) =
  var pb: array[32, byte]

  let occ = b.occupied.uint64
  copyMem(addr pb[0], unsafeAddr occ, 8)

  var occVar = b.occupied
  var idx = 0
  while not occVar.isEmpty():
    let sq    = occVar.lsb()
    occVar    = occVar and (occVar - Bitboard(1))
    let piece = b.mailbox[sq.int]

    var typ: uint8 = case piece.pieceType
      of Pawn:   0'u8
      of Knight: 1'u8
      of Bishop: 2'u8
      of Rook:   3'u8
      of Queen:  4'u8
      of King:   5'u8
      else:      0'u8

    if piece.pieceType == Rook and rookHasCastlingRights(b, sq, piece.color):
      typ = 6'u8

    var nibble = typ
    if piece.color == Black: nibble = nibble or 8'u8

    let byteIdx = 8 + (idx shr 1)
    if (idx and 1) == 0:
      pb[byteIdx] = nibble                          # low nibble
    else:
      pb[byteIdx] = pb[byteIdx] or (nibble shl 4)  # high nibble
    inc idx

  var ep: uint8 = if b.epSquare == NoSquare: 64'u8 else: uint8(b.epSquare.int)
  pb[24] = ep and 0x7F'u8
  if b.stm == Black: pb[24] = pb[24] or 0x80'u8

  pb[25] = if halfmoveClock >= 0: uint8(min(halfmoveClock, 255)) else: b.halfmove

  var fm = if fullmoveCounter >= 0: uint16(fullmoveCounter) else: b.fullmove
  copyMem(addr pb[26], addr fm, 2)

  let oldLen = vb.buf.len
  vb.buf.setLen(oldLen + 32)
  copyMem(addr vb.buf[oldLen], addr pb[0], 32)

proc writeMoveEval*(vb: var ViriBuffer; m: Move; evalWhiteRel: int) =
  var vType:  uint16 = 0
  var vPromo: uint16 = 0

  let mt     = m.moveType()
  let fromSq = m.fromSq()
  var toSq   = m.toSq()

  case mt
  of EnPassant:
    vType = 1
  of Castling:
    vType = 2
    let rookSq = toSq
    toSq = if fromSq.file < rookSq.file: fromSq.withFile(5) else: fromSq.withFile(3)
  of Promotion:
    vType = 3
    vPromo = case m.promoType()
      of PromoKnight: 0'u16
      of PromoBishop: 1'u16
      of PromoRook:   2'u16
      of PromoQueen:  3'u16
  of Normal:
    discard

  let vMove  = uint16(fromSq.int) or
               (uint16(toSq.int) shl 6) or
               (vPromo shl 12) or
               (vType  shl 14)

  let vScore = int16(clamp(evalWhiteRel, -32000, 32000))

  var b4: array[4, byte]
  copyMem(addr b4[0], unsafeAddr vMove,  2)
  copyMem(addr b4[2], unsafeAddr vScore, 2)
  let oldLen = vb.buf.len
  vb.buf.setLen(oldLen + 4)
  copyMem(addr vb.buf[oldLen], addr b4[0], 4)

proc patchWdl*(vb: var ViriBuffer; wdl: uint8) =
  if vb.buf.len >= 32:
    vb.buf[30] = wdl
  let oldLen = vb.buf.len
  vb.buf.setLen(oldLen + 4)
  zeroMem(addr vb.buf[oldLen], 4)

