import coretypes

const
  ALIGNMENT* = 64
  FT_IN*     = 768   
  HL*        = 1024  
  L2_SIZE*   = 16
  L3_SIZE*   = 32
  PAIR_COUNT* = HL div 2
  QA*        = 255   
  QB*        = 64    
  EVAL_SCALE* = 400
  EvalCacheSize* = 65536

const IsaName* =
  when defined(avx512vnni): "avx512+vnni"
  elif defined(avx512): "avx512"
  elif defined(avxvnni): "avx2+vnni"
  elif defined(avx2): "avx2"
  elif defined(neon) or defined(arm64) or defined(aarch64): "neon"
  else: "scalar"

type
  Accumulator* = object
    data* {.align(ALIGNMENT).}: array[HL, int16]

  NNUENetwork* = object
    ftWeight* {.align(ALIGNMENT).}: array[FT_IN, array[HL, int16]]
    ftBias*   {.align(ALIGNMENT).}: array[HL, int16]
    l1Weight* {.align(ALIGNMENT).}: array[HL div 4, array[L2_SIZE, array[4, int8]]]
    l1Bias* {.align(ALIGNMENT).}: array[L2_SIZE, int32]
    l2Weight* {.align(ALIGNMENT).}: array[L2_SIZE, array[L3_SIZE, int32]]
    l2Bias* {.align(ALIGNMENT).}: array[L3_SIZE, int32]
    l3Weight* {.align(ALIGNMENT).}: array[L3_SIZE, int32]
    l3Bias*: int32
    l2Int32Safe*: bool
    l2Int16Safe*: bool
    l2WeightPacked* {.align(ALIGNMENT).}: array[L2_SIZE div 2, array[L3_SIZE, array[2, int16]]]

  EvalCacheEntry* = uint64  ## upper 48 hash bits | uint16(eval)

  AccumulatorDelta* = object
    ## Feature changes a move applies to one perspective's accumulator.
    ## addCount == subCount == 0 means the accumulator is copied unchanged
    ## (null move).
    adds*: array[2, uint16]
    subs*: array[2, uint16]
    addCount*: uint8
    subCount*: uint8

  NNUEState* = object
    current*: int
    acc*: array[Color, array[MaxPly + 1, Accumulator]]
    ## Accumulator at [persp][ply] holds valid values. Updates are applied
    ## lazily: a push only records the delta, and evaluation walks back to
    ## the nearest computed ancestor and replays the pending deltas.
    computed*: array[Color, array[MaxPly + 1, bool]]
    ## King crossed the mirror boundary; recompute from the board instead
    ## of applying a delta. Resolved at the latest when pushing from that ply.
    needsRefresh*: array[Color, array[MaxPly + 1, bool]]
    delta*: array[Color, array[MaxPly + 1, AccumulatorDelta]]
    ## Per-thread cache of final evaluations keyed by full Zobrist hash.
    ## NNUE output depends only on piece placement and side to move, both
    ## covered by the hash, so a key match reproduces the exact same score.
    evalCache*: array[EvalCacheSize, EvalCacheEntry]
