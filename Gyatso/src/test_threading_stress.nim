import coretypes, tt, threading, board, search, magicbitboards, lookups, zobrist, utils, move
import std/times, std/os, std/locks, std/random

proc testTTConcurrency() =
  echo "Testing TT Concurrency..."
  initTT(16)
  
  const NumThreads = 4
  var threads: array[NumThreads, Thread[void]]
  
  proc worker() {.thread.} =
    var r = initRand(12345) # Deterministic for now, but concurrent access
    for i in 0..100000:
      let key = rand(r, int.high).uint64
      let depth = rand(r, 10)
      let score = rand(r, 20000)
      
      # Mock board
      var b: Board
      b.currentZobristKey = key
      
      storeTT(b, depth, score, -30000, 30000, Move(0), 0)
      
      var alpha = -30000
      var beta = 30000
      discard probeTT(key, depth, alpha, beta, 0)
      
  for i in 0 ..< NumThreads:
    createThread(threads[i], worker)
    
  for i in 0 ..< NumThreads:
    joinThread(threads[i])
    
  echo "TT Concurrency Test Passed (No Crashes)"

proc testSearchConcurrency() =
  echo "Testing Search Concurrency..."
  precomputeAttackTables()
  initMagicBitboards()
  initializeZobristKeys()
  initTT(16)
  
  initThreadPool(4)
  
  var b = initializeBoard()
  var info: SearchInfo
  info.depthLimit = 5
  info.allocatedTime = DurationZero 
  
  echo "Starting search with 4 threads..."
  startSearch(b, info)
  
  # Wait for completion (depth 5 should be fast)
  # But startSearch is async. We need to wait.
  # threading.waitSearch() joins threads.
  waitSearch()
  
  echo "Search Concurrency Test Passed"

when isMainModule:
  testTTConcurrency()
  testSearchConcurrency()
