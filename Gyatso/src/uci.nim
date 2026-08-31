import std/[strutils, atomics, monotimes, times, strformat]
import coretypes
import board
import movegen
import perft
import timeman
import search
import tt
import history
import bench
import threads
import evaluate
import nnuetypes

proc reply(s: string) {.inline.} =
  stdout.writeLine(s)
  stdout.flushFile()

proc handlePosition(line: string, b: var Board) =
  var rest = line
  if rest.startsWith("position "):
    rest = rest[9..^1]

  if rest.startsWith("startpos"):
    b = parseFen(StartPos)
    rest = rest[8..^1]
  elif rest.startsWith("fen "):
    rest = rest[4..^1]
    let movesIdx = rest.find(" moves ")
    if movesIdx >= 0:
      b = parseFen(rest[0 ..< movesIdx])
      rest = rest[movesIdx..^1]
    else:
      b = parseFen(rest)
      rest = ""
  else:
    b = parseFen(StartPos)

  let movesTag = " moves "
  let mIdx = rest.find(movesTag)
  if mIdx >= 0:
    let movePart = rest[mIdx + movesTag.len .. ^1].strip()
    for tok in movePart.split(' '):
      if tok.len < 4: continue
      let fromSq = parseSquare(tok[0..1])
      let toSq = parseSquare(tok[2..3])
      var ml: MoveList
      generateMoves(b, ml)
      for i in 0 ..< ml.len:
        let m = ml.moves[i]
        if m.fromSq == fromSq and m.toSq == toSq:
          if m.isPromotion() and tok.len == 5:
            let promoCh = tok[4]
            let pt = m.promoType
            let matches = (case promoCh:
              of 'q': pt == PromoQueen
              of 'r': pt == PromoRook
              of 'b': pt == PromoBishop
              of 'n': pt == PromoKnight
              else: false)
            if not matches: continue
          b.makeMove(m)
          break

proc handleGo(line: string, b: Board) =
  let tokens = line.split()
  var
    depth = 0
    movetime = 0
    wtime = 0
    btime = 0
    winc = 0
    binc = 0
    movestogo = 0
    infinite = false

  var i = 1
  while i < tokens.len:
    case tokens[i]:
    of "depth":
      inc i
      if i < tokens.len: depth = parseInt(tokens[i])
    of "movetime":
      inc i
      if i < tokens.len: movetime = parseInt(tokens[i])
    of "wtime":
      inc i
      if i < tokens.len: wtime = parseInt(tokens[i])
    of "btime":
      inc i
      if i < tokens.len: btime = parseInt(tokens[i])
    of "winc":
      inc i
      if i < tokens.len: winc = parseInt(tokens[i])
    of "binc":
      inc i
      if i < tokens.len: binc = parseInt(tokens[i])
    of "movestogo":
      inc i
      if i < tokens.len: movestogo = parseInt(tokens[i])
    of "infinite":
      infinite = true
    else:
      discard
    inc i

  var softMs: int64
  var hardMs: int64
  if infinite or (depth > 0 and movetime == 0 and wtime == 0 and btime == 0):
    softMs = int64(high(int32))
    hardMs = int64(high(int32))
  elif movetime > 0:
    softMs = int64(high(int32))
    hardMs = int64(movetime)
  else:
    let myTime = if b.stm == White: wtime else: btime
    let myInc  = if b.stm == White: winc  else: binc
    if myTime > 0:
      let tInfo = calcTimeInfo(myTime, myInc, movestogo)
      softMs = tInfo.softLimit
      hardMs = tInfo.hardLimit
    else:
      softMs = int64(high(int32))
      hardMs = int64(high(int32))

  let startTime = getMonoTime()

  dispatchHelpers(b, startTime, softMs, hardMs, depth, 0)

  var t0 = gThreadPool.threads[0]
  t0.board          = b
  t0.info.id        = 0
  t0.info.startTime = startTime
  t0.info.softLimitMs  = softMs
  t0.info.hardLimitMs  = hardMs
  t0.info.depthLimit   = depth
  t0.info.nodeLimit    = 0
  t0.info.nodes        = 0
  t0.info.selDepth     = 0
  t0.info.silent       = false
  t0.info.stopFlag     = addr gThreadPool.stopFlag
  t0.info.depthCompleted = 0
  t0.info.score        = 0
  zeroMem(addr t0.stack, sizeof(SearchStack))

  discard iterativeDeepening(t0.board, t0.info)

  # Block until all helpers stop.
  waitHelpers()

  let winner  = selectBestThread()
  let winTd   = gThreadPool.threads[winner]
  let bestMove = winTd.info.completedMove
  let mv = if bestMove == NullMove: "0000" else: moveToAlgebraic(bestMove)

  # Always print a final info line from the winner so the last PV matches bestmove.
  let elapsed  = (getMonoTime() - startTime).inMilliseconds
  let allNodes = totalNodes()
  var finalInfo = winTd.info
  finalInfo.silent = false
  finalInfo.pvLen[0] = winTd.info.completedPVLen
  for i in 0 ..< winTd.info.completedPVLen:
    finalInfo.pvTable[0][i] = winTd.info.completedPV[i]
  printInfo(winTd.info.depthCompleted, winTd.info.selDepth,
            winTd.info.score, allNodes, elapsed, finalInfo)

  reply "bestmove " & mv

proc handlePerft(args: string, b: var Board) =
  let depthStr = args.strip()
  if depthStr.len == 0:
    reply "Usage: perft <depth>"
    return
  var depth = 0
  try: depth = parseInt(depthStr)
  except ValueError:
    reply "Invalid depth: " & depthStr
    return
  if depth <= 0:
    reply "Depth must be >= 1"
    return
  perftBenchmark(b, depth)

proc stopSearch() =
  gThreadPool.stopFlag.store(true, moRelease)

proc runUciLoop*() =
  var currentBoard = parseFen(StartPos)

  while true:
    var line: string
    if not stdin.readLine(line): break
    line = line.strip()
    if line.len == 0: continue

    case line:
    of "quit":
      stopSearch()
      destroyThreadPool()
      freeSharedHistory()
      break

    of "uci":
      reply "id name Gyatso 1.5.0"
      reply "id author Gyatso Neesham"
      reply "option name Hash type spin default 16 min 1 max 65536"
      reply "option name Threads type spin default 1 min 1 max 512"
      reply "uciok"

    of "isready":
      reply "readyok"

    of "ucinewgame":
      stopSearch()
      waitHelpers()
      clearAllHistory()
      currentBoard = parseFen(StartPos)

    of "stop":
      stopSearch()

    of "d":
      reply currentBoard.toFen()

    of "eval":
      var state: NNUEState
      refreshNNUE(currentBoard, state)
      let ply = state.current
      var stmAcc  = if currentBoard.stm == White: state.white[ply] else: state.black[ply]
      var nstmAcc = if currentBoard.stm == White: state.black[ply] else: state.white[ply]
      let allEvals  = nnueAllBuckets(currentBoard, stmAcc, nstmAcc)
      let activeBucket = nnueBucket(currentBoard)

      let stmStr = if currentBoard.stm == White: "White" else: "Black"
      reply "\n NNUE network contributions (" & stmStr & " to move)"
      reply "+------------+------------+------------+------------+"
      reply "|   Bucket   |  Material  | Positional |   Total    |"
      reply "|            |   (PSQT)   |  (Layers)  |            |"
      reply "+------------+------------+------------+------------+"
      for b in 0..<NUM_OUTPUT_BUCKETS:
        let rawCp = allEvals[b]
        let pawns = rawCp.float64 / 100.0
        let sign  = if rawCp >= 0: "+" else: "-"
        let absPawns = abs(pawns)
        let marker = if b == activeBucket: " <-- this bucket is used" else: ""
        let cell = fmt"{sign}  {absPawns:5.2f}"
        reply fmt"|  {b:<9} |     0.00   |  {cell}   |  {cell}   |{marker}"
      reply "+------------+------------+------------+------------+"

      let finalCp  = allEvals[activeBucket]
      let finalPaw = finalCp.float64 / 100.0
      let finalSign = if finalCp >= 0: "+" else: "-"
      let sideStr = if currentBoard.stm == White: "white side" else: "black side"
      reply ""
      reply fmt"NNUE evaluation        {finalSign}{abs(finalPaw):.2f} ({sideStr})"
      reply fmt"Final evaluation       {finalSign}{abs(finalPaw):.2f} ({sideStr}) [with output buckets, active={activeBucket}]"
      reply ""

    else:
      if line.startsWith("setoption "):
        let parts = line.split()
        var nameIdx  = -1
        var valueIdx = -1
        for idx in 0 ..< parts.len:
          if parts[idx] == "name"  and idx + 1 < parts.len: nameIdx  = idx + 1
          if parts[idx] == "value" and idx + 1 < parts.len: valueIdx = idx + 1
        if nameIdx >= 0 and valueIdx >= 0:
          case parts[nameIdx].toLowerAscii():
          of "hash":
            try: initTT(parseInt(parts[valueIdx]))
            except ValueError: discard
          of "threads":
            try:
              let n = parseInt(parts[valueIdx])
              if n >= 1 and n <= MaxSearchThreads:
                initThreadPool(n)
            except ValueError: discard
          else: discard

      elif line.startsWith("position"):
        handlePosition(line, currentBoard)

      elif line.startsWith("go"):
        handleGo(line, currentBoard)

      elif line.startsWith("perft "):
        handlePerft(line[6..^1], currentBoard)

      elif line == "perft":
        reply "Usage: perft <depth>"

      elif line == "bench":
        stopSearch()
        runBench(DefaultBenchDepth)

      elif line.startsWith("bench "):
        stopSearch()
        let depthStr = line[6..^1].strip()
        var d = DefaultBenchDepth
        try: d = parseInt(depthStr)
        except ValueError:
          reply "Invalid depth: " & depthStr
        if d > 0:
          runBench(d)
        else:
          reply "Depth must be >= 1"
