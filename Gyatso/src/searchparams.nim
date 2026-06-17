import std/math
import coretypes

const
  NmpMinDepth* = 3
  NmpMinPly* = 1
  NmpBaseR* = 2
  NmpDepthDiv* = 4          # so R = 2 + depth div 4
  NmpVerificationDepth* = 14
  RfpDepth* = 12
  RfpLinearMargin* = 75
  RfpQuadraticMargin* = 15
  FpDepth* = 8
  FpMarginConst* = 75
  FpMarginScale* = 75

var
  LMR*: array[MaxPly, array[64, int]]

proc initTables*() =
  for depth in 1 ..< MaxPly:
    for moves in 1 ..< 64:
      LMR[depth][moves] = int(0.8 + ln(depth.float) * ln(1.2 * moves.float) / 1.8)
