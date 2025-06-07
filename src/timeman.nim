import types, position

type
  TimeManager* = object
    moveTime*: float         # Fixed time per move in seconds
    timeLeft*: array[Color, float]  # Time left for each player in seconds
    increment*: array[Color, float] # Increment per move in seconds
    movesToGo*: int         # Number of moves to next time control
    maxNodes*: int          # Maximum number of nodes to search

# Calculate how much time to use for the current move
proc calculateMoveTime*(tm: TimeManager, position: Position): float =
  # If we have a fixed move time, use that
  if tm.moveTime > 0:
    return tm.moveTime
  
  let us = position.us
  let timeLeft = tm.timeLeft[us]
  let increment = tm.increment[us]
  
  # If we're almost out of time, use a small fraction of what's left
  if timeLeft < 1.0:
    return timeLeft * 0.1
  
  # Estimate how many moves are left in the game
  let estimatedGameLength = 40
  let halfmovesPlayed = position.halfmovesPlayed
  let fullMovesPlayed = halfmovesPlayed div 2
  
  # Estimate moves to go
  var movesToGo = tm.movesToGo
  if movesToGo <= 0:
    # If no specific moves to go, estimate based on game phase
    let estimatedMovesLeft = max(20, estimatedGameLength - fullMovesPlayed)
    movesToGo = estimatedMovesLeft
  
  # Calculate base move time
  var moveTime = timeLeft / movesToGo.float
  
  # Add a portion of the increment
  if increment > 0:
    moveTime += increment * 0.75
  
  # Never use more than 40% of remaining time
  let maxTime = timeLeft * 0.4
  if moveTime > maxTime:
    moveTime = maxTime
  
  # Ensure we don't return a negative time
  return max(0.01, moveTime)

# Create a new time manager with default values
proc newTimeManager*(): TimeManager =
  var timeLeft: array[Color, float]
  var increment: array[Color, float]
  
  timeLeft[white] = float.high
  timeLeft[black] = float.high
  increment[white] = 0.0
  increment[black] = 0.0
  
  result = TimeManager(
    moveTime: 0.0,
    timeLeft: timeLeft,
    increment: increment,
    movesToGo: -1,
    maxNodes: high(int)
  )

# Set a fixed time per move
proc setMoveTime*(tm: var TimeManager, seconds: float) =
  tm.moveTime = seconds

# Set time left for a player
proc setTimeLeft*(tm: var TimeManager, color: Color, seconds: float) =
  tm.timeLeft[color] = seconds

# Set increment for a player
proc setIncrement*(tm: var TimeManager, color: Color, seconds: float) =
  tm.increment[color] = seconds

# Set moves to go until next time control
proc setMovesToGo*(tm: var TimeManager, moves: int) =
  tm.movesToGo = moves

# Set maximum number of nodes to search
proc setMaxNodes*(tm: var TimeManager, nodes: int) =
  tm.maxNodes = nodes