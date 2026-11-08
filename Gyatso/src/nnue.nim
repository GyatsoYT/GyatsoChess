import coretypes, bitboard, board, nnuetypes, threats
import std/[streams, strutils]
import simd
import attacks
when defined(nnueStats):
    import std/atomics

when defined(profileNNUE):
    var
        profComputeDeltaCalls*: uint64
        profComputeDeltaCyc*: uint64
        profApplyDeltaCalls*: uint64
        profApplyDeltaCyc*: uint64
        profForwardCalls*: uint64
        profForwardCyc*: uint64
        profRefreshCalls*: uint64
        profRefreshCyc*: uint64
    {.push header: "x86intrin.h".}
    proc rdtsc(): uint64 {.importc: "__rdtsc".}
    {.pop.}

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

when defined(avx512):
  const AccTileRegs = 12
else:
  const AccTileRegs = 8
const AccTileSize = AccTileRegs * CHUNK_SIZE

proc refreshAccumulator*(net: ptr NNUENetwork, b: Board,
                         acc: var Accumulator, perspective: Color) =
    when defined(profileNNUE):
        let t0 = rdtsc()
        defer:
            let t1 = rdtsc()
            profRefreshCalls += 1
            profRefreshCyc += (t1 - t0)
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
                var r = 0
                while r < AccTileRegs:
                    var w0 {.noinit.}, w1 {.noinit.}: VEPI16
                    vecLoadW8x2(cast[pointer](addr net.ftThreat[f][base + r * CHUNK_SIZE]), w0, w1)
                    regs[r] = vecAdd16(regs[r], w0)
                    regs[r + 1] = vecAdd16(regs[r + 1], w1)
                    r += 2
            for r in 0..<AccTileRegs:
                vecStore(addr acc.data[base + r * CHUNK_SIZE], regs[r])
            base += AccTileSize

proc refreshState*(net: ptr NNUENetwork, b: Board, state: var NNUEState) =
    state.current = 0
    state.deferred[0] = false
    for p in [White, Black]:
        net.refreshAccumulator(b, state.acc[p][0], p)
        state.accFlags[p][0] = AccComputed

proc applyDelta(net: ptr NNUENetwork, d: var PerspDelta,
                prev, curr: var Accumulator) {.inline.} =
    when defined(profileNNUE):
        let t0 = rdtsc()
        defer:
            let t1 = rdtsc()
            profApplyDeltaCalls += 1
            profApplyDeltaCyc += (t1 - t0)
    if d.nPsqtAdds == 0 and d.nPsqtSubs == 0 and
       d.nThAdds == 0 and d.nThSubs == 0:
        curr = prev  # null move
        return

    when not defined(simd):
        curr.data = prev.data
        for k in 0..<system.int(d.nThSubs):
            let f = system.int(d.thSubs[k])
            for o in 0..<HL:
                curr.data[o] -= int16(net.ftThreat[f][o])
        for k in 0..<system.int(d.nThAdds):
            let f = system.int(d.thAdds[k])
            for o in 0..<HL:
                curr.data[o] += int16(net.ftThreat[f][o])
        for k in 0..<system.int(d.nPsqtSubs):
            let f = system.int(d.psqtSubs[k])
            for o in 0..<HL:
                curr.data[o] -= net.ftPsqt[f][o]
        for k in 0..<system.int(d.nPsqtAdds):
            let f = system.int(d.psqtAdds[k])
            for o in 0..<HL:
                curr.data[o] += net.ftPsqt[f][o]
    else:
        var base = 0
        while base < HL:
            var regs {.noinit.}: array[AccTileRegs, VEPI16]
            for r in 0..<AccTileRegs:
                regs[r] = vecLoad(addr prev.data[base + r * CHUNK_SIZE])
            for k in 0..<system.int(d.nThSubs):
                let f = system.int(d.thSubs[k])
                var r = 0
                while r < AccTileRegs:
                    var w0 {.noinit.}, w1 {.noinit.}: VEPI16
                    vecLoadW8x2(cast[pointer](addr net.ftThreat[f][base + r * CHUNK_SIZE]), w0, w1)
                    regs[r] = vecSub16(regs[r], w0)
                    regs[r + 1] = vecSub16(regs[r + 1], w1)
                    r += 2
            for k in 0..<system.int(d.nThAdds):
                let f = system.int(d.thAdds[k])
                var r = 0
                while r < AccTileRegs:
                    var w0 {.noinit.}, w1 {.noinit.}: VEPI16
                    vecLoadW8x2(cast[pointer](addr net.ftThreat[f][base + r * CHUNK_SIZE]), w0, w1)
                    regs[r] = vecAdd16(regs[r], w0)
                    regs[r + 1] = vecAdd16(regs[r + 1], w1)
                    r += 2
            for k in 0..<system.int(d.nPsqtSubs):
                let f = system.int(d.psqtSubs[k])
                for r in 0..<AccTileRegs:
                    regs[r] = vecSub16(regs[r], vecLoad(addr net.ftPsqt[f][base + r * CHUNK_SIZE]))
            for k in 0..<system.int(d.nPsqtAdds):
                let f = system.int(d.psqtAdds[k])
                for r in 0..<AccTileRegs:
                    regs[r] = vecAdd16(regs[r], vecLoad(addr net.ftPsqt[f][base + r * CHUNK_SIZE]))
            for r in 0..<AccTileRegs:
                vecStore(addr curr.data[base + r * CHUNK_SIZE], regs[r])
            base += AccTileSize

proc forward*(net: ptr NNUENetwork, stmAcc, nstmAcc: var Accumulator): int {.inline.} =
    when defined(profileNNUE):
        let t0 = rdtsc()
        defer:
            let t1 = rdtsc()
            profForwardCalls += 1
            profForwardCyc += (t1 - t0)
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

proc resolveDeferred*(net: ptr NNUENetwork, b: var Board, state: var NNUEState) {.gcsafe.}

proc nnueEvaluate*(net: ptr NNUENetwork, b: var Board, state: var NNUEState): int {.inline, gcsafe.} =
    if state.deferred[state.current]:
        resolveDeferred(net, b, state)
    let ply = state.current
    let us = b.stm
    let them = us.opposite()
    net.updateAccumulator(b, state, us)
    net.updateAccumulator(b, state, them)
    result = forward(net, state.acc[us][ply], state.acc[them][ply])

    const MaxEval = MateValue - MaxPly - 100
    if result > MaxEval: result = MaxEval
    elif result < -MaxEval: result = -MaxEval

template getPieceAttacks(sq: Square, pt: PieceType, color: Color, occBB: Bitboard): Bitboard =
    case pt
    of Pawn:   getPawnAttacks(sq, color) and occBB
    of Knight: getKnightAttacks(sq) and occBB
    of Bishop: getBishopAttacks(sq, occBB) and occBB
    of Rook:   getRookAttacks(sq, occBB) and occBB
    of Queen:  getQueenAttacks(sq, occBB) and occBB
    else: Bitboard(0)

proc computeDeltaBoth(b: Board, m: Move, deltas: var array[Color, PerspDelta],
                      refreshPersp: Color, refreshActive: bool) =
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
        if refreshActive and p == refreshPersp:
            deltas[p].needsRefresh = true
        else:
            deltas[p].needsRefresh = false

    for p in [White, Black]:
        if deltas[p].needsRefresh:
            continue
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
    var changedMaskBB: Bitboard = fromSq.bit or toSq.bit
    if m.isEnPassant:
        let capSq = if us == White: toSq.int - 8 else: toSq.int + 8
        changedSqs[nChanged] = capSq; inc nChanged
        changedMaskBB = changedMaskBB or Square(capSq).bit
    elif m.isCastling:
        let rookFrom = toSq
        let kingTo = if fromSq.file < rookFrom.file: fromSq.withFile(6) else: fromSq.withFile(2)
        let rookTo = if fromSq.file < rookFrom.file: fromSq.withFile(5)
                     else: fromSq.withFile(3)
        changedSqs[nChanged] = rookTo.int; inc nChanged
        changedMaskBB = changedMaskBB or kingTo.bit or rookTo.bit

    let wPawns = b.byPiece[WhitePawn.ord]
    let bPawns = b.byPiece[BlackPawn.ord]
    let knights = b.byPiece[Knight.ord] or b.byPiece[Knight.ord + 6]
    let diagSliders = b.byPiece[Bishop.ord] or b.byPiece[Bishop.ord + 6] or
                      b.byPiece[Queen.ord]  or b.byPiece[Queen.ord + 6]
    let hvSliders   = b.byPiece[Rook.ord]   or b.byPiece[Rook.ord + 6] or
                      b.byPiece[Queen.ord]  or b.byPiece[Queen.ord + 6]

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

    var affMask: Bitboard = Bitboard(0)
    for ci in 0..<nChanged:
        let c = changedSqs[ci]
        let cSq = Square(c)
        let oldP = b.mailbox[c]
        let newP = newMail[c]
        let canPawnTarget = (oldP != NoPiece and (oldP.pieceType == Knight or oldP.pieceType == Rook)) or
                            (newP != NoPiece and (newP.pieceType == Knight or newP.pieceType == Rook))

        var attackers = getKnightAttacks(cSq) and knights
        if (bishopRayMask[c] and diagSliders) != Bitboard(0):
            attackers = attackers or (getBishopAttacks(cSq, occ) and diagSliders)
        if (rookRayMask[c] and hvSliders) != Bitboard(0):
            attackers = attackers or (getRookAttacks(cSq, occ) and hvSliders)
        if canPawnTarget:
            attackers = attackers or (getPawnAttacks(cSq, Black) and wPawns) or
                                     (getPawnAttacks(cSq, White) and bPawns)
        affMask = affMask or attackers

    var subRaw {.noinit.}: array[64, ThreatEdge]
    var nSubRaw = 0
    var addRaw {.noinit.}: array[64, ThreatEdge]
    var nAddRaw = 0

    template pushSubEdge(e: ThreatEdge) =
        if nSubRaw < 64:
            subRaw[nSubRaw] = e
            inc nSubRaw
        else:
            deltas[White].needsRefresh = true
            deltas[Black].needsRefresh = true
            return

    template pushAddEdge(e: ThreatEdge) =
        if nAddRaw < 64:
            addRaw[nAddRaw] = e
            inc nAddRaw
        else:
            deltas[White].needsRefresh = true
            deltas[Black].needsRefresh = true
            return

    let kings = b.byPiece[King.ord] or b.byPiece[King.ord + 6]
    let queens = b.byPiece[Queen.ord] or b.byPiece[Queen.ord + 6]
    let rooks = b.byPiece[Rook.ord] or b.byPiece[Rook.ord + 6]
    let knightsRooks = knights or rooks
    let notQueensKings = not (queens or kings)
    let newKings = if movingPt == King:
                       (if m.isCastling:
                            let kTo = if fromSq.file < toSq.file: fromSq.withFile(6) else: fromSq.withFile(2)
                            (kings and not fromSq.bit) or kTo.bit
                        else:
                            (kings and not fromSq.bit) or toSq.bit)
                   else: kings

    template emitSubAttacks(sq: Square, pt: PieceType, pc: Color) =
        if pt != King:
            var tgts = getPieceAttacks(sq, pt, pc, occ)
            case pt
            of Pawn: tgts = tgts and knightsRooks
            of Bishop, Rook: tgts = tgts and notQueensKings
            else: tgts = tgts and not kings
            let attPiece = makePiece(pc, pt)
            while not tgts.isEmpty:
                let dst = poplsb(tgts)
                let tp = b.mailbox[dst.int]
                pushSubEdge(makeEdge(sq.int, dst.int, attPiece, tp))

    template emitAddAttacks(sq: Square, pt: PieceType, pc: Color) =
        if pt != King:
            var tgts = getPieceAttacks(sq, pt, pc, newOcc) and not newKings
            let targetMask = ValidThreatTargetMask[pt.ord]
            let attPiece = makePiece(pc, pt)
            while not tgts.isEmpty:
                let dst = poplsb(tgts)
                let tp = newMail[dst.int]
                let ptOrd = tp.pieceType.ord
                if (targetMask and (1'u8 shl ptOrd)) != 0:
                    pushAddEdge(makeEdge(sq.int, dst.int, attPiece, tp))

    if m.isCastling:
        let rookFrom = toSq
        let rookTo = if fromSq.file < rookFrom.file: fromSq.withFile(5)
                     else: fromSq.withFile(3)
        emitSubAttacks(rookFrom, Rook, us)
        emitAddAttacks(rookTo, Rook, us)
    elif m.isEnPassant:
        let capSq = if us == White: toSq.int - 8 else: toSq.int + 8
        emitSubAttacks(fromSq, Pawn, us)
        emitAddAttacks(toSq, Pawn, us)
        emitSubAttacks(Square(capSq), Pawn, them)
    else:
        emitSubAttacks(fromSq, movingPt, movingColor)
        let dstPt = if m.isPromotion:
                        (case m.promoType
                         of PromoKnight: Knight
                         of PromoBishop: Bishop
                         of PromoRook:   Rook
                         of PromoQueen:  Queen)
                    else: movingPt
        emitAddAttacks(toSq, dstPt, movingColor)
        let capturedPiece = b.mailbox[toSq.int]
        if capturedPiece != NoPiece:
            emitSubAttacks(toSq, capturedPiece.pieceType, capturedPiece.color)

    var stationaryMask = affMask and not changedMaskBB
    while not stationaryMask.isEmpty:
        let oldSq = poplsb(stationaryMask).int
        let piece = b.mailbox[oldSq]
        let oldType = piece.pieceType.ord
        let oldColor = piece.color
        let pt = PieceType(oldType)
        let sq = Square(oldSq)
        let oldTargets = getPieceAttacks(sq, pt, oldColor, occ)
        let newTargets = getPieceAttacks(sq, pt, oldColor, newOcc)

        if oldTargets == newTargets and (oldTargets and changedMaskBB).isEmpty:
            continue

        let common = oldTargets and newTargets and not changedMaskBB
        var subTgts = (oldTargets and not common) and not kings
        case pt
        of Pawn: subTgts = subTgts and knightsRooks
        of Bishop, Rook: subTgts = subTgts and not queens
        else: discard
        var addTgts = (newTargets and not common) and not newKings

        if not subTgts.isEmpty or not addTgts.isEmpty:
            let targetMask = ValidThreatTargetMask[oldType]
            while not subTgts.isEmpty:
                let dst = poplsb(subTgts)
                let tp = b.mailbox[dst.int]
                pushSubEdge(makeEdge(oldSq, dst.int, piece, tp))

            while not addTgts.isEmpty:
                let dst = poplsb(addTgts)
                let tp = newMail[dst.int]
                let ptOrd = tp.pieceType.ord
                if (targetMask and (1'u8 shl ptOrd)) != 0:
                    pushAddEdge(makeEdge(oldSq, dst.int, piece, tp))

    let kingSqW = b.kingSquare(White)
    let flipW = computeFlip(White, kingSqW)
    let kingSqB = b.kingSquare(Black)
    let flipB = computeFlip(Black, kingSqB)

    var nSubsW = 0
    var nAddsW = 0
    var nSubsB = 0
    var nAddsB = 0

    var doW = not deltas[White].needsRefresh
    var doB = not deltas[Black].needsRefresh

    for i in 0..<nSubRaw:
        if not (doW or doB): break
        let e = subRaw[i]
        var idxW, idxB: int32
        threatIndexDual(e, flipW, flipB, doW, doB, idxW, idxB)
        if doW and idxW >= 0:
            if nSubsW >= MAX_THREAT_DELTA:
                deltas[White].needsRefresh = true
                doW = false
            else:
                deltas[White].thSubs[nSubsW] = uint16(idxW)
                inc nSubsW

        if doB and idxB >= 0:
            if nSubsB >= MAX_THREAT_DELTA:
                deltas[Black].needsRefresh = true
                doB = false
            else:
                deltas[Black].thSubs[nSubsB] = uint16(idxB)
                inc nSubsB

    for i in 0..<nAddRaw:
        if not (doW or doB): break
        let e = addRaw[i]
        var idxW, idxB: int32
        threatIndexDual(e, flipW, flipB, doW, doB, idxW, idxB)
        if doW and idxW >= 0:
            if nAddsW >= MAX_THREAT_DELTA:
                deltas[White].needsRefresh = true
                doW = false
            else:
                deltas[White].thAdds[nAddsW] = uint16(idxW)
                inc nAddsW

        if doB and idxB >= 0:
            if nAddsB >= MAX_THREAT_DELTA:
                deltas[Black].needsRefresh = true
                doB = false
            else:
                deltas[Black].thAdds[nAddsB] = uint16(idxB)
                inc nAddsB

    deltas[White].nThSubs = nSubsW
    deltas[White].nThAdds = nAddsW
    deltas[Black].nThSubs = nSubsB
    deltas[Black].nThAdds = nAddsB

proc resolveDeferred*(net: ptr NNUENetwork, b: var Board, state: var NNUEState) {.gcsafe.} =
    let ply = state.current
    let m = state.deferredMove[ply]

    let savedAttackValid = b.attackStateValid
    let savedThreats = b.threats
    let savedPinHV = b.pinHV
    let savedPinD12 = b.pinD12

    b.unmakeMove(m)

    for p in [White, Black]:
        if (state.accFlags[p][ply - 1] and AccNeedsRefresh) != 0:
            net.refreshAccumulator(b, state.acc[p][ply - 1], p)
            state.accFlags[p][ply - 1] = AccComputed

    let us = b.stm
    let movingPt = b.mailbox[m.fromSq.int].pieceType
    let kingToFile = if m.isCastling:
                       (if m.fromSq.file < m.toSq.file: 6 else: 2)
                     else: m.toSq.file
    let kingCross = movingPt == King and ((m.fromSq.file > 3) != (kingToFile > 3))

    when defined(profileNNUE):
        let t0 = rdtsc()
    var deltas {.noinit.}: array[Color, PerspDelta]
    computeDeltaBoth(b, m, deltas, us, kingCross)
    when defined(profileNNUE):
        let t1 = rdtsc()
        profComputeDeltaCalls += 1
        profComputeDeltaCyc += (t1 - t0)

    b.makeMove(m)

    b.attackStateValid = savedAttackValid
    b.threats = savedThreats
    b.pinHV = savedPinHV
    b.pinD12 = savedPinD12

    for p in [White, Black]:
        if deltas[p].needsRefresh:
            state.accFlags[p][ply] = AccNeedsRefresh
        else:
            state.accFlags[p][ply] = 0
            state.delta[p][ply] = deltas[p]

    state.deferred[ply] = false

proc pushAccumulator*(net: ptr NNUENetwork, b: var Board, m: Move,
                      state: var NNUEState) =
    if state.deferred[state.current]:
        resolveDeferred(net, b, state)
    let nextPly = state.current + 1
    state.deferred[nextPly] = true
    state.deferredMove[nextPly] = m
    state.accFlags[White][nextPly] = 0
    state.accFlags[Black][nextPly] = 0
    inc state.current

proc popAccumulator*(state: var NNUEState) {.inline.} =
    state.deferred[state.current] = false
    dec state.current

proc pushNullMove*(net: ptr NNUENetwork, b: var Board, state: var NNUEState) =
    if state.deferred[state.current]:
        resolveDeferred(net, b, state)
    let ply = state.current
    state.deferred[ply + 1] = false
    for p in [White, Black]:
        state.accFlags[p][ply + 1] = state.accFlags[p][ply] and AccNeedsRefresh
        state.delta[p][ply + 1] = PerspDelta()
    inc state.current

proc popNullMove*(state: var NNUEState) {.inline.} =
    state.deferred[state.current] = false
    dec state.current

proc verifyNNUE*(net: ptr NNUENetwork, b: var Board, state: var NNUEState) =
    if state.deferred[state.current]:
        resolveDeferred(net, b, state)
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