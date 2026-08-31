import coretypes

const
  ALIGNMENT*         = 64
  FT_IN*             = 768
  HL*                = 512
  QA*                = 255
  QB*                = 64
  EVAL_SCALE*        = 400
  NUM_OUTPUT_BUCKETS* = 8

type
  Accumulator* = object
    data* {.align(ALIGNMENT).}: array[HL, int16]

  NNUENetwork* = object
    ftWeight* {.align(ALIGNMENT).}: array[FT_IN, array[HL, int16]]
    ftBias*   {.align(ALIGNMENT).}: array[HL, int16]
    l1Weight* {.align(ALIGNMENT).}: array[NUM_OUTPUT_BUCKETS, array[HL * 2, int16]]
    l1Bias*:  array[NUM_OUTPUT_BUCKETS, int16]

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
