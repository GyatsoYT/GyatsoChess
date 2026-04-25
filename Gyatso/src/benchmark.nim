import coretypes, board, search, move, tt, magicbitboards, nnuetypes, nnue
import std/[times, monotimes, atomics, strutils, strformat]

const
  DefaultBenchDepth* = 15
  BenchmarkPositions* = [
    # Starting position
    "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1",
    # Kiwipete - complex middlegame
    "r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1",
    # CPW position 3
    "r3k2r/Pppp1ppp/1b3nbN/nP6/BBP1P3/q4N2/Pp1P2PP/R2Q1RK1 w kq - 0 1",
    # CPW position 4
    "rnbq1k1r/pp1Pbppp/2p5/8/2B5/8/PPP1NnPP/RNBQK2R w KQ - 1 8",
    # Tactics
    "2rr3k/pp3pp1/1nnqbN1p/3pN3/2pP4/2P3Q1/PPB4P/R4RK1 w - - 0 1",
    # Closed QGD
    "r1bq1rk1/pp2bppp/2n1pn2/3p4/3P4/2N1PN2/PP2BPPP/R1BQ1RK1 w - - 0 1",
    # Exchange variation
    "r1bqr1k1/pp3ppp/2pb1n2/3p4/3P4/2NBPN2/PP3PPP/R1BQR1K1 w - - 0 1",
    # Ruy Lopez
    "r2qk2r/ppp1bppp/2np1n2/1B2p3/4P3/3P1N2/PPP2PPP/RNBQR1K1 b kq - 0 1",
    # French Defense
    "3r1rk1/p4ppp/qp2p3/2ppPb2/5B2/1P1P2P1/P1P2P1P/R2QR1K1 w - - 0 1",
    # Italian Game
    "r1bq1rk1/1pp2ppp/p1np1n2/4p3/2B1P3/2NP1N2/PPP2PPP/R1BQR1K1 w - - 0 1",
    # Sicilian structures
    "r3r1k1/1ppq1ppp/p2p1n2/4pb2/4P1b1/1NNP2P1/PPP2PBP/R1BQR1K1 w - - 0 1",
    # Two Knights
    "r2q1rk1/ppp2ppp/2np1n2/2b1p3/2B1P3/2NP1N2/PPP2PPP/R1BQ1RK1 w - - 0 1",
    # Open file play
    "r4rk1/pp3ppp/3p1n2/q1pPp3/4P3/2P2N2/PP2QPPP/R4RK1 w - - 0 1",
    # Complex middlegame
    "r1b2rk1/pp2qppp/2np1n2/2p1p3/2B1P3/2NP1N2/PPP2PPP/R1BQ1RK1 w - - 0 1",
    # Italian with d3
    "r1bqr1k1/ppp2ppp/2np1n2/4p3/2B1P3/2NP1N2/PPP2PPP/R1BQR1K1 w - - 0 1",
  ]

type
  BenchResult* = object
    totalNodes*: uint64
    totalTimeMs*: int64
    nps*: uint64
    depth*: int

proc clearTT*() =
  ## Zero out the entire transposition table
  if transpositionTable != nil and ttSize > 0:
    zeroMem(transpositionTable, sizeof(TTEntry) * ttSize)

proc runBench*(depth: int = DefaultBenchDepth): BenchResult =
  ## Runs a fixed-depth search on all benchmark positions (single-threaded).
  ## Outputs per-position results and a final summary line with total node count.
  ## This is designed so OpenBench can parse the last line: "<totalNodes> nodes <nps> nps"
  result.depth = depth

  initThreadMagics()

  var totalNodes: uint64 = 0
  let totalStart = getMonoTime()

  echo ""
  echo fmt"Benchmarking {BenchmarkPositions.len} positions at depth {depth}..."
  echo ""

  for i, fen in BenchmarkPositions:
    # Fresh board for each position
    var b = initializeBoard(fen)

    # Clear TT between positions for reproducibility
    clearTT()
    newTTGeneration()

    # Set up a fixed-depth search with no time limit
    var stopFlag: Atomic[bool]
    stopFlag.store(false, moRelaxed)

    var info: SearchInfo
    info.startTime = getMonoTime()
    info.allocatedTime = DurationZero
    info.depthLimit = depth
    info.nodeLimit = 0
    info.stopFlag = addr stopFlag
    info.ponderFlag = nil
    info.nodeCounts = nil
    info.threadID = 0
    info.numThreads = 1
    info.nodes = 0
    info.selDepth = 0

    let posStart = getMonoTime()

    # Run the search (threadID = -1 suppresses UCI info output, matching searchNodes pattern)
    let (bestMove, _) = iterativeDeepening(b, info, threadID = -1)

    let posEnd = getMonoTime()
    let posTimeMs = (posEnd - posStart).inMilliseconds
    let nodes = info.nodes

    totalNodes += nodes

    echo fmt"pos {i + 1:>2}: bestmove {bestMove.toAlgebraic():<6} | nodes: {nodes:>12} | time: {posTimeMs}ms"

  let totalEnd = getMonoTime()
  let totalTimeMs = (totalEnd - totalStart).inMilliseconds
  let nps = if totalTimeMs > 0: (totalNodes * 1000) div totalTimeMs.uint64 else: 0'u64

  result.totalNodes = totalNodes
  result.totalTimeMs = totalTimeMs
  result.nps = nps

  echo ""
  echo "=== BENCHMARK RESULTS ==="
  echo fmt"Depth:       {depth}"
  echo fmt"Positions:   {BenchmarkPositions.len}"
  echo fmt"Total nodes: {totalNodes}"
  echo fmt"Total time:  {totalTimeMs}ms"
  echo fmt"NPS:         {nps}"
  echo ""
  # OpenBench-compatible summary line
  echo fmt"{totalNodes} nodes {nps} nps"
