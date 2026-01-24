import coretypes, board, move

type
  HistoryTables* = object
    # Main history: [color][from_to_combined]
    mainHistory*: array[2, array[4096, int16]]

    # Counter history: [prev_piece_type][prev_to][curr_piece_type][curr_to]
    counterHistory*: array[6, array[64, array[6, array[64, int16]]]]

    # Follow-up history: [grandparent_piece][grandparent_to][curr_piece][curr_to]
    followUpHistory*: array[6, array[64, array[6, array[64, int16]]]]

    # Tactical history: [attacker_piece][to_square][victim_piece]
    tacticalHistory*: array[6, array[64, array[6, int16]]]

    # Counter moves: [from_to_combined] -> Move
    counterMoves*: array[4096, Move]

# Initialize all to zero at search start
proc initHistory*(h: var HistoryTables) =
  zeroMem(addr h, sizeof(HistoryTables))

# Helper Functions

# Calculate history index from move
template historyIndex*(move: Move): int =
  (move.fromSquare.int shl 6) or move.toSquare.int

# Get piece index (0-5)
template getPieceIndex*(piece: Piece): int =
  let pt = pieceType(piece)
  case pt
  of Pawn: 0
  of Knight: 1
  of Bishop: 2
  of Rook: 3
  of Queen: 4
  of King: 5
  else: 0 # Should never happen for valid pieces

# Main history getter
template getMainHistory*(history: HistoryTables, color: Color,
    move: Move): int =
  history.mainHistory[color.ord][historyIndex(move)]

# Counter history getter
template getCounterHistory*(history: HistoryTables, prevMove: Move, currMove: Move,
                        board: Board): int =
  block:
    if prevMove == Move(0):
      0
    else:
      let prevPiece = board.pieces[prevMove.fromSquare]
      let currPiece = board.pieces[currMove.fromSquare]

      if prevPiece == NoPiece or currPiece == NoPiece:
        0
      else:
        let prevIdx = getPieceIndex(prevPiece)
        let currIdx = getPieceIndex(currPiece)
        history.counterHistory[prevIdx][prevMove.toSquare][currIdx][
            currMove.toSquare]

# Follow-up history getter
template getFollowUpHistory*(history: HistoryTables, grandparentMove: Move,
                         currMove: Move, board: Board): int =
  block:
    if grandparentMove == Move(0):
      0
    else:
      let gpPiece = board.pieces[grandparentMove.fromSquare]
      let currPiece = board.pieces[currMove.fromSquare]

      if gpPiece == NoPiece or currPiece == NoPiece:
        0
      else:
        let gpIdx = getPieceIndex(gpPiece)
        let currIdx = getPieceIndex(currPiece)
        history.followUpHistory[gpIdx][grandparentMove.toSquare][currIdx][
            currMove.toSquare]

# Tactical history getter
template getTacticalHistory*(history: HistoryTables, move: Move,
    board: Board): int =
  block:
    let attacker = board.pieces[move.fromSquare]
    if attacker == NoPiece:
      0
    else:
      var victim: Piece
      let isCapture = move.isCapture or move.isEnPassant

      if move.isEnPassant:
        # Victim is pawn of opposite color
        victim = makePiece(if board.sideToMove == White: Black else: White, Pawn)
      elif move.isCapture:
        victim = board.pieces[move.toSquare]
      else:
        victim = NoPiece

      if not isCapture or victim == NoPiece:
        0
      else:
        let attackerIdx = getPieceIndex(attacker)
        let victimIdx = getPieceIndex(victim)
        history.tacticalHistory[attackerIdx][move.toSquare][victimIdx]

# Combined quiet history (main + counter + follow-up)
template getContinuationHistory*(history: HistoryTables, prevMove: Move,
    grandparentMove: Move, resultMove: Move, board: Board): int =
  (getCounterHistory(history, prevMove, resultMove, board) * 2) +
  getFollowUpHistory(history, grandparentMove, resultMove, board)

# Combined quiet history (main + continuation)
template getQuietHistory*(history: HistoryTables, move: Move, board: Board,
                      prevMove: Move, grandparentMove: Move): int =
  var score = history.mainHistory[board.sideToMove.ord][historyIndex(move)].int
  score += getContinuationHistory(history, prevMove, grandparentMove, move, board)
  score

template updateHistoryStat*(stat: var int16, bonus: int) =
  var s = stat.int
  let gravityDiv = 512 + (abs(bonus) shr 4)
  s += (32 * bonus) - (s * abs(bonus)) div gravityDiv

  if s > 16384: s = 16384
  if s < -16384: s = -16384

  stat = s.int16

# Update all relevant histories after a beta cutoff
proc updateHistories*(history: var HistoryTables, board: Board, ml: MoveList, cutoffIndex: int,
                      depth: int, prevMove: Move, grandparentMove: Move) =

  let bestMove = ml.moves[cutoffIndex]
  let bonus = min(depth * depth, 400)
  let penalty = -bonus
  let color = board.sideToMove

  if bestMove.isCapture or bestMove.isPromotion:
    if bestMove.isCapture:
      let attackerIdx = getPieceIndex(board.pieces[bestMove.fromSquare])
      let toSq = bestMove.toSquare

      var victimIdx: int
      if bestMove.isEnPassant:
        victimIdx = 0
      else:
        let victim = board.pieces[bestMove.toSquare]
        if victim != NoPiece:
          victimIdx = getPieceIndex(victim)
        else:
          victimIdx = 0

      updateHistoryStat(history.tacticalHistory[attackerIdx][toSq][victimIdx], bonus)

  else:
    let idx = historyIndex(bestMove)

    updateHistoryStat(history.mainHistory[color.ord][idx], bonus)

    if prevMove != Move(0):
      history.counterMoves[historyIndex(prevMove)] = bestMove

      let prevPiece = board.pieces[prevMove.fromSquare]
      let currPiece = board.pieces[bestMove.fromSquare]
      if prevPiece != NoPiece and currPiece != NoPiece:
        let prevIdx = getPieceIndex(prevPiece)
        let currIdx = getPieceIndex(currPiece)
        updateHistoryStat(
          history.counterHistory[prevIdx][prevMove.toSquare][currIdx][
              bestMove.toSquare],
          bonus
        )

    if grandparentMove != Move(0):
      let gpPiece = board.pieces[grandparentMove.fromSquare]
      let currPiece = board.pieces[bestMove.fromSquare]
      if gpPiece != NoPiece and currPiece != NoPiece:
        let gpIdx = getPieceIndex(gpPiece)
        let currIdx = getPieceIndex(currPiece)
        updateHistoryStat(
          history.followUpHistory[gpIdx][grandparentMove.toSquare][currIdx][
              bestMove.toSquare],
          bonus
        )

  for i in 0 ..< cutoffIndex:
    let move = ml.moves[i]
    if move == bestMove: continue

    if move.isCapture or move.isPromotion:
      if move.isCapture:
        let attacker = board.pieces[move.fromSquare]
        if attacker == NoPiece: continue
        let aIdx = getPieceIndex(attacker)

        var vIdx = 0
        if move.isEnPassant:
          vIdx = 0
        else:
          let vic = board.pieces[move.toSquare]
          if vic != NoPiece:
            vIdx = getPieceIndex(vic)

        updateHistoryStat(history.tacticalHistory[aIdx][move.toSquare][vIdx], penalty)

    else:
      updateHistoryStat(history.mainHistory[color.ord][historyIndex(move)], penalty)

      if prevMove != Move(0):
        let prevPiece = board.pieces[prevMove.fromSquare]
        let currPiece = board.pieces[move.fromSquare]
        if prevPiece != NoPiece and currPiece != NoPiece:
          let prevIdx = getPieceIndex(prevPiece)
          let currIdx = getPieceIndex(currPiece)
          updateHistoryStat(
            history.counterHistory[prevIdx][prevMove.toSquare][currIdx][
                move.toSquare],
            penalty
          )

      if grandparentMove != Move(0):
        let gpPiece = board.pieces[grandparentMove.fromSquare]
        let currPiece = board.pieces[move.fromSquare]
        if gpPiece != NoPiece and currPiece != NoPiece:
          let gpIdx = getPieceIndex(gpPiece)
          let currIdx = getPieceIndex(currPiece)
          updateHistoryStat(
            history.followUpHistory[gpIdx][grandparentMove.toSquare][currIdx][
                move.toSquare],
            penalty
          )

