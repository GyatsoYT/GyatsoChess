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

proc isKiller(m: Move, ply: int): int {.inline.} =
  if killerMoves[ply][0] == m: 2
  elif killerMoves[ply][1] == m: 1
  else: 0

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
  var bestPacked = system.uint64(0)
  var bestIdx    = cur
  for i in cur ..< count:
    let remaining = system.uint64(count - 1 - i)
    let adjusted  = system.uint32(scores[i]) xor 0x80000000'u32
    let packed    = (system.uint64(adjusted) shl 32) or remaining
    if packed >= bestPacked:
      bestPacked = packed
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
  noisy:           MoveList
  noisyScores:     array[256, int32]
  noisyCur:        int
  badMoves:        array[64, Move]
  badScores:       array[64, int32]
  badCount:        int
  badCur:          int
  quiets:          MoveList
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

proc scoreQuiet(b: Board, m: Move, ply, prevPiece, prevToSq,
                prev2Piece, prev2ToSq: int): int32 {.inline.} =
  let killerSlot = isKiller(m, ply)
  if killerSlot > 0:
    return int32(KillerBase + killerSlot * 1_000)

  let stm       = b.stm.ord
  let fromSq    = m.fromSq.int
  let toSq      = m.histToSq.int
  let fromThrt  = if b.threats.hasSq(m.fromSq): 1 else: 0
  let toThrt    = if b.threats.hasSq(m.histToSq):   1 else: 0
  let histScore = system.int(historyTable[stm][fromSq][toSq][fromThrt][toThrt])
  let curPiece  = ord(b.mailbox[m.fromSq.int])
  let cont1 =
    if prevPiece >= 0:
      getContHistScore(prevPiece, prevToSq, curPiece, toSq)
    else: 0
  let cont2 =
    if prev2Piece >= 0:
      getContHistScore2(prev2Piece, prev2ToSq, curPiece, toSq)
    else: 0
  let contScore = 2 * cont1 + cont2

  int32(histScore + contScore)

proc init*(picker: var MovePicker,
           b: ptr Board,
           ttMove: Move,
           ply, prevPiece, prevToSq,
           prev2Piece, prev2ToSq: int,
           inCheck, isQSearch: bool) {.inline.} =
  ## Initializes only the scalar state; move/score buffers are filled lazily
  ## by the generation stages, so callers declare the picker `{.noinit.}`.
  picker.board          = b
  picker.ttMove         = ttMove
  picker.ply            = ply
  picker.prevPiece      = prevPiece
  picker.prevToSq       = prevToSq
  picker.prev2Piece     = prev2Piece
  picker.prev2ToSq      = prev2ToSq
  picker.stage          = StageTTMove
  picker.noisy.len      = 0
  picker.noisyCur       = 0
  picker.badCount       = 0
  picker.badCur         = 0
  picker.quiets.len     = 0
  picker.quietCur       = 0
  picker.skipQuietsMark = false
  picker.isQSearch      = isQSearch
  picker.inCheck        = inCheck

proc skipQuiets*(picker: var MovePicker) {.inline.} =
  picker.skipQuietsMark = true
  if picker.stage == StageQuiets:
    picker.stage = StageBadNoisies

proc next*(picker: var MovePicker): Move =
  let b = picker.board

  while true:
    case picker.stage

    of StageTTMove:
      picker.stage = StageGenNoisies
      if isTTMoveLegal(b[], picker.ttMove):
        return picker.ttMove

    of StageGenNoisies:
      generateCaptures(b[], picker.noisy)
      for i in 0 ..< picker.noisy.len:
        picker.noisyScores[i] = scoreNoisy(b[], picker.noisy.moves[i])
      picker.noisyCur = 0
      picker.stage    = StageGoodNoisies

    of StageGoodNoisies:
      while picker.noisyCur < picker.noisy.len:
        let m = pickBest(picker.noisy.moves, picker.noisyScores,
                         picker.noisyCur, picker.noisy.len)
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
        generateQuiets(b[], picker.quiets)
        for i in 0 ..< picker.quiets.len:
          picker.quietScores[i] = scoreQuiet(b[], picker.quiets.moves[i],
                                             picker.ply,
                                             picker.prevPiece,
                                             picker.prevToSq,
                                             picker.prev2Piece,
                                             picker.prev2ToSq)
        picker.quietCur = 0
        picker.stage    = StageQuiets

    of StageQuiets:
      if picker.skipQuietsMark:
        picker.stage = StageBadNoisies
        continue

      while picker.quietCur < picker.quiets.len:
        let m = pickBest(picker.quiets.moves, picker.quietScores,
                         picker.quietCur, picker.quiets.len)
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
