import coretypes
import board
import nnuetypes
import nnue

var gNetwork*: NNUENetwork

proc initNNUE*() =
  gNetwork = loadNetworkFromEmbedded()

proc evaluate*(b: Board, state: var NNUEState): int {.inline.} =
  ## Results are cached per thread: the index uses the low hash bits and the
  ## entry stores the upper 48 bits alongside the 16-bit score.
  const KeyMask = not 0xFFFF'u64
  let key = cast[uint64](b.hash)
  let entry = addr state.evalCache[key and uint64(EvalCacheSize - 1)]
  if ((entry[] xor key) and KeyMask) == 0:
    return system.int(cast[int16](uint16(entry[] and 0xFFFF'u64)))
  result = nnueEvaluate(addr gNetwork, b, state)
  if result > MateThreshold:
    result = MateThreshold
  elif result < -MateThreshold:
    result = -MateThreshold
  entry[] = (key and KeyMask) or uint64(cast[uint16](int16(result)))

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
