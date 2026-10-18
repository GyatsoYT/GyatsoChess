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
            let weight = vecLoad(addr net.ftWeight[index][o])
            let data = vecLoad(addr acc.data[o])
            let sum = vecAdd16(weight, data)
            vecStore(addr acc.data[o], sum)
            o += CHUNK_SIZE

when defined(simd):
    const UpdateUnroll = 4
    static: doAssert HL mod (CHUNK_SIZE * UpdateUnroll) == 0

    template updateLoop(body: untyped) =
        ## Runs `body` for every vector offset `i`, manually unrolled so the
        ## independent loads/stores of several vectors overlap.
        var base = 0
        while base < HL:
            for u in 0 ..< UpdateUnroll:
                let i {.inject.} = base + u * CHUNK_SIZE
                body
            base += CHUNK_SIZE * UpdateUnroll

proc addSub*(net: ptr NNUENetwork, addIdx, subIdx: int,
             prev: var Accumulator, curr: var Accumulator) {.inline.} =
    when not defined(simd):
        for i in 0..<HL:
            curr.data[i] = prev.data[i] + net.ftWeight[addIdx][i] - net.ftWeight[subIdx][i]
    else:
        let wa = addr net.ftWeight[addIdx]
        let ws = addr net.ftWeight[subIdx]
        updateLoop:
            let r = vecSub16(vecAdd16(vecLoad(addr prev.data[i]), vecLoad(addr wa[i])),
                             vecLoad(addr ws[i]))
            vecStore(addr curr.data[i], r)

proc addSubSub*(net: ptr NNUENetwork, addIdx, subIdx1, subIdx2: int,
                prev: var Accumulator, curr: var Accumulator) {.inline.} =
    when not defined(simd):
        for i in 0..<HL:
            curr.data[i] = prev.data[i] + net.ftWeight[addIdx][i] - net.ftWeight[subIdx1][i] - net.ftWeight[subIdx2][i]
    else:
        let wa = addr net.ftWeight[addIdx]
        let ws1 = addr net.ftWeight[subIdx1]
        let ws2 = addr net.ftWeight[subIdx2]
        updateLoop:
            let r = vecSub16(vecSub16(vecAdd16(vecLoad(addr prev.data[i]), vecLoad(addr wa[i])),
                                      vecLoad(addr ws1[i])), vecLoad(addr ws2[i]))
            vecStore(addr curr.data[i], r)

proc addSubAddSub*(net: ptr NNUENetwork, addIdx1, subIdx1, addIdx2, subIdx2: int,
                   prev: var Accumulator, curr: var Accumulator) {.inline.} =
    when not defined(simd):
        for i in 0..<HL:
            curr.data[i] = prev.data[i] + net.ftWeight[addIdx1][i] - net.ftWeight[subIdx1][i] +
                           net.ftWeight[addIdx2][i] - net.ftWeight[subIdx2][i]
    else:
        let wa1 = addr net.ftWeight[addIdx1]
        let ws1 = addr net.ftWeight[subIdx1]
        let wa2 = addr net.ftWeight[addIdx2]
        let ws2 = addr net.ftWeight[subIdx2]
        updateLoop:
            let p = vecLoad(addr prev.data[i])
            let r = vecSub16(vecAdd16(vecLoad(addr wa2[i]),
                                      vecSub16(vecAdd16(p, vecLoad(addr wa1[i])), vecLoad(addr ws1[i]))),
                             vecLoad(addr ws2[i]))
            vecStore(addr curr.data[i], r)

proc refreshAccumulator*(net: ptr NNUENetwork, board: Board, acc: var Accumulator, perspective: Color) =
    ## Full recompute of accumulator from board state
    let perspKingSq = board.kingSquare(perspective)
    var features {.noinit.}: array[32, int]
    var count = 0
    var occ = board.occupied
    while occ != Bitboard(0):
        let sq = poplsb(occ)
        let piece = board.mailbox[sq.int]
        if piece == NoPiece: continue
        features[count] = featureIndex(perspective, piece.color, piece.pieceType, sq, perspKingSq)
        inc count

    when not defined(simd):
        net.initAccumulator(acc)
        for f in 0 ..< count:
            net.addFeature(features[f], acc)
    else:
        # Keep a tile of the accumulator in registers while summing every
        # feature row, instead of one load/store pass over `acc` per piece.
        const Tile = 8
        static: doAssert HL mod (CHUNK_SIZE * Tile) == 0
        var base = 0
        while base < HL:
            var regs {.noinit.}: array[Tile, VEPI16]
            for t in 0 ..< Tile:
                regs[t] = vecLoad(addr net.ftBias[base + t * CHUNK_SIZE])
            for f in 0 ..< count:
                let row = addr net.ftWeight[features[f]]
                for t in 0 ..< Tile:
                    regs[t] = vecAdd16(regs[t], vecLoad(addr row[base + t * CHUNK_SIZE]))
            for t in 0 ..< Tile:
                vecStore(addr acc.data[base + t * CHUNK_SIZE], regs[t])
            base += CHUNK_SIZE * Tile

proc refreshState*(net: ptr NNUENetwork, board: Board, state: var NNUEState) =
    state.current = 0
    net.refreshAccumulator(board, state.white[0], White)
    net.refreshAccumulator(board, state.black[0], Black)
    state.whiteNeedsRefresh[0] = false
    state.blackNeedsRefresh[0] = false
    state.pending[0] = [false, false]

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
        # Independent int32 accumulator chains for ILP; int32 addition is
        # associative so the reduced total is bit-identical to a single chain.
        const Lanes = 4
        static: doAssert HL mod (CHUNK_SIZE * Lanes) == 0
        let qa = vecSetOne16(QA.int16)
        let zero = vecZero16()
        var sums {.noinit.}: array[2 * Lanes, VEPI32]
        for k in 0 ..< 2 * Lanes:
            sums[k] = vecZero32()

        var i = 0
        while i < HL:
            for k in 0 ..< Lanes:
                let o = i + k * CHUNK_SIZE
                let c = vecMin16(vecMax16(vecLoad(addr stmAcc.data[o]), zero), qa)
                let n = vecMin16(vecMax16(vecLoad(addr nstmAcc.data[o]), zero), qa)
                sums[k] = vecMaddAcc16(sums[k], vecMullo16(c, vecLoad(addr net.l1Weight[o])), c)
                sums[Lanes + k] = vecMaddAcc16(sums[Lanes + k],
                                               vecMullo16(n, vecLoad(addr net.l1Weight[HL + o])), n)
            i += Lanes * CHUNK_SIZE

        var total = sums[0]
        for k in 1 ..< 2 * Lanes:
            total = vecAdd32(total, sums[k])
        let rawSum = vecReduceAdd32(total)
        return system.int((rawSum div QA + net.l1Bias) * EVAL_SCALE div (QA * QB))

proc applyDelta(net: ptr NNUENetwork, d: AccDelta,
                prev: var Accumulator, curr: var Accumulator) {.inline.} =
    if d.addCount == 2:
        net.addSubAddSub(d.adds[0], d.subs[0], d.adds[1], d.subs[1], prev, curr)
    elif d.subCount == 2:
        net.addSubSub(d.adds[0], d.subs[0], d.subs[1], prev, curr)
    else:
        net.addSub(d.adds[0], d.subs[0], prev, curr)

proc ensureAccumulatorReady*(net: ptr NNUENetwork, board: Board, state: var NNUEState) {.inline.} =
    ## Materialise the current ply: apply a deferred incremental update, or
    ## recompute if the king crossed the mirror boundary. The parent ply is
    ## always materialised before a child is pushed, so deferral is one level.
    let ply = state.current
    if state.pending[ply][White.ord]:
        net.applyDelta(state.delta[ply][White.ord], state.white[ply - 1], state.white[ply])
        state.pending[ply][White.ord] = false
    if state.pending[ply][Black.ord]:
        net.applyDelta(state.delta[ply][Black.ord], state.black[ply - 1], state.black[ply])
        state.pending[ply][Black.ord] = false
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

proc computeDelta(board: Board, m: Move, perspective: Color): AccDelta {.inline.} =
    ## Feature changes of `m` (board is pre-move) for one perspective.
    let us = board.stm
    let them = us.opposite()
    let fromSq = m.fromSq
    let toSq = m.toSq
    let movingPiece = board.mailbox[fromSq.int]
    let movingPt = movingPiece.pieceType
    let movingColor = movingPiece.color

    # Get perspective king square for horizontal mirroring
    let perspKingSq = board.kingSquare(perspective)

    template idx(c: Color, pt: PieceType, sq: Square): int32 =
        int32(featureIndex(perspective, c, pt, sq, perspKingSq))

    if m.isCastling:
        let rookFrom = toSq
        let kingTo   = if fromSq.file < rookFrom.file: fromSq.withFile(6) else: fromSq.withFile(2)
        let rookTo   = if fromSq.file < rookFrom.file: fromSq.withFile(5) else: fromSq.withFile(3)
        result.adds = [idx(us, King, kingTo), idx(us, Rook, rookTo)]
        result.subs = [idx(us, King, fromSq), idx(us, Rook, rookFrom)]
        result.addCount = 2
        result.subCount = 2

    elif m.isEnPassant:
        let capSq = if us == White: (toSq.int - 8).Square else: (toSq.int + 8).Square
        result.adds[0] = idx(us, Pawn, toSq)
        result.subs = [idx(us, Pawn, fromSq), idx(them, Pawn, capSq)]
        result.addCount = 1
        result.subCount = 2

    else:
        let addPt = if m.isPromotion:
                        case m.promoType
                        of PromoKnight: Knight
                        of PromoBishop: Bishop
                        of PromoRook:   Rook
                        of PromoQueen:  Queen
                    else: movingPt
        result.adds[0] = idx(movingColor, addPt, toSq)
        result.subs[0] = idx(movingColor, movingPt, fromSq)
        result.addCount = 1
        let capturedPiece = board.mailbox[toSq.int]
        if capturedPiece != NoPiece:
            result.subs[1] = idx(capturedPiece.color, capturedPiece.pieceType, toSq)
            result.subCount = 2
        else:
            result.subCount = 1

proc pushAccumulator*(net: ptr NNUENetwork, board: Board, m: Move,
                      state: var NNUEState) =
    let ply = state.current
    let us = board.stm
    let movingPt = board.mailbox[m.fromSq.int].pieceType

    ensureAccumulatorReady(net, board, state)
    state.pending[ply + 1] = [false, false]

    for perspective in [White, Black]:
        let isOurKingMoving = (perspective == us) and (movingPt == King)

        if isOurKingMoving:
            # Castling is encoded king->rook; use the king's real destination
            # (g/c file). Comparing against the rook square misses FRC castles
            # that cross the mirror axis (e.g. Kd1 with the h-rook -> Kg1).
            let fromFile = m.fromSq.file
            let toFile   = if not m.isCastling: m.toSq.file
                           elif m.fromSq.file < m.toSq.file: 6
                           else: 2
            if (fromFile > 3) != (toFile > 3):
                if perspective == White:
                    state.whiteNeedsRefresh[ply + 1] = true
                else:
                    state.blackNeedsRefresh[ply + 1] = true
                continue

        # Incremental update, deferred until this ply is evaluated or extended
        state.delta[ply + 1][perspective.ord] = computeDelta(board, m, perspective)
        state.pending[ply + 1][perspective.ord] = true
        if perspective == White:
            state.whiteNeedsRefresh[ply + 1] = false
        else:
            state.blackNeedsRefresh[ply + 1] = false

    inc state.current

proc popAccumulator*(state: var NNUEState) {.inline.} =
    dec state.current

proc pushNullMove*(net: ptr NNUENetwork, board: Board, state: var NNUEState) =
    # Materialise the parent first (deferral is only one level deep), then
    # the null-move child is a plain copy.
    ensureAccumulatorReady(net, board, state)
    let ply = state.current
    state.pending[ply + 1] = [false, false]
    state.whiteNeedsRefresh[ply + 1] = false
    state.blackNeedsRefresh[ply + 1] = false
    state.white[ply + 1] = state.white[ply]
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