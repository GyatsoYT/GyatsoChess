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

const NNUE_EMBEDDED* = staticRead("../Net/GyatsoNet1024.bin")

proc loadNetworkFromStream*(s: Stream): NNUENetwork =
    for hlIdx in 0..<HL:
        for ftIdx in 0..<FT_IN:
            var raw = s.readInt16()
            var val: int16
            littleEndian16(addr val, addr raw)
            result.ftWeight[ftIdx][hlIdx] = val

    for i in 0..<HL:
        var raw = s.readInt16()
        var val: int16
        littleEndian16(addr val, addr raw)
        result.ftBias[i] = val

    for i in 0..<(HL * 2):
        var raw = s.readInt16()
        var val: int16
        littleEndian16(addr val, addr raw)
        result.l1Weight[i] = val

    var rawBias = s.readInt32()
    var val32: int32
    littleEndian32(addr val32, addr rawBias)
    result.l1Bias = val32

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

proc forward*(net: ptr NNUENetwork, stmAcc, nstmAcc: var Accumulator): int {.inline.} =
    when not defined(simd):
        var output: int32 = 0

        # STM half
        for i in 0..<HL:
            let input = stmAcc.data[i].int32
            let weight = net.l1Weight[i].int32
            let clipped = clamp(input, 0, QA.int32)
            output += (clipped * weight).int16 * clipped

        # NSTM half
        for i in 0..<HL:
            let input = nstmAcc.data[i].int32
            let weight = net.l1Weight[HL + i].int32
            let clipped = clamp(input, 0, QA.int32)
            output += (clipped * weight).int16 * clipped
        return system.int((output div QA + net.l1Bias) * EVAL_SCALE div (QA * QB))

    else:
        let qa   = vecSetOne16(QA.int16)
        let zero = vecZero16()
        var sumS0 = vecZero32()
        var sumS1 = vecZero32()
        var sumN0 = vecZero32()
        var sumN1 = vecZero32()

        var i = 0
        while i < HL:
            # STM pair
            let inpS0 = vecLoad(addr stmAcc.data[i])
            let inpS1 = vecLoad(addr stmAcc.data[i + CHUNK_SIZE])
            let clipS0 = vecMin16(vecMax16(inpS0, zero), qa)
            let clipS1 = vecMin16(vecMax16(inpS1, zero), qa)
            sumS0 = vecAdd32(sumS0, vecMadd16(vecMullo16(clipS0, vecLoad(addr net.l1Weight[i])),
                                              clipS0))
            sumS1 = vecAdd32(sumS1, vecMadd16(vecMullo16(clipS1, vecLoad(addr net.l1Weight[i + CHUNK_SIZE])),
                                              clipS1))
            # NSTM pair
            let inpN0 = vecLoad(addr nstmAcc.data[i])
            let inpN1 = vecLoad(addr nstmAcc.data[i + CHUNK_SIZE])
            let clipN0 = vecMin16(vecMax16(inpN0, zero), qa)
            let clipN1 = vecMin16(vecMax16(inpN1, zero), qa)
            sumN0 = vecAdd32(sumN0, vecMadd16(vecMullo16(clipN0, vecLoad(addr net.l1Weight[HL + i])),
                                              clipN0))
            sumN1 = vecAdd32(sumN1, vecMadd16(vecMullo16(clipN1, vecLoad(addr net.l1Weight[HL + i + CHUNK_SIZE])),
                                              clipN1))
            i += CHUNK_SIZE * 2

        let rawSum = vecReduceAdd32(
            vecAdd32(vecAdd32(sumS0, sumS1), vecAdd32(sumN0, sumN1)))
        return system.int((rawSum div QA + net.l1Bias) * EVAL_SCALE div (QA * QB))

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