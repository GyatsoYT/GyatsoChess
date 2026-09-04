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
  # Aspiration Windows
  AspMinDepth* = 3
  AspInitAlpha* = 20
  AspInitBeta* = 20
  AspWideNum* = 3
  AspWideDen* = 2
  AspMaxRetries* = 6
  AspFailHighMaxReduction* = 2
  TmTimeDiv* = 20
  TmIncNum* = 3
  TmIncDen* = 4
  TmHardNum* = 76
  TmHardDen* = 100
  TmSoftNum* = 52
  TmSoftDen* = 100
  StabilityScale*: array[0..4, int] = [100, 92, 85, 75, 65]

var
  LMR*: array[MaxPly, array[64, int]]
  StaticPruning*: array[MaxPly, int]
  LmpTable*: array[MaxPly, int]

proc initTables*() =
  for depth in 1 ..< MaxPly:
    for moves in 1 ..< 64:
      LMR[depth][moves] = int(0.8 + ln(depth.float) * ln(1.2 * moves.float) / 1.8)

  for depth in 0 ..< MaxPly:
    StaticPruning[depth] = -SeePruneCutoff * depth * depth # quiet moves

  for depth in 0 ..< MaxPly:
    LmpTable[depth] = 3 + depth * depth
