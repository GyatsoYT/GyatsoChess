import coretypes
import board
import movegen

import std/monotimes
import std/times
import std/strutils

proc perft*(b: var Board, depth: int): uint64 =
  ## Counts all leaf nodes at the given depth.
  if depth == 0: return 1
  var ml: MoveList
  generateMoves(b, ml)
  if depth == 1: return cast[uint64](ml.len)
  for i in 0 ..< ml.len:
    let m = ml.moves[i]
    b.makeMove(m)
    result += perft(b, depth - 1)
    b.unmakeMove(m)

proc moveToAlgebraic*(m: Move): string =
  result = toAlgebraic(m.fromSq) & toAlgebraic(m.toSq)
  if m.isPromotion():
    result &= (case m.promoType:
      of PromoQueen:  "q"
      of PromoRook:   "r"
      of PromoBishop: "b"
      of PromoKnight: "n")

proc perftSplit*(b: var Board, depth: int) =
  ## Prints per-root-move node counts
  var ml: MoveList
  generateMoves(b, ml)
  var total: uint64 = 0
  for i in 0 ..< ml.len:
    let m = ml.moves[i]
    b.makeMove(m)
    let nodes = perft(b, depth - 1)
    b.unmakeMove(m)
    echo moveToAlgebraic(m) & ": " & $nodes
    total += nodes
  echo ""
  echo "Nodes searched: " & $total

proc perftBenchmark*(b: var Board, depth: int) =
  ## Prints benchmark results (nodes, time, NPS).
  echo "Performance test to depth " & $depth
  let start = getMonoTime()
  let nodes = perft(b, depth)
  let elapsed = getMonoTime() - start
  let ms = float(elapsed.inMicroseconds) / 1000.0
  let nps = if ms > 0.0: int(float(nodes) / (ms / 1000.0)) else: 0
  echo "Nodes: " & $nodes
  echo "Time: " & ms.formatFloat(ffDecimal, 1) & " ms"
  echo "NPS: " & $nps
  stdout.flushFile()

proc perftNonBulk*(b: var Board, depth: int): uint64 =
  if depth == 0: return 1
  var ml: MoveList
  generateMoves(b, ml)
  for i in 0 ..< ml.len:
    let m = ml.moves[i]
    b.makeMove(m)
    result += perftNonBulk(b, depth - 1)
    b.unmakeMove(m)

proc qperftBenchmark*(b: var Board, depth: int) =
  ## Benchmark for non-bulk perft.
  echo "Performance test to depth " & $depth
  let start = getMonoTime()
  let nodes = perftNonBulk(b, depth)
  let elapsed = getMonoTime() - start
  let ms = float(elapsed.inMicroseconds) / 1000.0
  let nps = if ms > 0.0: int(float(nodes) / (ms / 1000.0)) else: 0
  echo "Nodes: " & $nodes
  echo "Time: " & ms.formatFloat(ffDecimal, 1) & " ms"
  echo "NPS: " & $nps
  stdout.flushFile()
