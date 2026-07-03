import std/[atomics, monotimes, times, strformat]
import coretypes
import board
import attacks
import perft
import search
import tt
import history

const
  DefaultBenchDepth* = 15

  BenchmarkPositions* = [
    "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1",
    "r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1",
    "r3k2r/Pppp1ppp/1b3nbN/nP6/BBP1P3/q4N2/Pp1P2PP/R2Q1RK1 w kq - 0 1",
    "rnbq1k1r/pp1Pbppp/2p5/8/2B5/8/PPP1NnPP/RNBQK2R w KQ - 1 8",
    "2rr3k/pp3pp1/1nnqbN1p/3pN3/2pP4/2P3Q1/PPB4P/R4RK1 w - - 0 1",
    "r1bq1rk1/pp2bppp/2n1pn2/3p4/3P4/2N1PN2/PP2BPPP/R1BQ1RK1 w - - 0 1",
    "r1bqr1k1/pp3ppp/2pb1n2/3p4/3P4/2NBPN2/PP3PPP/R1BQR1K1 w - - 0 1",
    "r2qk2r/ppp1bppp/2np1n2/1B2p3/4P3/3P1N2/PPP2PPP/RNBQR1K1 b kq - 0 1",
    "3r1rk1/p4ppp/qp2p3/2ppPb2/5B2/1P1P2P1/P1P2P1P/R2QR1K1 w - - 0 1",
    "r1bq1rk1/1pp2ppp/p1np1n2/4p3/2B1P3/2NP1N2/PPP2PPP/R1BQR1K1 w - - 0 1",
    "r3r1k1/1ppq1ppp/p2p1n2/4pb2/4P1b1/1NNP2P1/PPP2PBP/R1BQR1K1 w - - 0 1",
    "r2q1rk1/ppp2ppp/2np1n2/2b1p3/2B1P3/2NP1N2/PPP2PPP/R1BQ1RK1 w - - 0 1",
    "r4rk1/pp3ppp/3p1n2/q1pPp3/4P3/2P2N2/PP2QPPP/R4RK1 w - - 0 1",
    "r1b2rk1/pp2qppp/2np1n2/2p1p3/2B1P3/2NP1N2/PPP2PPP/R1BQ1RK1 w - - 0 1",
    "r1bqr1k1/ppp2ppp/2np1n2/4p3/2B1P3/2NP1N2/PPP2PPP/R1BQR1K1 w - - 0 1",
  ]

type BenchWorkerData = object
  fen:      string
  depth:    int
  bestMove: Move
  nodes:    uint64

proc benchWorker(data: ptr BenchWorkerData) {.thread.} =
  initThreadAttacks()

  var b = parseFen(data.fen)

  var stopFlag: Atomic[bool]
  stopFlag.store(false, moRelaxed)

  var info: SearchInfo
  info.startTime  = getMonoTime()
  info.allocMs    = high(int64)     # no time limit
  info.depthLimit = data.depth
  info.nodeLimit  = 0
  info.nodes      = 0
  info.selDepth   = 0
  info.stopFlag   = addr stopFlag
  info.silent     = true            # suppress per-depth info lines

  let (bestMove, _) = iterativeDeepening(b, info)
  data.bestMove = bestMove
  data.nodes    = info.nodes

proc clearTT() =
  ## Zero out the transposition table between positions for reproducibility.
  if ttTable != nil and ttMask > 0:
    zeroMem(ttTable, sizeof(TTCluster) * int(ttMask + 1))

proc runBench*(depth: int = DefaultBenchDepth) =
  var totalNodes: uint64 = 0
  let totalStart = getMonoTime()

  echo ""
  echo &"Benchmarking {BenchmarkPositions.len} positions at depth {depth}..."
  echo ""

  for i, fen in BenchmarkPositions:
    clearTT()
    clearHistory()

    var data: BenchWorkerData
    data.fen   = fen
    data.depth = depth

    let posStart = getMonoTime()

    var t: Thread[ptr BenchWorkerData]
    createThread(t, benchWorker, addr data)
    joinThread(t)

    let posTimeMs = (getMonoTime() - posStart).inMilliseconds
    let nodes     = data.nodes
    totalNodes   += nodes

    let mv = if data.bestMove == NullMove: "0000"
             else: moveToAlgebraic(data.bestMove)
    echo &"pos {i + 1:>2}: bestmove {mv:<6} | nodes: {nodes:>12} | time: {posTimeMs}ms"

  let totalTimeMs = (getMonoTime() - totalStart).inMilliseconds
  let nps = if totalTimeMs > 0: (totalNodes * 1000) div uint64(totalTimeMs)
            else: totalNodes

  echo ""
  echo "=== BENCHMARK RESULTS ==="
  echo &"Depth:       {depth}"
  echo &"Positions:   {BenchmarkPositions.len}"
  echo &"Total nodes: {totalNodes}"
  echo &"Total time:  {totalTimeMs}ms"
  echo &"NPS:         {nps}"
  echo ""
  # OpenBench-compatible summary line
  echo &"{totalNodes} nodes {nps} nps"
  stdout.flushFile()
