import math, coretypes

const
  SeePruneCutoff* = 20
  SeePruneCaptureCutoff* = 90

var
  LMR*: array[MaxPly, array[64, int]]
  StaticPruning*: array[2, array[MaxPly, int]]

# Initialize tables at module load
proc initTables*() =
  # Late Move Reduction table
  # Formula from dhouse: int(0.8 + log(depth) * log(1.2 * moves) / 2.5)
  for depth in 1 ..< MaxPly:
    for moves in 1 ..< 64:
      LMR[depth][moves] = int(0.8 + ln(depth.float) * ln(1.2 * moves.float) / 2.5)
  
  # Static Pruning tables
  for depth in 0 ..< MaxPly:
    # Index 0: Quiet move SEE pruning threshold
    StaticPruning[0][depth] = -SeePruneCutoff * depth * depth
    # Index 1: Capture SEE pruning threshold
    StaticPruning[1][depth] = -SeePruneCaptureCutoff * depth

# Call initialization at module load time
initTables()
