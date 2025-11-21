
import coretypes, utils, bitboard, zobrist, board, threading, logger, lookups, move, movegen, magicbitboards, evaluation, search, tt
import std/strutils
import std/times

# Global flag to control the engine loop
var quitEngine = false

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
  
  while not quitEngine:
    try:
      let line = stdin.readLine()
      log("UCI Input: " & line, Debug)
      
      let parts = line.split(' ')
      if parts.len == 0: continue
      
      let command = parts[0]
      
      case command
      of "uci":
        echo "id name Gyatso"
        echo "id author Antigravity"
        echo "uciok"
      of "isready":
        echo "readyok"
      of "quit":
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
        # go depth <x> wtime <x> btime <x> movestogo <x> movetime <x>
        var depth = 0
        var wtime = 0
        var btime = 0
        var movestogo = 30
        var movetime = 0
        var infinite = false
        
        var i = 1
        while i < parts.len:
          case parts[i]
          of "depth":
            inc i; depth = parseInt(parts[i])
          of "wtime":
            inc i; wtime = parseInt(parts[i])
          of "btime":
            inc i; btime = parseInt(parts[i])
          of "movestogo":
            inc i; movestogo = parseInt(parts[i])
          of "movetime":
            inc i; movetime = parseInt(parts[i])
          of "infinite":
            infinite = true
          else:
            discard
          inc i
          
        var allocatedTime = DurationZero
        
        if movetime > 0:
          allocatedTime = initDuration(milliseconds = movetime)
        elif wtime > 0 or btime > 0:
          let timeAvailable = if b.sideToMove == White: wtime else: btime
          let timePerMove = timeAvailable div movestogo
          allocatedTime = initDuration(milliseconds = timePerMove)
          
        if infinite:
          allocatedTime = DurationZero
          
        if depth > 0 and allocatedTime == DurationZero and not infinite:
           discard
           
        var limit: TimeLimit
        limit.allocatedTime = allocatedTime
        limit.depthLimit = depth
        
        let (bestMove, score) = iterativeDeepening(b, limit)
        echo "bestmove ", bestMove.toAlgebraic()
      of "d":
        b.printBoard()
      of "position":
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

  initTT(64) # 64 MB Transposition Table
  log("Transposition Table initialized.", Info)
  
  var uciThread: Thread[void]
  createThread(uciThread, uciLoop)
  
  joinThread(uciThread)
  
  log("Engine exiting.", Info)
  closeLogger()
