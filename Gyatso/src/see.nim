import coretypes, board, move, bitboard, lookups, utils, magicbitboards, evaluation


template getPieceValue*(pt: PieceType, phase: int): int =
  case pt
  of Pawn: 
    (PawnValueMG * phase + PawnValueEG * (PhaseTotal - phase)) div PhaseTotal
  of Knight: 
    (KnightValueMG * phase + KnightValueEG * (PhaseTotal - phase)) div PhaseTotal
  of Bishop: 
    (BishopValueMG * phase + BishopValueEG * (PhaseTotal - phase)) div PhaseTotal
  of Rook: 
    (RookValueMG * phase + RookValueEG * (PhaseTotal - phase)) div PhaseTotal
  of Queen: 
    (QueenValueMG * phase + QueenValueEG * (PhaseTotal - phase)) div PhaseTotal
  of King: KingValue
  else: 0

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
    
  let ourBishops = board.pieceBB[makePiece(bySide, Bishop)] and occupied
  let bishopAttacks = getBishopAttacks(sq, occupied)
  let attackingBishops = bishopAttacks and ourBishops
  if attackingBishops != 0:
    return (Bishop, bitScanForward(attackingBishops).Square)
    
  let ourRooks = board.pieceBB[makePiece(bySide, Rook)] and occupied
  let rookAttacks = getRookAttacks(sq, occupied)
  let attackingRooks = rookAttacks and ourRooks
  if attackingRooks != 0:
    return (Rook, bitScanForward(attackingRooks).Square)
    
  let ourQueens = board.pieceBB[makePiece(bySide, Queen)] and occupied
  let attackingQueens = (bishopAttacks or rookAttacks) and ourQueens
  if attackingQueens != 0:
    return (Queen, bitScanForward(attackingQueens).Square)
    
  let ourKing = board.pieceBB[makePiece(bySide, King)] and occupied
  let attackingKing = lookups.kingAttacks[sq] and ourKing
  if attackingKing != 0:
    return (King, bitScanForward(attackingKing).Square)
    
  return (NoPieceType, Square(0))

proc see*(board: Board, move: Move, phase: int): int =
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
    valueTarget = getPieceValue(Pawn, phase)
    let capturedSq = squareFromCoords(rankOf(fromSq), fileOf(toSq))
    occupied = occupied and not (1'u64 shl capturedSq)
  elif move.isCapture:
    let capturedPiece = board.pieces[toSq]
    valueTarget = getPieceValue(pieceType(capturedPiece), phase)
  else:
    valueTarget = 0
    
  if promo != NoPieceType:
    valueTarget += getPieceValue(promo, phase) - getPieceValue(Pawn, phase)
    
  gain[d] = valueTarget
  
  occupied = occupied and not (1'u64 shl fromSq)
  occupied = occupied or (1'u64 shl toSq)
  
  var attackerType = pieceType(board.pieces[fromSq])
  if promo != NoPieceType:
    attackerType = promo
    
  var side = if board.sideToMove == White: Black else: White
  
  while true:
    d += 1
    
    let (nextAttackerType, nextAttackerSq) = getLeastValuableAttacker(board, toSq, side, occupied, addr lookups.pawnAttacks)
    
    if nextAttackerType == NoPieceType:
      break
    
    gain[d] = getPieceValue(attackerType, phase) - gain[d-1]
    
    attackerType = nextAttackerType
    side = if side == White: Black else: White
    
    occupied = occupied and not (1'u64 shl nextAttackerSq)
    
  d -= 1
  while d > 0:
    d -= 1
    if -gain[d+1] < gain[d]:
      gain[d] = -gain[d+1]
      
  return gain[0]
