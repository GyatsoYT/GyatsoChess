import coretypes

const
  ALIGNMENT* = 64
  PSQT_IN*   = 768
  THREAT_IN* = 59808
  HL*        = 384
  PAIR_COUNT* = HL div 2
  L1_IN*     = 2 * PAIR_COUNT
  L2_SIZE*   = 16
  L3_SIZE*   = 32
  MAX_THREAT_DELTA* = 32
  QA*        = 255
  QB*        = 64
  EVAL_SCALE* = 400
  EvalCacheSize* = 131072

const IsaName* =
  when defined(avx512vnni): "avx512+vnni"
  elif defined(avx512): "avx512"
  elif defined(avxvnni): "avx2+vnni"
  elif defined(avx2): "avx2"
  elif defined(neon) or defined(arm64) or defined(aarch64): "neon"
  else: "scalar"

const
  AccComputed* = 1'u8
  AccNeedsRefresh* = 2'u8

type
  Accumulator* = object
    data* {.align(ALIGNMENT).}: array[HL, int16]

  NNUENetwork* = object
    ftPsqt*   {.align(ALIGNMENT).}: array[PSQT_IN, array[HL, int16]]
    ftThreat* {.align(ALIGNMENT).}: array[THREAT_IN, array[HL, int8]]
    ftBias*   {.align(ALIGNMENT).}: array[HL, int16]
    l1Weight* {.align(ALIGNMENT).}: array[L1_IN div 4, array[L2_SIZE, array[4, int8]]]
    l1Bias*   {.align(ALIGNMENT).}: array[L2_SIZE, int32]
    l2Weight* {.align(ALIGNMENT).}: array[L2_SIZE, array[L3_SIZE, int32]]
    l2Bias*   {.align(ALIGNMENT).}: array[L3_SIZE, int32]
    l3Weight* {.align(ALIGNMENT).}: array[L3_SIZE, int32]
    l3Bias*:  int32
    l2Int32Safe*: bool
    l2Int16Safe*: bool
    l2WeightPacked* {.align(ALIGNMENT).}: array[L2_SIZE div 2, array[L3_SIZE, array[2, int16]]]

  EvalCacheEntry* = uint64  ## upper 48 hash bits | uint16(eval)

  PerspDelta* = object
    psqtAdds*: array[4, uint16]
    psqtSubs*: array[4, uint16]
    nPsqtAdds*: int
    nPsqtSubs*: int
    thAdds*: array[MAX_THREAT_DELTA, uint16]
    thSubs*: array[MAX_THREAT_DELTA, uint16]
    nThAdds*: int
    nThSubs*: int
    needsRefresh*: bool

  NNUEState* = object
    current*: int
    acc* {.align(ALIGNMENT).}: array[Color, array[MaxPly + 1, Accumulator]]
    accFlags*: array[Color, array[MaxPly + 1, uint8]]
    delta*: array[Color, array[MaxPly + 1, PerspDelta]]
    evalCache*: array[EvalCacheSize, EvalCacheEntry]
