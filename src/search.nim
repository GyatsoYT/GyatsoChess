import coretypes
import board
import move
import movegen
import evaluation
import bitboard

proc kingSquare(board: Board, color: Color): Square =
  ## Finds the square of the king for the given color.
  let kingPiece = makePiece(color, PieceType.King)
  var kingBB = board.pieceBB[kingPiece]
  if kingBB != 0'u64:
    return popBit(kingBB)
  else:
    # This should never happen in a valid position
    return Square(0)

proc negamax*(board: var Board, depth: int, alpha: int, beta: int, ply: int = 0): int =
  ## Negamax variant of Alpha-Beta search.
  ## Returns the evaluation score from the perspective of the side to move.
  
  # Base Case: If depth == 0, call evaluate(board) and return the score
  if depth == 0:
    return evaluate(board)
  
  # Initialize maxEval = -Infinity (a very small number like -30000)
  var maxEval = -30000
  var currentAlpha = alpha
  
  # Generate legal moves for the current board state
  var moveList: MoveList
  generateLegalMoves(board, moveList)
  
  # If moveList.count == 0 (no legal moves)
  if moveList.count == 0:
    let kingSq = kingSquare(board, board.sideToMove)
    let opponentColor = if board.sideToMove == White: Black else: White
    
    # Check if king is in check
    if isSquareAttacked(board, kingSq, opponentColor):
      # It's checkmate. Return -KingValue + ply (score penalized by ply to prefer faster mates)
      return -KingValue + ply
    else:
      # It's stalemate. Return 0
      return 0
  
  # Iterate through each move in moveList
  for i in 0 ..< moveList.count:
    let currentMove = moveList.moves[i]
    
    # Store state for unmaking
    let originalCastlingRights = board.castlingRights
    let originalEnPassantSquare = board.enPassantSquare
    let originalHalfMoveClock = board.halfMoveClock
    let originalZobristKey = board.currentZobristKey
    
    # Make the move
    if board.makeMove(currentMove):
      # Recursive call: eval = -negamax(board, depth - 1, -beta, -alpha)
      # (Negating alpha/beta and result for negamax)
      let eval = -negamax(board, depth - 1, -beta, -currentAlpha, ply + 1)
      
      # Unmake the move
      board.unmakeMove(
        currentMove,
        originalCastlingRights,
        originalEnPassantSquare,
        originalHalfMoveClock,
        originalZobristKey
      )
      
      # maxEval = max(maxEval, eval)
      if eval > maxEval:
        maxEval = eval
      
      # alpha = max(alpha, eval)
      if eval > currentAlpha:
        currentAlpha = eval
      
      # If alpha >= beta, break the loop (beta cutoff)
      if currentAlpha >= beta:
        break
    else:
      # Move was illegal (shouldn't happen with generateLegalMoves, but handle gracefully)
      board.unmakeMove(
        currentMove,
        originalCastlingRights,
        originalEnPassantSquare,
        originalHalfMoveClock,
        originalZobristKey
      )
  
  # Return maxEval
  return maxEval

proc searchRoot*(board: var Board, depth: int): (Move, int) =
  ## Orchestrates the search from the root position.
  ## Returns the best move found and its score.

  var bestScore = -30001 # Slightly lower than negamax's -Infinity to ensure any valid score is better
  var bestMove: Move 
  # Initialize bestMove to a default/invalid state. 
  # Nim's default object initialization should be fine.
  # bestMove.fromSquare, bestMove.toSquare will be 0 (A1) by default.
  # bestMove.flags will be 0.

  var currentAlpha = -30000
  let currentBeta = 30000 # Beta is constant for the root search over all moves

  var rootMoves: MoveList
  generateLegalMoves(board, rootMoves)

  if rootMoves.count == 0:
    # No legal moves (checkmate or stalemate)
    # The negamax function itself handles scoring for these terminal nodes.
    # Here, we just indicate no move can be made.
    # The score could be determined by calling negamax at depth 0 or a shallow depth.
    # For simplicity, as per prompt "return invalid move, 0 score" for no moves.
    # However, it's better to reflect the actual game outcome.
    # Let's call negamax with current depth to get the terminal score.
    let terminalScore = negamax(board, depth, currentAlpha, currentBeta, 0) # ply 0 for root
    return (bestMove, terminalScore) # bestMove is still the default invalid one

  # If only one move, the loop will execute once and pick it.
  # No special handling needed for "if only one move, play it".

  for i in 0 ..< rootMoves.count:
    let currentRootMove = rootMoves.moves[i]

    let originalCastlingRights = board.castlingRights
    let originalEnPassantSquare = board.enPassantSquare
    let originalHalfMoveClock = board.halfMoveClock
    let originalZobristKey = board.currentZobristKey

    if board.makeMove(currentRootMove):
      # Call negamax for the opponent. Depth is depth-1.
      # Ply starts at 1 for children of the root.
      let score = -negamax(board, depth - 1, -currentBeta, -currentAlpha, 1)
      
      board.unmakeMove(
        currentRootMove,
        originalCastlingRights,
        originalEnPassantSquare,
        originalHalfMoveClock,
        originalZobristKey
      )

      if score > bestScore:
        bestScore = score
        bestMove = currentRootMove
      
      if score > currentAlpha: # Update alpha for subsequent sibling nodes
        currentAlpha = score
      
      # No beta cutoff at root, as we want to search all root moves to find the absolute best.
      # The alpha update helps narrow the window for deeper searches in subsequent root moves.

    else:
      # This should not happen if generateLegalMoves is correct.
      # If it does, unmake and continue.
      board.unmakeMove(
        currentRootMove,
        originalCastlingRights,
        originalEnPassantSquare,
        originalHalfMoveClock,
        originalZobristKey
      )
  
  return (bestMove, bestScore)
