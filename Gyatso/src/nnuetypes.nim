import coretypes

const
  ALIGNMENT* = 64
  FT_IN*     = 768   
  HL*        = 256   
  QA*        = 255   
  QB*        = 64    
  EVAL_SCALE* = 400

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
    white*:   array[MaxPly, Accumulator]
    black*:   array[MaxPly, Accumulator]

  UpdateQueue* = object
    adds*: array[2, int]
    addCount*: int8
    subs*: array[2, int]
    subCount*: int8
