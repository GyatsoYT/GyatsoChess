import coretypes
import board
import bitboard

type
  HistoryTable*        = array[2, array[64, array[64, array[2, array[2, int16]]]]]
  ContinuationHistory* = array[12, array[64, array[12, array[64, int16]]]]

var historyTable*         {.threadvar.}: HistoryTable
var continuationHistory*  {.threadvar.}: ContinuationHistory
var continuationHistory2* {.threadvar.}: ContinuationHistory

proc clearHistory*() =
  for col in 0..1:
    for f in 0..63:
      for t in 0..63:
        for a in 0..1:
          for b in 0..1:
            historyTable[col][f][t][a][b] = 0
  for pp in 0..11:
    for ps in 0..63:
      for cp in 0..11:
        for cs in 0..63:
          continuationHistory[pp][ps][cp][cs]  = 0
          continuationHistory2[pp][ps][cp][cs] = 0

proc ageHistory*() =
  for col in 0..1:
    for f in 0..63:
      for t in 0..63:
        for a in 0..1:
          for b in 0..1:
            let v = system.int(historyTable[col][f][t][a][b])
            historyTable[col][f][t][a][b] = int16(v * 3 div 4)

proc isQuietMove*(b: Board, m: Move): bool {.inline.} =
  if m.isPromotion() or m.isEnPassant(): return false
  return b.mailbox[m.toSq.int] == NoPiece

proc getBonus*(depth: int): int {.inline.} =
  min(1500, depth * depth + 2 * depth)

proc gravityUpdate*(slot: var int16, change: int) {.inline.} =
  let cur   = system.int(slot)
  let delta = abs(change)
  slot = int16(cur + change - (cur * delta div 16384))

proc updateHistory*(b: Board, m: Move, change: int) =
  let stm          = b.stm.ord
  let fromSq       = m.fromSq.int
  let toSq         = m.toSq.int
  let fromAttacked = if b.threats.hasSq(m.fromSq): 1 else: 0
  let toAttacked   = if b.threats.hasSq(m.toSq):   1 else: 0
  gravityUpdate(historyTable[stm][fromSq][toSq][fromAttacked][toAttacked], change)

proc updateContHist*(prevPiece, prevToSq, curPiece, curToSq, change: int) {.inline.} =
  gravityUpdate(continuationHistory[prevPiece][prevToSq][curPiece][curToSq], change)

proc getContHistScore*(prevPiece, prevToSq, curPiece, curToSq: int): int {.inline.} =
  system.int(continuationHistory[prevPiece][prevToSq][curPiece][curToSq])

proc updateContHist2*(prevPiece, prevToSq, curPiece, curToSq, change: int) {.inline.} =
  gravityUpdate(continuationHistory2[prevPiece][prevToSq][curPiece][curToSq], change)

proc getContHistScore2*(prevPiece, prevToSq, curPiece, curToSq: int): int {.inline.} =
  system.int(continuationHistory2[prevPiece][prevToSq][curPiece][curToSq])
