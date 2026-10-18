import coretypes

const
  ALIGNMENT* = 64
  FT_IN*     = 768   
  HL*        = 1024  
  QA*        = 255   
  QB*        = 64    
  EVAL_SCALE* = 400
  EvalCacheSize* = 1 shl 16

type
  Accumulator* = object
    data* {.align(ALIGNMENT).}: array[HL, int16]

  NNUENetwork* = object
    ftWeight* {.align(ALIGNMENT).}: array[FT_IN, array[HL, int16]]
    ftBias*   {.align(ALIGNMENT).}: array[HL, int16]
    l1Weight* {.align(ALIGNMENT).}: array[HL * 2, int16]
    l1Bias*:  int32

  NNUEState* = object
    current*: int
    white*:   array[MaxPly + 1, Accumulator]
    black*:   array[MaxPly + 1, Accumulator]
    whiteNeedsRefresh*: array[MaxPly + 1, bool]
    blackNeedsRefresh*: array[MaxPly + 1, bool]
    ## Deferred incremental update: when pending[ply][p] is set, accumulator
    ## `p` at `ply` equals the one at ply-1 plus delta[ply][p], not yet applied.
    pending*: array[MaxPly + 1, array[2, bool]]
    delta*:   array[MaxPly + 1, array[2, AccDelta]]
    ## Direct-mapped cache of NNUE outputs keyed by the full Zobrist hash.
    ## The network output is a pure function of the position, so a hit
    ## returns exactly what forward() would.
    evalCache*: array[EvalCacheSize, EvalCacheEntry]

  EvalCacheEntry* = object
    key*: uint64
    value*: int32

  ## Feature changes of one move for one perspective. subCount == 0 means a
  ## plain copy (null move); otherwise 1 add with 1-2 subs, or 2 adds/2 subs.
  AccDelta* = object
    adds*: array[2, int32]
    subs*: array[2, int32]
    addCount*: int32
    subCount*: int32
