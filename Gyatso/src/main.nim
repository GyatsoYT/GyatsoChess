import std/[os, strutils]
import attacks
import evaluate
import uci
import tt
import searchparams
import history
import bench
import threads

when isMainModule:
  initAttacks()
  initThreadAttacks()
  initTT(16)
  initTables()
  initNNUE()
  initHistoryModule()
  initThreadPool(1)

  let args = commandLineParams()
  if args.len >= 1 and args[0].toLowerAscii() == "bench":
    var depth = DefaultBenchDepth
    if args.len >= 2:
      try: depth = parseInt(args[1])
      except ValueError: discard
    runBench(depth)
    quit(0)

  runUciLoop()
