import std/math
import coretypes
import searchparams

type TimeManager* = object
  optTime*: int64
  maxTime*: int64
  scale*: float64
  prevBestMove*: Move
  stability*: int
  avgScore*: int
  hasAvgScore*: bool

proc initTimeManager*(myTime, myInc, movesToGo, moveOverhead: int): TimeManager =
  let limitMs = max(1, myTime - moveOverhead)
  let mtg = if movesToGo > 0: movesToGo else: TmDefaultMovesToGo
  let baseTime = limitMs.float64 / mtg.float64 + myInc.float64 * TmIncrementScale
  result.maxTime = max(1'i64, int64(limitMs.float64 * TmHardTimeScale))
  result.optTime = max(1'i64, int64(min(baseTime * TmSoftTimeScale, result.maxTime.float64)))
  result.scale = 1.0
  result.prevBestMove = NullMove
  result.stability = 0
  result.hasAvgScore = false

proc stopSoft*(tm: TimeManager, elapsedMs: int64): bool {.inline.} =
  elapsedMs.float64 >= tm.optTime.float64 * tm.scale

proc stopHard*(tm: TimeManager, elapsedMs: int64): bool {.inline.} =
  elapsedMs >= tm.maxTime

proc updateNodeScale*(tm: var TimeManager, bestMoveNodes, totalNodes: uint64) =
  let bmFrac = bestMoveNodes.float64 / max(1.0, totalNodes.float64)
  tm.scale = max(TmNodeBase - bmFrac * TmNodeScale, TmNodeScaleMin)

proc update*(tm: var TimeManager, depth: int, totalNodes: uint64,
             bestMove: Move, bestMoveNodes: uint64) =
  if bestMove == tm.prevBestMove:
    inc tm.stability
  else:
    tm.stability = 1
    tm.prevBestMove = bestMove

  let bmFrac = bestMoveNodes.float64 / max(1.0, totalNodes.float64)
  var scale = max(TmNodeBase - bmFrac * TmNodeScale, TmNodeScaleMin)

  if depth >= 6:
    let s = tm.stability.float64
    scale *= min(TmBmStabMax,
                 TmBmStabMin + TmBmStabScale * pow(s + TmBmStabOffset, TmBmStabPower))

  tm.scale = max(scale, TmScaleMin)
