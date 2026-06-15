import coretypes
import board
import bitboard
import history

# Killer move table: 2 killers per ply, indexed by ply
var killerMoves*: array[MaxPly + 1, array[2, Move]]

proc storeKiller*(ply: int, m: Move) {.inline.} =
  if killerMoves[ply][0] != m:
    killerMoves[ply][1] = killerMoves[ply][0]
    killerMoves[ply][0] = m

proc isKiller(m: Move, ply: int): int {.inline.} =
  if killerMoves[ply][0] == m: 2
  elif killerMoves[ply][1] == m: 1
  else: 0

func isCapture(b: Board, m: Move): bool {.inline.} =
  if m.isEnPassant: return true
  b.mailbox[m.toSq.int] != NoPiece

proc scoreMove*(b: Board, m: Move, ttMove: Move, ply: int): int {.inline.} =
  if m == ttMove:
    return 1_000_000

  let isCap = isCapture(b, m)
  let isPromo = m.isPromotion()

  const pieceValues = [100, 300, 310, 500, 900, 10000]

  if isCap:
    let attackerVal = pieceValues[b.mailbox[m.fromSq.int].pieceType.ord]
    let victimVal = if m.isEnPassant: 100
                    else: pieceValues[b.mailbox[m.toSq.int].pieceType.ord]

    if victimVal >= attackerVal or m.isEnPassant:
      # Good capture
      var score = 200_000 + victimVal * 100 - attackerVal
      if isPromo:
        let promoVal = case m.promoType
                       of PromoQueen:  900
                       of PromoRook:   500
                       of PromoBishop: 300
                       of PromoKnight: 350
        score += promoVal
      return score
    else:
      # Bad capture — below killers
      return victimVal * 100 - attackerVal + 10_000

  elif isPromo:
    # Non-capture promotion — treat like a good capture
    let promoVal = case m.promoType
                   of PromoQueen:  900
                   of PromoRook:   500
                   of PromoBishop: 300
                   of PromoKnight: 350
    return 200_000 + promoVal

  else:
    let killerSlot = isKiller(m, ply)
    if killerSlot > 0:
      return 150_000 + killerSlot * 1_000 
    
    # Retrieve threat indexed butterfly history score
    let stm = b.stm.ord
    let fromSq = m.fromSq.int
    let toSq = m.toSq.int
    let fromAttacked = if b.threats.hasSq(m.fromSq): 1 else: 0
    let toAttacked = if b.threats.hasSq(m.toSq): 1 else: 0
    return system.int(historyTable[stm][fromSq][toSq][fromAttacked][toAttacked])

proc sortMoves*(b: Board, ml: var MoveList, ttMove: Move, ply: int) =
  var scores: array[256, int]
  for i in 0 ..< ml.len:
    scores[i] = scoreMove(b, ml.moves[i], ttMove, ply)

  # Insertion sort
  for i in 1 ..< ml.len:
    let keyMove  = ml.moves[i]
    let keyScore = scores[i]
    var j = i - 1
    while j >= 0 and scores[j] < keyScore:
      ml.moves[j + 1] = ml.moves[j]
      scores[j + 1]   = scores[j]
      dec j
    ml.moves[j + 1]  = keyMove
    scores[j + 1]    = keyScore
