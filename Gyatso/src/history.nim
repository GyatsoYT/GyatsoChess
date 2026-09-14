import coretypes
import board
import bitboard
import zobrist
import std/locks

const
  CorrHistSize* = 16384
  CorrHistMask* = system.uint64(CorrHistSize - 1)
  CorrHistGrain* = 512
  CorrHistWeightScale* = 256
  CorrHistMax* = CorrHistGrain * 32

type
  HistoryTable* = array[2, array[64, array[64, array[2, array[2, int16]]]]]
  ContinuationHistory* = array[12, array[64, array[12, array[64, int16]]]]
  PawnCorrHist* = array[2, array[CorrHistSize, int16]]
  NonPawnCorrHist* = array[2, array[2, array[CorrHistSize, int16]]]

type HistoryData* = object
  historyTable*: HistoryTable
  continuationHistory*: ContinuationHistory
  continuationHistory2*: ContinuationHistory
  pawnCorrHist*: PawnCorrHist
  nonPawnCorrHist*: NonPawnCorrHist

var gHistData* {.threadvar.}: ptr HistoryData

var gSharedHistData*: ptr HistoryData = nil

var gHistRegistry: array[MaxSearchThreads, ptr HistoryData]
var gHistRegistryLen: int = 0
var gHistLock: Lock

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
  let stm = b.stm.ord
  let fromSq = m.fromSq.int
  let toSq = m.toSq.int
  let fromAttacked = if b.threats.hasSq(m.fromSq): 1 else: 0
  let toAttacked = if b.threats.hasSq(m.toSq): 1 else: 0
  updateHistoryStat(gHistData.historyTable[stm][fromSq][toSq][fromAttacked][
      toAttacked], change)

template historyTable*(): untyped = gHistData.historyTable

proc updateContHist*(prevPiece, prevToSq, curPiece, curToSq,
    change: int) {.inline.} =
  updateHistoryStat(gHistData.continuationHistory[prevPiece][prevToSq][
      curPiece][curToSq], change)

proc getContHistScore*(prevPiece, prevToSq, curPiece,
    curToSq: int): int {.inline.} =
  system.int(gHistData.continuationHistory[prevPiece][prevToSq][curPiece][curToSq])

proc updateContHist2*(prevPiece, prevToSq, curPiece, curToSq,
    change: int) {.inline.} =
  updateHistoryStat(gHistData.continuationHistory2[prevPiece][prevToSq][
      curPiece][curToSq], change)

proc getContHistScore2*(prevPiece, prevToSq, curPiece,
    curToSq: int): int {.inline.} =
  system.int(gHistData.continuationHistory2[prevPiece][prevToSq][curPiece][curToSq])

proc getPawnCorrection*(b: Board): int {.inline.} =
  if gHistData == nil: return 0
  let side = b.stm.ord
  let pawnIdx = system.int(b.pawnHash.uint64 and CorrHistMask)
  system.int(gHistData.pawnCorrHist[side][pawnIdx]) div CorrHistGrain

proc getNonPawnCorrection*(b: Board): int {.inline.} =
  if gHistData == nil: return 0
  let side = b.stm.ord
  let wIdx = system.int(b.nonPawnHash[0].uint64 and CorrHistMask)
  let bIdx = system.int(b.nonPawnHash[1].uint64 and CorrHistMask)
  let wCorr = system.int(gHistData.nonPawnCorrHist[0][side][
      wIdx]) div CorrHistGrain
  let bCorr = system.int(gHistData.nonPawnCorrHist[1][side][
      bIdx]) div CorrHistGrain
  wCorr + bCorr

proc getCorrection*(b: Board): int {.inline.} =
  getPawnCorrection(b) + getNonPawnCorrection(b)

proc updateCorrEntry(entry: var int16, newWeight, scaledDiff: int) {.inline.} =
  let old = system.int(entry)
  var update = old * (CorrHistWeightScale - newWeight) + scaledDiff * newWeight
  update = update div CorrHistWeightScale
  entry = int16(clamp(update, -CorrHistMax, CorrHistMax))

proc updatePawnCorrection*(b: Board, depth, diff: int) {.inline.} =
  if gHistData == nil: return
  let side = b.stm.ord
  let newWeight = min(16, 1 + depth)
  let scaledDiff = clamp(diff, -1000, 1000) * CorrHistGrain
  let pawnIdx = system.int(b.pawnHash.uint64 and CorrHistMask)
  updateCorrEntry(gHistData.pawnCorrHist[side][pawnIdx], newWeight, scaledDiff)

proc updateNonPawnCorrection*(b: Board, depth, diff: int) {.inline.} =
  if gHistData == nil: return
  let side = b.stm.ord
  let newWeight = min(16, 1 + depth)
  let scaledDiff = clamp(diff, -1000, 1000) * CorrHistGrain
  let wIdx = system.int(b.nonPawnHash[0].uint64 and CorrHistMask)
  let bIdx = system.int(b.nonPawnHash[1].uint64 and CorrHistMask)
  updateCorrEntry(gHistData.nonPawnCorrHist[0][side][wIdx], newWeight, scaledDiff)
  updateCorrEntry(gHistData.nonPawnCorrHist[1][side][bIdx], newWeight, scaledDiff)

proc updateCorrection*(b: Board, depth, diff: int) {.inline.} =
  updatePawnCorrection(b, depth, diff)
  updateNonPawnCorrection(b, depth, diff)
