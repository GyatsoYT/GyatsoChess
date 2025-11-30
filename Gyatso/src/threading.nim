import std/locks
import std/atomics
import std/os
import coretypes, board, search, magicbitboards, move


type
  ThreadData* = object
    threadID*: int
    board*: Board
    info*: SearchInfo
    
  ThreadPool* = object
    threads*: seq[Thread[ThreadData]]
    numThreads*: int
    
var pool* {.threadvar.}: ThreadPool 
var searchRunning*: bool = false
var mainStopFlag*: ptr Atomic[bool]

proc worker(data: ThreadData) {.thread.} =
  initThreadMagics()
  var b = data.board
  var info = data.info
  
  let (bestMove, _) = iterativeDeepening(b, info, data.threadID)
  
  if data.threadID == 0:
    echo "bestmove ", bestMove.toAlgebraic()
    flushFile(stdout)



proc initThreadPool*(numThreads: int) =
  pool.numThreads = numThreads
  pool.threads = newSeq[Thread[ThreadData]](numThreads)
  
  # Allocate shared stop flag if not already
  if mainStopFlag == nil:
    mainStopFlag = cast[ptr Atomic[bool]](allocShared0(sizeof(Atomic[bool])))

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
    
  for i in 0 ..< pool.numThreads:
    var data: ThreadData
    data.threadID = i
    data.board = board
    data.info = info
    data.info.stopFlag = mainStopFlag
    
    createThread(pool.threads[i], worker, data)

proc waitSearch*() =
  if searchRunning:
    for i in 0 ..< pool.numThreads:
      joinThread(pool.threads[i])
    searchRunning = false
