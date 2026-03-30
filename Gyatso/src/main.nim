import coretypes, zobrist, board, threading, logger, lookups, move, movegen, magicbitboards, evaluation, tt, nnuetypes, nnue, search
import std/strutils
import std/times
import std/atomics

# Global flag to control the engine loop
var quitEngine = false
var uciChess960 = false
var uciPonder = false
var isPondering = false
# var lastPonderMove = Move(0)

proc calculateSearchTime(wtime, btime, winc, binc, movestogo: int,
    sideToMove: Color): Duration =
  let timeAvailable = if sideToMove == White: wtime else: btime
  let inc = if sideToMove == White: winc else: binc

  var timeForMove = 0

  if movestogo > 0:
    timeForMove = timeAvailable div movestogo
  else:
    timeForMove = (timeAvailable div 30) + inc

  if timeForMove > 50:
    timeForMove -= 50

  return initDuration(milliseconds = timeForMove)

proc perftDriver(board: var Board, depth: int): uint64 =
  if depth == 0: return 1

  var nodes: uint64 = 0
  var ml: MoveList
  generatePseudoLegalMoves(board, ml)

  for i in 0 ..< ml.count:
    let m = ml.moves[i]
    if board.makeMove(m):
      nodes += perftDriver(board, depth - 1)
      board.unmakeMove(m)

  return nodes

proc parseMove(board: var Board, moveStr: string): Move =
  var ml: MoveList
  generateLegalMoves(board, ml)

  for i in 0 ..< ml.count:
    let m = ml.moves[i]
    if m.toAlgebraic() == moveStr:
      return m

  return Move(0)

proc uciLoop() {.thread, gcsafe.} =
  initThreadMagics() # Initialize thread-local magic bitboards
  var b = initializeBoard()

  initThreadPool(1) # Default to 1 thread

  while not quitEngine:
    try:
      let line = stdin.readLine()
      log("UCI Input: " & line, Debug)

      let parts = line.split(' ')
      if parts.len == 0: continue

      let command = parts[0]

      case command
      of "uci":
        echo "id name Gyatso 1.3.0"
        echo "id author Gyatso Neesham"
        echo "option name Hash type spin default 64 min 1 max 1024"
        echo "option name Threads type spin default 1 min 1 max 128"
        echo "option name UCI_Chess960 type check default false"
        echo "option name Ponder type check default false"
        echo "option name Log Engine type check default false"
        echo "option name EvalFile type string default <embedded>"
        echo "uciok"
      of "isready":
        echo "readyok"
      of "setoption":
        # setoption name <Name> value <Value>
        var name = ""
        var value = ""
        var parsingName = false
        var parsingValue = false

        for i in 1 ..< parts.len:
          if parts[i] == "name":
            parsingName = true
            parsingValue = false
            continue
          elif parts[i] == "value":
            parsingName = false
            parsingValue = true
            continue

          if parsingName:
            if name.len > 0: name.add(" ")
            name.add(parts[i])
          elif parsingValue:
            if value.len > 0: value.add(" ")
            value.add(parts[i])

        if name == "Hash":
          try:
            let mb = parseInt(value)
            initTT(mb)
            log("TT resized to " & $mb & " MB", Info)
          except ValueError:
            log("Invalid Hash value: " & value, Warn)
        elif name == "UCI_Chess960":
          if value == "true":
            uciChess960 = true
          else:
            uciChess960 = false
          log("UCI_Chess960 set to " & $uciChess960, Info)
        elif name == "Threads":
          try:
            let t = parseInt(value)
            if t >= 1:
              initThreadPool(t)
              log("Threads set to " & $t, Info)
            else:
              log("Invalid Threads value: " & value, Warn)
          except ValueError:
            log("Invalid Threads value: " & value, Warn)
        elif name == "Ponder":
          if value == "true":
            uciPonder = true
          else:
            uciPonder = false
          log("Ponder set to " & $uciPonder, Info)
        elif name == "Log Engine":
          if value == "true":
            setLoggerState(true)
            log("Logging enabled", Info)
          else:
            log("Logging disabled", Info)
            setLoggerState(false)
        elif name == "EvalFile":
          try:
            if value == "" or value == "<embedded>":
              initNNUE()
              log("NNUE loaded from embedded weights", Info)
            else:
              initNNUE(value)
              log("NNUE loaded from " & value, Info)
          except IOError:
            log("Failed to load NNUE file: " & value, Warn)


      of "stop":
        stopSearch()
        if isPondering:
          isPondering = false
          if mainPonderFlag != nil:
            mainPonderFlag[].store(false, moRelaxed)
          log("Stop received - clearing ponder state", Info)
      of "ponderhit":
        # Transition from pondering to regular search
        if isPondering:
          isPondering = false
          if mainPonderFlag != nil:
            mainPonderFlag[].store(false, moRelaxed)
          log("Ponderhit received - transitioning to regular search", Info)
      of "quit":
        stopSearch()
        quitEngine = true
      of "testmoves":
        var ml: MoveList
        generatePseudoLegalMoves(b, ml)
        echo "Generated ", ml.count, " moves:"
        for i in 0 ..< ml.count:
          let m = ml.moves[i]
          echo m.toAlgebraic(), " flags: ", m.flags
      of "testattacks":
        let us = b.sideToMove
        let them = if us == White: Black else: White
        echo "Attacked squares by ", if them == White: "White" else: "Black", ":"
        for sqInt in 0..63:
          let sq = sqInt.Square
          if isSquareAttacked(b, sq, them):
            echo sq, " is attacked"
      of "testmake":
        var ml: MoveList
        generatePseudoLegalMoves(b, ml)
        if ml.count > 0:
          let m = ml.moves[0]
          echo "Making move: ", m.toAlgebraic()
          let keyBefore = b.currentZobristKey
          if b.makeMove(m):
            echo "Move made. Key: ", b.currentZobristKey.toHex
            b.unmakeMove(m)
            echo "Move unmade. Key: ", b.currentZobristKey.toHex
            if b.currentZobristKey == keyBefore:
              echo "Success: Key restored."
            else:
              echo "FAILURE: Key mismatch!"
          else:
            echo "Move was illegal."
      of "perft":
        if parts.len > 1:
          try:
            let depth = parseInt(parts[1])
            echo "Performance test to depth ", depth
            let startTime = cpuTime()
            let nodes = perftDriver(b, depth)
            let endTime = cpuTime()
            let duration = endTime - startTime
            echo "Nodes: ", nodes
            echo "Time: ", duration * 1000, " ms"
            if duration > 0:
              echo "NPS: ", (nodes.float / duration).int
          except ValueError:
            echo "Invalid depth"
      of "go":
        # go depth <x> wtime <x> btime <x> winc <x> binc <x> movestogo <x> movetime <x> ponder
        var depth = 0
        var wtime = 0
        var btime = 0
        var winc = 0
        var binc = 0
        var movestogo = 0 # 0 means not specified
        var movetime = 0
        var infinite = false
        var ponder = false

        var i = 1
        while i < parts.len:
          case parts[i]
          of "depth":
            inc i; depth = parseInt(parts[i])
          of "wtime":
            inc i; wtime = parseInt(parts[i])
          of "btime":
            inc i; btime = parseInt(parts[i])
          of "winc":
            inc i; winc = parseInt(parts[i])
          of "binc":
            inc i; binc = parseInt(parts[i])
          of "movestogo":
            inc i; movestogo = parseInt(parts[i])
          of "movetime":
            inc i; movetime = parseInt(parts[i])
          of "infinite":
            infinite = true
          of "ponder":
            ponder = true
          else:
            discard
          inc i

        var allocatedTime = DurationZero

        if movetime > 0:
          allocatedTime = initDuration(milliseconds = movetime)
        elif wtime > 0 or btime > 0:
          allocatedTime = calculateSearchTime(wtime, btime, winc, binc,
              movestogo, b.sideToMove)

        if ponder:
          # Pondering mode: set flag but KEEP the allocated time for when ponderhit arrives
          isPondering = true
          if mainPonderFlag != nil:
            mainPonderFlag[].store(true, moRelaxed)
          log("Starting ponder search", Info)
        else:
          # Regular search: ensure ponder flag is OFF
          isPondering = false
          if mainPonderFlag != nil:
            mainPonderFlag[].store(false, moRelaxed)

        if infinite:
          allocatedTime = DurationZero

        if depth > 0 and allocatedTime == DurationZero and not infinite and not ponder:
          # Fixed depth search, no time limit
          discard

        var info: SearchInfo
        info.allocatedTime = allocatedTime
        info.depthLimit = depth
        info.ponderFlag = mainPonderFlag
        info.movesToGo = movestogo
        info.increment = initDuration(milliseconds = if b.sideToMove ==
            White: winc else: binc)
        # info.stopFlag is set by startSearch

        startSearch(b, info)
      of "eval":
        var tempState: NNUEState
        refreshState(addr gNetwork, b, tempState)
        let score = evaluate(b, tempState)
        echo "evaluation ", score, " cp"
        flushFile(stdout)
      of "d":
        b.printBoard()
      of "position":
        # Stop pondering if we receive a position command
        if isPondering:
          stopSearch()
          isPondering = false
          log("Stopping ponder search due to position change", Info)

        # position [startpos | fen <fen>] [moves <moves>]
        if parts.len > 1:
          var moveIdx = -1

          if parts[1] == "startpos":
            b = initializeBoard()
            moveIdx = 2
          elif parts[1] == "fen":
            var fen = ""
            var i = 2
            while i < parts.len and parts[i] != "moves":
              fen.add(parts[i] & " ")
              inc i
            b = initializeBoard(fen.strip())
            moveIdx = i

          if moveIdx != -1 and moveIdx < parts.len and parts[moveIdx] == "moves":
            for i in (moveIdx + 1) ..< parts.len:
              let m = parseMove(b, parts[i])
              if m != Move(0):
                discard b.makeMove(m)
              else:
                echo "Invalid move: ", parts[i]
      else:
        log("Unknown command: " & line, Warn)

    except EOFError:
      quitEngine = true

when isMainModule:
  initLogger()
  log("Gyatso Chess Engine Started", Info)

  precomputeAttackTables()
  log("Attack tables precomputed.", Info)

  initMagicBitboards()
  log("Magic bitboards initialized.", Info)

  initializeZobristKeys()
  log("Zobrist keys initialized.", Info)

  initTT(16) # 16 MB Transposition Table
  log("Transposition Table initialized.", Info)

  initNNUE()
  log("NNUE network loaded.", Info)

  var uciThread: Thread[void]
  createThread(uciThread, uciLoop)

  joinThread(uciThread)

  log("Engine exiting.", Info)
  closeLogger()
