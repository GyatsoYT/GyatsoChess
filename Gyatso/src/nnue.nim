import coretypes, bitboard, board, nnuetypes, threats
import std/[streams, strutils]
import simd
import attacks
when defined(nnueStats):
    import std/atomics

const
    NNUE_EMBEDDED* = staticRead("../Net/GyatsoNet384TIx16x32.bin")
    NNUE_PAIRWISE_PERM_TEXT = staticRead("../Net/GyatsoNet384TIx16x32.perm")
    NNUE_PAIRWISE_PERMUTATION: array[PAIR_COUNT, int] = block:
      var p: array[PAIR_COUNT, int]
      let tokens = NNUE_PAIRWISE_PERM_TEXT.splitWhitespace()
      doAssert tokens.len == PAIR_COUNT, "Permutation file must have " & $PAIR_COUNT & " integers"
      for i in 0 ..< PAIR_COUNT:
        p[i] = parseInt(tokens[i])
      p
    NNUE_RAW_BYTES* = THREAT_IN * HL + PSQT_IN * HL * 2 + HL * 2 +
                     HL * L2_SIZE + L2_SIZE * 4 + L2_SIZE * L3_SIZE * 4 +
                     L3_SIZE * 4 + L3_SIZE * 4 + 4
    NNUE_PADDING_BYTES* = (64 - NNUE_RAW_BYTES mod 64) mod 64
    NNUE_FILE_BYTES* = NNUE_RAW_BYTES + NNUE_PADDING_BYTES
    NNUE_NNZ_INDEX_LUT: array[256, array[8, uint16]] = block:
        var table: array[256, array[8, uint16]]
        for mask in 0..255:
            var count = 0
            for bit in 0..7:
                if (mask and (1 shl bit)) != 0:
                    table[mask][count] = uint16(bit)
                    inc count
        table
    NNUE_NNZ_COUNT_LUT: array[256, uint8] = block:
        var table: array[256, uint8]
        for mask in 0..255:
            var count = 0
            for bit in 0..7:
                if (mask and (1 shl bit)) != 0:
                    inc count
            table[mask] = uint8(count)
        table

when defined(nnueStats):
    const NNUE_STATS_SAMPLE_MASK = 4095'u64
    var nnueStatsEvalCounter {.global.}: Atomic[system.uint64]
    var nnueStatsSampleCounter {.global.}: Atomic[system.uint64]
    var nnueStatsNonzeroBlocks {.global.}: Atomic[system.uint64]
    var nnueStatsActivationCounts {.global.}: array[PAIR_COUNT, Atomic[system.uint64]]

    proc recordPairwiseStats(inputs: ptr uint8) {.inline.} =
        let ticket = nnueStatsEvalCounter.fetchAdd(1'u64, moRelaxed)
        if (ticket and NNUE_STATS_SAMPLE_MASK) == 0:
            let values = cast[ptr UncheckedArray[uint8]](inputs)
            var activeBlocks = 0'u64
            for pairIndex in 0..<PAIR_COUNT:
                if values[pairIndex] != 0:
                    discard nnueStatsActivationCounts[pairIndex].fetchAdd(1'u64, moRelaxed)
                if values[PAIR_COUNT + pairIndex] != 0:
                    discard nnueStatsActivationCounts[pairIndex].fetchAdd(1'u64, moRelaxed)
            for blockIdx in 0..<(L1_IN div 4):
                if values[blockIdx * 4] != 0 or values[blockIdx * 4 + 1] != 0 or
                   values[blockIdx * 4 + 2] != 0 or values[blockIdx * 4 + 3] != 0:
                    inc activeBlocks
            discard nnueStatsNonzeroBlocks.fetchAdd(activeBlocks, moRelaxed)
            discard nnueStatsSampleCounter.fetchAdd(1'u64, moRelaxed)

    proc writeNNUEActivationStats*(path: string) =
        let samples = nnueStatsSampleCounter.load(moRelaxed)
        let blocks = nnueStatsNonzeroBlocks.load(moRelaxed)
        var output = newFileStream(path, fmWrite)
        if output == nil:
            raise newException(IOError, "Cannot write NNUE activation stats: " & path)
        defer: output.close()
        output.writeLine("# samples " & $samples)
        output.writeLine("# nonzero_blocks " & $blocks)
        for i in 0..<PAIR_COUNT:
            output.writeLine($i & " " & $nnueStatsActivationCounts[i].load(moRelaxed))

proc readU8(data: string, offset: var int): uint8 {.inline.} =
    result = uint8(ord(data[offset]))
    inc offset

proc readI8(data: string, offset: var int): int8 {.inline.} =
    result = cast[int8](data.readU8(offset))

proc readI16(data: string, offset: var int): int16 {.inline.} =
    let lo = uint16(data.readU8(offset))
    let hi = uint16(data.readU8(offset))
    result = cast[int16](lo or (hi shl 8))

proc readI32(data: string, offset: var int): int32 {.inline.} =
    let b0 = uint32(data.readU8(offset))
    let b1 = uint32(data.readU8(offset))
    let b2 = uint32(data.readU8(offset))
    let b3 = uint32(data.readU8(offset))
    result = cast[int32](b0 or (b1 shl 8) or (b2 shl 16) or (b3 shl 24))

proc loadNetworkInto*(net: ptr NNUENetwork, data: string) =
    if data.len != NNUE_FILE_BYTES:
        raise newException(IOError,
            "Invalid NNUE length: got " & $data.len &
            " bytes; expected " & $NNUE_FILE_BYTES & " (raw tensors plus Bullet padding)")

    const PaddingMarker = "bullet"
    for i in 0..<NNUE_PADDING_BYTES:
        if data[NNUE_RAW_BYTES + i] != PaddingMarker[i mod PaddingMarker.len]:
            raise newException(IOError, "Invalid NNUE padding marker")

    var offset = 0
    let perm = NNUE_PAIRWISE_PERMUTATION
    var newIndexByOld: array[PAIR_COUNT, int]
    for newIndex, oldIndex in perm:
        newIndexByOld[oldIndex] = newIndex

    for feature in 0..<PSQT_IN:
        for hidden in 0..<HL:
            let side = hidden div PAIR_COUNT
            let pair = hidden mod PAIR_COUNT
            let permutedHidden = side * PAIR_COUNT + newIndexByOld[pair]
            net.ftPsqt[feature][permutedHidden] = data.readI16(offset)

    for feature in 0..<THREAT_IN:
        for hidden in 0..<HL:
            let side = hidden div PAIR_COUNT
            let pair = hidden mod PAIR_COUNT
            let permutedHidden = side * PAIR_COUNT + newIndexByOld[pair]
            net.ftThreat[feature][permutedHidden] = data.readI8(offset)

    for hidden in 0..<HL:
        let side = hidden div PAIR_COUNT
        let pair = hidden mod PAIR_COUNT
        let permutedHidden = side * PAIR_COUNT + newIndexByOld[pair]
        net.ftBias[permutedHidden] = data.readI16(offset)

    var rawL1: array[L1_IN div 4, array[L2_SIZE, array[4, int8]]]
    for chunk in 0..<(L1_IN div 4):
        for o in 0..<L2_SIZE:
            for j in 0..<4:
                rawL1[chunk][o][j] = data.readI8(offset)

    for c in 0..<(L1_IN div 4):
        for o in 0..<L2_SIZE:
            for j in 0..<4:
                net.l1Weight[c][o][j] = 0

    for chunk in 0..<(L1_IN div 4):
        for o in 0..<L2_SIZE:
            for j in 0..<4:
                let src = chunk * 4 + j
                let half = src div PAIR_COUNT
                let dstIn = half * PAIR_COUNT + newIndexByOld[src mod PAIR_COUNT]
                net.l1Weight[dstIn div 4][o][dstIn mod 4] = rawL1[chunk][o][j]

    for o in 0..<L2_SIZE:
        let raw = data.readI32(offset)
        net.l1Bias[o] = cast[int32]((int64(raw) + 1) shr 1)

    for input in 0..<L2_SIZE:
        for output in 0..<L3_SIZE:
            net.l2Weight[input][output] = data.readI32(offset)

    for output in 0..<L3_SIZE:
        net.l2Bias[output] = data.readI32(offset)

    for input in 0..<L3_SIZE:
        net.l3Weight[input] = data.readI32(offset)

    net.l3Bias = data.readI32(offset)

    net.l2Int32Safe = true
    for output in 0..<L3_SIZE:
        var bound = int64(abs(net.l2Bias[output]))
        for input in 0..<L2_SIZE:
            var weight = int64(net.l2Weight[input][output])
            if weight < 0: weight = -weight
            bound += int64(QB * QB) * weight
        if bound > int64(high(int32)):
            net.l2Int32Safe = false

    net.l2Int16Safe = net.l2Int32Safe
    for output in 0..<L3_SIZE:
        for input in 0..<L2_SIZE:
            let w = net.l2Weight[input][output]
            if w < int32(low(int16)) or w > int32(high(int16)):
                net.l2Int16Safe = false
    if net.l2Int16Safe:
        for pair in 0..<(L2_SIZE div 2):
            for output in 0..<L3_SIZE:
                net.l2WeightPacked[pair][output][0] = int16(net.l2Weight[pair * 2][output])
                net.l2WeightPacked[pair][output][1] = int16(net.l2Weight[pair * 2 + 1][output])

    doAssert offset == NNUE_RAW_BYTES

proc loadNetworkFromStream*(net: ptr NNUENetwork, s: Stream) =
    loadNetworkInto(net, s.readAll())

proc loadNetworkFromFile*(net: ptr NNUENetwork, path: string) =
    let s = newFileStream(path, fmRead)
    if s == nil:
        raise newException(IOError, "Cannot open NNUE network file: " & path)
    defer: s.close()
    loadNetworkFromStream(net, s)

proc loadNetworkFromEmbedded*(net: ptr NNUENetwork) =
    loadNetworkInto(net, NNUE_EMBEDDED)

const
  AccTileRegs = when defined(avx512): 12 else: 8
  AccTileSize = AccTileRegs * CHUNK_SIZE

proc refreshAccumulator*(net: ptr NNUENetwork, b: Board,
                         acc: var Accumulator, perspective: Color) =
    var thFeats {.noinit.}: array[128, int32]
    var psqtFeats {.noinit.}: array[32, uint16]
    var nTh, nPsqt: int
    computeThreatFeatures(b, perspective, thFeats, nTh, psqtFeats, nPsqt)

    when not defined(simd):
        acc.data = net.ftBias
        for i in 0..<nPsqt:
            let f = system.int(psqtFeats[i])
            for o in 0..<HL:
                acc.data[o] += net.ftPsqt[f][o]
        for i in 0..<nTh:
            let f = system.int(thFeats[i])
            for o in 0..<HL:
                acc.data[o] += int16(net.ftThreat[f][o])
    else:
        var base = 0
        while base < HL:
            var regs {.noinit.}: array[AccTileRegs, VEPI16]
            for r in 0..<AccTileRegs:
                regs[r] = vecLoad(addr net.ftBias[base + r * CHUNK_SIZE])
            for i in 0..<nPsqt:
                let f = system.int(psqtFeats[i])
                for r in 0..<AccTileRegs:
                    regs[r] = vecAdd16(regs[r], vecLoad(addr net.ftPsqt[f][base + r * CHUNK_SIZE]))
            for i in 0..<nTh:
                let f = system.int(thFeats[i])
                for r in 0..<AccTileRegs:
                    regs[r] = vecAdd16(regs[r], vecLoadW8(cast[pointer](addr net.ftThreat[f][base + r * CHUNK_SIZE])))
            for r in 0..<AccTileRegs:
                vecStore(addr acc.data[base + r * CHUNK_SIZE], regs[r])
            base += AccTileSize

proc refreshState*(net: ptr NNUENetwork, b: Board, state: var NNUEState) =
    state.current = 0
    for p in [White, Black]:
        net.refreshAccumulator(b, state.acc[p][0], p)
        state.accFlags[p][0] = AccComputed

proc applyDelta(net: ptr NNUENetwork, d: PerspDelta,
                prev, curr: var Accumulator) {.inline.} =
    if d.nPsqtAdds == 0 and d.nPsqtSubs == 0 and
       d.nThAdds == 0 and d.nThSubs == 0:
        curr = prev  # null move
        return

    when not defined(simd):
        curr.data = prev.data
        for k in 0..<d.nThSubs:
            let f = system.int(d.thSubs[k])
            for o in 0..<HL:
                curr.data[o] -= int16(net.ftThreat[f][o])
        for k in 0..<d.nThAdds:
            let f = system.int(d.thAdds[k])
            for o in 0..<HL:
                curr.data[o] += int16(net.ftThreat[f][o])
        for k in 0..<d.nPsqtSubs:
            let f = system.int(d.psqtSubs[k])
            for o in 0..<HL:
                curr.data[o] -= net.ftPsqt[f][o]
        for k in 0..<d.nPsqtAdds:
            let f = system.int(d.psqtAdds[k])
            for o in 0..<HL:
                curr.data[o] += net.ftPsqt[f][o]
    else:
        var base = 0
        while base < HL:
            var regs {.noinit.}: array[AccTileRegs, VEPI16]
            for r in 0..<AccTileRegs:
                regs[r] = vecLoad(addr prev.data[base + r * CHUNK_SIZE])
            for k in 0..<d.nThSubs:
                let f = system.int(d.thSubs[k])
                for r in 0..<AccTileRegs:
                    regs[r] = vecSub16(regs[r], vecLoadW8(cast[pointer](addr net.ftThreat[f][base + r * CHUNK_SIZE])))
            for k in 0..<d.nThAdds:
                let f = system.int(d.thAdds[k])
                for r in 0..<AccTileRegs:
                    regs[r] = vecAdd16(regs[r], vecLoadW8(cast[pointer](addr net.ftThreat[f][base + r * CHUNK_SIZE])))
            for k in 0..<d.nPsqtSubs:
                let f = system.int(d.psqtSubs[k])
                for r in 0..<AccTileRegs:
                    regs[r] = vecSub16(regs[r], vecLoad(addr net.ftPsqt[f][base + r * CHUNK_SIZE]))
            for k in 0..<d.nPsqtAdds:
                let f = system.int(d.psqtAdds[k])
                for r in 0..<AccTileRegs:
                    regs[r] = vecAdd16(regs[r], vecLoad(addr net.ftPsqt[f][base + r * CHUNK_SIZE]))
            for r in 0..<AccTileRegs:
                vecStore(addr curr.data[base + r * CHUNK_SIZE], regs[r])
            base += AccTileSize

proc forward*(net: ptr NNUENetwork, stmAcc, nstmAcc: var Accumulator): int {.inline.} =
    var pairwise {.noinit.}: array[L1_IN, uint8]
    var l1Sums {.noinit.}: array[L2_SIZE, int32]
    when defined(avx512) or defined(avx2) or defined(neon) or defined(arm64) or defined(aarch64):
        var blocks {.noinit.}: array[L1_IN div 4, uint16]
        let nnzCount = simd.gyatsoPairwiseNnz(addr stmAcc.data[0], addr nstmAcc.data[0],
            addr pairwise[0], addr blocks[0],
            addr NNUE_NNZ_INDEX_LUT[0][0], addr NNUE_NNZ_COUNT_LUT[0])
        simd.gyatsoMultilayerL1Blocks(addr pairwise[0], addr net.l1Weight[0][0][0],
            addr l1Sums[0], addr blocks[0], nnzCount)
    else:
        simd.gyatsoPairwise(addr stmAcc.data[0], addr nstmAcc.data[0], addr pairwise[0])
        simd.gyatsoMultilayerL1(addr pairwise[0], addr net.l1Weight[0][0][0],
            addr l1Sums[0], addr NNUE_NNZ_INDEX_LUT[0][0], addr NNUE_NNZ_COUNT_LUT[0])
    when defined(nnueStats):
        recordPairwiseStats(addr pairwise[0])

    var l1Out {.noinit.}: array[L2_SIZE, int32]
    for i in 0..<L2_SIZE:
        let scaled = (l1Sums[i] + net.l1Bias[i]) shr 8
        let clipped = clamp(scaled, 0, QB.int32)
        l1Out[i] = clipped * clipped

    var l2Out {.noinit.}: array[L3_SIZE, int32]
    when defined(avx512) or defined(avx2):
        if net.l2Int16Safe:
            simd.gyatsoMultilayerL2Madd(addr l1Out[0], addr net.l2WeightPacked[0][0][0],
                addr net.l2Bias[0], addr l2Out[0], int32(QB * QB * QB))
        else:
            simd.gyatsoMultilayerL2(addr l1Out[0], addr net.l2Weight[0][0],
                addr net.l2Bias[0], addr l2Out[0], int32(QB * QB * QB),
                int32(ord(net.l2Int32Safe)))
    else:
        simd.gyatsoMultilayerL2(addr l1Out[0], addr net.l2Weight[0][0],
            addr net.l2Bias[0], addr l2Out[0], int32(QB * QB * QB),
            int32(ord(net.l2Int32Safe)))

    let output = simd.gyatsoMultilayerOutput(addr l2Out[0],
        addr net.l3Weight[0], net.l3Bias)

    return system.int(output * int64(EVAL_SCALE) div int64(QB * QB * QB * QB))

proc updateAccumulator(net: ptr NNUENetwork, b: Board, state: var NNUEState,
                       p: Color) {.inline.} =
    let n = state.current
    if (state.accFlags[p][n] and AccComputed) != 0:
        return
    if (state.accFlags[p][n] and AccNeedsRefresh) != 0:
        net.refreshAccumulator(b, state.acc[p][n], p)
        state.accFlags[p][n] = AccComputed
        return
    var j = n - 1
    while (state.accFlags[p][j] and AccComputed) == 0:
        dec j
    while j < n:
        net.applyDelta(state.delta[p][j + 1], state.acc[p][j], state.acc[p][j + 1])
        inc j
        state.accFlags[p][j] = AccComputed

proc nnueEvaluate*(net: ptr NNUENetwork, b: Board, state: var NNUEState): int {.inline.} =
    let ply = state.current
    let us = b.stm
    let them = us.opposite()
    net.updateAccumulator(b, state, us)
    net.updateAccumulator(b, state, them)
    result = forward(net, state.acc[us][ply], state.acc[them][ply])

    const MaxEval = MateValue - MaxPly - 100
    if result > MaxEval: result = MaxEval
    elif result < -MaxEval: result = -MaxEval

func packEdge(src, dst, attType: int, attColor: Color, tgtPt: int, tgtColor: Color): uint32 {.inline.} =
    uint32(src or (dst shl 6) or (attType shl 12) or (attColor.ord shl 15) or (tgtPt shl 16) or (tgtColor.ord shl 19))

func unpackEdge(e: uint32, src, dst, attType: var int, attColor: var Color, tgtPt: var int, tgtColor: var Color) {.inline.} =
    src = system.int(e and 0x3F)
    dst = system.int((e shr 6) and 0x3F)
    attType = system.int((e shr 12) and 0x7)
    attColor = Color(system.int((e shr 15) and 0x1))
    tgtPt = system.int((e shr 16) and 0x7)
    tgtColor = Color(system.int((e shr 19) and 0x1))

const ValidThreatTargetMask: array[5, uint8] = [
    (1'u8 shl Knight.ord) or (1'u8 shl Rook.ord), # Pawn: 10
    (1'u8 shl Pawn.ord) or (1'u8 shl Knight.ord) or (1'u8 shl Bishop.ord) or (1'u8 shl Rook.ord) or (1'u8 shl Queen.ord), # Knight: 31
    (1'u8 shl Pawn.ord) or (1'u8 shl Knight.ord) or (1'u8 shl Bishop.ord) or (1'u8 shl Rook.ord), # Bishop: 15
    (1'u8 shl Pawn.ord) or (1'u8 shl Knight.ord) or (1'u8 shl Bishop.ord) or (1'u8 shl Rook.ord), # Rook: 15
    (1'u8 shl Pawn.ord) or (1'u8 shl Knight.ord) or (1'u8 shl Bishop.ord) or (1'u8 shl Rook.ord) or (1'u8 shl Queen.ord)  # Queen: 31
]

proc addRawEdges(mailbox: array[64, Piece], occ: Bitboard,
                 src: int, attType: int, attColor: Color,
                 buf: var array[128, uint32], n: var int) {.inline.} =
    let sq = Square(src)
    var targets: Bitboard
    case PieceType(attType)
    of Pawn:   targets = getPawnAttacks(sq, attColor) and occ
    of Knight: targets = getKnightAttacks(sq) and occ
    of Bishop: targets = getBishopAttacks(sq, occ) and occ
    of Rook:   targets = getRookAttacks(sq, occ) and occ
    of Queen:  targets = getQueenAttacks(sq, occ) and occ
    else: return

    let targetMask = ValidThreatTargetMask[attType]
    while not targets.isEmpty:
        let dst = poplsb(targets)
        let tp = mailbox[dst.int]
        let ptOrd = tp.pieceType.ord
        if (targetMask and (1'u8 shl ptOrd)) != 0:
            if n < 128:
                buf[n] = packEdge(src, dst.int, attType, attColor, ptOrd, tp.color)
                inc n

proc computeDeltaBoth(b: Board, m: Move, deltas: var array[Color, PerspDelta]) =
    let us = b.stm
    let them = us.opposite()
    let fromSq = m.fromSq
    let toSq = m.toSq
    let movingPiece = b.mailbox[fromSq.int]
    let movingPt = movingPiece.pieceType
    let movingColor = movingPiece.color

    for p in [White, Black]:
        deltas[p].nPsqtAdds = 0
        deltas[p].nPsqtSubs = 0
        deltas[p].nThAdds = 0
        deltas[p].nThSubs = 0
        deltas[p].needsRefresh = false

    for p in [White, Black]:
        let kingSq = b.kingSquare(p)
        let flip = computeFlip(p, kingSq)

        template psqtAdd(pc: Color, pt: PieceType, sq: Square) =
            deltas[p].psqtAdds[deltas[p].nPsqtAdds] = uint16(psqtIndex(p, pc, pt, sq, flip))
            inc deltas[p].nPsqtAdds
        template psqtSub(pc: Color, pt: PieceType, sq: Square) =
            deltas[p].psqtSubs[deltas[p].nPsqtSubs] = uint16(psqtIndex(p, pc, pt, sq, flip))
            inc deltas[p].nPsqtSubs

        if m.isCastling:
            let kingFrom = fromSq
            let rookFrom = toSq
            let kingTo = if fromSq.file < rookFrom.file: fromSq.withFile(6)
                         else: fromSq.withFile(2)
            let rookTo = if fromSq.file < rookFrom.file: fromSq.withFile(5)
                         else: fromSq.withFile(3)
            psqtAdd(us, King, kingTo)
            psqtSub(us, King, kingFrom)
            psqtAdd(us, Rook, rookTo)
            psqtSub(us, Rook, rookFrom)
        elif m.isEnPassant:
            let capSq = if us == White: (toSq.int - 8).Square
                        else: (toSq.int + 8).Square
            psqtAdd(us, Pawn, toSq)
            psqtSub(us, Pawn, fromSq)
            psqtSub(them, Pawn, capSq)
        elif m.isPromotion:
            let promoPt = case m.promoType
                of PromoKnight: Knight
                of PromoBishop: Bishop
                of PromoRook:   Rook
                of PromoQueen:  Queen
            let capturedPiece = b.mailbox[toSq.int]
            psqtAdd(us, promoPt, toSq)
            psqtSub(us, Pawn, fromSq)
            if capturedPiece != NoPiece:
                psqtSub(capturedPiece.color, capturedPiece.pieceType, toSq)
        else:
            let capturedPiece = b.mailbox[toSq.int]
            psqtAdd(movingColor, movingPt, toSq)
            psqtSub(movingColor, movingPt, fromSq)
            if capturedPiece != NoPiece:
                psqtSub(capturedPiece.color, capturedPiece.pieceType, toSq)

    # Threat deltas
    let occ = b.occupied

    var changedSqs {.noinit.}: array[6, int]
    var nChanged = 0
    changedSqs[nChanged] = fromSq.int; inc nChanged
    changedSqs[nChanged] = toSq.int; inc nChanged
    if m.isEnPassant:
        let capSq = if us == White: toSq.int - 8 else: toSq.int + 8
        changedSqs[nChanged] = capSq; inc nChanged
    elif m.isCastling:
        let rookFrom = toSq
        let rookTo = if fromSq.file < rookFrom.file: fromSq.withFile(5)
                     else: fromSq.withFile(3)
        changedSqs[nChanged] = rookFrom.int; inc nChanged
        changedSqs[nChanged] = rookTo.int; inc nChanged

    let wPawns = b.byPiece[WhitePawn.ord]
    let bPawns = b.byPiece[BlackPawn.ord]
    let knights = b.byPiece[Knight.ord] or b.byPiece[Knight.ord + 6]
    let diagSliders = b.byPiece[Bishop.ord] or b.byPiece[Bishop.ord + 6] or
                      b.byPiece[Queen.ord]  or b.byPiece[Queen.ord + 6]
    let hvSliders   = b.byPiece[Rook.ord]   or b.byPiece[Rook.ord + 6] or
                      b.byPiece[Queen.ord]  or b.byPiece[Queen.ord + 6]

    var affMask: Bitboard = Bitboard(0)
    for ci in 0..<nChanged:
        let c = changedSqs[ci]
        let cSq = Square(c)
        let standing = b.mailbox[c]
        if standing != NoPiece and standing.pieceType != King:
            affMask = affMask or cSq.bit
        let attackers = (getPawnAttacks(cSq, Black) and wPawns) or
                        (getPawnAttacks(cSq, White) and bPawns) or
                        (getKnightAttacks(cSq) and knights) or
                        (getBishopAttacks(cSq, occ) and diagSliders) or
                        (getRookAttacks(cSq, occ) and hvSliders)
        affMask = affMask or attackers

    var affSqs {.noinit.}: array[32, int]
    var affTypes {.noinit.}: array[32, int]
    var affColors {.noinit.}: array[32, Color]
    var nAff = 0
    while not affMask.isEmpty and nAff < 32:
        let sq = poplsb(affMask)
        let pc = b.mailbox[sq.int]
        affSqs[nAff] = sq.int
        affTypes[nAff] = pc.pieceType.ord
        affColors[nAff] = pc.color
        inc nAff

    var newMail: array[64, Piece] = b.mailbox
    var newOcc: Bitboard = occ
    if m.isCastling:
        let kingFrom = fromSq
        let rookFrom = toSq
        let kingTo = if fromSq.file < rookFrom.file: fromSq.withFile(6)
                     else: fromSq.withFile(2)
        let rookTo = if fromSq.file < rookFrom.file: fromSq.withFile(5)
                     else: fromSq.withFile(3)
        newMail[kingFrom.int] = NoPiece
        newMail[rookFrom.int] = NoPiece
        newMail[kingTo.int] = makePiece(us, King)
        newMail[rookTo.int] = makePiece(us, Rook)
        newOcc = (newOcc and not kingFrom.bit and not rookFrom.bit) or
                 kingTo.bit or rookTo.bit
    elif m.isEnPassant:
        let capSq = if us == White: toSq.int - 8 else: toSq.int + 8
        newMail[fromSq.int] = NoPiece
        newMail[toSq.int] = movingPiece
        newMail[capSq] = NoPiece
        newOcc = (newOcc and not fromSq.bit and not Square(capSq).bit) or toSq.bit
    elif m.isPromotion:
        let promoPt = case m.promoType
            of PromoKnight: Knight
            of PromoBishop: Bishop
            of PromoRook:   Rook
            of PromoQueen:  Queen
        newMail[fromSq.int] = NoPiece
        newMail[toSq.int] = makePiece(us, promoPt)
        newOcc = (newOcc and not fromSq.bit) or toSq.bit
    else:
        newMail[fromSq.int] = NoPiece
        newMail[toSq.int] = movingPiece
        newOcc = (newOcc and not fromSq.bit) or toSq.bit

    var oldRaw {.noinit.}: array[128, uint32]
    var nOld = 0
    var newRaw {.noinit.}: array[128, uint32]
    var nNew = 0

    for ai in 0..<nAff:
        let oldSq = affSqs[ai]
        let oldType = affTypes[ai]
        let oldColor = affColors[ai]

        addRawEdges(b.mailbox, occ, oldSq, oldType, oldColor, oldRaw, nOld)

        let piece = b.mailbox[oldSq]
        var newSq = oldSq
        var newType = oldType
        var alive = true

        if oldSq == fromSq.int:
            if m.isCastling and movingPt == King:
                alive = false
            else:
                newSq = toSq.int
                if m.isPromotion:
                    newType = (case m.promoType
                        of PromoKnight: Knight.ord
                        of PromoBishop: Bishop.ord
                        of PromoRook:   Rook.ord
                        of PromoQueen:  Queen.ord)
        elif m.isCastling and oldSq == toSq.int:
            let rookTo = if fromSq.file < toSq.file: fromSq.withFile(5)
                         else: fromSq.withFile(3)
            newSq = rookTo.int
        elif m.isEnPassant:
            let capSq = if us == White: toSq.int - 8 else: toSq.int + 8
            if oldSq == capSq:
                alive = false
        else:
            if oldSq == toSq.int and piece != NoPiece and piece.color != movingColor:
                alive = false

        if alive:
            let newColor = if oldSq == fromSq.int: movingColor else: oldColor
            addRawEdges(newMail, newOcc, newSq, newType, newColor, newRaw, nNew)

    var subRaw {.noinit.}: array[64, uint32]
    var nSubRaw = 0
    var addRaw {.noinit.}: array[64, uint32]
    var nAddRaw = 0

    if nOld <= 64 and nNew <= 64:
        var newUsedMask: uint64 = 0
        var oldUsedMask: uint64 = 0
        for i in 0..<nOld:
            let o = oldRaw[i]
            for j in 0..<nNew:
                if ((newUsedMask and (1'u64 shl j)) == 0) and o == newRaw[j]:
                    oldUsedMask = oldUsedMask or (1'u64 shl i)
                    newUsedMask = newUsedMask or (1'u64 shl j)
                    break
        for i in 0..<nOld:
            if (oldUsedMask and (1'u64 shl i)) == 0:
                subRaw[nSubRaw] = oldRaw[i]
                inc nSubRaw
        for j in 0..<nNew:
            if (newUsedMask and (1'u64 shl j)) == 0:
                addRaw[nAddRaw] = newRaw[j]
                inc nAddRaw
    else:
        deltas[White].needsRefresh = true
        deltas[Black].needsRefresh = true
        return

    for p in [White, Black]:
        if deltas[p].needsRefresh: continue

        let kingSq = b.kingSquare(p)
        let flip = computeFlip(p, kingSq)

        var nSubs = 0
        var nAdds = 0

        for i in 0..<nSubRaw:
            var src, dst, attType, tgtPt: int
            var attColor, tgtColor: Color
            unpackEdge(subRaw[i], src, dst, attType, attColor, tgtPt, tgtColor)
            let rel = tgtPt + (if tgtColor == p: 0 else: 6)
            let idx = threatIndex(attType, attColor == p, flip, src, dst, rel)
            if idx >= 0:
                if nSubs >= MAX_THREAT_DELTA:
                    deltas[p].needsRefresh = true
                    break
                deltas[p].thSubs[nSubs] = uint32(idx)
                inc nSubs

        if not deltas[p].needsRefresh:
            for i in 0..<nAddRaw:
                var src, dst, attType, tgtPt: int
                var attColor, tgtColor: Color
                unpackEdge(addRaw[i], src, dst, attType, attColor, tgtPt, tgtColor)
                let rel = tgtPt + (if tgtColor == p: 0 else: 6)
                let idx = threatIndex(attType, attColor == p, flip, src, dst, rel)
                if idx >= 0:
                    if nAdds >= MAX_THREAT_DELTA:
                        deltas[p].needsRefresh = true
                        break
                    deltas[p].thAdds[nAdds] = uint32(idx)
                    inc nAdds

        deltas[p].nThSubs = nSubs
        deltas[p].nThAdds = nAdds

proc pushAccumulator*(net: ptr NNUENetwork, b: Board, m: Move,
                      state: var NNUEState) =
    let ply = state.current
    let us = b.stm
    let movingPt = b.mailbox[m.fromSq.int].pieceType

    var deltas {.noinit.}: array[Color, PerspDelta]
    computeDeltaBoth(b, m, deltas)

    for perspective in [White, Black]:
        if (state.accFlags[perspective][ply] and AccNeedsRefresh) != 0:
            net.refreshAccumulator(b, state.acc[perspective][ply], perspective)
            state.accFlags[perspective][ply] = AccComputed

        state.accFlags[perspective][ply + 1] = 0

        let kingToFile = if m.isCastling:
                           (if m.fromSq.file < m.toSq.file: 6 else: 2)
                         else: m.toSq.file
        if perspective == us and movingPt == King and
                (m.fromSq.file > 3) != (kingToFile > 3):
            state.accFlags[perspective][ply + 1] = AccNeedsRefresh
        elif deltas[perspective].needsRefresh:
            state.accFlags[perspective][ply + 1] = AccNeedsRefresh
        else:
            state.accFlags[perspective][ply + 1] = 0
            state.delta[perspective][ply + 1] = deltas[perspective]

    inc state.current

proc popAccumulator*(state: var NNUEState) {.inline.} =
    dec state.current

proc pushNullMove*(state: var NNUEState) =
    let ply = state.current
    for p in [White, Black]:
        state.accFlags[p][ply + 1] = state.accFlags[p][ply] and AccNeedsRefresh
        state.delta[p][ply + 1] = PerspDelta()
    inc state.current

proc popNullMove*(state: var NNUEState) {.inline.} =
    dec state.current

proc verifyNNUE*(net: ptr NNUENetwork, b: Board, state: var NNUEState) =
    let ply = state.current
    for p in [White, Black]:
        net.updateAccumulator(b, state, p)
        var reference: Accumulator
        net.refreshAccumulator(b, reference, p)
        for i in 0..<HL:
            doAssert state.acc[p][ply].data[i] == reference.data[i],
                $p & " accumulator mismatch at index " & $i &
                ": incremental=" & $state.acc[p][ply].data[i] &
                " expected=" & $reference.data[i]