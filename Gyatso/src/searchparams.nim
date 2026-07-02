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
  SeePruneCutoff* = 50
  # Aspiration Windows
  AspMinDepth* = 3
  AspInitAlpha* = 20
  AspInitBeta* = 20
  AspWideNum* = 3
  AspWideDen* = 2
  AspMaxRetries* = 6
  AspFailHighMaxReduction* = 2

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
