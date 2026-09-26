import std/math
import coretypes

const
  NmpMinDepth* = 3
  NmpMinPly* = 1
  NmpBaseR* = 2
  NmpDepthDiv* = 4 # so R = 2 + depth div 4
  NmpVerificationDepth* = 14
  RfpDepth* = 12
  RfpLinearMargin* = 75
  RfpQuadraticMargin* = 15
  RfpImprovementClamp* = 80
  # TT-PV adjustments
  TtPvRfpMargin* = 25
  TtPvLmrReduction* = 1
  FpDepth* = 8
  FpMarginConst* = 75
  FpMarginScale* = 75
  # Internal Iterative Reduction
  IirMinDepth* = 4
  # Singular Extension
  SeMinDepth* = 7
  SeDepthOffset* = 3
  SeMarginConst* = 0
  SeMarginScale* = 2
  SeDepthSub* = 1
  SeDepthDiv* = 2
  SePositiveExt* = 1
  SeDoubleExt* = 2
  SeDoubleMargin* = 20
  SeMultiCutLerp* = 40
  # Negative Extension
  SeNegativeExtTtBeta* = 2
  SeePruneCutoff* = 50
  SeePruningA* = 12
  SeePruningB* = 41
  # Aspiration Windows
  AspMinDepth* = 3
  AspInitAlpha* = 20
  AspInitBeta* = 20
  AspWideNum* = 3
  AspWideDen* = 2
  AspMaxRetries* = 6
  AspFailHighMaxReduction* = 2
  # Time Management
  TmDefaultMovesToGo* = 20
  TmIncrementScale*   = 0.90
  TmSoftTimeScale*    = 0.68
  TmHardTimeScale*    = 0.58
  MoveOverheadMs*     = 10
  TmNodeBase*         = 2.55
  TmNodeScale*        = 1.55
  TmNodeScaleMin*     = 0.20
  TmBmStabMin*        = 0.78
  TmBmStabMax*        = 2.36
  TmBmStabScale*      = 8.59
  TmBmStabOffset*     = 0.9
  TmBmStabPower*      = -2.57
  TmScaleMin*         = 0.20

var
  gMoveOverhead*: int = MoveOverheadMs
  LMR*: array[MaxPly, array[64, int]]

const
  StaticPruning*: array[MaxPly, int] = block:
    var t: array[MaxPly, int]
    for depth in 0 ..< MaxPly:
      t[depth] = -SeePruneCutoff * depth * depth
    t

  SEEPruning*: array[MaxPly, int] = block:
    var t: array[MaxPly, int]
    for depth in 0 ..< MaxPly:
      t[depth] = -(SeePruningA * depth * depth + SeePruningB * depth)
    t

  LmpTable*: array[MaxPly, int] = block:
    var t: array[MaxPly, int]
    for depth in 0 ..< MaxPly:
      t[depth] = 3 + depth * depth
    t

proc initTables*() =
  for depth in 1 ..< MaxPly:
    for moves in 1 ..< 64:
      LMR[depth][moves] = int(0.8 + ln(depth.float) * ln(1.2 * moves.float) / 1.8)
