
import coretypes, bitboard, board, movegen, search, evaluate, attacks, zobrist,
       tt, searchparams, history, nnuetypes, nnue
import std/[os, strutils, random, monotimes, times, atomics, cpuinfo,
            parseopt, json, math]

type
  BinRecord* {.packed.} = object
    packedBoard*: array[24, uint8]  ## bytes  0..23
    sideToMove*:  uint8              ## byte   24
    castlingRights*: uint8           ## byte   25
    enPassantFile*: int8             ## byte   26
    halfmoveClock*: uint8            ## byte   27
    scoreCp*:     int16              ## bytes 28..29
    wdl*:         float32            ## bytes 30..33
    pieceCount*:  uint8              ## byte   34
    padding*:     array[5, uint8]    ## bytes 35..39

static:
  doAssert sizeof(BinRecord) == 40, "BinRecord must be exactly 40 bytes"

{.push inline.}

proc pieceNibble(p: Piece): uint8 =
  let colorBit: uint8 = if p.color == Black: 8'u8 else: 0'u8
  let typeBits: uint8 = case p.pieceType
    of Pawn:   1'u8
    of Knight: 2'u8
    of Bishop: 3'u8
    of Rook:   4'u8
    of Queen:  5'u8
    of King:   6'u8
    else:      0'u8
  colorBit or typeBits

proc packPositionFromBoard*(b: Board; scoreCp: int16; wdl: float32;
                            outBuf: var BinRecord) =
  zeroMem(addr outBuf, 40)

  let occBB: Bitboard = b.occupied
  let occupied: uint64 = occBB.uint64
  outBuf.pieceCount = uint8(occBB.popcount())
  copyMem(addr outBuf.packedBoard[0], unsafeAddr occupied, 8)

  var occVar: Bitboard = occBB
  var nibbleIdx = 0
  while not occVar.isEmpty():
    let sqIdx = occVar.lsb().int
    occVar = occVar and (occVar - Bitboard(1))
    let nibble = pieceNibble(b.mailbox[sqIdx])
    let byteIdx = 8 + (nibbleIdx shr 1)
    if (nibbleIdx and 1) == 0:
      outBuf.packedBoard[byteIdx] = nibble
    else:
      outBuf.packedBoard[byteIdx] = outBuf.packedBoard[byteIdx] or (nibble shl 4)
    inc nibbleIdx

  outBuf.sideToMove     = if b.stm == White: 0'u8 else: 1'u8
  outBuf.castlingRights = cast[uint8](b.castling)
  outBuf.enPassantFile  = if b.epSquare == NoSquare: -1'i8
                          else: int8(b.epSquare.file)
  outBuf.halfmoveClock  = min(b.halfmove, 255'u8)
  outBuf.scoreCp        = scoreCp
  outBuf.wdl            = wdl

{.pop.}

const WdlScale = 400.0'f32

func evalToWdl(scoreCp: int): float32 {.inline.} =
  1.0'f32 / (1.0'f32 + exp(-scoreCp.float32 / WdlScale))

const
  BloomBits   = 1 shl 26
  BloomMask   = BloomBits - 1
  BloomBytes  = BloomBits shr 3

var gBloomFilter {.global.}: array[BloomBytes, uint8]

proc bloomCheck(key: uint64): bool {.inline.} =
  let h1 = system.int((key * 0x9e3779b97f4a7c15'u64) shr 38) and BloomMask
  let h2 = system.int((key * 0x6c62272e07bb0142'u64) shr 38) and BloomMask
  let b1 = uint8(1) shl (h1 and 7)
  let b2 = uint8(1) shl (h2 and 7)
  (gBloomFilter[h1 shr 3] and b1) != 0 and
  (gBloomFilter[h2 shr 3] and b2) != 0

proc bloomInsert(key: uint64) {.inline.} =
  let h1 = system.int((key * 0x9e3779b97f4a7c15'u64) shr 38) and BloomMask
  let h2 = system.int((key * 0x6c62272e07bb0142'u64) shr 38) and BloomMask
  gBloomFilter[h1 shr 3] = gBloomFilter[h1 shr 3] or (uint8(1) shl (h1 and 7))
  gBloomFilter[h2 shr 3] = gBloomFilter[h2 shr 3] or (uint8(1) shl (h2 and 7))

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

type
  BufferedPosition = object
    record:   BinRecord
    evalWdl:  float32

type
  GameResult = enum
    grWhiteWin, grBlackWin, grDraw, grOngoing

  AdjState = object
    winCount:    int
    winSide:     Color
    drawStreak:  int

var tNNUE {.threadvar.}: NNUEState

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
  info.nodeLimit     = hardNodes   # hard: abort mid-search
  info.softNodeLimit = softNodes   # soft: exit after depth completes
  info.nodes         = 0
  info.selDepth      = 0
  info.silent        = true
  info.stopFlag      = addr stopFlag

  refreshNNUE(b, tNNUE)

  let (move, score) = iterativeDeepening(b, info)
  return (move, score)

proc playGame(book: var OpeningBook;
              rng: var Rand;
              softNodes, hardNodes: uint64;
              randPlies: int;
              filterWindow: int;
              lambda: float32;
              stopFlag: var Atomic[bool];
              positions: var seq[BufferedPosition]): GameResult =

  positions.setLen(0)

  var b: Board
  if book.fens.len > 0:
    let (bookIdx, fen) = selectOpening(book, rng)
    book.counts[bookIdx] += 1
    b = parseFen(fen)
  else:
    b = parseFen(StartPos)

  let varietyTarget = rng.rand(randPlies) + 1
  var varietyPlayed = 0
  while varietyPlayed < varietyTarget:
    var vml: MoveList
    generateMoves(b, vml)
    if vml.len == 0: break
    let idx = rng.rand(vml.len - 1)
    b.makeMove(vml.moves[idx])
    inc varietyPlayed

  var adj: AdjState
  var moveCount = 0
  var ply       = 0

  while true:
    inc moveCount
    if moveCount > 300: return grDraw

    # Draw detection
    if b.isFiftyMove():        return grDraw
    if b.isRepetition():       return grDraw
    if b.isInsufficientMaterial(): return grDraw

    var ml: MoveList
    generateMoves(b, ml)
    if ml.len == 0:
      if not b.checkers.isEmpty():
        return if b.stm == White: grBlackWin else: grWhiteWin
      else:
        return grDraw

    let (bestMove, scoreStm) = searchPosition(b, softNodes, hardNodes, stopFlag)
    if bestMove == NullMove: return grDraw

    let absScore = abs(scoreStm)

    if absScore >= 2500:
      let winningSide = if scoreStm > 0: b.stm else: b.stm.opposite()
      if adj.winCount > 0 and adj.winSide == winningSide:
        inc adj.winCount
      else:
        adj.winCount = 1
        adj.winSide  = winningSide
      adj.drawStreak = 0
    elif moveCount > 80 and absScore <= 15 and b.halfmove >= 30:
      inc adj.drawStreak
      adj.winCount = 0
    else:
      adj.winCount   = 0
      adj.drawStreak = 0

    if adj.winCount >= 4:
      return if adj.winSide == White: grWhiteWin else: grBlackWin
    if adj.drawStreak >= 10:
      return grDraw

    let staticEval = evaluate(b, tNNUE)

    b.makeMove(bestMove)
    inc ply

    let givesCheck = not b.checkers.isEmpty()

    let scoreDelta = abs(staticEval - scoreStm)
    let passFilter = filterWindow <= 0 or scoreDelta <= filterWindow

    let moveIsQuiet = bestMove.isQuiet() and
                      (b.history[b.histLen - 1].captured == NoPiece)

    if moveIsQuiet and
       not givesCheck and
       absScore <= 2500 and
       ply >= 16 and
       passFilter:

      let pc = b.occupied.popcount()
      if pc >= 3 and pc <= 32:
        let hk = b.hash.uint64
        if not bloomCheck(hk):
          bloomInsert(hk)

          let weAre = b.stm.opposite()

          let scoreCpWhite: int16 =
            if weAre == White: int16(scoreStm) else: int16(-scoreStm)

          let ew = evalToWdl(scoreStm)
          let evalWdlWhite: float32 =
            if weAre == White: ew else: 1.0'f32 - ew

          var bp: BufferedPosition
          packPositionFromBoard(b, scoreCpWhite, 0.0'f32, bp.record)
          bp.evalWdl = evalWdlWhite
          positions.add(bp)

  return grOngoing  # unreachable

const MaxFileSize = 512 * 1024 * 1024

type
  DataWriter = object
    dir:               string
    threadId:          int
    fileIndex:         int
    f:                 File
    bytesWritten:      int64
    recordsSinceFlush: int

proc initDataWriter(dir: string; threadId: int; fileIndex: int = 0): DataWriter =
  result.dir       = dir
  result.threadId  = threadId
  result.fileIndex = fileIndex
  let path = dir / ("data_T" & $threadId & "_F" & $fileIndex & ".bin")
  result.f = open(path, fmAppend)

proc writeRecord(w: var DataWriter; rec: var BinRecord) {.inline.} =
  if w.bytesWritten + 40 > MaxFileSize:
    w.f.close()
    inc w.fileIndex
    let path = w.dir / ("data_T" & $w.threadId & "_F" & $w.fileIndex & ".bin")
    w.f = open(path, fmWrite)
    w.bytesWritten      = 0
    w.recordsSinceFlush = 0
  discard w.f.writeBuffer(addr rec, 40)
  w.bytesWritten += 40
  inc w.recordsSinceFlush
  if w.recordsSinceFlush >= 2000:
    w.f.flushFile()
    w.recordsSinceFlush = 0

proc closeWriter(w: var DataWriter) {.inline.} =
  w.f.flushFile()
  w.f.close()

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
    ttSizeMb:     int
    lambda:       float32
    randPlies:    int
    filterWindow: int
    seed:         uint64
    shared:       SharedState

var gTotalPositions {.global.}: Atomic[int64]
var gTotalGames     {.global.}: Atomic[int64]
var gStopFlag       {.global.}: Atomic[bool]

proc workerThread(args: WorkerArgs) {.thread.} =
  initThreadAttacks()
  initHistoryData()

  tNNUE = NNUEState()

  var book: OpeningBook
  if args.bookPath.len > 0:
    book = loadOpeningBook(args.bookPath)

  var rng       = initRand(int64(args.seed) + int64(args.threadId) * 1_000_003'i64)
  var writer    = initDataWriter(args.outputDir, args.threadId)
  var positions: seq[BufferedPosition] = @[]
  var localStop: Atomic[bool]
  localStop.store(false, moRelaxed)

  while not args.shared.stopFlag[].load(moRelaxed):
    newTTGeneration()

    let res = playGame(book, rng, args.softNodes, args.hardNodes,
                       args.randPlies, args.filterWindow, args.lambda,
                       localStop, positions)
    if res == grOngoing: continue

    let gameWdl: float32 = case res
      of grWhiteWin: 1.0'f32
      of grBlackWin: 0.0'f32
      else:          0.5'f32

    for i in 0 ..< positions.len:
      positions[i].record.wdl =
        args.lambda * gameWdl + (1.0'f32 - args.lambda) * positions[i].evalWdl
      writer.writeRecord(positions[i].record)

    discard args.shared.totalPositions[].fetchAdd(int64(positions.len), moRelaxed)
    discard args.shared.totalGames[].fetchAdd(1'i64, moRelaxed)

    if args.shared.totalPositions[].load(moRelaxed) >= args.shared.targetPositions:
      args.shared.stopFlag[].store(true, moRelaxed)

  closeWriter(writer)

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
  var lambda          = 0.5'f32
  var randPlies       = 8
  var filterWindow    = 300
  var seed: uint64    = 42

  var p = initOptParser(commandLineParams())
  while true:
    p.next()
    case p.kind
    of cmdEnd: break
    of cmdShortOption, cmdLongOption:
      case p.key
      of "book":     p.next(); bookPath        = p.key
      of "output":   p.next(); outputDir       = p.key
      of "target":   p.next(); targetPositions = parseBiggestInt(p.key).int64
      of "workers":  p.next(); numWorkers      = parseInt(p.key)
      of "sn":       p.next(); softNodes       = parseBiggestUInt(p.key)
      of "hn":       p.next(); hardNodes       = parseBiggestUInt(p.key)
      of "tt":       p.next(); ttSizeMb        = parseInt(p.key)
      of "lambda":   p.next(); lambda          = parseFloat(p.key).float32
      of "randplies":p.next(); randPlies       = parseInt(p.key)
      of "filter":   p.next(); filterWindow    = parseInt(p.key)
      of "seed":     p.next(); seed            = parseBiggestUInt(p.key)
      else: discard
    of cmdArgument: discard

  lambda = clamp(lambda, 0.0'f32, 1.0'f32)

  if hardNodes > 0 and softNodes > hardNodes:
    softNodes = hardNodes

  initAttacks()
  initThreadAttacks()
  initTT(16)
  initTables()
  initNNUE()
  initHistoryModule()
  createDir(outputDir)

  echo "┌─────────────────────────────────────────┐"
  echo "│         Gyatso Datagen v2.0             │"
  echo "└─────────────────────────────────────────┘"
  echo "  Book:        ", if bookPath.len > 0: bookPath else: "<none — bookless mode>"
  echo "  Output:      ", outputDir
  echo "  Target:      ", fmtNum(targetPositions)
  echo "  Workers:     ", numWorkers
  echo "  Soft nodes:  ", softNodes, "  (exit after depth)"
  echo "  Hard nodes:  ", hardNodes, "  (mid-search abort)"
  echo "  TT/worker:   ", ttSizeMb, " MB"
  echo "  Lambda:      ", lambda, "  (WDL mix: game×λ + eval×(1-λ))"
  echo "  Rand plies:  ", randPlies
  echo "  Filter:      ", if filterWindow > 0: $filterWindow & " cp" else: "off"
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
    args.ttSizeMb     = ttSizeMb
    args.lambda       = lambda
    args.randPlies    = randPlies
    args.filterWindow = filterWindow
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

  let elapsed = (getMonoTime() - startTime).inSeconds
  let finalPos = gTotalPositions.load(moRelaxed)
  let finalGms = gTotalGames.load(moRelaxed)
  echo ""
  echo "Done!"
  echo "  Positions : ", fmtNum(finalPos)
  echo "  Games     : ", fmtNum(finalGms)
  echo "  Elapsed   : ", elapsed, "s"
  echo "  avg pos/g : ", if finalGms > 0: $system.int(finalPos div finalGms) else: "N/A"
