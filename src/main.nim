# Program entry point and UCI loop will be implemented here. 
import strutils
import os # For exit, sleep
import logger # Import the new logger
import std/strformat # For fmt
import std/times # For epochTime, for perft timing

# Import other engine modules to ensure their global state/keys are initialized if needed.
# For example, zobrist keys are initialized upon module import.
# import zobrist # Removed as it was unused for now
import lookups # Added import for lookups
import board # For Board type and initializeBoard, for perft
import perft # For the perft function
import magicbitboards # For magic bitboards
import coretypes # For PieceType, Square, algebraicToSquare, etc.
import move # For Move, MoveList, Flags
import movegen # For generateLegalMoves
import utils # For algebraicToSquare, squareToAlgebraic

const
  EngineName* = "Gyatso"
  EngineAuthor* = "Gyatso Neesham"

var engineShouldQuit {.volatile.}: bool = false

# It's good practice to have a global board object that UCI commands like "position" would update.
# For the perft command, if this board isn't explicitly set by a "position" command yet,
# we'll use a fresh board from the starting FEN.
var globalBoard*: Board
var isBoardInitialized*: bool = false # Flag to track if globalBoard is set by "position"

# Helper function to convert UCI promotion character to PieceType
proc uciCharToPromotionPieceType(promoChar: char): PieceType =
  case promoChar.toLowerAscii():
  of 'q': return PieceType.Queen
  of 'r': return PieceType.Rook
  of 'b': return PieceType.Bishop
  of 'n': return PieceType.Knight
  else: return PieceType.NoPieceType # Indicates no valid promotion char

# Helper function to find and apply a UCI move string
# Returns true if the move was found and successfully applied, false otherwise.
proc findAndApplyUciMove(boardToUpdate: var Board; uciMoveStr: string): bool =
  if uciMoveStr.len < 4:
    log(fmt"Invalid UCI move string (too short): {uciMoveStr}", LogLevel.Warn)
    return false

  let fromSq = algebraicToSquare(uciMoveStr[0..1])
  let toSq = algebraicToSquare(uciMoveStr[2..3])
  var promotionType = PieceType.NoPieceType

  if uciMoveStr.len == 5:
    promotionType = uciCharToPromotionPieceType(uciMoveStr[4])
    if promotionType == PieceType.NoPieceType:
      log(fmt"Invalid promotion character in UCI move: {uciMoveStr}", LogLevel.Warn)
      return false
  elif uciMoveStr.len > 5:
    log(fmt"Invalid UCI move string (too long): {uciMoveStr}", LogLevel.Warn)
    return false

  var legalMoves: MoveList
  generateLegalMoves(boardToUpdate, legalMoves)

  for i in 0 ..< legalMoves.count:
    let candidateMove = legalMoves.moves[i]
    if candidateMove.fromSquare == fromSq and candidateMove.toSquare == toSq:
      var moveMatches = false
      if promotionType != PieceType.NoPieceType: # UCI move has promotion
        if (candidateMove.flags and FlagPromotion) != 0 and candidateMove.promotionPiece == promotionType:
          moveMatches = true
      else: # UCI move has no promotion
        if (candidateMove.flags and FlagPromotion) == 0:
          moveMatches = true
      
      if moveMatches:
        # Found the matching legal move, now apply it to the board
        let promoStr = if candidateMove.promotionPiece != PieceType.NoPieceType: $candidateMove.promotionPiece else: ""
        log(fmt"Applying UCI move: {uciMoveStr} (parsed as {squareToAlgebraic(candidateMove.fromSquare)}{squareToAlgebraic(candidateMove.toSquare)}{promoStr})", LogLevel.Debug)
        if boardToUpdate.makeMove(candidateMove):
          return true # Move successfully made
        else:
          # This should ideally not happen if generateLegalMoves is correct
          # and findMatchingMove selects a truly legal one.
          log(fmt"Error: makeMove failed for a supposedly legal UCI move: {uciMoveStr}", LogLevel.Error)
          return false
  
  log(fmt"Could not find a legal move matching UCI string: {uciMoveStr} for current board.", LogLevel.Warn)
  return false

proc uciInputThread() =
  ## Reads UCI commands from stdin and processes them.
  log("UCI input thread started.", LogLevel.Info)
  while not engineShouldQuit:
    if endOfFile(stdin):
      log("stdin reached EOF. Quitting input thread.", LogLevel.Info)
      engineShouldQuit = true
      break
    
    let line = stdin.readLine().strip()
    if line == "": 
      if not engineShouldQuit: sleep(10)
      continue

    log(fmt"UCI Received: {line}", LogLevel.Debug)

    let parts = line.splitWhitespace()
    if parts.len == 0: continue

    let command = parts[0]

    case command:
    of "uci":
      log("UCI command: uci", LogLevel.Info)
      echo "id name ", EngineName
      echo "id author ", EngineAuthor
      # TODO: Add any UCI options the engine supports here
      echo "uciok"
    of "isready":
      log("UCI command: isready", LogLevel.Info)
      # TODO: Potentially check if all initializations are complete
      echo "readyok"
    of "position":
      log(fmt"UCI command: {line}", LogLevel.Info)
      var fen = board.DefaultFen
      var moveStartIndex = -1
      var currentFenParts: seq[string]
      var readingFen = false

      if parts.len > 1:
        if parts[1] == "startpos":
          fen = board.DefaultFen
          log("Position set to startpos.", LogLevel.Info)
          if parts.len > 2 and parts[2] == "moves":
            moveStartIndex = 3
        elif parts[1] == "fen":
          readingFen = true
          var fenPartIndex = 2
          while fenPartIndex < parts.len and parts[fenPartIndex] != "moves":
            currentFenParts.add(parts[fenPartIndex])
            fenPartIndex += 1
          if currentFenParts.len > 0:
            fen = currentFenParts.join(" ")
            # Ensure FEN has 6 parts, or handle gracefully if board.setupBoardFromFen can.
            # For now, assume valid FEN string is formed.
            log(fmt"FEN string to parse: '{fen}'", LogLevel.Debug)
          else:
            log("FEN keyword found but no FEN string followed.", LogLevel.Warn)
            echo "info string Error: FEN keyword found but no FEN string."
            continue # Skip to next command
          
          if fenPartIndex < parts.len and parts[fenPartIndex] == "moves":
            moveStartIndex = fenPartIndex + 1
        else:
          log(fmt"Invalid position command format: {line}", LogLevel.Warn)
          echo "info string Error: Invalid position command."
          continue
      else: # "position" alone, implies startpos. Some GUIs might send this.
        fen = board.DefaultFen
        log("Position set to startpos (implicit).", LogLevel.Info)


      globalBoard = initializeBoard(fen)
      isBoardInitialized = true
      log(fmt"Board initialized. FEN: '{fen}'. Side to move: {globalBoard.sideToMove}", LogLevel.Info)

      if moveStartIndex != -1:
        log("Applying moves:", LogLevel.Info)
        var movesAppliedSuccessfully = true
        for i in moveStartIndex ..< parts.len:
          let uciMoveStr = parts[i]
          log(fmt"Attempting to apply move: {uciMoveStr}", LogLevel.Debug)
          if not findAndApplyUciMove(globalBoard, uciMoveStr):
            log(fmt"Failed to apply UCI move: {uciMoveStr}. Stopping further move application.", LogLevel.Error)
            echo fmt"info string Error: Failed to apply move '{uciMoveStr}'"
            movesAppliedSuccessfully = false
            break
          log(fmt"Successfully applied move: {uciMoveStr}. Board side to move now: {globalBoard.sideToMove}", LogLevel.Info)
        
        if movesAppliedSuccessfully:
          log("All UCI moves applied successfully.", LogLevel.Info)
        else:
          log("Board state may be inconsistent due to failed move application.", LogLevel.Warn)
      
      # It's good practice to acknowledge the position has been set.
      # Some engines might print the final FEN here after applying moves.
      echo "info string Position processed."

    of "go":
      log(fmt"UCI command: {line}", LogLevel.Info)
      if not isBoardInitialized:
        log("Board not initialized. 'go' command ignored.", LogLevel.Warn)
        echo "info string Board not set. Use 'position' command first."
        continue

      if parts.len > 1 and parts[1] == "perft":
        if parts.len == 3:
          try:
            let depth = parseInt(parts[2])
            if depth < 0:
              log("Perft depth must be non-negative.", LogLevel.Warn)
              echo "info string Perft depth must be non-negative."
            else:
              log(fmt"Starting 'go perft {depth}' on current board state.", LogLevel.Info)
              
              let startTime = epochTime()
              # Pass a copy of globalBoard if perft modifies it and doesn't restore perfectly,
              # or ensure perft restores it. Current perft is var Board, assumes restoration.
              var boardCopyForPerft = globalBoard # Make a copy for safety if perft doesn't perfectly restore.
                                                 # The prompt implies perft should restore the var Board it receives.
                                                 # If perft is trusted to restore, globalBoard can be passed directly.
                                                 # Let's assume perft restores globalBoard.
              let nodes = perft.perft(globalBoard, depth)
              let endTime = epochTime()
              let durationMs = (endTime - startTime) * 1000.0

              echo fmt"Nodes: {nodes}" 
              log(fmt"Perft({depth}) result: {nodes} nodes.", LogLevel.Info)
              
              echo fmt"info string Perft({depth}) result: {nodes} nodes."
              echo fmt"info string Perft({depth}) time: {durationMs:.2f} ms."
              if durationMs > 0.001:
                  let nps = float(nodes) / (durationMs / 1000.0)
                  echo fmt"info string Perft({depth}) NPS: {nps:.0f}"
              else:
                  echo fmt"info string Perft({depth}) NPS: N/A (duration too short)"
              
          except ValueError:
            log(fmt"Invalid depth for perft: {parts[2]}", LogLevel.Warn)
            echo "info string Invalid depth for perft. Must be an integer."
          except Exception as e:
            log(fmt"Error during perft execution: {e.msg}", LogLevel.Error)
            echo fmt"info string Error during perft: {e.msg}"
        else:
          log("Invalid 'go perft' command. Use: go perft <depth>", LogLevel.Warn)
          echo "info string Usage: go perft <depth>"
      elif parts.len > 1 and parts[1] == "perftdivide":
        if parts.len == 3:
          try:
            let depth = parseInt(parts[2])
            if depth < 0:
              log("PerftDivide depth must be non-negative.", LogLevel.Warn)
              echo "info string PerftDivide depth must be non-negative."
            elif depth == 0:
              log("PerftDivide depth 0 is trivial (1 node). Use depth >= 1 for meaningful division.", LogLevel.Info)
              echo "info string PerftDivide(0): 1 node. Use depth >= 1 for full output."
              echo "Nodes: 1" # Match standard perft output for depth 0
            else:
              log(fmt"Starting 'go perftdivide {depth}' on current board state.", LogLevel.Info)
              echo fmt"info string Starting PerftDivide for depth {depth}..."
              
              let startTime = epochTime()
              # perftDivide also takes var Board and is expected to restore it.
              let totalNodes = perft.perftDivide(globalBoard, depth)
              let endTime = epochTime()
              let durationMs = (endTime - startTime) * 1000.0

              # perftDivide itself prints the breakdown. Here, we print the total again for consistency and timing.
              echo fmt"info string PerftDivide({depth}) total nodes: {totalNodes}."
              echo fmt"info string PerftDivide({depth}) time: {durationMs:.2f} ms."
              if durationMs > 0.001:
                  let nps = float(totalNodes) / (durationMs / 1000.0)
                  echo fmt"info string PerftDivide({depth}) NPS: {nps:.0f}"
              else:
                  echo fmt"info string PerftDivide({depth}) NPS: N/A (duration too short)"
              log(fmt"PerftDivide({depth}) finished. Total nodes: {totalNodes}. Time: {durationMs:.2f} ms.", LogLevel.Info)

          except ValueError:
            log(fmt"Invalid depth for perftdivide: {parts[2]}", LogLevel.Warn)
            echo "info string Invalid depth for perftdivide. Must be an integer."
          except Exception as e:
            log(fmt"Error during perftdivide execution: {e.msg}", LogLevel.Error)
            echo fmt"info string Error during perftdivide: {e.msg}"
        else:
          log("Invalid 'go perftdivide' command. Use: go perftdivide <depth>", LogLevel.Warn)
          echo "info string Usage: go perftdivide <depth>"
      else:
        log("Other 'go' subcommands not implemented yet.", LogLevel.Info)
        echo "info string Search/other go commands not implemented yet."
    of "quit":
      log("UCI command: quit", LogLevel.Info)
      engineShouldQuit = true
      break # Exit while loop for uciInputThread
    else:
      log(fmt"Unknown UCI command: {command} from line: {line}", LogLevel.Warn)
      echo fmt"info string Unknown command: {command}"
  
  log("UCI input thread finished.", LogLevel.Info)

proc uciLoop*() =
  ## Main UCI loop for the engine.
  echo EngineName, " by ", EngineAuthor, ". Type 'uci' for UCI mode." 
  log(EngineName & " by " & EngineAuthor & ". UCI mode initialized.", LogLevel.Info)
  # (The above message is more for console direct use, UCI GUIs will send 'uci')

  var inputThread: Thread[void]
  try:
    # Note: If src/threading.nim was successfully fixed to re-export createThread,
    # this would ideally use `threading.createThread`.
    # For now, assuming std/threads is used directly or transitively via other imports if `threading.nim` has issues.
    createThread(inputThread, uciInputThread)
    log("UCI input thread created successfully.", LogLevel.Info)
  except Defect as e:
    log(fmt"Fatal: Could not create input thread: {e.msg}", LogLevel.Fatal)
    # echo is still fine here as logger might not be fully working if thread creation fails critically
    echo "Fatal: Could not create input thread: ", e.msg 
    quit(1)

  # Main thread loop: waits for quit signal or can perform other tasks.
  # For now, it just waits.
  while not engineShouldQuit:
    # Main engine logic could potentially check for commands from a queue here
    # or perform other periodic tasks if not in a thinking state.
    sleep(50) # Check for quit signal periodically

  log("Engine shutting down. Joining input thread...", LogLevel.Info)
  joinThread(inputThread)
  log("Input thread joined. Engine has quit.", LogLevel.Info)

# Program entry point
when isMainModule:
  initLogger(verbosity = LogLevel.Debug) # Initialize logger first
  log("Engine starting...", LogLevel.Info)

  lookups.precomputeAttackTables()
  log("Precomputed attack tables initialized.", LogLevel.Info)
  # Zobrist keys are initialized when the zobrist module is imported.
  # No board needs to be initialized here by default for UCI;
  # it will be set by a "position" command from the GUI.
  
  # Magic bitboards are initialized when the magicbitboards module is imported (if designed that way) 
  # or need an explicit init call here.
  # Assuming magicbitboards.initRookMagics() and initBishopMagics() are needed based on their structure.
  magicbitboards.initRookMagics()
  magicbitboards.initBishopMagics()
  log("Magic bitboards initialized.", LogLevel.Info)
  
  # Initialize the global board to startpos, so "go" or "perft" can run if no "position" is sent first.
  # This is a common practice for UCI engines.
  globalBoard = initializeBoard()
  isBoardInitialized = true # Mark as initialized to default starting position
  log("Global board initialized to starting position.", LogLevel.Info)

  uciLoop() 
  
  magicbitboards.deinitRookMagics()
  magicbitboards.deinitBishopMagics()
  log("Magic bitboards deinitialized.", LogLevel.Info)

  deinitLogger() # Deinitialize logger before exiting
  log("Engine exited.", LogLevel.Info) # This log might not be written if file is already closed 