import std/atomics
import coretypes, board, search, magicbitboards, move, tt

const MaxThreads* = 256

type
  ThreadData* = object
    threadID*: int
    board*: Board
    info*: SearchInfo
    
  ThreadPool* = object
    threads*: array[MaxThreads, Thread[ThreadData]]
    numThreads*: int
    
var pool*: ThreadPool
var searchRunning*: bool = false
var mainStopFlag*: ptr Atomic[bool]
var sharedNodeCounts*: ptr UncheckedArray[uint64]
var mainPonderFlag*: ptr Atomic[bool]

proc worker(data: ThreadData) {.thread.} =
  initThreadMagics()
  var b = data.board
  var info = data.info
  
  let (bestMove, _) = iterativeDeepening(b, info, data.threadID)
  
  if data.threadID == 0:
    # Get ponder move suggestion from TT (best continuation after our move)
    var ponderMove = Move(0)
    if bestMove != Move(0):
      # Make bestMove on a copy, then probe TT for its best continuation
      var tempBoard = data.board
      discard tempBoard.makeMove(bestMove)
      var alpha = -Infinity
      var beta = Infinity
      let (hit, _, ttMove, _, _) = probeTT(tempBoard.currentZobristKey, 0, alpha, beta, tempBoard.gamePly)
      if hit and ttMove != Move(0):
        ponderMove = ttMove
    
    # Output bestmove with optional ponder move
    if ponderMove != Move(0):
      echo "bestmove ", bestMove.toAlgebraic(), " ponder ", ponderMove.toAlgebraic()
    else:
      echo "bestmove ", bestMove.toAlgebraic()
    flushFile(stdout)



proc initThreadPool*(numThreads: int) =
  pool.numThreads = clamp(numThreads, 1, MaxThreads)
  
  # Allocate shared stop flag if not already
  if mainStopFlag == nil:
    mainStopFlag = cast[ptr Atomic[bool]](allocShared0(sizeof(Atomic[bool])))
  
  # Allocate shared ponder flag if not already
  if mainPonderFlag == nil:
    mainPonderFlag = cast[ptr Atomic[bool]](allocShared0(sizeof(Atomic[bool])))
    
  # Allocate shared node counters
  if sharedNodeCounts != nil:
    deallocShared(sharedNodeCounts)
  sharedNodeCounts = cast[ptr UncheckedArray[uint64]](allocShared0(sizeof(uint64) * numThreads))

proc stopSearch*() =
  if searchRunning:
    if mainStopFlag != nil:
      mainStopFlag[].store(true, moRelaxed)
      
    for i in 0 ..< pool.numThreads:
      joinThread(pool.threads[i])
      
    searchRunning = false

proc startSearch*(board: Board, info: SearchInfo) {.gcsafe.} =
  if searchRunning:
    stopSearch()
    
  searchRunning = true
  if mainStopFlag != nil:
    mainStopFlag[].store(false, moRelaxed)
  
  # Set ponder flag from info (main.nim will have set this in SearchInfo)
  if mainPonderFlag != nil and info.ponderFlag != nil:
    mainPonderFlag[].store(info.ponderFlag[].load(moRelaxed), moRelaxed)
    
  # Reset node counts
  if sharedNodeCounts != nil:
    for i in 0 ..< pool.numThreads:
      sharedNodeCounts[i] = 0
    
  for i in 0 ..< pool.numThreads:
    var data: ThreadData
    data.threadID = i
    data.board = board
    data.info = info
    data.info.stopFlag = mainStopFlag
    data.info.ponderFlag = mainPonderFlag
    data.info.threadID = i
    data.info.numThreads = pool.numThreads
    data.info.nodeCounts = sharedNodeCounts
    
    createThread(pool.threads[i], worker, data)

proc waitSearch*() =
  if searchRunning:
    for i in 0 ..< pool.numThreads:
      joinThread(pool.threads[i])
    searchRunning = false
