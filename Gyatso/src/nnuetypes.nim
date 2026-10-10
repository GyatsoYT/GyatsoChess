import coretypes

const
  ALIGNMENT* = 64
  FT_IN*     = 768   
  HL*        = 1024  
  L1_INPUTS* = HL
  L1_TILES*  = L1_INPUTS div 4
  L2_SIZE*   = 16
  L3_SIZE*   = 32
  QA*        = 255   
  QB*        = 64
  Q2*        = 262_144
  EVAL_SCALE* = 400

type
  Accumulator* = object
    data* {.align(ALIGNMENT).}: array[HL, int16]

  NNUENetwork* = object
    ftWeight* {.align(ALIGNMENT).}: array[FT_IN, array[HL, int16]]
    ftBias*   {.align(ALIGNMENT).}: array[HL, int16]
    # Trainer writes l1 weights output-major; each four-byte input tile is
    # rearranged as [output][4] for AVX2/AVX-512/NEON dot products.
    l1Weight* {.align(ALIGNMENT).}: array[L1_TILES, array[L2_SIZE, array[4, int8]]]
    l1DotWeight* {.align(ALIGNMENT).}: array[L1_TILES, array[L2_SIZE, array[4, int8]]]
    l1UnsafePairs*: array[L1_TILES * L2_SIZE * 2, uint16]
    l1UnsafeCount*: int
    l1Bias* {.align(ALIGNMENT).}: array[L2_SIZE, int32]
    l2Weight* {.align(ALIGNMENT).}: array[L3_SIZE, array[L2_SIZE, int32]]
    l2Bias* {.align(ALIGNMENT).}: array[L3_SIZE, int32]
    l3Weight* {.align(ALIGNMENT).}: array[L3_SIZE, int32]
    l3Bias*: int32
    # Exact dequantized forms are prepared once at load time. The dense tail
    # is small, so this avoids per-node integer scaling and division.
    l2WeightFloat* {.align(ALIGNMENT).}: array[L3_SIZE, array[L2_SIZE, float32]]
    l2BiasFloat* {.align(ALIGNMENT).}: array[L3_SIZE, float32]
    l3WeightFloat* {.align(ALIGNMENT).}: array[L3_SIZE, float32]
    l3BiasFloat*: float32

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
