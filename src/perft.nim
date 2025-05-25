import coretypes, board, move, movegen, utils, strformat

# Helper to convert a Move object to its UCI string representation
proc promotionPieceToChar(pt: PieceType): char =
  case pt:
  of PieceType.Queen: 'q'
  of PieceType.Rook: 'r'
  of PieceType.Bishop: 'b'
  of PieceType.Knight: 'n'
  else: '\0' # Should indicate no promotion or error

proc moveToUciString*(move: Move): string =
  result = squareToAlgebraic(move.fromSquare) & squareToAlgebraic(move.toSquare)
  if (move.flags and FlagPromotion) != 0:
    let promoChar = promotionPieceToChar(move.promotionPiece)
    if promoChar != '\0':
      result.add(promoChar)

proc perft*(boardState: var Board, depth: int): uint64 =
  ## Calculates the number of leaf nodes in the move generation tree up to a certain depth.
  ## boardState is modified during the process but restored after each branch.
  if depth == 0:
    return 1'u64

  var nodes: uint64 = 0
  var legalMoves: MoveList 
  
  # generateLegalMoves does not modify the boardState passed to it,
  # as it operates on an internal temporary board.
  generateLegalMoves(boardState, legalMoves)

  # Optimization: if depth is 1, the number of legal moves is the perft count.
  if depth == 1:
    return uint64(legalMoves.count)

  for i in 0 ..< legalMoves.count:
    let currentMove = legalMoves.moves[i]
    
    # Store original state values from boardState BEFORE making the move.
    # These are crucial for correctly restoring the board state with unmakeMove.
    let originalCastlingRights = boardState.castlingRights
    let originalEnPassantSquare = boardState.enPassantSquare
    let originalHalfMoveClock = boardState.halfMoveClock
    let originalZobristKey = boardState.currentZobristKey
    
    # Call makeMove on boardState.
    # generateLegalMoves should have ensured that this move is fully legal,
    # meaning makeMove should successfully update the board without leaving the king in check.
    # The boolean returned by makeMove confirms this.
    let moveWasActuallyLegal = boardState.makeMove(currentMove)

    if not moveWasActuallyLegal:
      # This state indicates a potential bug or inconsistency between generateLegalMoves and makeMove.
      # A move deemed legal by generateLegalMoves was then found to be illegal by makeMove.
      # For a strict perft, such paths should not be counted.
      # However, the prompt implies makeMove will succeed based on generateLegalMoves's output.
      # If this happens, the perft result will be incorrect.
      # For now, we continue as if generateLegalMoves is the source of truth for what branches to explore.
      # If makeMove internally failed and didn't update the board properly, unmakeMove might also fail.
      # The safest is to only recurse if makeMove confirmed legality.
      # Let's adjust to only recurse if makeMove returned true.
      # This also aligns with the idea that nodes are positions reachable by legal moves.
      # Update: The prompt states "this makeMove should always succeed".
      # So, we will proceed with the recursive call assuming `moveWasActuallyLegal` is true.
      # If it's not, it's a deeper issue in movegen/board logic.
      # For the sake of perft correctness, if `makeMove` says it's not legal, we should not count it.
      # I will stick to the strict interpretation: only count nodes after a successful makeMove.
      # This also makes perft a better test for makeMove's own legality checks.
      #
      # Re-reading the prompt: "Since generateLegalMoves already verified legality regarding self-check,
      # this makeMove should always succeed for valid moves from generateLegalMoves."
      # This implies we can assume `moveWasActuallyLegal` will be true.
      # If it's false, it signals a bug elsewhere. Perft should reveal this.
      # So, we proceed with recursion. If `makeMove` itself has issues, the Zobrist key or other state
      # might be corrupted for the `unmakeMove` call.
      # Given the prompt, I will assume `moveWasActuallyLegal` is true.
      # The return value of `makeMove` is primarily for the `generateLegalMoves` internal loop.
      # In perft, we trust `generateLegalMoves` provided a valid sequence.
      discard "Assuming makeMove succeeded as per generateLegalMoves output."
    
    nodes += perft(boardState, depth - 1)
    
    # Call unmakeMove to restore boardState to its state BEFORE currentMove was made.
    # This ensures the next iteration of the loop starts from the correct original position.
    boardState.unmakeMove(
      currentMove,
      originalCastlingRights,
      originalEnPassantSquare,
      originalHalfMoveClock,
      originalZobristKey
    )
  return nodes 

proc perftDivide*(boardState: var Board, depth: int): uint64 =
  ## Calculates perft for a given depth, printing the breakdown for the first level of moves.
  ## Calls the main 'perft' function for sub-branches.
  ## boardState is modified during the process but restored after each branch.

  if depth == 0:
    # This base case is primarily for the recursive calls made by 'perft'
    # If perftDivide is called with depth 0 directly, it means 1 node (the current position).
    # However, perftDivide's main loop won't run for depth 0.
    echo "PerftDivide(0): 1 node (current position)"
    return 1'u64

  var totalNodes: uint64 = 0
  var legalMoves: MoveList
  
  # Generate legal moves for the current board state.
  # generateLegalMoves operates on a copy or is non-destructive to boardState here.
  generateLegalMoves(boardState, legalMoves)

  echo fmt"PerftDivide for depth {depth}. Found {legalMoves.count} legal moves:"

  # If depth is 1, each legal move is a leaf node.
  if depth == 1:
    for i in 0 ..< legalMoves.count:
      let move = legalMoves.moves[i]
      echo fmt"{moveToUciString(move)}: 1"
    totalNodes = uint64(legalMoves.count)
    echo fmt"Total nodes for PerftDivide({depth}): {totalNodes}"
    return totalNodes

  # For depth > 1, iterate through moves, make them, and call 'perft' for depth-1.
  for i in 0 ..< legalMoves.count:
    let currentMoveToDivide = legalMoves.moves[i]
    
    # Store original state for unmakeMove
    let originalCastlingRights = boardState.castlingRights
    let originalEnPassantSquare = boardState.enPassantSquare
    let originalHalfMoveClock = boardState.halfMoveClock
    let originalZobristKey = boardState.currentZobristKey
    
    # Make the move on the board
    let moveWasActuallyLegal = boardState.makeMove(currentMoveToDivide)

    if not moveWasActuallyLegal:
      # This indicates a serious issue if generateLegalMoves is trusted.
      # Log an error and potentially skip this branch or report an error.
      echo fmt"ERROR in PerftDivide: makeMove failed for {moveToUciString(currentMoveToDivide)}. Skipping this branch."
      # To be safe, try to unmake even if make failed, assuming make might have partially changed state.
      # Or, better, if makeMove guarantees no change on failure, then unmake isn't strictly needed.
      # Given the current structure, if makeMove returns false, its effect on the board is undefined
      # without inspecting board.nim. A robust makeMove should not alter board state if it returns false.
      # For now, we'll print an error and continue, assuming unmakeMove might still be needed.
      # The 'perft' function call will be skipped for this branch.
      boardState.unmakeMove( # Attempt to restore, though state might be suspect
            currentMoveToDivide,
            originalCastlingRights,
            originalEnPassantSquare,
            originalHalfMoveClock,
            originalZobristKey
      )
      continue # Skip to the next move
    
    # Recursively call the standard 'perft' for the remaining depth
    let nodesForThisBranch = perft(boardState, depth - 1)
    totalNodes += nodesForThisBranch
    
    echo fmt"{moveToUciString(currentMoveToDivide)}: {nodesForThisBranch}"
    
    # Unmake the move to restore the board state for the next iteration
    boardState.unmakeMove(
      currentMoveToDivide,
      originalCastlingRights,
      originalEnPassantSquare,
      originalHalfMoveClock,
      originalZobristKey
    )
  
  echo fmt"Total nodes for PerftDivide({depth}): {totalNodes}"
  return totalNodes 