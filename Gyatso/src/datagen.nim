import coretypes, bitboard, board, movegen, search, attacks, evaluate,
       tt, searchparams, history, nnue, viriformat
import std/[os, strutils, random, monotimes, times, atomics, cpuinfo,
            parseopt, json]

type
  OpeningBook = object
    fens:   seq[string]
    counts: seq[int]

proc loadOpeningBook(path: string): OpeningBook =
  for line in lines(path):
    let s = line.strip()
    if s.len == 0 or s[0] == '#': continue
    let parts = s.split(' ')
    if parts.len >= 4:
      result.fens.add(parts[0] & " " & parts[1] & " " & parts[2] & " " & parts[3])
      result.counts.add(0)

proc selectOpening(book: var OpeningBook; rng: var Rand): (int, string) {.inline.} =
  var total = 0.0'f64
  for c in book.counts: total += 1.0 / (c.float64 + 1.0)
  var r = rng.rand(total)
  for i in 0 ..< book.fens.len:
    r -= 1.0 / (book.counts[i].float64 + 1.0)
    if r <= 0.0: return (i, book.fens[i])
  let idx = book.fens.len - 1
  return (idx, book.fens[idx])

proc searchPosition(b: var Board;
                    softNodes, hardNodes: uint64;
                    stopFlag: var Atomic[bool]): (Move, int) =
  stopFlag.store(false, moRelaxed)

  var info: SearchInfo
  info.id            = 0
  info.startTime     = getMonoTime()
  info.softLimitMs   = int64(high(int32))
  info.hardLimitMs   = int64(high(int32))
  info.depthLimit    = 0
  info.nodeLimit     = hardNodes
  info.softNodeLimit = softNodes
  info.nodes         = 0
  info.selDepth      = 0
  info.silent        = true
  info.stopFlag      = addr stopFlag

  let (move, score) = iterativeDeepening(b, info)
  return (move, score)

proc dgPlayGame(book: var OpeningBook;
                rng: var Rand;
                softNodes, hardNodes: uint64;
                vb: var ViriBuffer): (int, bool) =

  var b: Board
  var numRandom: int

  if book.fens.len > 0:
    let (bookIdx, fen) = selectOpening(book, rng)
    book.counts[bookIdx] += 1
    b = parseFen(fen)
    numRandom = rng.rand(9)
  else:
    b = parseFen(StartPos)
    numRandom = 8 + rng.rand(2)

  for i in 0 ..< numRandom:
    var ml: MoveList
    generateMoves(b, ml)
    if ml.len == 0: return (0, false)
    let mv = ml.moves[rng.rand(ml.len - 1)]
    b.makeMove(mv)

  vb.reset()
  vb.writeBoard(b)

  var numEntries  = 0
  var moveCount   = 0
  var winCount    = 0
  var winSide     = White
  var drawStreak  = 0
  var gameOutcome = 0.5'f64
  var localStop: Atomic[bool]
  localStop.store(false, moRelaxed)

  for ply in 0 ..< 512:
    inc moveCount

    if b.isInsufficientMaterial() or b.halfmove >= 100 or b.isRepetition():
      gameOutcome = 0.5
      break

    if moveCount > 300:
      gameOutcome = 0.5
      break

    let (bestMove, scoreStm) = searchPosition(b, softNodes, hardNodes, localStop)

    if bestMove == NullMove:
      if not b.checkers.isEmpty():
        gameOutcome = if b.stm == White: 0.0 else: 1.0
      else:
        gameOutcome = 0.5
      break

    let whiteScore = if b.stm == White: scoreStm else: -scoreStm
    let absScore   = abs(scoreStm)

    if ply == 0 and absScore > 400:
      return (0, false)

    vb.writeMoveEval(bestMove, whiteScore)
    inc numEntries

    if absScore >= 2500:
      let winningSide = if scoreStm > 0: b.stm else: b.stm.opposite()
      if winCount > 0 and winSide == winningSide:
        inc winCount
      else:
        winCount = 1
        winSide  = winningSide
      drawStreak = 0
    elif moveCount > 80 and absScore <= 15 and b.halfmove >= 30:
      inc drawStreak
      winCount = 0
    else:
      winCount   = 0
      drawStreak = 0

    if winCount >= 4:
      gameOutcome = if winSide == White: 1.0 else: 0.0
      break
    if drawStreak >= 10:
      gameOutcome = 0.5
      break

    b.makeMove(bestMove)

  if numEntries == 0: return (0, false)

  let wdl: uint8 = if gameOutcome == 1.0: 2'u8 elif gameOutcome == 0.0: 0'u8 else: 1'u8
  vb.patchWdl(wdl)

  return (numEntries, true)

type
  SharedState = object
    totalPositions:  ptr Atomic[int64]
    totalGames:      ptr Atomic[int64]
    targetPositions: int64
    stopFlag:        ptr Atomic[bool]

  WorkerArgs = object
    threadId:     int
    outputDir:    string
    bookPath:     string
    softNodes:    uint64
    hardNodes:    uint64
    seed:         uint64
    shared:       SharedState

var gTotalPositions {.global.}: Atomic[int64]
var gTotalGames     {.global.}: Atomic[int64]
var gStopFlag       {.global.}: Atomic[bool]

proc workerThread(args: WorkerArgs) {.thread.} =
  initThreadAttacks()
  initHistoryData()

  var book: OpeningBook
  if args.bookPath.len > 0:
    book = loadOpeningBook(args.bookPath)

  var rng = initRand(int64(args.seed) + int64(args.threadId) * 1_000_003'i64)

  let path = args.outputDir / ("data_" & $getMonoTime().ticks & "_t" & $args.threadId & ".vf")
  var f = open(path, fmWrite)
  defer: f.close()

  var vb: ViriBuffer

  while not args.shared.stopFlag[].load(moRelaxed):
    if args.shared.totalPositions[].load(moRelaxed) >= args.shared.targetPositions:
      break

    newTTGeneration()

    let (posCount, played) = dgPlayGame(book, rng, args.softNodes, args.hardNodes, vb)
    if not played or posCount == 0:
      continue

    discard args.shared.totalPositions[].fetchAdd(int64(posCount), moRelaxed)
    discard args.shared.totalGames[].fetchAdd(1'i64, moRelaxed)

    if vb.buf.len > 0:
      let n = f.writeBuffer(addr vb.buf[0], vb.buf.len)
      doAssert n == vb.buf.len, "short write — disk full or IO error"
      f.flushFile()

    if args.shared.totalPositions[].load(moRelaxed) >= args.shared.targetPositions:
      args.shared.stopFlag[].store(true, moRelaxed)

const StateFile = "datagen_state.json"

proc saveState(dir: string; totalPos, totalGames: int64; seed: uint64) =
  let j = %*{"total_positions_written": totalPos,
              "total_games_played":     totalGames,
              "rng_seed":               seed.int64}
  writeFile(dir / StateFile, $j)

proc loadState(dir: string): JsonNode =
  let path = dir / StateFile
  if fileExists(path): return parseJson(readFile(path))
  return nil

proc fmtNum(n: int64): string {.inline.} =
  if   n >= 1_000_000_000: $(n div 1_000_000_000) & "." &
                            $((n mod 1_000_000_000) div 100_000_000) & "B"
  elif n >= 1_000_000:     $(n div 1_000_000) & "." &
                            $((n mod 1_000_000) div 100_000) & "M"
  elif n >= 1_000:         $(n div 1_000) & "." &
                            $((n mod 1_000) div 100) & "K"
  else:                    $n

when isMainModule:
  var bookPath        = ""
  var outputDir       = "./data"
  var targetPositions = 100_000_000'i64
  var numWorkers      = max(1, countProcessors() - 1)
  var softNodes       = 5_000'u64
  var hardNodes       = 8_000_000'u64
  var ttSizeMb        = 4
  var seed: uint64    = 42

  proc nextVal(p: var OptParser): string =
    if p.val.len > 0: p.val
    else:
      p.next()
      p.key

  var p = initOptParser(commandLineParams())
  while true:
    p.next()
    case p.kind
    of cmdEnd: break
    of cmdShortOption, cmdLongOption:
      case p.key
      of "book":     bookPath        = p.nextVal()
      of "output":   outputDir       = p.nextVal()
      of "target":   targetPositions = parseBiggestInt(p.nextVal()).int64
      of "workers":  numWorkers      = parseInt(p.nextVal())
      of "sn":       softNodes       = parseBiggestUInt(p.nextVal())
      of "hn":       hardNodes       = parseBiggestUInt(p.nextVal())
      of "tt":       ttSizeMb        = parseInt(p.nextVal())
      of "seed":     seed            = parseBiggestUInt(p.nextVal())
      else: discard
    of cmdArgument: discard

  if hardNodes > 0 and softNodes > hardNodes:
    softNodes = hardNodes

  initAttacks()
  initThreadAttacks()
  initTT(ttSizeMb)
  initTables()
  initNNUE()
  initHistoryModule()
  createDir(outputDir)

  echo "┌─────────────────────────────────────────┐"
  echo "│      Gyatso Datagen v3.0 (viriformat)   │"
  echo "└─────────────────────────────────────────┘"
  echo "  Book:        ", if bookPath.len > 0: bookPath else: "<none — bookless mode>"
  echo "  Output:      ", outputDir
  echo "  Target:      ", fmtNum(targetPositions)
  echo "  Workers:     ", numWorkers
  echo "  Soft nodes:  ", softNodes, "  (exit after depth)"
  echo "  Hard nodes:  ", hardNodes, "  (mid-search abort)"
  echo "  TT size:     ", ttSizeMb, " MB"
  echo "  Seed:        ", seed
  echo "  NNUE:        embedded (", NNUE_EMBEDDED.len, " bytes)"
  when defined(avx512): echo "  SIMD:        AVX-512"
  elif defined(avx2):   echo "  SIMD:        AVX-2"
  elif defined(simd):   echo "  SIMD:        SSE4"
  else:                 echo "  SIMD:        scalar"
  when defined(bmi2):   echo "  BMI2:        yes (PEXT/PDEP)"
  else:                 echo "  BMI2:        no"
  echo ""

  let stateJson = loadState(outputDir)
  if stateJson != nil:
    stdout.write "Found previous state. Resume? (y/n): "
    stdout.flushFile()
    let resp = stdin.readLine().strip().toLowerAscii()
    if resp == "y":
      let prevPos   = stateJson["total_positions_written"].getBiggestInt().int64
      let prevGames = stateJson["total_games_played"].getBiggestInt().int64
      gTotalPositions.store(prevPos,   moRelaxed)
      gTotalGames.store(prevGames,     moRelaxed)
      echo "Resuming: ", fmtNum(prevPos), " positions, ", fmtNum(prevGames), " games"

  gStopFlag.store(false, moRelaxed)

  var shared: SharedState
  shared.totalPositions  = addr gTotalPositions
  shared.totalGames      = addr gTotalGames
  shared.targetPositions = targetPositions
  shared.stopFlag        = addr gStopFlag

  var threads = newSeq[Thread[WorkerArgs]](numWorkers)
  let startTime = getMonoTime()

  for i in 0 ..< numWorkers:
    var args: WorkerArgs
    args.threadId     = i
    args.outputDir    = outputDir
    args.bookPath     = bookPath
    args.softNodes    = softNodes
    args.hardNodes    = hardNodes
    args.seed         = seed + cast[uint64](i) * 999_983'u64
    args.shared       = shared
    createThread(threads[i], workerThread, args)

  var lastReportTime = getMonoTime()
  var lastReportPos  = gTotalPositions.load(moRelaxed)
  var lastSaveGames  = 0'i64

  while not gStopFlag.load(moRelaxed):
    sleep(5000)

    let now         = getMonoTime()
    let totalPos    = gTotalPositions.load(moRelaxed)
    let totalGms    = gTotalGames.load(moRelaxed)
    let intervalMs  = (now - lastReportTime).inMilliseconds
    let intervalPos = totalPos - lastReportPos
    let posPerSec   = if intervalMs > 0:
                        system.int(float64(intervalPos) * 1000.0 / float64(intervalMs))
                      else: 0
    let remaining   = targetPositions - totalPos
    let eta         = if posPerSec > 0: remaining div int64(posPerSec) else: 0'i64

    stdout.write "\rGames: "   & fmtNum(totalGms) &
                 "  Pos: "     & fmtNum(totalPos) &
                 "  pos/s: "   & $posPerSec &
                 "  ETA: "     & $(eta div 60) & "m" & $(eta mod 60) & "s    "
    stdout.flushFile()

    lastReportTime = now
    lastReportPos  = totalPos

    if totalGms - lastSaveGames >= 5000:
      saveState(outputDir, totalPos, totalGms, seed)
      lastSaveGames = totalGms

  for i in 0 ..< numWorkers:
    joinThread(threads[i])

  saveState(outputDir, gTotalPositions.load(moRelaxed),
            gTotalGames.load(moRelaxed), seed)

  let elapsed  = (getMonoTime() - startTime).inSeconds
  let finalPos = gTotalPositions.load(moRelaxed)
  let finalGms = gTotalGames.load(moRelaxed)
  echo ""
  echo "Done!"
  echo "  Positions : ", fmtNum(finalPos)
  echo "  Games     : ", fmtNum(finalGms)
  echo "  Elapsed   : ", elapsed, "s"
  echo "  avg pos/g : ", if finalGms > 0: $system.int(finalPos div finalGms) else: "N/A"
