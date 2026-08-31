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

const NNUE_EMBEDDED* = staticRead("../Net/GyatsoNet512HMOB.bin")

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

    for b in 0..<NUM_OUTPUT_BUCKETS:
        for neuron in 0..<(HL * 2):
            var raw = s.readInt16()
            var val: int16
            littleEndian16(addr val, addr raw)
            result.l1Weight[b][neuron] = val

    for b in 0..<NUM_OUTPUT_BUCKETS:
        var rawBias = s.readInt16()
        var val16: int16
        littleEndian16(addr val16, addr rawBias)
        result.l1Bias[b] = val16

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
            let weight = vecLoad(addr net.ftWeight[index][o])
            let data = vecLoad(addr acc.data[o])
            let sum = vecAdd16(weight, data)
            vecStore(addr acc.data[o], sum)
            o += CHUNK_SIZE

proc removeFeature*(net: ptr NNUENetwork, index: int, acc: var Accumulator) {.inline.} =
    when not defined(simd):
        for o in 0..<HL:
            acc.data[o] -= net.ftWeight[index][o]
    else:
        var o = 0
        while o < HL:
            let weight = vecLoad(addr net.ftWeight[index][o])
            let data = vecLoad(addr acc.data[o])
            let sum = vecSub16(data, weight)
            vecStore(addr acc.data[o], sum)
            o += CHUNK_SIZE

proc addSub*(net: ptr NNUENetwork, addIdx, subIdx: int,
             prev: var Accumulator, curr: var Accumulator) {.inline.} =
    when not defined(simd):
        for i in 0..<HL:
            curr.data[i] = prev.data[i] + net.ftWeight[addIdx][i] - net.ftWeight[subIdx][i]
    else:
        var i = 0
        while i < HL:
            let a = vecLoad(addr net.ftWeight[addIdx][i])
            let b = vecLoad(addr net.ftWeight[subIdx][i])
            let p = vecLoad(addr prev.data[i])
            let r = vecSub16(vecAdd16(p, a), b)
            vecStore(addr curr.data[i], r)
            i += CHUNK_SIZE

proc addSubSub*(net: ptr NNUENetwork, addIdx, subIdx1, subIdx2: int,
                prev: var Accumulator, curr: var Accumulator) {.inline.} =
    when not defined(simd):
        for i in 0..<HL:
            curr.data[i] = prev.data[i] + net.ftWeight[addIdx][i] - net.ftWeight[subIdx1][i] - net.ftWeight[subIdx2][i]
    else:
        var i = 0
        while i < HL:
            let a = vecLoad(addr net.ftWeight[addIdx][i])
            let b = vecLoad(addr net.ftWeight[subIdx1][i])
            let c = vecLoad(addr net.ftWeight[subIdx2][i])
            let p = vecLoad(addr prev.data[i])
            let r = vecSub16(vecSub16(vecAdd16(p, a), b), c)
            vecStore(addr curr.data[i], r)
            i += CHUNK_SIZE

proc addSubAddSub*(net: ptr NNUENetwork, addIdx1, subIdx1, addIdx2, subIdx2: int,
                   prev: var Accumulator, curr: var Accumulator) {.inline.} =
    when not defined(simd):
        for i in 0..<HL:
            curr.data[i] = prev.data[i] + net.ftWeight[addIdx1][i] - net.ftWeight[subIdx1][i] +
                           net.ftWeight[addIdx2][i] - net.ftWeight[subIdx2][i]
    else:
        var i = 0
        while i < HL:
            let a1 = vecLoad(addr net.ftWeight[addIdx1][i])
            let s1 = vecLoad(addr net.ftWeight[subIdx1][i])
            let a2 = vecLoad(addr net.ftWeight[addIdx2][i])
            let s2 = vecLoad(addr net.ftWeight[subIdx2][i])
            let p = vecLoad(addr prev.data[i])
            let r = vecSub16(vecAdd16(a2, vecSub16(vecAdd16(p, a1), s1)), s2)
            vecStore(addr curr.data[i], r)
            i += CHUNK_SIZE

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

func outputBucket*(board: Board): int {.inline.} =
    var count = 0
    var occ = board.occupied
    while occ != Bitboard(0):
        let sq = poplsb(occ)
        let piece = board.mailbox[sq.int]
        if piece != NoPiece and piece.pieceType != King:
            inc count
    result = min(count * NUM_OUTPUT_BUCKETS div 32, NUM_OUTPUT_BUCKETS - 1)

proc forward*(net: ptr NNUENetwork, stmAcc, nstmAcc: var Accumulator, bucket: int): int {.inline.} =
    when not defined(simd):
        var output: int32 = 0

        # STM half
        for i in 0..<HL:
            let input = stmAcc.data[i].int32
            let weight = net.l1Weight[bucket][i].int32
            let clipped = clamp(input, 0, QA.int32)
            output += (clipped * weight).int16 * clipped

        # NSTM half
        for i in 0..<HL:
            let input = nstmAcc.data[i].int32
            let weight = net.l1Weight[bucket][HL + i].int32
            let clipped = clamp(input, 0, QA.int32)
            output += (clipped * weight).int16 * clipped
        return system.int((output div QA + net.l1Bias[bucket].int32) * EVAL_SCALE div (QA * QB))

    else:
        var
            sum = vecZero32()
            qa = vecSetOne16(QA.int16)
            zero = vecZero16()

        # STM half: weight indices 0..<HL
        var i = 0
        while i < HL:
            let inp = vecLoad(addr stmAcc.data[i])
            let wt = vecLoad(addr net.l1Weight[bucket][i])
            let clipped = vecMin16(vecMax16(inp, zero), qa)
            let product = vecMadd16(vecMullo16(clipped, wt), clipped)
            sum = vecAdd32(sum, product)
            i += CHUNK_SIZE

        # NSTM half: weight indices HL..<HL*2
        i = 0
        while i < HL:
            let inp = vecLoad(addr nstmAcc.data[i])
            let wt = vecLoad(addr net.l1Weight[bucket][HL + i])
            let clipped = vecMin16(vecMax16(inp, zero), qa)
            let product = vecMadd16(vecMullo16(clipped, wt), clipped)
            sum = vecAdd32(sum, product)
            i += CHUNK_SIZE

        let rawSum = vecReduceAdd32(sum)
        return system.int((rawSum div QA + net.l1Bias[bucket].int32) * EVAL_SCALE div (QA * QB))

proc forwardAllBuckets*(net: ptr NNUENetwork, stmAcc, nstmAcc: var Accumulator): array[NUM_OUTPUT_BUCKETS, int] =
    for b in 0..<NUM_OUTPUT_BUCKETS:
        result[b] = forward(net, stmAcc, nstmAcc, b)

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
    let bucket = outputBucket(board)
    if board.stm == White:
        result = forward(net, state.white[ply], state.black[ply], bucket)
    else:
        result = forward(net, state.black[ply], state.white[ply], bucket)

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
        let kingTo = toSq

        var rookFrom, rookTo: Square
        # Kingside: king lands on g-file (file index 6)
        if toSq.file == 6:
            if us == White:
                rookFrom = makeSquare(0, 7)  # H1
                rookTo   = makeSquare(0, 5)  # F1
            else:
                rookFrom = makeSquare(7, 7)  # H8
                rookTo   = makeSquare(7, 5)  # F8
        else:
            if us == White:
                rookFrom = makeSquare(0, 0)  # A1
                rookTo   = makeSquare(0, 3)  # D1
            else:
                rookFrom = makeSquare(7, 0)  # A8
                rookTo   = makeSquare(7, 3)  # D8

        let kingAddIdx = featureIndex(perspective, us, King, kingTo, perspKingSq)
        let kingSubIdx = featureIndex(perspective, us, King, kingFrom, perspKingSq)
        let rookAddIdx = featureIndex(perspective, us, Rook, rookTo, perspKingSq)
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