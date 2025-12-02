import coretypes, board, move, bitboard, lookups, utils, evaluation, magicbitboards

# Value of pieces for SEE
# We use the values from evaluation.nim
const
  ValuePawn = PawnValue
  ValueKnight = KnightValue
  ValueBishop = BishopValue
  ValueRook = RookValue
  ValueQueen = QueenValue
  ValueKing = KingValue

proc getPieceValue(pt: PieceType): int =
  case pt
  of Pawn: ValuePawn
  of Knight: ValueKnight
  of Bishop: ValueBishop
  of Rook: ValueRook
  of Queen: ValueQueen
  of King: ValueKing
  else: 0

# Helper to find the least valuable attacker for a side
proc getLeastValuableAttacker(board: Board, sq: Square, bySide: Color, occupied: Bitboard, pawnAttacks: ptr array[Color, array[Square, Bitboard]]): (PieceType, Square) =
  # 1. Pawns
  # We need to check if any pawn of 'bySide' attacks 'sq'.
  # This is equivalent to checking if a pawn on 'sq' would attack a pawn of 'bySide'.
  # Actually, we have precomputed pawn attacks.
  # pawnAttacks[bySide][sq] gives squares that a pawn on 'sq' attacks? No.
  # Usually pawnAttacks[side][sq] is "squares attacked BY a pawn of 'side' on 'sq'".
  # We want attackers OF 'sq'.
  # So we check if a pawn of OPPONENT (them) on 'sq' would attack our pawns?
  # No.
  # If we want to know if White attacks sq with a pawn:
  # Check if Black pawn on sq attacks any White pawn.
  # So we use pawnAttacks[them][sq] & board.pieceBB[WhitePawn].
  
  let them = if bySide == White: Black else: White
  #echo "Debug LVA: sq=", sq, " bySide=", bySide, " them=", them
  
  let pawnAttacksBB = lookups.pawnAttacks[them][sq]
  let ourPawns = board.pieceBB[makePiece(bySide, Pawn)] and occupied
  let attackingPawns = pawnAttacksBB and ourPawns
  
  #echo "Debug LVA: pawnAttacksBB=", pawnAttacksBB, " ourPawns=", ourPawns, " attacking=", attackingPawns
  
  if attackingPawns != 0:
    return (Pawn, bitScanForward(attackingPawns).Square)
    
  # 2. Knights
  let ourKnights = board.pieceBB[makePiece(bySide, Knight)] and occupied
  let attackingKnights = lookups.knightAttacks[sq] and ourKnights
  if attackingKnights != 0:
    return (Knight, bitScanForward(attackingKnights).Square)
    
  # 3. Bishops
  let ourBishops = board.pieceBB[makePiece(bySide, Bishop)] and occupied
  let bishopAttacks = getBishopAttacks(sq, occupied)
  let attackingBishops = bishopAttacks and ourBishops
  if attackingBishops != 0:
    return (Bishop, bitScanForward(attackingBishops).Square)
    
  # 4. Rooks
  let ourRooks = board.pieceBB[makePiece(bySide, Rook)] and occupied
  let rookAttacks = getRookAttacks(sq, occupied)
  let attackingRooks = rookAttacks and ourRooks
  if attackingRooks != 0:
    return (Rook, bitScanForward(attackingRooks).Square)
    
  # 5. Queens
  let ourQueens = board.pieceBB[makePiece(bySide, Queen)] and occupied
  # Queens attack like Bishop + Rook
  let attackingQueens = (bishopAttacks or rookAttacks) and ourQueens
  if attackingQueens != 0:
    return (Queen, bitScanForward(attackingQueens).Square)
    
  # 6. King
  let ourKing = board.pieceBB[makePiece(bySide, King)] and occupied
  let attackingKing = lookups.kingAttacks[sq] and ourKing
  if attackingKing != 0:
    return (King, bitScanForward(attackingKing).Square)
    
  return (NoPieceType, Square(0))

proc see*(board: Board, move: Move): int =
  # Static Exchange Evaluation
  
  var gain: array[32, int]
  var d = 0
  
  let fromSq = move.fromSquare
  let toSq = move.toSquare
  let promo = move.promotion
  
  var occupied = board.allPiecesBB
  
  # Initial capture value
  var valueTarget = 0
  if move.isEnPassant:
    valueTarget = ValuePawn
    # Remove the captured pawn (which is not on toSq)
    # The captured pawn is at toSq rank +/- 1
    # But for SEE logic, we just assume we got the value.
    # We need to update occupied properly.
    # For EP, the pawn being captured is at (toSq file, fromSq rank).
    let capturedSq = squareFromCoords(rankOf(fromSq), fileOf(toSq))
    occupied = occupied and not (1'u64 shl capturedSq)
  elif move.isCapture:
    let capturedPiece = board.pieces[toSq]
    valueTarget = getPieceValue(pieceType(capturedPiece))
    #echo "SEE Debug: Capture ", pieceType(capturedPiece), " Value: ", valueTarget
  else:
    valueTarget = 0
    
  # If promotion, we gain value (Queen - Pawn)
  if promo != NoPieceType:
    valueTarget += getPieceValue(promo) - ValuePawn
    
  gain[d] = valueTarget
 # echo "SEE Debug: gain[0] = ", gain[0]
  
  # Make the move on the bitboard (conceptually)
  # Remove 'fromSq' from occupied
  occupied = occupied and not (1'u64 shl fromSq)
  # Add 'toSq' to occupied (it's occupied by the attacker now)
  occupied = occupied or (1'u64 shl toSq)
  
  # The piece now on toSq is the attacker
  var attackerType = pieceType(board.pieces[fromSq])
  if promo != NoPieceType:
    attackerType = promo
    
  var side = if board.sideToMove == White: Black else: White
  
  # Loop
  while true:
    d += 1
    
    # Find least valuable attacker for 'side' attacking 'toSq'
    # We need to pass 'occupied' because it changes
    # We can't use the helper exactly as is because it uses board.pieceBB which is static
    # But we can mask board.pieceBB with current 'occupied'.
    # However, if a piece moved (the initial mover), it's no longer at fromSq.
    # We handled that by updating 'occupied'.
    # But board.pieceBB still has the piece at fromSq.
    # So (board.pieceBB and occupied) will correctly exclude the moved piece from its old square.
    # But it won't include it at its new square 'toSq'.
    # The piece at 'toSq' is the one that just captured.
    # It is now a target.
    # The next attacker will capture IT.
    
    # So we need to find an attacker from 'side' that attacks 'toSq'.
    # The attacker must be in 'occupied'.
    
    let (nextAttackerType, nextAttackerSq) = getLeastValuableAttacker(board, toSq, side, occupied, addr lookups.pawnAttacks)
    
    if nextAttackerType == NoPieceType:
      break
      
    # Value of the piece being captured (the previous attacker)
    # gain[d] = value(previousAttacker) - gain[d-1]
    gain[d] = getPieceValue(attackerType) - gain[d-1]
    
    attackerType = nextAttackerType
    side = if side == White: Black else: White
    
    # Remove the new attacker from occupied
    occupied = occupied and not (1'u64 shl nextAttackerSq)
    
  # Propagate back
  d -= 1
  while d > 0:
    d -= 1
    if -gain[d+1] < gain[d]:
      gain[d] = -gain[d+1]
      
  return gain[0]
