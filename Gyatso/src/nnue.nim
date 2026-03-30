import coretypes, bitboard, board, nnuetypes, move, utils
import std/[streams, endians]

when defined(simd):
    import simd

func featureIndex*(perspective, pieceColor: Color, pt: PieceType, sq: Square): int {.inline.} =
    let colorIdx = if perspective == pieceColor: 0 else: 1
    let ptIdx = pt.ord  # Pawn=0..King=5
    let sqIdx = if perspective == White: sq.int else: (sq.int xor 56)
    result = (colorIdx * 6 + ptIdx) * 64 + sqIdx

const NNUE_EMBEDDED* = staticRead("../Net/GyatsoNet.bin")

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
    net.initAccumulator(acc)
    var occ = board.allPiecesBB
    while occ != 0:
        let sq = popBit(occ)
        let piece = board.pieces[sq]
        if piece == NoPiece: continue
        let pt = pieceType(piece)
        let pc = pieceColor(piece)
        let idx = featureIndex(perspective, pc, pt, sq)
        net.addFeature(idx, acc)

proc refreshState*(net: ptr NNUENetwork, board: Board, state: var NNUEState) =
    state.current = 0
    net.refreshAccumulator(board, state.white[0], White)
    net.refreshAccumulator(board, state.black[0], Black)

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
        return int((output div QA + net.l1Bias) * EVAL_SCALE div (QA * QB))

    else:
        var
            sum = vecZero32()
            qa = vecSetOne16(QA.int16)
            zero = vecZero16()

        # STM half: weight indices 0..<HL
        var i = 0
        while i < HL:
            let inp = vecLoad(addr stmAcc.data[i])
            let wt = vecLoad(addr net.l1Weight[i])
            let clipped = vecMin16(vecMax16(inp, zero), qa)
            let product = vecMadd16(vecMullo16(clipped, wt), clipped)
            sum = vecAdd32(sum, product)
            i += CHUNK_SIZE

        # NSTM half: weight indices HL..<HL*2
        i = 0
        while i < HL:
            let inp = vecLoad(addr nstmAcc.data[i])
            let wt = vecLoad(addr net.l1Weight[HL + i])
            let clipped = vecMin16(vecMax16(inp, zero), qa)
            let product = vecMadd16(vecMullo16(clipped, wt), clipped)
            sum = vecAdd32(sum, product)
            i += CHUNK_SIZE

        let rawSum = vecReduceAdd32(sum)
        return int((rawSum div QA + net.l1Bias) * EVAL_SCALE div (QA * QB))

proc nnueEvaluate*(net: ptr NNUENetwork, board: Board, state: var NNUEState): int {.inline.} =
    let ply = state.current
    if board.sideToMove == White:
        result = forward(net, state.white[ply], state.black[ply])
    else:
        result = forward(net, state.black[ply], state.white[ply])

    # Clamp to safe range
    const MaxEval = MateValue - MaxPly - 100
    if result > MaxEval: result = MaxEval
    elif result < -MaxEval: result = -MaxEval

proc computeUpdateQueue*(net: ptr NNUENetwork, board: Board, m: Move,
                         perspective: Color, state: var NNUEState) =
    let us = board.sideToMove
    let them = if us == White: Black else: White
    let fromSq = m.fromSquare
    let toSq = m.toSquare
    let movingPiece = board.pieces[fromSq]
    let movingPt = pieceType(movingPiece)
    let movingColor = pieceColor(movingPiece)

    var queue: UpdateQueue
    queue.reset()

    let ply = state.current

    if m.isCastle:
        let kingFrom = fromSq
        let kingTo = toSq  # Note: in Gyatso, king toSq is the destination square

        var rookFrom, rookTo: Square
        if m.flags == KingCastle.int:
            # Kingside
            if us == White:
                rookFrom = squareFromCoords(0, 7)  # h1
                rookTo = squareFromCoords(0, 5)     # f1
            else:
                rookFrom = squareFromCoords(7, 7)  # h8
                rookTo = squareFromCoords(7, 5)     # f8
        else:
            # Queenside
            if us == White:
                rookFrom = squareFromCoords(0, 0)  # a1
                rookTo = squareFromCoords(0, 3)     # d1
            else:
                rookFrom = squareFromCoords(7, 0)  # a8
                rookTo = squareFromCoords(7, 3)     # d8

        let kingAddIdx = featureIndex(perspective, us, King, kingTo)
        let kingSubIdx = featureIndex(perspective, us, King, kingFrom)
        let rookAddIdx = featureIndex(perspective, us, Rook, rookTo)
        let rookSubIdx = featureIndex(perspective, us, Rook, rookFrom)

        queue.queueAddSub(kingAddIdx, kingSubIdx)
        queue.queueAddSub(rookAddIdx, rookSubIdx)

    elif m.isEnPassant:
        let capSq = if us == White: (toSq.int - 8).Square else: (toSq.int + 8).Square
        let addIdx = featureIndex(perspective, us, Pawn, toSq)
        let subIdx1 = featureIndex(perspective, us, Pawn, fromSq)
        let subIdx2 = featureIndex(perspective, them, Pawn, capSq)
        queue.queueAddSubSub(addIdx, subIdx1, subIdx2)

    elif m.isPromotion:
        let promoPt = m.promotion
        if m.isCapture:
            let capturedPiece = board.pieces[toSq]
            let capturedPt = pieceType(capturedPiece)
            let capturedColor = pieceColor(capturedPiece)
            let addIdx = featureIndex(perspective, us, promoPt, toSq)
            let subIdx1 = featureIndex(perspective, us, Pawn, fromSq)
            let subIdx2 = featureIndex(perspective, capturedColor, capturedPt, toSq)
            queue.queueAddSubSub(addIdx, subIdx1, subIdx2)
        else:
            let addIdx = featureIndex(perspective, us, promoPt, toSq)
            let subIdx = featureIndex(perspective, us, Pawn, fromSq)
            queue.queueAddSub(addIdx, subIdx)

    elif m.isCapture:
        let capturedPiece = board.pieces[toSq]
        let capturedPt = pieceType(capturedPiece)
        let capturedColor = pieceColor(capturedPiece)
        let addIdx = featureIndex(perspective, movingColor, movingPt, toSq)
        let subIdx1 = featureIndex(perspective, movingColor, movingPt, fromSq)
        let subIdx2 = featureIndex(perspective, capturedColor, capturedPt, toSq)
        queue.queueAddSubSub(addIdx, subIdx1, subIdx2)

    else:
        let addIdx = featureIndex(perspective, movingColor, movingPt, toSq)
        let subIdx = featureIndex(perspective, movingColor, movingPt, fromSq)
        queue.queueAddSub(addIdx, subIdx)
    if perspective == White:
        queue.apply(net, state.white[ply], state.white[ply + 1])
    else:
        queue.apply(net, state.black[ply], state.black[ply + 1])

proc pushAccumulator*(net: ptr NNUENetwork, board: Board, m: Move,
                      state: var NNUEState) =
    computeUpdateQueue(net, board, m, White, state)
    computeUpdateQueue(net, board, m, Black, state)
    inc state.current

proc popAccumulator*(state: var NNUEState) {.inline.} =
    dec state.current

proc pushNullMove*(state: var NNUEState) =
    let ply = state.current
    state.white[ply + 1] = state.white[ply]
    state.black[ply + 1] = state.black[ply]
    inc state.current

proc popNullMove*(state: var NNUEState) {.inline.} =
    dec state.current

proc verifyNNUE*(net: ptr NNUENetwork, board: Board, state: var NNUEState) =
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
