import coretypes, board, move, bitboard, lookups, utils, evaluation, magicbitboards

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
  let them = if bySide == White: Black else: White
  
  let pawnAttacksBB = lookups.pawnAttacks[them][sq]
  let ourPawns = board.pieceBB[makePiece(bySide, Pawn)] and occupied
  let attackingPawns = pawnAttacksBB and ourPawns
  
  if attackingPawns != 0:
    return (Pawn, bitScanForward(attackingPawns).Square)
    
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
    let capturedSq = squareFromCoords(rankOf(fromSq), fileOf(toSq))
    occupied = occupied and not (1'u64 shl capturedSq)
  elif move.isCapture:
    let capturedPiece = board.pieces[toSq]
    valueTarget = getPieceValue(pieceType(capturedPiece))
  else:
    valueTarget = 0
    
  # If promotion, we gain value (Queen - Pawn)
  if promo != NoPieceType:
    valueTarget += getPieceValue(promo) - ValuePawn
    
  gain[d] = valueTarget
  occupied = occupied and not (1'u64 shl fromSq)
  occupied = occupied or (1'u64 shl toSq)
  
  # The piece now on toSq is the attacker
  var attackerType = pieceType(board.pieces[fromSq])
  if promo != NoPieceType:
    attackerType = promo
    
  var side = if board.sideToMove == White: Black else: White
  
  # Loop
  while true:
    d += 1
    
   
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
