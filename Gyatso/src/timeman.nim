import std/times
import std/monotimes
import move

const
  MoveOverheadMs* = 50  # Safety margin in milliseconds
  Window* = 50          # Centipawns for score oscillation threshold

type
  TimeManager* = object
    # Time tracking
    startTime: MonoTime
    allocatedTime*: Duration
    idealAllocatedTime: Duration
    remainingTime: Duration
    increment: Duration
    movesToGo: int
    
    # Best move stability tracking
    stability: float              # 0.0 to 1.0
    prevBestMove: Move
    
    # Score oscillation tracking
    prevScore: int
    currentDepth: int

proc initTimeManager*(allocatedTime, remainingTime, increment: Duration, movesToGo: int): TimeManager =
  ## Initialize a new TimeManager with the given time control parameters
  result.startTime = getMonoTime()
  result.allocatedTime = allocatedTime
  result.idealAllocatedTime = allocatedTime
  result.remainingTime = remainingTime
  result.increment = increment
  result.movesToGo = max(1, movesToGo)
  result.stability = 0.0
  result.prevBestMove = Move(0)
  result.prevScore = 0
  result.currentDepth = 0

proc timeElapsed*(tm: TimeManager): Duration =
  return getMonoTime() - tm.startTime

proc updateStability*(tm: var TimeManager, currentBestMove: Move) =
  if currentBestMove == tm.prevBestMove and tm.prevBestMove != Move(0):
    tm.stability = min(1.0, tm.stability + 0.1)
  else:
    tm.stability = 0.0
  
  tm.prevBestMove = currentBestMove

proc updateScoreOscillation*(tm: var TimeManager, currentScore: int) =
  if tm.currentDepth <= 1:
    tm.prevScore = currentScore
    tm.currentDepth = tm.currentDepth + 1
    return
  
  let diff = currentScore - tm.prevScore
  
  if abs(diff) <= Window:
    tm.allocatedTime = tm.idealAllocatedTime
  elif diff < 0:
    let multiplier = min(1.16, 1.04 * float(-diff div Window))
    let newAlloc = int(tm.idealAllocatedTime.inMilliseconds.float * multiplier)
    tm.idealAllocatedTime = initDuration(milliseconds = newAlloc)
  else:
    let multiplier = min(1.04, 1.02 * float(diff div Window))
    let newAlloc = int(tm.idealAllocatedTime.inMilliseconds.float * multiplier)
    tm.idealAllocatedTime = initDuration(milliseconds = newAlloc)
  
  let maxAllowed = tm.remainingTime - initDuration(milliseconds = MoveOverheadMs)
  tm.allocatedTime = min(tm.idealAllocatedTime, maxAllowed)
  
  tm.prevScore = currentScore
  tm.currentDepth = tm.currentDepth + 1

proc keepSearching*(tm: var TimeManager) =
  if tm.remainingTime == DurationZero:
    return
  let mtg = float(max(1, tm.movesToGo))
  let newAllocMs = tm.remainingTime.inMilliseconds.float * (0.5 / mtg + 0.5) + 
                   tm.increment.inMilliseconds.float
  
  let maxAllowedMs = tm.remainingTime.inMilliseconds - MoveOverheadMs
  tm.allocatedTime = initDuration(milliseconds = min(int(newAllocMs), maxAllowedMs))

proc shouldStopEarly*(tm: TimeManager): bool =
  let elapsed = tm.timeElapsed()
  let thresholdMs = (2.0 - tm.stability) * tm.allocatedTime.inMilliseconds.float / 2.0
  
  return elapsed.inMilliseconds.float > thresholdMs

proc outOfTime*(tm: TimeManager): bool =
  if tm.allocatedTime == DurationZero:
    return false
  
  return tm.timeElapsed() >= tm.allocatedTime
