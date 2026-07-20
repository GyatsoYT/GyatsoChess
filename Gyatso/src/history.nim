import coretypes
import board
import bitboard
import std/locks

type
  HistoryTable*        = array[2, array[64, array[64, array[2, array[2, int16]]]]]
  ContinuationHistory* = array[12, array[64, array[12, array[64, int16]]]]

type HistoryData = object
  historyTable*:         HistoryTable
  continuationHistory*:  ContinuationHistory
  continuationHistory2*: ContinuationHistory

var gHistData {.threadvar.}: ptr HistoryData

const MaxSearchThreads* = 256

var gHistRegistry:     array[MaxSearchThreads, ptr HistoryData]
var gHistRegistryLen:  int  = 0
var gHistLock:         Lock

proc initHistoryModule*() =
  initLock(gHistLock)

proc initHistoryData*() =
  gHistData = cast[ptr HistoryData](alloc0(sizeof(HistoryData)))
  withLock(gHistLock):
    assert gHistRegistryLen < MaxSearchThreads, "too many search threads"
    gHistRegistry[gHistRegistryLen] = gHistData
    inc gHistRegistryLen

proc freeHistoryData*() =
  if gHistData == nil: return
  withLock(gHistLock):
    for i in 0 ..< gHistRegistryLen:
      if gHistRegistry[i] == gHistData:
        gHistRegistry[i] = gHistRegistry[gHistRegistryLen - 1]
        dec gHistRegistryLen
        break
  dealloc(gHistData)
  gHistData = nil

proc clearHistory*() =
  if gHistData != nil:
    zeroMem(gHistData, sizeof(HistoryData))

proc clearAllHistory*() =
  withLock(gHistLock):
    for i in 0 ..< gHistRegistryLen:
      zeroMem(gHistRegistry[i], sizeof(HistoryData))

proc ageHistory*() =
  for col in 0..1:
    for f in 0..63:
      for t in 0..63:
        for a in 0..1:
          for b in 0..1:
            let v = system.int(gHistData.historyTable[col][f][t][a][b])
            gHistData.historyTable[col][f][t][a][b] = int16(v * 3 div 4)

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
  gravityUpdate(gHistData.historyTable[stm][fromSq][toSq][fromAttacked][toAttacked], change)

template historyTable*(): untyped = gHistData.historyTable

proc updateContHist*(prevPiece, prevToSq, curPiece, curToSq, change: int) {.inline.} =
  gravityUpdate(gHistData.continuationHistory[prevPiece][prevToSq][curPiece][curToSq], change)

proc getContHistScore*(prevPiece, prevToSq, curPiece, curToSq: int): int {.inline.} =
  system.int(gHistData.continuationHistory[prevPiece][prevToSq][curPiece][curToSq])

proc updateContHist2*(prevPiece, prevToSq, curPiece, curToSq, change: int) {.inline.} =
  gravityUpdate(gHistData.continuationHistory2[prevPiece][prevToSq][curPiece][curToSq], change)

proc getContHistScore2*(prevPiece, prevToSq, curPiece, curToSq: int): int {.inline.} =
  system.int(gHistData.continuationHistory2[prevPiece][prevToSq][curPiece][curToSq])
