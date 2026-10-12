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

  NNUEState* = object
    current*: int
    white*:   array[MaxPly + 1, Accumulator]
    black*:   array[MaxPly + 1, Accumulator]
    whiteNeedsRefresh*: array[MaxPly + 1, bool]
    blackNeedsRefresh*: array[MaxPly + 1, bool]

  UpdateQueue* = object
    adds*: array[2, int]
    addCount*: int8
    subs*: array[2, int]
    subCount*: int8
