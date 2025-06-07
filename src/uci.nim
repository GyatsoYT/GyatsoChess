import
  types,
  move,
  position,
  bitboard,
  perft,
  castling,
  movegen,
  search,
  timeman
  
import std/[strutils, strformat, times]
import options
const
  defaultHashSizeMB = 4
  maxHashSizeMB = 1_048_576
  defaultNumThreads = 1

type
  UciState = object
    position: Position
    uciCompatibleOutput: bool = false
    timeManager: TimeManager
    maxDepth: Ply

proc info(uciState: UciState, s: string) =
  if not uciState.uciCompatibleOutput:
    echo s
  else:
    echo "info string ", s

proc uci(uciState: var UciState) =
  uciState.uciCompatibleOutput = true
  echo "id name Gyatso 0.1"
  echo "id author Gyatso Team"
  echo "option name Hash type spin default ",
    defaultHashSizeMB, " min 1 max ", maxHashSizeMB
  echo "option name Threads type spin default ",
    defaultNumThreads, " min 1 max 8"
  echo "option name MultiPV type spin default 1 min 1 max 1000"
  echo "option name UCI_Chess960 type check default false"
  echo "uciok"

proc setOption(uciState: var UciState, params: seq[string]) =
  if params.len == 4 and params[0] == "name" and params[2] == "value":
    case params[1].toLowerAscii
    of "Hash".toLowerAscii:
      let newHashSizeMB = params[3].parseInt
      if newHashSizeMB < 1 or newHashSizeMB > maxHashSizeMB:
        uciState.info "Invalid value"
      else:
        uciState.info fmt"Set hash size to {newHashSizeMB} MB"
    of "UCI_Chess960".toLowerAscii:
      discard
    of "Threads".toLowerAscii:
      let newNumThreads = params[3].parseInt
      if newNumThreads < 1 or newNumThreads > 8:
        uciState.info "Invalid value"
      else:
        uciState.info fmt"Set number of search threads to {newNumThreads}"
    of "MultiPV".toLowerAscii:
      let newMultiPv = params[3].parseInt
      if newMultiPv < 1 or newMultiPv > 1000:
        uciState.info "Invalid value"
      else:
        uciState.info fmt"Set multi pv to {newMultiPv}"
    else:
      uciState.info fmt"Unknown option: {params[1]}"
  else:
    uciState.info "Unknown parameters"

proc stop(uciState: var UciState) =
  discard

proc setPosition(uciState: var UciState, params: seq[string]) =
  var
    index = 0
    position: Position
  if params.len >= 1 and params[0] == "startpos":
    # Initialize to start position
    position.us = white
    position.halfmovesPlayed = 0
    position.halfmoveClock = 0
    position.enPassantTarget = noSquare
    position.rookSource = [[classicalRookSource[white][queenside], classicalRookSource[white][kingside]], 
                          [classicalRookSource[black][queenside], classicalRookSource[black][kingside]]]
    
    # Set up pieces
    position[pawn] = ranks[a2] or ranks[a7]
    position[knight] = b1.toBitboard or g1.toBitboard or b8.toBitboard or g8.toBitboard
    position[bishop] = c1.toBitboard or f1.toBitboard or c8.toBitboard or f8.toBitboard
    position[rook] = a1.toBitboard or h1.toBitboard or a8.toBitboard or h8.toBitboard
    position[queen] = d1.toBitboard or d8.toBitboard
    position[king] = e1.toBitboard or e8.toBitboard
    
    # Set up colors
    position[white] = ranks[a1] or ranks[a2]
    position[black] = ranks[a7] or ranks[a8]
    
    index = 1
  elif params.len >= 1 and params[0] == "fen":
    # TODO: Implement FEN parsing
    uciState.info "FEN parsing not implemented yet"
    return
  else:
    uciState.info "Unknown parameters"
    return

  if params.len > index and params[index] == "moves":
    index += 1
    # Apply moves
    for i in index ..< params.len:
      let moveStr = params[i]
      var moves: array[320, Move]
      let numMoves = position.generateMoves(moves)
      var found = false
      
      for j in 0 ..< numMoves:
        if $moves[j] == moveStr:
          position = position.doMove(moves[j])
          found = true
          break
      
      if not found:
        uciState.info fmt"Invalid move: {moveStr}"
        return
  
  uciState.position = position

# Helper for UCI info string formatting (ensure MaxSearchPly is accessible)
proc formatScoreForUci(score: Value, plyDepth: Ply): string =
  # Uses valueCheckmate from types.nim and search.MaxSearchPly from search.nim
  if abs(score) > valueCheckmate - search.MaxSearchPly.Value : 
    # ... (rest of your existing logic, seems okay) ...
    let pliesFromCurrentNode = valueInfinity - abs(score) 
    var movesToMate = (pliesFromCurrentNode + 1) div 2
    if score < 0: movesToMate = -movesToMate
    return fmt"score mate {movesToMate}"
  else:
    return fmt"score cp {score}"

# Callback for iterativeDeepening to send UCI info
proc sendUciInfo(depth: Ply, score: Value, iterNodes: uint64, totalTimeMs: int, pv: seq[Move]) =
  var pvStr = ""
  for m in pv: pvStr &= " " & $m 

  let scoreUciStr = formatScoreForUci(score, depth) # depth is current iteration depth
  # NPS uses search.nodesSearchedGlobal for total nodes in the whole "go" command
  let npsCalc = search.nodesSearchedGlobal * 1000'u64 
  let nps = if totalTimeMs > 0: npsCalc div totalTimeMs.uint64 else: 0'u64 
  
  # iterNodes is nodes for this iteration, search.nodesSearchedGlobal for total nodes
  echo fmt"info depth {depth} {scoreUciStr} seldepth {depth} nodes {search.nodesSearchedGlobal} nps {nps} time {totalTimeMs} pv{pvStr}"
  # Note: seldepth (selective depth) would ideally be the max ply reached in qsearch for this iteration.
  # For now, using main depth for seldepth is a common placeholder.


proc go(uciState: var UciState, params: seq[string]) =
  uciState.timeManager = newTimeManager()
  uciState.maxDepth = search.MaxSearchPly # Default to max search ply from search module

  search.searchCancelledFlagGlobal = false # Reset stop flag before new search

  # Parse go parameters
  for i in 0 ..< params.len:
    if i + 1 < params.len:
      case params[i]
      of "depth":
        uciState.maxDepth = params[i + 1].parseInt.Ply
      of "movetime":
        uciState.timeManager.setMoveTime(params[i + 1].parseFloat / 1000.0)
      of "wtime":
        uciState.timeManager.setTimeLeft(white, params[i + 1].parseFloat / 1000.0)
      of "btime":
        uciState.timeManager.setTimeLeft(black, params[i + 1].parseFloat / 1000.0)
      of "winc":
        uciState.timeManager.setIncrement(white, params[i + 1].parseFloat / 1000.0)
      of "binc":
        uciState.timeManager.setIncrement(black, params[i + 1].parseFloat / 1000.0)
      of "movestogo":
        uciState.timeManager.setMovesToGo(params[i + 1].parseInt)
      of "nodes":
        uciState.timeManager.setMaxNodes(params[i + 1].parseInt) # timeman stores int
      else: discard 

  let timeForThisMoveSec = uciState.timeManager.calculateMoveTime(uciState.position)
  # timeman.maxNodes is int. iterativeDeepening expects uint64.
  var maxNodesForThisMove: uint64
  if uciState.timeManager.maxNodes == high(int) or uciState.timeManager.maxNodes <= 0: # Check for default/no limit
      maxNodesForThisMove = high(uint64)
  else:
      maxNodesForThisMove = uciState.timeManager.maxNodes.uint64

  # Call iterativeDeepening with all required arguments
  let result = iterativeDeepening(
    uciState.position, 
    uciState.maxDepth, 
    timeForThisMoveSec, 
    maxNodesForThisMove, 
    sendUciInfo # Pass the callback procedure
  )
  
  # Output best move (noMove is from types.nim, exported via move.nim)
  if result.bestMove != noMove: 
    echo "bestmove ", $result.bestMove 
  else:
    echo "bestmove 0000" # Standard for no legal move or null move

proc perft(uciState: UciState, params: seq[string]) =
  if params.len >= 1:
    let
      start = epochTime()
      nodes = uciState.position.perft(params[0].parseInt, printRootMoveNodes = true)
      s = epochTime() - start
    uciState.info fmt"{nodes} nodes in {s:0.3f} seconds"
    uciState.info fmt"{(nodes.float / s).int} nodes per second"
  else:
    uciState.info "Missing depth parameter"

proc uciLoop*() =
  var uciState = UciState(
    timeManager: newTimeManager(),
    maxDepth: 64.Ply
  )
  
  # Initialize to start position
  uciState.position.us = white
  uciState.position.halfmovesPlayed = 0
  uciState.position.halfmoveClock = 0
  uciState.position.enPassantTarget = noSquare
  uciState.position.rookSource = [[classicalRookSource[white][queenside], classicalRookSource[white][kingside]], 
                                [classicalRookSource[black][queenside], classicalRookSource[black][kingside]]]
  
  # Set up pieces
  uciState.position[pawn] = ranks[a2] or ranks[a7]
  uciState.position[knight] = b1.toBitboard or g1.toBitboard or b8.toBitboard or g8.toBitboard
  uciState.position[bishop] = c1.toBitboard or f1.toBitboard or c8.toBitboard or f8.toBitboard
  uciState.position[rook] = a1.toBitboard or h1.toBitboard or a8.toBitboard or h8.toBitboard
  uciState.position[queen] = d1.toBitboard or d8.toBitboard
  uciState.position[king] = e1.toBitboard or e8.toBitboard
  
  # Set up colors
  uciState.position[white] = ranks[a1] or ranks[a2]
  uciState.position[black] = ranks[a7] or ranks[a8]

  while true:
    try:
      let command = readLine(stdin)
      let params = command.splitWhitespace()
      if params.len == 0 or params[0] == "":
        continue
      case params[0]
      of "uci":
        uciState.uci()
      of "setoption":
        uciState.setOption(params[1 ..^ 1])
      of "isready":
        echo "readyok"
      of "position":
        uciState.setPosition(params[1 ..^ 1])
      of "go":
        uciState.go(params[1 ..^ 1])
      of "stop":
        uciState.stop()
      of "quit":
        uciState.stop()
        break
      of "ucinewgame":
        # Reset position to start position
        uciState.position.us = white
        uciState.position.halfmovesPlayed = 0
        uciState.position.halfmoveClock = 0
        uciState.position.enPassantTarget = noSquare
        uciState.position.rookSource = [[classicalRookSource[white][queenside], classicalRookSource[white][kingside]], 
                                      [classicalRookSource[black][queenside], classicalRookSource[black][kingside]]]
        
        # Set up pieces
        uciState.position[pawn] = ranks[a2] or ranks[a7]
        uciState.position[knight] = b1.toBitboard or g1.toBitboard or b8.toBitboard or g8.toBitboard
        uciState.position[bishop] = c1.toBitboard or f1.toBitboard or c8.toBitboard or f8.toBitboard
        uciState.position[rook] = a1.toBitboard or h1.toBitboard or a8.toBitboard or h8.toBitboard
        uciState.position[queen] = d1.toBitboard or d8.toBitboard
        uciState.position[king] = e1.toBitboard or e8.toBitboard
        
        # Set up colors
        uciState.position[white] = ranks[a1] or ranks[a2]
        uciState.position[black] = ranks[a7] or ranks[a8]
      of "print":
        echo uciState.position
      of "perft":
        uciState.perft(params[1 ..^ 1])
      else:
        uciState.info fmt"Unknown command: {params[0]}"
        uciState.info "Use 'help' for a list of commands"
    except EOFError:
      uciState.info "Quitting because of reaching end of file"
      break
    except IndexDefect as e: # Specifically catch IndexDefect
      # Print the basic error message via UCI
      if uciState.uciCompatibleOutput:
        echo "info string CRITICAL IndexDefect: " & e.msg
        echo "info string StackTrace (IndexDefect below, then re-raising):"
        for line in e.getStackTrace().splitLines:
          echo "info string   " & line
      else:
        echo "CRITICAL IndexDefect: " & e.msg
        echo "StackTrace (IndexDefect below, then re-raising):"
        echo e.getStackTrace()
      
      # Re-raise to get Nim's default full error output and crash,
      # which is better for debugging this specific problem.
      raise e 
    except CatchableError as e: # Catch other "normal" errors
      if uciState.uciCompatibleOutput:
        echo "info string Error (" & $e.name & "): " & e.msg
        echo "info string StackTrace (" & $e.name & "):"
        for line in e.getStackTrace().splitLines:
          echo "info string   " & line
      else:
        echo "Error (" & $e.name & "): " & e.msg
        echo "StackTrace (" & $e.name & "):"
        echo e.getStackTrace()
      # For other catchable errors, we might not want to crash the engine for UCI.
      # You can decide if you want to `raise e` here too or just report.
    except: # For anything else, truly unexpected (less common)
      let e = getCurrentException()
      let msg = getCurrentExceptionMsg()
      if uciState.uciCompatibleOutput:
        echo "info string UNHANDLED Exception (" & $e.name & "): " & msg
        # Attempt to get stack trace if available
        # var trace = ""
        # try: trace = e.getStackTrace() except: discard
        # if trace != "":
        #   for line in trace.splitLines:
        #     echo "info string   " & line
      else:
        echo "UNHANDLED Exception (" & $e.name & "): " & msg
        # try: echo e.getStackTrace() except: discard
      # Potentially re-raise here too if you want it to crash for any unknown error.
      # raise e