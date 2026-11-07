import coretypes
import board
import nnuetypes
import nnue
import threats

var gNetwork* {.global.}: ptr NNUENetwork

proc initNNUE*() =
  gNetwork = cast[ptr NNUENetwork](allocShared0(sizeof(NNUENetwork)))
  loadNetworkFromEmbedded(gNetwork)

proc evaluate*(b: Board, state: var NNUEState): int {.inline.} =
  const KeyMask = not 0xFFFF'u64
  let key = cast[uint64](b.hash)
  let entry = addr state.evalCache[key and uint64(EvalCacheSize - 1)]
  if ((entry[] xor key) and KeyMask) == 0:
    return system.int(cast[int16](uint16(entry[] and 0xFFFF'u64)))
  result = nnueEvaluate(gNetwork, b, state)
  if result > MateThreshold:
    result = MateThreshold
  elif result < -MateThreshold:
    result = -MateThreshold
  entry[] = (key and KeyMask) or uint64(cast[uint16](int16(result)))

func evalCachePrefetch(p: pointer) {.importc: "__builtin_prefetch", nodecl, inline.}

proc prefetchEvalCache*(state: var NNUEState, key: uint64) {.inline.} =
  evalCachePrefetch(addr state.evalCache[key and uint64(EvalCacheSize - 1)])

proc refreshNNUE*(b: Board, state: var NNUEState) {.inline.} =
  refreshState(gNetwork, b, state)

proc nnuePush*(b: Board, m: Move, state: var NNUEState) {.inline.} =
  pushAccumulator(gNetwork, b, m, state)

proc nnuePop*(state: var NNUEState) {.inline.} =
  popAccumulator(state)

proc nnuePushNull*(state: var NNUEState) {.inline.} =
  pushNullMove(state)

proc nnuePopNull*(state: var NNUEState) {.inline.} =
  popNullMove(state)

proc verifyEval*(b: Board, state: var NNUEState) {.inline.} =
  verifyNNUE(gNetwork, b, state)
