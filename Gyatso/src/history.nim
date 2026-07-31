import coretypes
import board
import bitboard
import std/locks

type
  HistoryTable*        = array[2, array[64, array[64, array[2, array[2, int16]]]]]
  ContinuationHistory* = array[12, array[64, array[12, array[64, int16]]]]

type HistoryData* = object
  historyTable*:         HistoryTable
  continuationHistory*:  ContinuationHistory
  continuationHistory2*: ContinuationHistory

var gHistData* {.threadvar.}: ptr HistoryData

var gSharedHistData*: ptr HistoryData = nil

var gHistRegistry:    array[MaxSearchThreads, ptr HistoryData]
var gHistRegistryLen: int = 0
var gHistLock:        Lock

proc initHistoryModule*() =
  initLock(gHistLock)
  gSharedHistData = cast[ptr HistoryData](allocShared0(sizeof(HistoryData)))

proc initHistoryData*() =
  gHistData = gSharedHistData
  withLock(gHistLock):
    var alreadyRegistered = false
    for i in 0 ..< gHistRegistryLen:
      if gHistRegistry[i] == gHistData:
        alreadyRegistered = true
        break
    if not alreadyRegistered:
      assert gHistRegistryLen < MaxSearchThreads, "too many search threads"
      gHistRegistry[gHistRegistryLen] = gHistData
      inc gHistRegistryLen

proc freeHistoryData*() =
  gHistData = nil

proc freeSharedHistory*() =
  if gSharedHistData != nil:
    deallocShared(gSharedHistData)
    gSharedHistData = nil
    withLock(gHistLock):
      gHistRegistryLen = 0

proc clearHistory*() =
  if gHistData != nil:
    zeroMem(gHistData, sizeof(HistoryData))

proc clearAllHistory*() =
  if gSharedHistData != nil:
    zeroMem(gSharedHistData, sizeof(HistoryData))

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

template updateHistoryStat*(stat: var int16, bonus: int) =
  var s = system.int(stat)
  let gravityDiv = 512 + (abs(bonus) shr 4)
  s += (32 * bonus) - (s * abs(bonus)) div gravityDiv
  stat = int16(clamp(s, -16384, 16384))

proc updateHistory*(b: Board, m: Move, change: int) =
  let stm          = b.stm.ord
  let fromSq       = m.fromSq.int
  let toSq         = m.toSq.int
  let fromAttacked = if b.threats.hasSq(m.fromSq): 1 else: 0
  let toAttacked   = if b.threats.hasSq(m.toSq):   1 else: 0
  updateHistoryStat(gHistData.historyTable[stm][fromSq][toSq][fromAttacked][toAttacked], change)

template historyTable*(): untyped = gHistData.historyTable

proc updateContHist*(prevPiece, prevToSq, curPiece, curToSq, change: int) {.inline.} =
  updateHistoryStat(gHistData.continuationHistory[prevPiece][prevToSq][curPiece][curToSq], change)

proc getContHistScore*(prevPiece, prevToSq, curPiece, curToSq: int): int {.inline.} =
  system.int(gHistData.continuationHistory[prevPiece][prevToSq][curPiece][curToSq])

proc updateContHist2*(prevPiece, prevToSq, curPiece, curToSq, change: int) {.inline.} =
  updateHistoryStat(gHistData.continuationHistory2[prevPiece][prevToSq][curPiece][curToSq], change)

proc getContHistScore2*(prevPiece, prevToSq, curPiece, curToSq: int): int {.inline.} =
  system.int(gHistData.continuationHistory2[prevPiece][prevToSq][curPiece][curToSq])
