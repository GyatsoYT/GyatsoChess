import math, coretypes

const
  SeePruneCutoff* = 20
  SeePruneCaptureCutoff* = 90

var
  LMR*: array[MaxPly, array[64, int]]
  StaticPruning*: array[2, array[MaxPly, int]]
  LateMovePruning*: array[MaxPly, int]

# Initialize tables at module load
proc initTables*() =
  for depth in 1 ..< MaxPly:
    for moves in 1 ..< 64:
      LMR[depth][moves] = int(0.8 + ln(depth.float) * ln(1.2 * moves.float) / 2.5)
  
  for depth in 0 ..< MaxPly:
    StaticPruning[0][depth] = -SeePruneCutoff * depth * depth
    StaticPruning[1][depth] = -SeePruneCaptureCutoff * depth
  
  # Late Move Pruning thresholds: 3 + depth^2
  for depth in 0 ..< MaxPly:
    LateMovePruning[depth] = 3 + depth * depth

initTables()
