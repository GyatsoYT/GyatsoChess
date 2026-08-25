import coretypes
import board
import nnuetypes
import nnue

var gNetwork*: NNUENetwork

proc initNNUE*() =
  gNetwork = loadNetworkFromEmbedded()

proc evaluate*(b: Board, state: var NNUEState): int {.inline.} =
  result = nnueEvaluate(addr gNetwork, b, state)
  if result > MateThreshold:
    result = MateThreshold
  elif result < -MateThreshold:
    result = -MateThreshold

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

proc getBucketScore*(b: Board, bucket: int, state: var NNUEState): int {.inline.} =
  ## Returns the evaluation for a specific output bucket.
  let ply = state.current
  if b.stm == White:
    var wAcc = state.white[ply]
    var bAcc = state.black[ply]
    result = forwardWithBucket(addr gNetwork, bucket, wAcc, bAcc)
  else:
    var bAcc = state.black[ply]
    var wAcc = state.white[ply]
    result = forwardWithBucket(addr gNetwork, bucket, bAcc, wAcc)
  # Always return from white's perspective for display
  if b.stm == Black:
    result = -result

proc getActiveBucket*(b: Board): int {.inline.} =
  ## Returns the output bucket index that will be used for this position.
  outputBucket(b)
