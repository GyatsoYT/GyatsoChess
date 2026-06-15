import coretypes
import board
import bitboard

type
  HistoryTable* = array[2, array[64, array[64, array[2, array[2, int16]]]]]

var historyTable* {.threadvar.}: HistoryTable

proc clearHistory*() =
  # Reset the entire history table to 0
  for col in 0..1:
    for f in 0..63:
      for t in 0..63:
        for a in 0..1:
          for b in 0..1:
            historyTable[col][f][t][a][b] = 0

proc ageHistory*() =
  # Age history by multiplying by 3/4
  for col in 0..1:
    for f in 0..63:
      for t in 0..63:
        for a in 0..1:
          for b in 0..1:
            let v = system.int(historyTable[col][f][t][a][b])
            historyTable[col][f][t][a][b] = int16(v * 3 div 4)

proc isQuietMove*(b: Board, m: Move): bool {.inline.} =
  # A quiet move is not a capture and not a promotion
  if m.isPromotion() or m.isEnPassant(): return false
  return b.mailbox[m.toSq.int] == NoPiece

proc getBonus*(depth: int): int {.inline.} =
  min(1500, depth * depth + 2 * depth)

proc getPenalty*(depth: int): int {.inline.} =
  min(1000, depth * depth + 2 * depth)

proc updateHistory*(b: Board, m: Move, change: int) =
  let stm = b.stm.ord
  let fromSq = m.fromSq.int
  let toSq = m.toSq.int
  let fromAttacked = if b.threats.hasSq(m.fromSq): 1 else: 0
  let toAttacked = if b.threats.hasSq(m.toSq): 1 else: 0
  
  let val = system.int(historyTable[stm][fromSq][toSq][fromAttacked][toAttacked])
  let absChange = abs(change)
  
  # Gravity update formula: val = val + change - (val * abs(change) / 16384)
  let newVal = val + change - (val * absChange div 16384)
  historyTable[stm][fromSq][toSq][fromAttacked][toAttacked] = int16(newVal)
