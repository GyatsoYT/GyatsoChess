import std/[atomics, locks, monotimes]
import coretypes
import board
import attacks
import search
import history

type
  ThreadData* = object
    id*:           int
    nativeThread*: Thread[ptr ThreadData]
    board*:        Board
    stack*:        SearchStack
    info*:         SearchInfo
    histData*:     ptr HistoryData
    generation*:   int       ## last dispatched generation; compared against pool's searchGeneration

  ThreadPool* = object
    threads*:          array[MaxSearchThreads, ptr ThreadData]
    threadCount*:      int
    stopFlag*:         Atomic[bool]
    poolLock*:         Lock
    startCond*:        Cond
    doneCond*:         Cond
    helpersRunning*:   int
    threadsAlive*:     bool
    searchGeneration*: int

var gThreadPool*: ThreadPool

proc totalNodes*(): uint64 =
  for i in 0 ..< gThreadPool.threadCount:
    if gThreadPool.threads[i] != nil:
      result += gThreadPool.threads[i].info.nodes

proc threadEntry(td: ptr ThreadData) {.thread.} =
  initHistoryData()
  initThreadAttacks()
  td.histData = gHistData

  while true:
    acquire(gThreadPool.poolLock)
    while td.generation == gThreadPool.searchGeneration and gThreadPool.threadsAlive:
      wait(gThreadPool.startCond, gThreadPool.poolLock)

    if not gThreadPool.threadsAlive:
      release(gThreadPool.poolLock)
      freeHistoryData()
      break

    td.generation = gThreadPool.searchGeneration
    release(gThreadPool.poolLock)

    discard iterativeDeepening(td.board, td.info)

    acquire(gThreadPool.poolLock)
    dec gThreadPool.helpersRunning
    if gThreadPool.helpersRunning == 0:
      signal(gThreadPool.doneCond)
    release(gThreadPool.poolLock)

proc destroyThreadPool*() =
  if gThreadPool.threadCount == 0: return

  # Signal helpers to exit.
  acquire(gThreadPool.poolLock)
  gThreadPool.threadsAlive = false
  broadcast(gThreadPool.startCond)
  release(gThreadPool.poolLock)

  # Join all helper threads
  for i in 1 ..< gThreadPool.threadCount:
    if gThreadPool.threads[i] != nil:
      joinThread(gThreadPool.threads[i].nativeThread)
      deallocShared(gThreadPool.threads[i])
      gThreadPool.threads[i] = nil

  if gThreadPool.threads[0] != nil:
    deallocShared(gThreadPool.threads[0])
    gThreadPool.threads[0] = nil

  gThreadPool.threadCount = 0

proc initThreadPool*(requestedCount: int) =

  destroyThreadPool()

  let count = max(1, min(requestedCount, MaxSearchThreads))

  initLock(gThreadPool.poolLock)
  initCond(gThreadPool.startCond)
  initCond(gThreadPool.doneCond)

  gThreadPool.threadsAlive     = true
  gThreadPool.searchGeneration = 0
  gThreadPool.helpersRunning   = 0
  gThreadPool.threadCount      = count
  gThreadPool.stopFlag.store(false, moRelaxed)
  gSmpThreadCount = count

  for i in 0 ..< count:
    let td = cast[ptr ThreadData](allocShared0(sizeof(ThreadData)))
    td.id = i
    td.info.id = i
    td.info.stopFlag = addr gThreadPool.stopFlag
    td.generation = 0
    gThreadPool.threads[i] = td

  initHistoryData()
  initThreadAttacks()
  gNodeAggregator = totalNodes

  for i in 1 ..< count:
    createThread(gThreadPool.threads[i].nativeThread, threadEntry, gThreadPool.threads[i])

proc dispatchHelpers*(rootBoard: Board,
                      startTime: MonoTime,
                      softLimitMs, hardLimitMs: int64,
                      depthLimit: int, nodeLimit: uint64) =
 
  gThreadPool.stopFlag.store(false, moRelease)
  for i in 1 ..< gThreadPool.threadCount:
    let td = gThreadPool.threads[i]
    td.board = rootBoard
    td.info.id           = i
    td.info.startTime    = startTime
    td.info.softLimitMs  = softLimitMs
    td.info.hardLimitMs  = hardLimitMs
    td.info.depthLimit   = depthLimit
    td.info.nodeLimit    = nodeLimit
    td.info.nodes        = 0
    td.info.selDepth     = 0
    td.info.silent       = true
    td.info.stopFlag     = addr gThreadPool.stopFlag
    td.info.depthCompleted = 0
    td.info.score        = 0
    zeroMem(addr td.stack, sizeof(SearchStack))

  acquire(gThreadPool.poolLock)
  gThreadPool.helpersRunning = max(0, gThreadPool.threadCount - 1)
  inc gThreadPool.searchGeneration
  broadcast(gThreadPool.startCond)
  release(gThreadPool.poolLock)

proc waitHelpers*() =
  gThreadPool.stopFlag.store(true, moRelease)
  if gThreadPool.threadCount > 1:
    acquire(gThreadPool.poolLock)
    while gThreadPool.helpersRunning > 0:
      wait(gThreadPool.doneCond, gThreadPool.poolLock)
    release(gThreadPool.poolLock)

proc selectBestThread*(): int =
  if gThreadPool.threadCount == 1: return 0

  var votes:      array[4096, int64]
  var minScore:   int   = high(int)
  var firstValid: int   = -1

  for i in 0 ..< gThreadPool.threadCount:
    let td = gThreadPool.threads[i]
    if td.info.depthCompleted == 0 or td.info.pvTable[0][0] == NullMove: continue
    if firstValid == -1: firstValid = i
    if td.info.score < minScore: minScore = td.info.score

  if firstValid == -1: return 0

  var bestThread = firstValid
  for i in 0 ..< gThreadPool.threadCount:
    let td = gThreadPool.threads[i]
    if td.info.depthCompleted == 0 or td.info.pvTable[0][0] == NullMove: continue

    let mv      = td.info.pvTable[0][0]
    let moveIdx = (mv.fromSq.int * 64 + mv.toSq.int) and 4095
    let weight  = int64(td.info.score - minScore + 50) * int64(td.info.depthCompleted)
    votes[moveIdx] += weight

    let bestMv  = gThreadPool.threads[bestThread].info.pvTable[0][0]
    let bestIdx = (bestMv.fromSq.int * 64 + bestMv.toSq.int) and 4095
    if votes[moveIdx] > votes[bestIdx]:
      bestThread = i

  return bestThread

