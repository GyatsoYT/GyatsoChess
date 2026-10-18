import coretypes, bitboard, board, nnuetypes
import std/[streams, strutils]
import simd
when defined(nnueStats):
    import std/atomics

func featureIndex*(perspective, pieceColor: Color, pt: PieceType, sq: Square, perspectiveKingSq: Square): int {.inline.} =
    let colorIdx = if perspective == pieceColor: 0 else: 1
    let ptIdx = pt.ord  # Pawn=0..King=5
    var sqIdx = if perspective == White: sq.int else: (sq.int xor 56)
    # Horizontal mirror: flip file when perspective king is on files e-h
    if (perspectiveKingSq.int mod 8) > 3:
        sqIdx = sqIdx xor 7
    result = (colorIdx * 6 + ptIdx) * 64 + sqIdx

const
    NNUE_EMBEDDED* = staticRead("../Net/GyatsoNet1024x16x32.bin")
    NNUE_PAIRWISE_PERMUTATION = staticRead("../Net/GyatsoNet1024x16x32.perm")
    NNUE_RAW_BYTES* = FT_IN * HL * 2 + HL * 2 + HL * L2_SIZE +
                     L2_SIZE * 4 + L2_SIZE * L3_SIZE * 4 +
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

proc readPairwisePermutation(): array[PAIR_COUNT, int] =
    let values = NNUE_PAIRWISE_PERMUTATION.splitWhitespace()
    if values.len != PAIR_COUNT:
        raise newException(IOError, "NNUE permutation must contain exactly " & $PAIR_COUNT & " indices")

    var seen: array[PAIR_COUNT, bool]
    for newIndex, token in values:
        var oldIndex: int
        try:
            oldIndex = parseInt(token)
        except ValueError:
            raise newException(IOError, "Invalid integer in NNUE permutation: " & token)
        if oldIndex < 0 or oldIndex >= PAIR_COUNT or seen[oldIndex]:
            raise newException(IOError, "NNUE permutation indices must be unique values in 0.." & $(PAIR_COUNT - 1))
        result[newIndex] = oldIndex
        seen[oldIndex] = true

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
            for blockIdx in 0..<(HL div 4):
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

proc loadNetworkFromBytes(data: string): NNUENetwork =
    if data.len != NNUE_FILE_BYTES:
        raise newException(IOError,
            "Invalid multilayer NNUE length: got " & $data.len &
            " bytes; expected " & $NNUE_FILE_BYTES & " (raw tensors plus Bullet padding)")

    const PaddingMarker = "bullet"
    for i in 0..<NNUE_PADDING_BYTES:
        if data[NNUE_RAW_BYTES + i] != PaddingMarker[i mod PaddingMarker.len]:
            raise newException(IOError, "Invalid multilayer NNUE padding marker")

    var offset = 0
    let permutation = readPairwisePermutation()
    var newIndexByOld: array[PAIR_COUNT, int]
    for newIndex, oldIndex in permutation:
        newIndexByOld[oldIndex] = newIndex

    for hidden in 0..<HL:
        let side = hidden div PAIR_COUNT
        let pair = hidden mod PAIR_COUNT
        let permutedHidden = side * PAIR_COUNT + newIndexByOld[pair]
        for feature in 0..<FT_IN:
            result.ftWeight[feature][permutedHidden] = data.readI16(offset)

    for hidden in 0..<HL:
        let side = hidden div PAIR_COUNT
        let pair = hidden mod PAIR_COUNT
        let permutedHidden = side * PAIR_COUNT + newIndexByOld[pair]
        result.ftBias[permutedHidden] = data.readI16(offset)

    for output in 0..<L2_SIZE:
        for oldInput in 0..<HL:
            let side = oldInput div PAIR_COUNT
            let pair = oldInput mod PAIR_COUNT
            let input = side * PAIR_COUNT + newIndexByOld[pair]
            result.l1Weight[input div 4][output][input mod 4] = data.readI8(offset)

    for output in 0..<L2_SIZE:
        result.l1Bias[output] = data.readI32(offset)

    for output in 0..<L3_SIZE:
        for input in 0..<L2_SIZE:
            result.l2Weight[input][output] = data.readI32(offset)

    for output in 0..<L3_SIZE:
        result.l2Bias[output] = data.readI32(offset)

    for input in 0..<L3_SIZE:
        result.l3Weight[input] = data.readI32(offset)
    result.l3Bias = data.readI32(offset)

    doAssert offset == NNUE_RAW_BYTES

    result.l2Int32Safe = true
    for output in 0..<L3_SIZE:
        var bound = int64(result.l2Bias[output])
        if bound < 0: bound = -bound
        for input in 0..<L2_SIZE:
            var weight = int64(result.l2Weight[input][output])
            if weight < 0: weight = -weight
            bound += int64(QB * QB) * weight
        if bound > int64(high(int32)):
            result.l2Int32Safe = false

    result.l2Int16Safe = result.l2Int32Safe
    for output in 0..<L3_SIZE:
        for input in 0..<L2_SIZE:
            let w = result.l2Weight[input][output]
            if w < int32(low(int16)) or w > int32(high(int16)):
                result.l2Int16Safe = false
    if result.l2Int16Safe:
        for pair in 0..<(L2_SIZE div 2):
            for output in 0..<L3_SIZE:
                result.l2WeightPacked[pair][output][0] = int16(result.l2Weight[pair * 2][output])
                result.l2WeightPacked[pair][output][1] = int16(result.l2Weight[pair * 2 + 1][output])

proc loadNetworkFromStream*(s: Stream): NNUENetwork =
    return loadNetworkFromBytes(s.readAll())

proc loadNetwork*(path: string): NNUENetwork =
    let s = newFileStream(path, fmRead)
    if s == nil:
        raise newException(IOError, "Cannot open NNUE network file: " & path)
    defer: s.close()
    return loadNetworkFromStream(s)

proc loadNetworkFromEmbedded*(): NNUENetwork =
    let s = newStringStream(NNUE_EMBEDDED)
    return loadNetworkFromStream(s)

proc initAccumulator*(net: ptr NNUENetwork, acc: var Accumulator) {.inline.} =
    acc.data = net.ftBias

proc addFeature*(net: ptr NNUENetwork, index: int, acc: var Accumulator) {.inline.} =
    when not defined(simd):
        for o in 0..<HL:
            acc.data[o] += net.ftWeight[index][o]
    else:
        var o = 0
        while o < HL:
            let w0 = vecLoad(addr net.ftWeight[index][o])
            let d0 = vecLoad(addr acc.data[o])
            let w1 = vecLoad(addr net.ftWeight[index][o + CHUNK_SIZE])
            let d1 = vecLoad(addr acc.data[o + CHUNK_SIZE])
            vecStore(addr acc.data[o], vecAdd16(d0, w0))
            vecStore(addr acc.data[o + CHUNK_SIZE], vecAdd16(d1, w1))
            o += CHUNK_SIZE * 2

proc removeFeature*(net: ptr NNUENetwork, index: int, acc: var Accumulator) {.inline.} =
    when not defined(simd):
        for o in 0..<HL:
            acc.data[o] -= net.ftWeight[index][o]
    else:
        var o = 0
        while o < HL:
            let w0 = vecLoad(addr net.ftWeight[index][o])
            let d0 = vecLoad(addr acc.data[o])
            let w1 = vecLoad(addr net.ftWeight[index][o + CHUNK_SIZE])
            let d1 = vecLoad(addr acc.data[o + CHUNK_SIZE])
            vecStore(addr acc.data[o], vecSub16(d0, w0))
            vecStore(addr acc.data[o + CHUNK_SIZE], vecSub16(d1, w1))
            o += CHUNK_SIZE * 2

proc addSub*(net: ptr NNUENetwork, addIdx, subIdx: int,
             prev: var Accumulator, curr: var Accumulator) {.inline.} =
    when not defined(simd):
        for i in 0..<HL:
            curr.data[i] = prev.data[i] + net.ftWeight[addIdx][i] - net.ftWeight[subIdx][i]
    else:
        var i = 0
        while i < HL:
            let a0 = vecLoad(addr net.ftWeight[addIdx][i])
            let b0 = vecLoad(addr net.ftWeight[subIdx][i])
            let p0 = vecLoad(addr prev.data[i])
            let a1 = vecLoad(addr net.ftWeight[addIdx][i + CHUNK_SIZE])
            let b1 = vecLoad(addr net.ftWeight[subIdx][i + CHUNK_SIZE])
            let p1 = vecLoad(addr prev.data[i + CHUNK_SIZE])
            vecStore(addr curr.data[i], vecSub16(vecAdd16(p0, a0), b0))
            vecStore(addr curr.data[i + CHUNK_SIZE], vecSub16(vecAdd16(p1, a1), b1))
            i += CHUNK_SIZE * 2

proc addSubSub*(net: ptr NNUENetwork, addIdx, subIdx1, subIdx2: int,
                prev: var Accumulator, curr: var Accumulator) {.inline.} =
    when not defined(simd):
        for i in 0..<HL:
            curr.data[i] = prev.data[i] + net.ftWeight[addIdx][i] - net.ftWeight[subIdx1][i] - net.ftWeight[subIdx2][i]
    else:
        var i = 0
        while i < HL:
            let a0 = vecLoad(addr net.ftWeight[addIdx][i])
            let b0 = vecLoad(addr net.ftWeight[subIdx1][i])
            let c0 = vecLoad(addr net.ftWeight[subIdx2][i])
            let p0 = vecLoad(addr prev.data[i])
            let a1 = vecLoad(addr net.ftWeight[addIdx][i + CHUNK_SIZE])
            let b1 = vecLoad(addr net.ftWeight[subIdx1][i + CHUNK_SIZE])
            let c1 = vecLoad(addr net.ftWeight[subIdx2][i + CHUNK_SIZE])
            let p1 = vecLoad(addr prev.data[i + CHUNK_SIZE])
            vecStore(addr curr.data[i], vecSub16(vecSub16(vecAdd16(p0, a0), b0), c0))
            vecStore(addr curr.data[i + CHUNK_SIZE], vecSub16(vecSub16(vecAdd16(p1, a1), b1), c1))
            i += CHUNK_SIZE * 2

proc addSubAddSub*(net: ptr NNUENetwork, addIdx1, subIdx1, addIdx2, subIdx2: int,
                   prev: var Accumulator, curr: var Accumulator) {.inline.} =
    when not defined(simd):
        for i in 0..<HL:
            curr.data[i] = prev.data[i] + net.ftWeight[addIdx1][i] - net.ftWeight[subIdx1][i] +
                           net.ftWeight[addIdx2][i] - net.ftWeight[subIdx2][i]
    else:
        var i = 0
        while i < HL:
            let d0_a = vecSub16(vecLoad(addr net.ftWeight[addIdx1][i]),
                                vecLoad(addr net.ftWeight[subIdx1][i]))
            let d0_b = vecSub16(vecLoad(addr net.ftWeight[addIdx2][i]),
                                vecLoad(addr net.ftWeight[subIdx2][i]))
            let d1_a = vecSub16(vecLoad(addr net.ftWeight[addIdx1][i + CHUNK_SIZE]),
                                vecLoad(addr net.ftWeight[subIdx1][i + CHUNK_SIZE]))
            let d1_b = vecSub16(vecLoad(addr net.ftWeight[addIdx2][i + CHUNK_SIZE]),
                                vecLoad(addr net.ftWeight[subIdx2][i + CHUNK_SIZE]))
            vecStore(addr curr.data[i],
                     vecAdd16(vecLoad(addr prev.data[i]), vecAdd16(d0_a, d0_b)))
            vecStore(addr curr.data[i + CHUNK_SIZE],
                     vecAdd16(vecLoad(addr prev.data[i + CHUNK_SIZE]), vecAdd16(d1_a, d1_b)))
            i += CHUNK_SIZE * 2

proc applyDelta(net: ptr NNUENetwork, d: AccumulatorDelta,
                prev, curr: var Accumulator) {.inline.} =
    template f(x: uint16): system.int = system.int(x)
    if d.addCount == 1:
        if d.subCount == 1:
            net.addSub(f(d.adds[0]), f(d.subs[0]), prev, curr)
        else:
            net.addSubSub(f(d.adds[0]), f(d.subs[0]), f(d.subs[1]), prev, curr)
    elif d.addCount == 2:
        net.addSubAddSub(f(d.adds[0]), f(d.subs[0]), f(d.adds[1]), f(d.subs[1]), prev, curr)
    else:
        curr = prev

proc refreshAccumulator*(net: ptr NNUENetwork, board: Board, acc: var Accumulator, perspective: Color) =
    ## Full recompute of accumulator from board state
    let perspKingSq = board.kingSquare(perspective)
    net.initAccumulator(acc)
    var occ = board.occupied
    while occ != Bitboard(0):
        let sq = poplsb(occ)
        let piece = board.mailbox[sq.int]
        if piece == NoPiece: continue
        let pt = piece.pieceType
        let pc = piece.color
        let idx = featureIndex(perspective, pc, pt, sq, perspKingSq)
        net.addFeature(idx, acc)

proc refreshState*(net: ptr NNUENetwork, board: Board, state: var NNUEState) =
    state.current = 0
    for p in [White, Black]:
        net.refreshAccumulator(board, state.acc[p][0], p)
        state.computed[p][0] = true
        state.needsRefresh[p][0] = false

proc forward*(net: ptr NNUENetwork, stmAcc, nstmAcc: var Accumulator): int {.inline.} =
    var pairwise {.noinit.}: array[HL, uint8]
    var l1Sums {.noinit.}: array[L2_SIZE, int32]
    when defined(avx512) or defined(avx2) or defined(neon) or defined(arm64) or defined(aarch64):
        var blocks {.noinit.}: array[256, uint16]
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

proc updateAccumulator(net: ptr NNUENetwork, board: Board, state: var NNUEState,
                       p: Color) {.inline.} =
    ## Bring acc[p][current] up to date. Plies below `current` never have an
    ## unresolved refresh behind an uncomputed entry (pushes resolve it), and
    ## the root is always computed, so the backward walk terminates on a
    ## valid accumulator.
    let n = state.current
    if state.computed[p][n]:
        return
    if state.needsRefresh[p][n]:
        net.refreshAccumulator(board, state.acc[p][n], p)
        state.needsRefresh[p][n] = false
        state.computed[p][n] = true
        return
    var j = n - 1
    while not state.computed[p][j]:
        dec j
    while j < n:
        net.applyDelta(state.delta[p][j + 1], state.acc[p][j], state.acc[p][j + 1])
        inc j
        state.computed[p][j] = true

proc nnueEvaluate*(net: ptr NNUENetwork, board: Board, state: var NNUEState): int {.inline.} =
    let ply = state.current
    let us = board.stm
    let them = us.opposite()
    net.updateAccumulator(board, state, us)
    net.updateAccumulator(board, state, them)
    result = forward(net, state.acc[us][ply], state.acc[them][ply])

    # Clamp to safe range
    const MaxEval = MateValue - MaxPly - 100
    if result > MaxEval: result = MaxEval
    elif result < -MaxEval: result = -MaxEval

func computeDelta(board: Board, m: Move, perspective: Color): AccumulatorDelta {.inline.} =
    let us = board.stm
    let them = us.opposite()
    let fromSq = m.fromSq
    let toSq = m.toSq
    let movingPiece = board.mailbox[fromSq.int]
    let movingPt = movingPiece.pieceType
    let movingColor = movingPiece.color

    # Get perspective king square for horizontal mirroring
    let perspKingSq = board.kingSquare(perspective)

    template addSub(a, s: int) =
        result.adds[result.addCount] = uint16(a)
        inc result.addCount
        result.subs[result.subCount] = uint16(s)
        inc result.subCount
    template addSubSub(a, s1, s2: int) =
        addSub(a, s1)
        result.subs[result.subCount] = uint16(s2)
        inc result.subCount

    if m.isCastling:
        let kingFrom = fromSq
        let rookFrom = toSq
        let kingTo   = if fromSq.file < rookFrom.file: fromSq.withFile(6) else: fromSq.withFile(2)
        let rookTo   = if fromSq.file < rookFrom.file: fromSq.withFile(5) else: fromSq.withFile(3)

        let kingAddIdx = featureIndex(perspective, us, King, kingTo,   perspKingSq)
        let kingSubIdx = featureIndex(perspective, us, King, kingFrom, perspKingSq)
        let rookAddIdx = featureIndex(perspective, us, Rook, rookTo,   perspKingSq)
        let rookSubIdx = featureIndex(perspective, us, Rook, rookFrom, perspKingSq)

        addSub(kingAddIdx, kingSubIdx)
        addSub(rookAddIdx, rookSubIdx)

    elif m.isEnPassant:
        let capSq = if us == White: (toSq.int - 8).Square else: (toSq.int + 8).Square
        let addIdx = featureIndex(perspective, us, Pawn, toSq, perspKingSq)
        let subIdx1 = featureIndex(perspective, us, Pawn, fromSq, perspKingSq)
        let subIdx2 = featureIndex(perspective, them, Pawn, capSq, perspKingSq)
        addSubSub(addIdx, subIdx1, subIdx2)

    elif m.isPromotion:
        let promoPt = case m.promoType
            of PromoKnight: Knight
            of PromoBishop: Bishop
            of PromoRook:   Rook
            of PromoQueen:  Queen
        let capturedPiece = board.mailbox[toSq.int]
        if capturedPiece != NoPiece:
            let capturedPt    = capturedPiece.pieceType
            let capturedColor = capturedPiece.color
            let addIdx  = featureIndex(perspective, us, promoPt, toSq, perspKingSq)
            let subIdx1 = featureIndex(perspective, us, Pawn, fromSq, perspKingSq)
            let subIdx2 = featureIndex(perspective, capturedColor, capturedPt, toSq, perspKingSq)
            addSubSub(addIdx, subIdx1, subIdx2)
        else:
            let addIdx = featureIndex(perspective, us, promoPt, toSq, perspKingSq)
            let subIdx = featureIndex(perspective, us, Pawn, fromSq, perspKingSq)
            addSub(addIdx, subIdx)

    else:
        let capturedPiece = board.mailbox[toSq.int]
        if capturedPiece != NoPiece:
            let capturedPt    = capturedPiece.pieceType
            let capturedColor = capturedPiece.color
            let addIdx  = featureIndex(perspective, movingColor, movingPt, toSq, perspKingSq)
            let subIdx1 = featureIndex(perspective, movingColor, movingPt, fromSq, perspKingSq)
            let subIdx2 = featureIndex(perspective, capturedColor, capturedPt, toSq, perspKingSq)
            addSubSub(addIdx, subIdx1, subIdx2)
        else:
            let addIdx = featureIndex(perspective, movingColor, movingPt, toSq, perspKingSq)
            let subIdx = featureIndex(perspective, movingColor, movingPt, fromSq, perspKingSq)
            addSub(addIdx, subIdx)

proc pushAccumulator*(net: ptr NNUENetwork, board: Board, m: Move,
                      state: var NNUEState) =
    ## Record the move's feature delta; it is applied only if a descendant
    ## position is evaluated.
    let ply = state.current
    let us = board.stm
    let movingPt = board.mailbox[m.fromSq.int].pieceType

    for perspective in [White, Black]:
        # The board is at this ply only now, so a pending refresh must be
        # resolved before the next ply can depend on it.
        if state.needsRefresh[perspective][ply]:
            net.refreshAccumulator(board, state.acc[perspective][ply], perspective)
            state.needsRefresh[perspective][ply] = false
            state.computed[perspective][ply] = true

        state.computed[perspective][ply + 1] = false
        # Castling is encoded king->rook, so the king's real destination is
        # the g- or c-file, not toSq.
        let kingToFile = if m.isCastling: (if m.fromSq.file < m.toSq.file: 6 else: 2)
                         else: m.toSq.file
        if perspective == us and movingPt == King and
                (m.fromSq.file > 3) != (kingToFile > 3):
            state.needsRefresh[perspective][ply + 1] = true
        else:
            state.needsRefresh[perspective][ply + 1] = false
            state.delta[perspective][ply + 1] = computeDelta(board, m, perspective)

    inc state.current

proc popAccumulator*(state: var NNUEState) {.inline.} =
    dec state.current

proc pushNullMove*(state: var NNUEState) =
    ## Pieces are unchanged: the child reuses the parent through an empty
    ## delta, or inherits a pending refresh (the board has the same pieces).
    let ply = state.current
    for p in [White, Black]:
        state.computed[p][ply + 1] = false
        state.needsRefresh[p][ply + 1] = state.needsRefresh[p][ply]
        state.delta[p][ply + 1] = AccumulatorDelta()
    inc state.current

proc popNullMove*(state: var NNUEState) {.inline.} =
    dec state.current

proc verifyNNUE*(net: ptr NNUENetwork, board: Board, state: var NNUEState) =
    let ply = state.current
    for p in [White, Black]:
        net.updateAccumulator(board, state, p)
        var reference: Accumulator
        net.refreshAccumulator(board, reference, p)
        for i in 0..<HL:
            doAssert state.acc[p][ply].data[i] == reference.data[i],
                $p & " accumulator mismatch at index " & $i &
                ": incremental=" & $state.acc[p][ply].data[i] &
                " expected=" & $reference.data[i]