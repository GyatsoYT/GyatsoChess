import coretypes
import board
import nnuetypes
import nnue

var gNetwork* {.global.}: ptr NNUENetwork

proc alignedAlloc0(size: int, alignment: int): pointer =
  when defined(windows):
    proc c_aligned_malloc(size: csize_t, alignment: csize_t): pointer {.importc: "_aligned_malloc", header: "<malloc.h>".}
    result = c_aligned_malloc(csize_t(size), csize_t(alignment))
  elif defined(posix):
    proc posix_memalign(memptr: ptr pointer, alignment: csize_t, size: csize_t): cint {.importc: "posix_memalign", header: "<stdlib.h>".}
    var p: pointer = nil
    if posix_memalign(addr p, csize_t(alignment), csize_t(size)) == 0:
      result = p
    else:
      result = nil
  else:
    result = allocShared0(size)
  if result != nil:
    zeroMem(result, size)

proc initNNUE*() =
  gNetwork = cast[ptr NNUENetwork](alignedAlloc0(sizeof(NNUENetwork), ALIGNMENT))
  doAssert gNetwork != nil, "Failed to allocate memory for NNUE network"
  loadNetworkFromEmbedded(gNetwork)

proc evaluate*(b: Board, state: var NNUEState): int {.inline.} =
  const KeyMask = not 0xFFFF'u64
  let key = cast[uint64](b.hash)
  let entry = addr state.evalCache[key and uint64(EvalCacheSize - 1)]
  if ((entry[] xor key) and KeyMask) == 0:
    return system.int(cast[int16](uint16(entry[] and 0xFFFF'u64)))
  result = nnueEvaluate(gNetwork, b, state)
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
