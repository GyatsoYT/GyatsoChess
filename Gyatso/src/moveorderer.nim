import coretypes
import board
import bitboard
import history
import see
import movegen

var killerMoves* {.threadvar.}: array[MaxPly + 1, array[2, Move]]

proc storeKiller*(ply: int, m: Move) {.inline.} =
  if killerMoves[ply][0] != m:
    killerMoves[ply][1] = killerMoves[ply][0]
    killerMoves[ply][0] = m

func isCapture*(b: Board, m: Move): bool {.inline.} =
  if m.isEnPassant: return true
  if m.isCastling: return false  # toSq is own rook, not a capture
  b.mailbox[m.toSq.int] != NoPiece

const
  TtMoveScore*     = 2_000_000
  GoodCaptureBase* = 1_000_000
  KillerBase*      = 900_000
  BadCaptureBase*  = -1_000_000

const mvvlvaVictimBonus: array[PieceType, int] = [
  1, 4, 4, 6, 12, 0, 0,
]

const mvvlvaAttackerPenalty: array[PieceType, int] = [
  0, 1, 1, 2, 4, 5, 0,
]

func mvvlvaScore(attackerPt, victimPt: PieceType): int {.inline.} =
  mvvlvaVictimBonus[victimPt] * 8 - mvvlvaAttackerPenalty[attackerPt]

proc pickBest(moves: var array[256, Move],
              scores: var array[256, int32],
              cur, count: int): Move {.inline.} =
  var bestIdx    = cur
  var bestScore = scores[cur]
  for i in (cur + 1) ..< count:
    if scores[i] > bestScore:
      bestScore = scores[i]
      bestIdx    = i
  if bestIdx != cur:
    let tmpMove     = moves[cur]
    let tmpScore    = scores[cur]
    moves[cur]      = moves[bestIdx]
    scores[cur]     = scores[bestIdx]
    moves[bestIdx]  = tmpMove
    scores[bestIdx] = tmpScore
  result = moves[cur]

type MovePickerStage* = enum
  StageTTMove
  StageGenNoisies
  StageGoodNoisies
  StageGenQuiets
  StageQuiets
  StageBadNoisies
  StageDone

type MovePicker* = object
  board*:          ptr Board
  ttMove*:         Move
  ply*:            int
  prevPiece*:      int
  prevToSq*:       int
  prev2Piece*:     int
  prev2ToSq*:      int
  stage*:          MovePickerStage
  noisyMoves:      MoveList
  noisyScores:     array[256, int32]
  noisyCur:        int
  badMoves:        array[64, Move]
  badScores:       array[64, int32]
  badCount:        int
  badCur:          int
  quietMoves:      MoveList
  quietScores:     array[256, int32]
  quietCur:        int
  skipQuietsMark*: bool
  isQSearch*:      bool
  inCheck*:        bool

func isTTMoveLegal(b: Board, m: Move): bool {.inline.} =
  if m == NullMove: return false
  let moving = b.mailbox[m.fromSq.int]
  if moving == NoPiece: return false
  if moving.color != b.stm: return false
  if m.isCastling: return true   # king->rook encoding: toSq is own rook, always legal to probe
  let dest = b.mailbox[m.toSq.int]
  if dest != NoPiece and dest.color == b.stm: return false
  if m.isEnPassant and b.epSquare != m.toSq: return false
  true

proc scoreNoisy(b: Board, m: Move): int32 {.inline.} =
  let mt      = m.moveType
  let isPromo = mt == Promotion
  let isEP    = mt == EnPassant
  let isCap   = isEP or (b.mailbox[m.toSq.int] != NoPiece)

  let attackerPt: PieceType =
    if isPromo:
      case m.promoType
      of PromoQueen:  Queen
      of PromoKnight: Knight
      of PromoBishop: Bishop
      of PromoRook:   Rook
    else:
      b.mailbox[m.fromSq.int].pieceType

  let victimPt: PieceType =
    if isEP:    Pawn
    elif isCap: b.mailbox[m.toSq.int].pieceType
    else:       NoPieceType

  let mvvlva     = if victimPt != NoPieceType: mvvlvaScore(attackerPt, victimPt) else: 0
  let promoBonus =
    if not isPromo: 0
    elif attackerPt == Queen or attackerPt == Knight: 500
    else: 200

  int32(GoodCaptureBase + promoBonus + mvvlva)

proc scoreQuiets(b: Board, ml: MoveList, scores: var array[256, int32],
                 ply, prevPiece, prevToSq, prev2Piece, prev2ToSq: int) {.inline.} =
  ## Thread-local tables and continuation rows are resolved once per batch
  ## instead of once per move.
  let killer0 = killerMoves[ply][0]
  let killer1 = killerMoves[ply][1]
  let hist = gHistData
  let stm = b.stm.ord
  let threats = b.threats
  let cont1 = if prevPiece >= 0: addr hist.continuationHistory[prevPiece][prevToSq] else: nil
  let cont2 = if prev2Piece >= 0: addr hist.continuationHistory2[prev2Piece][prev2ToSq] else: nil
  for i in 0 ..< ml.len:
    let m = ml.moves[i]
    if m == killer0:
      scores[i] = int32(KillerBase + 2 * 1_000)
      continue
    if m == killer1:
      scores[i] = int32(KillerBase + 1 * 1_000)
      continue
    let fromSq   = m.fromSq.int
    let toSq     = m.histToSq.int
    let fromThrt = if threats.hasSq(m.fromSq): 1 else: 0
    let toThrt   = if threats.hasSq(m.histToSq): 1 else: 0
    var score = system.int(hist.historyTable[stm][fromSq][toSq][fromThrt][toThrt])
    let curPiece = ord(b.mailbox[fromSq])
    if cont1 != nil:
      score += 2 * system.int(cont1[][curPiece][toSq])
    if cont2 != nil:
      score += system.int(cont2[][curPiece][toSq])
    scores[i] = int32(score)

proc initMovePicker*(picker: var MovePicker, b: ptr Board,
                     ttMove: Move,
                     ply, prevPiece, prevToSq,
                     prev2Piece, prev2ToSq: int,
                     inCheck, isQSearch: bool) {.inline.} =
  # Search reads threats/pins for every move it gets from the picker.
  b[].ensureAttackState()
  picker.board          = b
  picker.ttMove         = ttMove
  picker.ply            = ply
  picker.prevPiece      = prevPiece
  picker.prevToSq       = prevToSq
  picker.prev2Piece     = prev2Piece
  picker.prev2ToSq      = prev2ToSq
  picker.stage          = StageTTMove
  picker.noisyMoves.len = 0
  picker.noisyCur       = 0
  picker.badCount       = 0
  picker.badCur         = 0
  picker.quietMoves.len = 0
  picker.quietCur       = 0
  picker.skipQuietsMark = false
  picker.isQSearch      = isQSearch
  picker.inCheck        = inCheck

proc skipQuiets*(picker: var MovePicker) {.inline.} =
  picker.skipQuietsMark = true
  if picker.stage == StageQuiets:
    picker.stage = StageBadNoisies

proc next*(picker: var MovePicker): Move {.inline.} =
  let b = picker.board

  while true:
    case picker.stage

    of StageTTMove:
      picker.stage = StageGenNoisies
      if isTTMoveLegal(b[], picker.ttMove):
        return picker.ttMove

    of StageGenNoisies:
      generateCaptures(b[], picker.noisyMoves)
      for i in 0 ..< picker.noisyMoves.len:
        picker.noisyScores[i] = scoreNoisy(b[], picker.noisyMoves.moves[i])
      picker.noisyCur = 0
      picker.stage    = StageGoodNoisies

    of StageGoodNoisies:
      while picker.noisyCur < picker.noisyMoves.len:
        let m = pickBest(picker.noisyMoves.moves, picker.noisyScores,
                         picker.noisyCur, picker.noisyMoves.len)
        inc picker.noisyCur
        if m == picker.ttMove: continue
        if see(b[], m, 0):
          return m
        else:
          if picker.badCount < 64:
            picker.badMoves[picker.badCount]  = m
            picker.badScores[picker.badCount] = picker.noisyScores[picker.noisyCur - 1]
            inc picker.badCount

      if picker.isQSearch:
        picker.stage = if picker.inCheck: StageBadNoisies else: StageDone
      else:
        picker.stage = StageGenQuiets

    of StageGenQuiets:
      if picker.skipQuietsMark:
        picker.stage = StageBadNoisies
      else:
        generateQuiets(b[], picker.quietMoves)
        scoreQuiets(b[], picker.quietMoves, picker.quietScores, picker.ply,
                    picker.prevPiece, picker.prevToSq,
                    picker.prev2Piece, picker.prev2ToSq)
        picker.quietCur = 0
        picker.stage    = StageQuiets

    of StageQuiets:
      if picker.skipQuietsMark:
        picker.stage = StageBadNoisies
        continue

      while picker.quietCur < picker.quietMoves.len:
        let m = pickBest(picker.quietMoves.moves, picker.quietScores,
                         picker.quietCur, picker.quietMoves.len)
        inc picker.quietCur
        if m == picker.ttMove: continue
        return m

      picker.stage = StageBadNoisies

    of StageBadNoisies:
      while picker.badCur < picker.badCount:
        let m = picker.badMoves[picker.badCur]
        inc picker.badCur
        if m == picker.ttMove: continue
        return m

      picker.stage = StageDone

    of StageDone:
      return NullMove
