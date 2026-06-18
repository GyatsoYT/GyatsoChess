import coretypes
import board
import bitboard
import history
import see

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

const mvvlvaVictimBonus: array[PieceType, int] = [
  1, 
  4, 
  4, 
  6, 
  12,
  0, 
  0, 
]

const mvvlvaAttackerPenalty: array[PieceType, int] = [
  0,
  1,    
  1,    
  2,    
  4,    
  5,    
  0,    
]

func mvvlvaScore(attackerPt, victimPt: PieceType): int {.inline.} =
  mvvlvaVictimBonus[victimPt] * 8 - mvvlvaAttackerPenalty[attackerPt]

const
  TtMoveScore*         = 2_000_000
  GoodCaptureBase*     = 1_000_000
  KillerBase*          = 900_000
  BadCaptureBase*      = -1_000_000

proc scoreMove*(b: Board, m: Move, ttMove: Move, ply: int): int =

  # 1. TT move
  if m == ttMove:
    return TtMoveScore

  let isCap  = isCapture(b, m)
  let isPromo = m.isPromotion

  # Capture or promotion
  if isCap or isPromo:

    # Determine promo piece type
    let promoPt: PieceType =
      if isPromo:
        case m.promoType
        of PromoQueen:  Queen
        of PromoKnight: Knight
        of PromoBishop: Bishop
        of PromoRook:   Rook
      else:
        NoPieceType

    # Classify promotion quality independent of capture
    let isGoodPromo: bool =
      isPromo and (promoPt == Queen or promoPt == Knight)

    # Run SEE to decide good vs bad exchange
    let seeOk = see(b, m, 0)

    if seeOk:
      let attackerPt =
        if isPromo: promoPt
        else:        b.mailbox[m.fromSq.int].pieceType

      let victimPt: PieceType =
        if m.isEnPassant: Pawn
        elif isCap:       b.mailbox[m.toSq.int].pieceType
        else:             NoPieceType

      let mvvlva =
        if victimPt != NoPieceType: mvvlvaScore(attackerPt, victimPt)
        else: 0

      let promoBonus =
        if isGoodPromo: 500
        elif isPromo:   200
        else: 0

      return GoodCaptureBase + promoBonus + mvvlva

    else:
      let attackerPt =
        if isPromo: promoPt
        else:        b.mailbox[m.fromSq.int].pieceType

      let victimPt: PieceType =
        if m.isEnPassant: Pawn
        elif isCap:       b.mailbox[m.toSq.int].pieceType
        else:             NoPieceType

      let mvvlva =
        if victimPt != NoPieceType: mvvlvaScore(attackerPt, victimPt)
        else: 0

      let promoBonus =
        if isPromo: 100
        else: 0

      return BadCaptureBase + promoBonus + mvvlva

  # 3. Killers
  let killerSlot = isKiller(m, ply)
  if killerSlot > 0:
    return KillerBase + killerSlot * 1_000

  # 4. History heuristic
  let stm      = b.stm.ord
  let fromSq   = m.fromSq.int
  let toSq     = m.toSq.int
  let fromThrt = if b.threats.hasSq(m.fromSq): 1 else: 0
  let toThrt   = if b.threats.hasSq(m.toSq):   1 else: 0
  return system.int(historyTable[stm][fromSq][toSq][fromThrt][toThrt])

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
