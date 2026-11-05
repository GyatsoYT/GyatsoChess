import coretypes
import board
import bitboard
import nnuetypes
import nnue

var gNetwork*: NNUENetwork

proc initNNUE*() =
  gNetwork = loadNetworkFromEmbedded()

const
  MaterialScaleMax = 256
  MaterialScaleMin = 128
  FullNonPawnMaterial = 4100

func nonPawnMaterial(b: Board): int {.inline.} =
  320 * (b.pieces(WhiteKnight).popcount +
         b.pieces(BlackKnight).popcount) +
  330 * (b.pieces(WhiteBishop).popcount +
         b.pieces(BlackBishop).popcount) +
  500 * (b.pieces(WhiteRook).popcount +
         b.pieces(BlackRook).popcount) +
  900 * (b.pieces(WhiteQueen).popcount +
         b.pieces(BlackQueen).popcount)

func scaleByMaterial(b: Board, score: int): int {.inline.} =
  let material = min(nonPawnMaterial(b), FullNonPawnMaterial)
  let scale = MaterialScaleMin +
    (MaterialScaleMax - MaterialScaleMin) * material div FullNonPawnMaterial
  score * scale div MaterialScaleMax

proc evaluate*(b: Board, state: var NNUEState): int {.inline.} =
  ## Results are cached per thread: the index uses the low hash bits and the
  ## entry stores the upper 48 bits alongside the 16-bit score.
  const KeyMask = not 0xFFFF'u64
  let key = cast[uint64](b.hash)
  let entry = addr state.evalCache[key and system.uint64(EvalCacheSize - 1)]
  if ((entry[] xor key) and KeyMask) == 0:
    return system.int(cast[int16](uint16(entry[] and 0xFFFF'u64)))
  result = nnueEvaluate(addr gNetwork, b, state)

  if abs(result) < MateThreshold:
    result = scaleByMaterial(b, result)
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
