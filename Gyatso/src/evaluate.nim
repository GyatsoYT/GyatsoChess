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

proc nnueBucket*(b: Board): int {.inline.} =
  outputBucket(b)

proc nnueAllBuckets*(b: Board, stmAcc, nstmAcc: var Accumulator): array[NUM_OUTPUT_BUCKETS, int] {.inline.} =
  forwardAllBuckets(addr gNetwork, stmAcc, nstmAcc)
