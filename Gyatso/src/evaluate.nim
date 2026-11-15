import coretypes
import bitboard
import board
import nnuetypes
import nnue

var gNetwork*: NNUENetwork

const
  MaterialScaleQuant*  = 16384
  MaterialScaleKnight* = 400
  MaterialScaleBishop* = 450
  MaterialScaleRook*   = 650
  MaterialScaleQueen*  = 1250
  MaterialScaleStart*  = 4 * (MaterialScaleKnight + MaterialScaleBishop + MaterialScaleRook) +
                    2 * MaterialScaleQueen

proc initNNUE*() =
  gNetwork = loadNetworkFromEmbedded()

func materialScale(b: Board): system.int {.inline.} =
  let knights = system.int((b.byPiece[Knight.ord] or b.byPiece[Knight.ord + 6]).popcount())
  let bishops = system.int((b.byPiece[Bishop.ord] or b.byPiece[Bishop.ord + 6]).popcount())
  let rooks   = system.int((b.byPiece[Rook.ord]   or b.byPiece[Rook.ord + 6]).popcount())
  let queens  = system.int((b.byPiece[Queen.ord]  or b.byPiece[Queen.ord + 6]).popcount())
  knights * MaterialScaleKnight + bishops * MaterialScaleBishop +
    rooks * MaterialScaleRook + queens * MaterialScaleQueen +
    (MaterialScaleQuant - MaterialScaleStart)

proc evaluate*(b: Board, state: var NNUEState): int {.inline.} =
  const KeyMask = not 0xFFFF'u64
  let key = cast[uint64](b.hash)
  let entry = addr state.evalCache[key and system.uint64(EvalCacheSize - 1)]
  if ((entry[] xor key) and KeyMask) == 0:
    return system.int(cast[int16](uint16(entry[] and 0xFFFF'u64)))
  result = nnueEvaluate(addr gNetwork, b, state)
  result = (result * b.materialScale()) div MaterialScaleQuant
  if result > MateThreshold:
    result = MateThreshold
  elif result < -MateThreshold:
    result = -MateThreshold
  entry[] = (key and KeyMask) or system.uint64(cast[uint16](int16(result)))

func evalCachePrefetch(p: pointer) {.importc: "__builtin_prefetch", nodecl, inline.}

proc prefetchEvalCache*(state: var NNUEState, key: uint64) {.inline.} =
  ## Warm the evalCache line for `key` ahead of the child's evaluate() call.
  evalCachePrefetch(addr state.evalCache[key and system.uint64(EvalCacheSize - 1)])

proc refreshNNUE*(b: Board, state: var NNUEState) {.inline.} =
  refreshState(addr gNetwork, b, state)

proc nnuePush*(b: Board, m: Move, state: var NNUEState) {.inline.} =
  pushAccumulator(addr gNetwork, b, m, state)

proc nnuePop*(state: var NNUEState) {.inline.} =
  popAccumulator(state)

proc nnuePushNull*(state: var NNUEState) {.inline.} =
  pushNullMove(state)

proc nnuePopNull*(state: var NNUEState) {.inline.} =
  popNullMove(state)

proc verifyEval*(b: Board, state: var NNUEState) {.inline.} =
  verifyNNUE(addr gNetwork, b, state)