import coretypes, bitboard, board, nnuetypes
import std/[streams, endians]

when defined(simd):
    import simd

func featureIndex*(perspective, pieceColor: Color, pt: PieceType, sq: Square, perspectiveKingSq: Square): int {.inline.} =
    let colorIdx = if perspective == pieceColor: 0 else: 1
    let ptIdx = pt.ord  # Pawn=0..King=5
    var sqIdx = if perspective == White: sq.int else: (sq.int xor 56)
    # Horizontal mirror: flip file when perspective king is on files e-h
    if (perspectiveKingSq.int mod 8) > 3:
        sqIdx = sqIdx xor 7
    result = (colorIdx * 6 + ptIdx) * 64 + sqIdx

const NNUE_EMBEDDED* = staticRead("../Net/GyatsoNet1024x16x32.bin")

const
    NET_DATA_BYTES = FT_IN * HL * sizeof(int16) + HL * sizeof(int16) +
        L1_INPUTS * L2_SIZE * sizeof(int8) + L2_SIZE * sizeof(int32) +
        L2_SIZE * L3_SIZE * sizeof(int32) + L3_SIZE * sizeof(int32) +
        L3_SIZE * sizeof(int32) + sizeof(int32)
    NET_PADDING_BYTES = (64 - (NET_DATA_BYTES mod 64)) mod 64

proc readLittleInt16(s: Stream): int16 {.inline.} =
    var raw = s.readInt16()
    littleEndian16(addr result, addr raw)

proc readLittleInt32(s: Stream): int32 {.inline.} =
    var raw = s.readInt32()
    littleEndian32(addr result, addr raw)

proc loadNetworkFromStream*(s: Stream): NNUENetwork =
    for hlIdx in 0..<HL:
        for ftIdx in 0..<FT_IN:
            result.ftWeight[ftIdx][hlIdx] = readLittleInt16(s)

    for i in 0..<HL:
        result.ftBias[i] = readLittleInt16(s)

    for output in 0..<L2_SIZE:
        for input in 0..<L1_INPUTS:
            let tile = input div 4
            let lane = input mod 4
            result.l1Weight[tile][output][lane] = s.readInt8()

    for tile in 0..<L1_TILES:
        for output in 0..<L2_SIZE:
            result.l1DotWeight[tile][output] = result.l1Weight[tile][output]
            when (defined(avx2) and not defined(avxvnni)) or
                    (defined(avx512) and not defined(avx512vnni)):
                for pair in 0..<2:
                    let lane = pair * 2
                    let w0 = result.l1Weight[tile][output][lane].int32
                    let w1 = result.l1Weight[tile][output][lane + 1].int32
                    if abs(w0) + abs(w1) > 128:
                        let encoded = (tile * L2_SIZE + output) * 2 + pair
                        result.l1UnsafePairs[result.l1UnsafeCount] = uint16(encoded)
                        inc result.l1UnsafeCount
                        result.l1DotWeight[tile][output][lane] = 0
                        result.l1DotWeight[tile][output][lane + 1] = 0

    for i in 0..<L2_SIZE:
        result.l1Bias[i] = readLittleInt32(s)

    for output in 0..<L3_SIZE:
        for input in 0..<L2_SIZE:
            result.l2Weight[output][input] = readLittleInt32(s)
            result.l2WeightFloat[output][input] =
                float32(result.l2Weight[output][input]) / float32(Q2)
    for output in 0..<L3_SIZE:
        result.l2Bias[output] = readLittleInt32(s)
        result.l2BiasFloat[output] = float32(result.l2Bias[output]) / float32(Q2)

    for i in 0..<L3_SIZE:
        result.l3Weight[i] = readLittleInt32(s)
        result.l3WeightFloat[i] = float32(result.l3Weight[i]) *
            (float32(EVAL_SCALE) / 16_777_216.0'f32)
    result.l3Bias = readLittleInt32(s)
    result.l3BiasFloat = float32(result.l3Bias) / 16_777_216.0'f32

    let padding = s.readAll()
    if padding.len != NET_PADDING_BYTES:
        raise newException(IOError, "Invalid multilayer NNUE size: expected " &
            $(NET_DATA_BYTES + NET_PADDING_BYTES) & " bytes, got " &
            $(NET_DATA_BYTES + padding.len))
    const padMarker = "bullet"
    for i, byte in padding:
        if byte != padMarker[i mod padMarker.len]:
            raise newException(IOError, "Invalid multilayer NNUE padding")

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

proc reset*(q: var UpdateQueue) {.inline.} =
    q.addCount = 0
    q.subCount = 0

proc queueAddSub*(q: var UpdateQueue, addIdx, subIdx: int) {.inline.} =
    q.adds[q.addCount] = addIdx
    inc q.addCount
    q.subs[q.subCount] = subIdx
    inc q.subCount

proc queueAddSubSub*(q: var UpdateQueue, addIdx, subIdx1, subIdx2: int) {.inline.} =
    q.adds[q.addCount] = addIdx
    inc q.addCount
    q.subs[q.subCount] = subIdx1
    inc q.subCount
    q.subs[q.subCount] = subIdx2
    inc q.subCount

proc apply*(q: var UpdateQueue, net: ptr NNUENetwork,
            oldAcc, newAcc: var Accumulator) {.inline.} =
    if q.addCount == 0 and q.subCount == 0:
        return
    elif q.addCount == 1 and q.subCount == 1:
        net.addSub(q.adds[0], q.subs[0], oldAcc, newAcc)
    elif q.addCount == 1 and q.subCount == 2:
        net.addSubSub(q.adds[0], q.subs[0], q.subs[1], oldAcc, newAcc)
    elif q.addCount == 2 and q.subCount == 2:
        net.addSubAddSub(q.adds[0], q.subs[0], q.adds[1], q.subs[1], oldAcc, newAcc)
    else:
        doAssert false, "invalid add/sub configuration: " & $q.addCount & " adds, " & $q.subCount & " subs"
    q.reset()

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
    net.refreshAccumulator(board, state.white[0], White)
    net.refreshAccumulator(board, state.black[0], Black)
    state.whiteNeedsRefresh[0] = false
    state.blackNeedsRefresh[0] = false

func packPairwiseTile(values: ptr uint8, tile: int): uint32 {.inline.} =
    cast[ptr UncheckedArray[uint32]](values)[tile]

proc forward*(net: ptr NNUENetwork, stmAcc, nstmAcc: var Accumulator): int {.inline.} =
    var pairwise {.align(ALIGNMENT), noinit.}: array[L1_INPUTS, uint8]

    when defined(simd):
        var i = 0
        while i < HL div 2:
            vecPairwisePack(addr pairwise[i], addr stmAcc.data[i],
                            addr stmAcc.data[i + HL div 2])
            vecPairwisePack(addr pairwise[i + HL div 2], addr nstmAcc.data[i],
                            addr nstmAcc.data[i + HL div 2])
            i += PAIRWISE_LANES
    else:
        for i in 0..<(HL div 2):
            let sa = clamp(stmAcc.data[i].int32, 0, QA.int32)
            let sb = clamp(stmAcc.data[i + HL div 2].int32, 0, QA.int32)
            let na = clamp(nstmAcc.data[i].int32, 0, QA.int32)
            let nb = clamp(nstmAcc.data[i + HL div 2].int32, 0, QA.int32)
            pairwise[i] = uint8((sa * sb) shr 8)
            pairwise[i + HL div 2] = uint8((na * nb) shr 8)

    var l1Sums {.noinit.}: array[L2_SIZE, int32]
    when defined(avx512):
        var sums0 = vecZeroI32()
        var sums1 = vecZeroI32()
        var sums2 = vecZeroI32()
        var sums3 = vecZeroI32()
        var tile = 0
        while tile < L1_TILES:
            let p0 = packPairwiseTile(addr pairwise[0], tile)
            let p1 = packPairwiseTile(addr pairwise[0], tile + 1)
            let p2 = packPairwiseTile(addr pairwise[0], tile + 2)
            let p3 = packPairwiseTile(addr pairwise[0], tile + 3)
            sums0 = vecDotTile(sums0, p0, addr net.l1DotWeight[tile][0][0])
            sums1 = vecDotTile(sums1, p1, addr net.l1DotWeight[tile + 1][0][0])
            sums2 = vecDotTile(sums2, p2, addr net.l1DotWeight[tile + 2][0][0])
            sums3 = vecDotTile(sums3, p3, addr net.l1DotWeight[tile + 3][0][0])
            tile += 4
        let total = vecAdd32(vecAdd32(sums0, sums1), vecAdd32(sums2, sums3))
        vecStoreI32(addr l1Sums[0], total)
    elif defined(avx2):
        var s00 = vecZeroI32()
        var s01 = vecZeroI32()
        var s10 = vecZeroI32()
        var s11 = vecZeroI32()
        var s20 = vecZeroI32()
        var s21 = vecZeroI32()
        var s30 = vecZeroI32()
        var s31 = vecZeroI32()
        var tile = 0
        while tile < L1_TILES:
            let p0 = packPairwiseTile(addr pairwise[0], tile)
            let p1 = packPairwiseTile(addr pairwise[0], tile + 1)
            let p2 = packPairwiseTile(addr pairwise[0], tile + 2)
            let p3 = packPairwiseTile(addr pairwise[0], tile + 3)
            let partial0 = vecDotTilePair(s00, s01, p0,
                addr net.l1DotWeight[tile][0][0], addr net.l1DotWeight[tile][8][0])
            let partial1 = vecDotTilePair(s10, s11, p1,
                addr net.l1DotWeight[tile + 1][0][0], addr net.l1DotWeight[tile + 1][8][0])
            let partial2 = vecDotTilePair(s20, s21, p2,
                addr net.l1DotWeight[tile + 2][0][0], addr net.l1DotWeight[tile + 2][8][0])
            let partial3 = vecDotTilePair(s30, s31, p3,
                addr net.l1DotWeight[tile + 3][0][0], addr net.l1DotWeight[tile + 3][8][0])
            s00 = partial0.a
            s01 = partial0.b
            s10 = partial1.a
            s11 = partial1.b
            s20 = partial2.a
            s21 = partial2.b
            s30 = partial3.a
            s31 = partial3.b
            tile += 4
        let total0 = vecAdd32(vecAdd32(s00, s10), vecAdd32(s20, s30))
        let total1 = vecAdd32(vecAdd32(s01, s11), vecAdd32(s21, s31))
        vecStoreI32(addr l1Sums[0], total0)
        vecStoreI32(addr l1Sums[8], total1)
    elif defined(neon) or defined(arm64) or defined(aarch64):
        var sums: array[L2_SIZE div 4, VEPI32]
        for lane in 0..<sums.len: sums[lane] = vecZeroI32()
        for tile in 0..<L1_TILES:
            let packed = packPairwiseTile(addr pairwise[0], tile)
            if packed != 0:
                for group in 0..<sums.len:
                    sums[group] = vecDotTile(sums[group], packed,
                        addr net.l1Weight[tile][group * 4][0])
        for group in 0..<sums.len:
            vecStoreI32(addr l1Sums[group * 4], sums[group])
    else:
        for output in 0..<L2_SIZE: l1Sums[output] = 0
        for tile in 0..<L1_TILES:
            let offset = tile * 4
            let packed = packPairwiseTile(addr pairwise[0], tile)
            if packed != 0:
                for output in 0..<L2_SIZE:
                    for lane in 0..<4:
                        l1Sums[output] += int32(pairwise[offset + lane]) *
                            int32(net.l1Weight[tile][output][lane])

    when (defined(avx2) and not defined(avxvnni)) or
            (defined(avx512) and not defined(avx512vnni)):
        for active in 0..<net.l1UnsafeCount:
            let encoded = system.int(net.l1UnsafePairs[active])
            let pair = encoded and 1
            let output = (encoded div 2) mod L2_SIZE
            let tile = encoded div (L2_SIZE * 2)
            let offset = tile * 4
            let lane = pair * 2
            l1Sums[output] += int32(pairwise[offset + lane]) *
                int32(net.l1Weight[tile][output][lane])
            l1Sums[output] += int32(pairwise[offset + lane + 1]) *
                int32(net.l1Weight[tile][output][lane + 1])

    var hidden {.noinit.}: array[L2_SIZE, float32]
    const L1_SCALE = float32(QA * QB)
    for output in 0..<L2_SIZE:
        let preActivation = clamp(l1Sums[output] + net.l1Bias[output], 0, QA.int32 * QB.int32)
        let clipped = float32(preActivation) / L1_SCALE
        hidden[output] = clipped * clipped

    var l2Output {.noinit.}: array[L3_SIZE, float32]
    for output in 0..<L3_SIZE:
        var sum = net.l2BiasFloat[output]
        for input in 0..<L2_SIZE:
            sum += hidden[input] * net.l2WeightFloat[output][input]
        l2Output[output] = clamp(sum, 0.0'f32, 1.0'f32)

    var output = net.l3BiasFloat
    for input in 0..<L3_SIZE:
        output += l2Output[input] * net.l3WeightFloat[input]
    return system.int(output * float32(EVAL_SCALE))

proc ensureAccumulatorReady*(net: ptr NNUENetwork, board: Board, state: var NNUEState) {.inline.} =
    ## Lazy refresh: recompute accumulator if king crossed mirror boundary
    let ply = state.current
    if state.whiteNeedsRefresh[ply]:
        net.refreshAccumulator(board, state.white[ply], White)
        state.whiteNeedsRefresh[ply] = false
    if state.blackNeedsRefresh[ply]:
        net.refreshAccumulator(board, state.black[ply], Black)
        state.blackNeedsRefresh[ply] = false

proc nnueEvaluate*(net: ptr NNUENetwork, board: Board, state: var NNUEState): int {.inline.} =
    # Ensure accumulators are valid before evaluation
    ensureAccumulatorReady(net, board, state)
    let ply = state.current
    if board.stm == White:
        result = forward(net, state.white[ply], state.black[ply])
    else:
        result = forward(net, state.black[ply], state.white[ply])

    # Clamp to safe range
    const MaxEval = MateValue - MaxPly - 100
    if result > MaxEval: result = MaxEval
    elif result < -MaxEval: result = -MaxEval

proc computeUpdateQueue*(net: ptr NNUENetwork, board: Board, m: Move,
                         perspective: Color, state: var NNUEState) =
    let us = board.stm
    let them = us.opposite()
    let fromSq = m.fromSq
    let toSq = m.toSq
    let movingPiece = board.mailbox[fromSq.int]
    let movingPt = movingPiece.pieceType
    let movingColor = movingPiece.color

    # Get perspective king square for horizontal mirroring
    let perspKingSq = board.kingSquare(perspective)

    var queue: UpdateQueue
    queue.reset()

    let ply = state.current

    if m.isCastling:
        let kingFrom = fromSq
        let rookFrom = toSq
        let kingTo   = if fromSq.file < rookFrom.file: fromSq.withFile(6) else: fromSq.withFile(2)
        let rookTo   = if fromSq.file < rookFrom.file: fromSq.withFile(5) else: fromSq.withFile(3)

        let kingAddIdx = featureIndex(perspective, us, King, kingTo,   perspKingSq)
        let kingSubIdx = featureIndex(perspective, us, King, kingFrom, perspKingSq)
        let rookAddIdx = featureIndex(perspective, us, Rook, rookTo,   perspKingSq)
        let rookSubIdx = featureIndex(perspective, us, Rook, rookFrom, perspKingSq)

        queue.queueAddSub(kingAddIdx, kingSubIdx)
        queue.queueAddSub(rookAddIdx, rookSubIdx)

    elif m.isEnPassant:
        let capSq = if us == White: (toSq.int - 8).Square else: (toSq.int + 8).Square
        let addIdx = featureIndex(perspective, us, Pawn, toSq, perspKingSq)
        let subIdx1 = featureIndex(perspective, us, Pawn, fromSq, perspKingSq)
        let subIdx2 = featureIndex(perspective, them, Pawn, capSq, perspKingSq)
        queue.queueAddSubSub(addIdx, subIdx1, subIdx2)

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
            queue.queueAddSubSub(addIdx, subIdx1, subIdx2)
        else:
            let addIdx = featureIndex(perspective, us, promoPt, toSq, perspKingSq)
            let subIdx = featureIndex(perspective, us, Pawn, fromSq, perspKingSq)
            queue.queueAddSub(addIdx, subIdx)

    else:
        let capturedPiece = board.mailbox[toSq.int]
        if capturedPiece != NoPiece:
            let capturedPt    = capturedPiece.pieceType
            let capturedColor = capturedPiece.color
            let addIdx  = featureIndex(perspective, movingColor, movingPt, toSq, perspKingSq)
            let subIdx1 = featureIndex(perspective, movingColor, movingPt, fromSq, perspKingSq)
            let subIdx2 = featureIndex(perspective, capturedColor, capturedPt, toSq, perspKingSq)
            queue.queueAddSubSub(addIdx, subIdx1, subIdx2)
        else:
            let addIdx = featureIndex(perspective, movingColor, movingPt, toSq, perspKingSq)
            let subIdx = featureIndex(perspective, movingColor, movingPt, fromSq, perspKingSq)
            queue.queueAddSub(addIdx, subIdx)
    if perspective == White:
        queue.apply(net, state.white[ply], state.white[ply + 1])
    else:
        queue.apply(net, state.black[ply], state.black[ply + 1])

proc pushAccumulator*(net: ptr NNUENetwork, board: Board, m: Move,
                      state: var NNUEState) =
    let ply = state.current
    let us = board.stm
    let movingPt = board.mailbox[m.fromSq.int].pieceType

    ensureAccumulatorReady(net, board, state)

    for perspective in [White, Black]:
        let isOurKingMoving = (perspective == us) and (movingPt == King)

        if isOurKingMoving:
            let fromFile = m.fromSq.file
            let toFile   = m.toSq.file
            if (fromFile > 3) != (toFile > 3):
                if perspective == White:
                    state.whiteNeedsRefresh[ply + 1] = true
                else:
                    state.blackNeedsRefresh[ply + 1] = true
                continue

        # Normal incremental update
        computeUpdateQueue(net, board, m, perspective, state)
        if perspective == White:
            state.whiteNeedsRefresh[ply + 1] = false
        else:
            state.blackNeedsRefresh[ply + 1] = false

    inc state.current

proc popAccumulator*(state: var NNUEState) {.inline.} =
    dec state.current

proc pushNullMove*(state: var NNUEState) =
    let ply = state.current
    state.whiteNeedsRefresh[ply + 1] = state.whiteNeedsRefresh[ply]
    state.blackNeedsRefresh[ply + 1] = state.blackNeedsRefresh[ply]
    if not state.whiteNeedsRefresh[ply]:
        state.white[ply + 1] = state.white[ply]
    if not state.blackNeedsRefresh[ply]:
        state.black[ply + 1] = state.black[ply]
    inc state.current

proc popNullMove*(state: var NNUEState) {.inline.} =
    dec state.current

proc verifyNNUE*(net: ptr NNUENetwork, board: Board, state: var NNUEState) =
    ensureAccumulatorReady(net, board, state)

    var whiteRef, blackRef: Accumulator
    net.refreshAccumulator(board, whiteRef, White)
    net.refreshAccumulator(board, blackRef, Black)

    let ply = state.current
    for i in 0..<HL:
        doAssert state.white[ply].data[i] == whiteRef.data[i],
            "White accumulator mismatch at index " & $i &
            ": incremental=" & $state.white[ply].data[i] &
            " expected=" & $whiteRef.data[i]
        doAssert state.black[ply].data[i] == blackRef.data[i],
            "Black accumulator mismatch at index " & $i &
            ": incremental=" & $state.black[ply].data[i] &
            " expected=" & $blackRef.data[i]