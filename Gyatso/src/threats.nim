import std/bitops
import coretypes, bitboard, attacks, board

const HALF_THREATS* = 29904

const ValidThreatTargetMask*: array[5, uint8] = [
    (1'u8 shl Knight.ord) or (1'u8 shl Rook.ord), # Pawn: 10
    (1'u8 shl Pawn.ord) or (1'u8 shl Knight.ord) or (1'u8 shl Bishop.ord) or (1'u8 shl Rook.ord) or (1'u8 shl Queen.ord), # Knight: 31
    (1'u8 shl Pawn.ord) or (1'u8 shl Knight.ord) or (1'u8 shl Bishop.ord) or (1'u8 shl Rook.ord), # Bishop: 15
    (1'u8 shl Pawn.ord) or (1'u8 shl Knight.ord) or (1'u8 shl Bishop.ord) or (1'u8 shl Rook.ord), # Rook: 15
    (1'u8 shl Pawn.ord) or (1'u8 shl Knight.ord) or (1'u8 shl Bishop.ord) or (1'u8 shl Rook.ord) or (1'u8 shl Queen.ord)  # Queen: 31
]

var
  thAtt: array[4, array[64, uint64]]
  thRank: array[4, array[64, array[64, uint8]]]
  thBase: array[4, array[64, int32]]
  thCount: array[4, int32]
  thClassOff: array[4, int32]
  thTarget: array[4, array[12, int]]
  pawnTarget: array[12, int]
  thTargetOff: array[4, array[12, int32]]
  pawnTargetOff: array[12, int32]
  pawnSqOffset: array[64, int32] = block:
    var tbl: array[64, int32]
    for s in 0 ..< 64:
      tbl[s] = int32(((s shr 3) - 1) * 14 + 2 * (s and 7) - 1)
    tbl

proc makeTargets(valid: openArray[int]): array[12, int] =
  for i in 0 ..< 12: result[i] = -1
  for i, v in valid:
    result[v] = i
    result[v + 6] = i + valid.len

proc initThreats*() =
  for t in 0 ..< 4:
    var running = 0'i32
    for s in 0 ..< 64:
      let sq = Square(s)
      thAtt[t][s] = case t
        of 0: getKnightAttacks(sq).uint64
        of 1: getBishopAttacks(sq, Bitboard(0)).uint64
        of 2: getRookAttacks(sq, Bitboard(0)).uint64
        else: getQueenAttacks(sq, Bitboard(0)).uint64
      thBase[t][s] = running
      for d in 0 ..< 64:
        thRank[t][s][d] = uint8(countSetBits(thAtt[t][s] and ((1'u64 shl d) - 1)))
      running += int32(countSetBits(thAtt[t][s]))
    thCount[t] = running

  thTarget[0] = makeTargets([0, 1, 2, 3, 4])
  thTarget[1] = makeTargets([0, 1, 2, 3])
  thTarget[2] = makeTargets([0, 1, 2, 3])
  thTarget[3] = makeTargets([0, 1, 2, 3, 4])

  pawnTarget = makeTargets([1, 3])

  var off = int32(4 * 84)
  let classes = [10'i32, 8, 8, 10]
  for t in 0 ..< 4:
    thClassOff[t] = off
    off += classes[t] * thCount[t]
  doAssert off == HALF_THREATS, "Threat offset mismatch: " & $off & " != " & $HALF_THREATS

  for t in 0 ..< 4:
    for rel in 0 ..< 12:
      let cls = thTarget[t][rel]
      thTargetOff[t][rel] = if cls < 0: -1'i32 else: thClassOff[t] + int32(cls) * thCount[t]

  for rel in 0 ..< 12:
    let cls = pawnTarget[rel]
    pawnTargetOff[rel] = if cls < 0: -1'i32 else: int32(cls * 84)

proc threatIndex*(attType: int, attFriendly: bool, flip: int,
                  src, dst: int, relTgt: int): int {.inline.} =
  let s = src xor flip
  let d = dst xor flip
  let side = if attFriendly: 0 else: HALF_THREATS

  if attType == 0: # Pawn
    let pOff = pawnTargetOff[relTgt]
    let ident = ord((d and 7) > (s and 7))
    return side + system.int(pOff) + system.int(pawnSqOffset[s]) + ident

  let t = attType - 1
  if d > s and (relTgt mod 6) == attType: return -1
  let targetOff = thTargetOff[t][relTgt]
  side + system.int(targetOff) + system.int(thBase[t][s]) + system.int(thRank[t][s][d])

proc threatIndexDual*(e: uint32,
                      flipW, flipB: int,
                      doW, doB: bool,
                      idxW, idxB: var int32) {.inline.} =
  let src = system.int(e and 0x3F)
  let dst = system.int((e shr 6) and 0x3F)
  let attType = system.int((e shr 12) and 0x7)
  let attColor = uint8((e shr 15) and 0x1)
  let tgtPt = system.int((e shr 16) and 0x7)
  let tgtColor = uint8((e shr 19) and 0x1)

  let sideW = int32(attColor) * HALF_THREATS
  let sideB = int32(1'u8 xor attColor) * HALF_THREATS
  let relW = tgtPt + system.int(tgtColor) * 6
  let relB = tgtPt + system.int(1'u8 xor tgtColor) * 6

  if attType == 0: # Pawn
    let baseW = sideW + pawnTargetOff[relW]
    let baseB = sideB + pawnTargetOff[relB]
    if doW:
      let sW = src xor flipW
      let dW = dst xor flipW
      let identW = int32(ord((dW and 7) > (sW and 7)))
      idxW = baseW + pawnSqOffset[sW] + identW
    if doB:
      let sB = src xor flipB
      let dB = dst xor flipB
      let identB = int32(ord((dB and 7) > (sB and 7)))
      idxB = baseB + pawnSqOffset[sB] + identB
  else:
    let t = attType - 1
    let isSamePt = (tgtPt == attType)
    let baseW = sideW + thTargetOff[t][relW]
    let baseB = sideB + thTargetOff[t][relB]
    if doW:
      let sW = src xor flipW
      let dW = dst xor flipW
      if isSamePt and dW > sW:
        idxW = -1
      else:
        let belowW = int32(thRank[t][sW][dW])
        idxW = baseW + thBase[t][sW] + belowW
    if doB:
      let sB = src xor flipB
      let dB = dst xor flipB
      if isSamePt and dB > sB:
        idxB = -1
      else:
        let belowB = int32(thRank[t][sB][dB])
        idxB = baseB + thBase[t][sB] + belowB

proc computeFlip*(perspective: Color, kingSq: Square): int {.inline.} =
  result = if perspective == Black: 56 else: 0
  if kingSq.file > 3:
    result = result xor 7

proc psqtIndex*(perspective: Color, pieceColor: Color, pt: PieceType,
                sq: Square, flip: int): int {.inline.} =
  let colorIdx = if perspective == pieceColor: 0 else: 1
  (colorIdx * 6 + pt.ord) * 64 + (sq.int xor flip)

proc computeThreatFeatures*(b: Board, perspective: Color,
                            outThreat: var array[128, int32], nThreat: var int,
                            outPsqt: var array[32, uint16], nPsqt: var int) =
  let kingSq = b.kingSquare(perspective)
  let flip = computeFlip(perspective, kingSq)
  let occ = b.occupied

  nThreat = 0
  nPsqt = 0

  var occCopy = occ
  while not occCopy.isEmpty:
    let sq = poplsb(occCopy)
    let piece = b.mailbox[sq.int]
    if piece == NoPiece: continue
    outPsqt[nPsqt] = uint16(psqtIndex(perspective, piece.color,
                                        piece.pieceType, sq, flip))
    inc nPsqt

  for pieceOrd in 0 ..< 12:
    let piece = Piece(pieceOrd)
    let pt = piece.pieceType
    if pt == King: continue
    let attColor = piece.color
    let attType = pt.ord

    var pcs = b.byPiece[pieceOrd]
    while not pcs.isEmpty:
      let src = poplsb(pcs)
      var tgts: Bitboard
      case pt
      of Pawn:   tgts = getPawnAttacks(src, attColor) and occ
      of Knight: tgts = getKnightAttacks(src) and occ
      of Bishop: tgts = getBishopAttacks(src, occ) and occ
      of Rook:   tgts = getRookAttacks(src, occ) and occ
      of Queen:  tgts = getQueenAttacks(src, occ) and occ
      else: continue

      let targetMask = ValidThreatTargetMask[attType]
      while not tgts.isEmpty:
        let dst = poplsb(tgts)
        let tgtPiece = b.mailbox[dst.int]
        let tgtPtOrd = tgtPiece.pieceType.ord
        if (targetMask and (1'u8 shl tgtPtOrd)) == 0: continue
        let relTgt = tgtPtOrd + (if tgtPiece.color == perspective: 0 else: 6)
        let attFriendly = (attColor == perspective)
        let idx = threatIndex(attType, attFriendly, flip, src.int, dst.int, relTgt)
        if idx >= 0:
          doAssert nThreat < 128, "Too many threat features"
          outThreat[nThreat] = int32(idx)
          inc nThreat
