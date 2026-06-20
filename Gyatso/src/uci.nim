import std/[strutils, atomics, monotimes, locks]
import coretypes
import board
import attacks
import movegen
import perft
import timeman
import search
import tt
import history
import bench

var
  gStopFlag*:      Atomic[bool]
  gSearchThread*:  Thread[void]
  gSearchRunning*: bool = false
  gSearchLock*:    Lock

type GoParams = object
  b:    Board
  info: SearchInfo

var gGoParams: GoParams

initLock(gSearchLock)

proc searchThread() {.thread.} =
  initThreadAttacks()
  var params = gGoParams
  var b      = params.b

  let (bestMove, _) = iterativeDeepening(b, params.info)

  let mv = if bestMove == NullMove: "0000"
           else: moveToAlgebraic(bestMove)
  echo "bestmove " & mv
  stdout.flushFile()

  withLock(gSearchLock):
    gSearchRunning = false

proc startSearch(b: Board, info: SearchInfo) =
  if gSearchRunning:
    gStopFlag.store(true, moRelease)
    joinThread(gSearchThread)

  gStopFlag.store(false, moRelease)
  gGoParams      = GoParams(b: b, info: info)
  gSearchRunning = true
  createThread(gSearchThread, searchThread)

proc stopSearch() =
  gStopFlag.store(true, moRelease)

proc joinSearch() =
  if gSearchRunning:
    joinThread(gSearchThread)
    gSearchRunning = false

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
      let toSq   = parseSquare(tok[2..3])
      var ml: MoveList
      generateMoves(b, ml)
      var found = false
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
              else:   false)
            if not matches: continue
          b.makeMove(m)
          found = true
          break

proc handleGo(line: string, b: Board) =
  let tokens = line.split()
  var
    depth     = 0
    movetime  = 0
    wtime     = 0
    btime     = 0
    winc      = 0
    binc      = 0
    movestogo = 0
    infinite  = false

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

  var allocMs: int
  if infinite or (depth > 0 and movetime == 0 and wtime == 0 and btime == 0):
    allocMs = high(int) div 2
  elif movetime > 0:
    allocMs = movetime
  else:
    let myTime = if b.stm == White: wtime else: btime
    let myInc  = if b.stm == White: winc  else: binc
    allocMs = if myTime > 0: calcMoveTime(myTime, myInc, movestogo)
              else: high(int) div 2

  var info = SearchInfo(
    startTime:  getMonoTime(),
    allocMs:    int64(allocMs),
    depthLimit: depth,
    nodeLimit:  0,
    nodes:      0,
    selDepth:   0,
    stopFlag:   addr gStopFlag
  )

  startSearch(b, info)

proc handlePerft(args: string, b: var Board) =
  let depthStr = args.strip()
  if depthStr.len == 0:
    reply "Usage: perft <depth>"
    return
  var depth = 0
  try:   depth = parseInt(depthStr)
  except ValueError:
    reply "Invalid depth: " & depthStr
    return
  if depth <= 0:
    reply "Depth must be >= 1"
    return
  perftBenchmark(b, depth)

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
      joinSearch()
      break

    of "uci":
      reply "id name Gyatso Rewrite"
      reply "id author Gyatso Neesham"
      reply "option name Hash type spin default 16 min 1 max 65536"
      reply "option name Threads type spin default 1 min 1 max 1"
      reply "uciok"

    of "isready":
      reply "readyok"

    of "ucinewgame":
      stopSearch()
      joinSearch()
      clearHistory()
      currentBoard = parseFen(StartPos)

    of "stop":
      stopSearch()
      joinSearch()

    of "d":
      reply currentBoard.toFen()

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
        joinSearch()
        runBench(DefaultBenchDepth)

      elif line.startsWith("bench "):
        stopSearch()
        joinSearch()
        let depthStr = line[6..^1].strip()
        var d = DefaultBenchDepth
        try: d = parseInt(depthStr)
        except ValueError:
          reply "Invalid depth: " & depthStr
        if d > 0:
          runBench(d)
        else:
          reply "Depth must be >= 1"
