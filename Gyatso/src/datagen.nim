import coretypes, board, move, movegen, search, evaluation, bitboard,
       zobrist, magicbitboards, lookups, tt, tables, utils, nnue
import std/[os, strutils, random, monotimes, times, atomics, cpuinfo,
            parseopt, json, sets]

type
  BinRecord* {.packed.} = object
    packedBoard*: array[24, uint8]  # 0..23
    sideToMove*: uint8              # 24
    castlingRights*: uint8          # 25
    enPassantFile*: int8            # 26
    halfmoveClock*: uint8           # 27
    scoreCp*: int16                 # 28..29
    wdl*: float32                   # 30..33
    pieceCount*: uint8              # 34
    padding*: array[5, uint8]       # 35..39

static:
  doAssert sizeof(BinRecord) == 40, "BinRecord must be exactly 40 bytes"

{.push inline.}

proc pieceNibble(p: Piece): uint8 {.inline.} =
  let colorBit: uint8 = if pieceColor(p) == Black: 8 else: 0
  let typeBits: uint8 = case pieceType(p)
    of Pawn: 1
    of Knight: 2
    of Bishop: 3
    of Rook: 4
    of Queen: 5
    of King: 6
    else: 0
  return colorBit or typeBits

proc packPositionFromBoard*(b: Board; scoreCp: int16; wdl: float32;
                            outBuf: var BinRecord) =
  var zero: BinRecord
  copyMem(addr outBuf, addr zero, 40)

  var occupied: uint64 = b.allPiecesBB
  outBuf.pieceCount = countBits(occupied).uint8
  copyMem(addr outBuf.packedBoard[0], addr occupied, 8)

  var occ = occupied
  var nibbleIdx = 0
  while occ != 0:
    let sq = countTrailingZeroBits(occ).Square
    occ = occ and (occ - 1)
    let nibble = pieceNibble(b.pieces[sq])
    let byteIdx = 8 + (nibbleIdx shr 1)
    if (nibbleIdx and 1) == 0:
      outBuf.packedBoard[byteIdx] = nibble
    else:
      outBuf.packedBoard[byteIdx] = outBuf.packedBoard[byteIdx] or (nibble shl 4)
    inc nibbleIdx

  outBuf.sideToMove      = if b.sideToMove == White: 0'u8 else: 1'u8
  outBuf.castlingRights  = b.castlingRights.uint8
  outBuf.enPassantFile   = if b.enPassantSquare == NoSquare: -1'i8
                           else: fileOf(b.enPassantSquare.Square).int8
  outBuf.halfmoveClock   = min(b.halfMoveClock, 255).uint8
  outBuf.scoreCp         = scoreCp
  outBuf.wdl             = wdl

{.pop.}

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
  var total = 0.0
  for c in book.counts: total += 1.0 / (c.float + 1.0)
  var r = rng.rand(total)
  for i in 0 ..< book.fens.len:
    r -= 1.0 / (book.counts[i].float + 1.0)
    if r <= 0.0: return (i, book.fens[i])
  let idx = book.fens.len - 1
  return (idx, book.fens[idx])

type
  BufferedPosition = object
    record: BinRecord

type
  GameResult = enum
    grWhiteWin, grBlackWin, grDraw, grOngoing

  AdjudicationState = object
    winCount:        int
    lastWinSide:     Color
    drawStreak:      int   # consecutive near-zero evals


{.push inline.}
proc isQuietMove(m: Move): bool = not m.isCapture and not m.isPromotion
{.pop.}

proc playGame(book: var OpeningBook; rng: var Rand; nodeLimit: int;
              positions: var seq[BufferedPosition]): GameResult =
  positions.setLen(0)

  let (bookIdx, fen) = selectOpening(book, rng)
  book.counts[bookIdx] += 1

  var b = initializeBoard(fen)

  # ── Variety phase: play 0-4 random legal moves after the opening ──
  # No scoring, no position recording, just diversify the tree.
  let varietyCount = rng.rand(9)           # uniform in [0, 9]
  var varietyPlayed = 0
  while varietyPlayed < varietyCount:
    var vml: MoveList
    generateLegalMoves(b, vml)
    if vml.count == 0: break
    let randIdx = rng.rand(vml.count - 1)
    if not b.makeMove(vml.moves[randIdx]): break  # illegal (shouldn't happen post-legal-gen)
    inc varietyPlayed

  var adj: AdjudicationState
  var seenHashes: HashSet[uint64]
  seenHashes.init()
  seenHashes.incl(b.currentZobristKey)

  var ply      = 0
  var moveCount = 0

  while true:
    inc moveCount
    if moveCount > 300: return grDraw

    var ml: MoveList
    generateLegalMoves(b, ml)

    if ml.count == 0:
      let us   = b.sideToMove
      let them = if us == White: Black else: White
      let kingSq = bitScanForward(b.pieceBB[makePiece(us, King)]).Square
      if isSquareAttacked(b, kingSq, them):
        return if us == White: grBlackWin else: grWhiteWin
      else:
        return grDraw

    # ── Search ──
    let (bestMove, score) = searchNodes(b, nodeLimit)
    if bestMove == Move(0): return grDraw

    let absScore = abs(score)

    # Win/draw adjudication
    if absScore >= 2000:
      let winningSide = if score > 0: b.sideToMove
                        else: (if b.sideToMove == White: Black else: White)

      if adj.winCount > 0 and adj.lastWinSide == winningSide:
        inc adj.winCount
      else:
        adj.winCount    = 1
        adj.lastWinSide = winningSide

      adj.drawStreak = 0

    # ── Draw adjudication ──
    elif moveCount > 100 and b.halfMoveClock >= 40 and absScore <= 10:
      inc adj.drawStreak
      adj.winCount = 0

    # ── Reset if broken ──
    else:
      adj.winCount   = 0
      adj.drawStreak = 0

    # ── Apply decisions ──
    if adj.winCount >= 8:
      return if adj.lastWinSide == White: grWhiteWin else: grBlackWin

    if adj.drawStreak >= 8:
      return grDraw

    discard b.makeMove(bestMove)
    inc ply

    if b.halfMoveClock >= 100: return grDraw
    if b.isRepetition():        return grDraw
    if b.isInsufficientMaterial(): return grDraw

    # ── Position filtering ──
    # Record position only after the move that produced it
    let quiet      = isQuietMove(bestMove)
    let opponent   = b.sideToMove
    let weAre      = if opponent == White: Black else: White
    let oppKingSq  = bitScanForward(b.pieceBB[makePiece(opponent, King)]).Square
    let givesCheck = isSquareAttacked(b, oppKingSq, weAre)

    if quiet and not givesCheck and absScore <= 2000 and ply >= 16:
      let pc = countBits(b.allPiecesBB)
      if pc >= 3 and pc <= 32:
        if not seenHashes.contains(b.currentZobristKey):
          seenHashes.incl(b.currentZobristKey)

          # Score from White's perspective (absolute)
          let scoreCpWhite: int16 =
            if weAre == White: score.int16 else: (-score).int16

          var bp: BufferedPosition
          # wdl assigned at end of game; 0.0 placeholder now
          packPositionFromBoard(b, scoreCpWhite, 0.0'f32, bp.record)
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

proc initDataWriter(dir: string; threadId, fileIndex: int = 0): DataWriter =
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
    w.bytesWritten    = 0
    w.recordsSinceFlush = 0
  discard w.f.writeBuffer(addr rec, 40)
  w.bytesWritten += 40
  inc w.recordsSinceFlush
  if w.recordsSinceFlush >= 1000:
    w.f.flushFile()
    w.recordsSinceFlush = 0

proc closeWriter(w: var DataWriter) {.inline.} =
  w.f.flushFile(); w.f.close()

type
  SharedState = object
    totalPositions:  ptr Atomic[int64]
    totalGames:      ptr Atomic[int64]
    targetPositions: int64
    stopFlag:        ptr Atomic[bool]

  WorkerArgs = object
    threadId:   int
    outputDir:  string
    bookPath:   string
    nodeLimit:  int
    seed:       uint64
    shared:     SharedState

var gTotalPositions {.global.}: Atomic[int64]
var gTotalGames     {.global.}: Atomic[int64]
var gStopFlag       {.global.}: Atomic[bool]

proc workerThread(args: WorkerArgs) {.thread.} =
  initThreadMagics()

  var book      = loadOpeningBook(args.bookPath)
  var rng       = initRand(args.seed.int64 + args.threadId.int64 * 1000)
  var writer    = initDataWriter(args.outputDir, args.threadId)
  var positions: seq[BufferedPosition] = @[]

  while not args.shared.stopFlag[].load(moRelaxed):
    let res = playGame(book, rng, args.nodeLimit, positions)
    if res == grOngoing: continue

    let wdlVal: float32 = case res
      of grWhiteWin: 1.0'f32
      of grBlackWin: 0.0'f32
      else:          0.5'f32

    for i in 0 ..< positions.len:
      positions[i].record.wdl = wdlVal
      writer.writeRecord(positions[i].record)

    discard args.shared.totalPositions[].fetchAdd(positions.len.int64, moRelaxed)
    discard args.shared.totalGames[].fetchAdd(1'i64, moRelaxed)

    if args.shared.totalPositions[].load(moRelaxed) >= args.shared.targetPositions:
      args.shared.stopFlag[].store(true, moRelaxed)

  closeWriter(writer)

const StateFile = "datagen_state.json"

proc saveState(dir: string; totalPos, totalGames: int64; seed: uint64) =
  let j = %*{"total_positions_written": totalPos,
              "total_games_played": totalGames,
              "rng_seed": seed.int64}
  writeFile(dir / StateFile, $j)

proc loadState(dir: string): JsonNode =
  let path = dir / StateFile
  if fileExists(path): return parseJson(readFile(path))
  return nil

proc fmtNum(n: int64): string {.inline.} =
  if n >= 1_000_000: $(n div 1_000_000) & "." & $((n mod 1_000_000) div 100_000) & "M"
  elif n >= 1_000:   $(n div 1_000) & "." & $((n mod 1_000) div 100) & "K"
  else: $n


when isMainModule:
  var bookPath        = ""
  var outputDir       = "./data"
  var targetPositions = 100_000_000'i64
  var numWorkers      = max(1, countProcessors() - 1)
  var nodeLimit       = 5000
  var seed: uint64    = 42

  var p = initOptParser(commandLineParams())
  while true:
    p.next()
    case p.kind
    of cmdEnd: break
    of cmdShortOption, cmdLongOption:
      case p.key
      of "book":    p.next(); bookPath        = p.key
      of "output":  p.next(); outputDir       = p.key
      of "target":  p.next(); targetPositions = parseBiggestInt(p.key).int64
      of "workers": p.next(); numWorkers      = parseInt(p.key)
      of "nodes":   p.next(); nodeLimit       = parseInt(p.key)
      of "seed":    p.next(); seed            = parseBiggestUInt(p.key)
      else: discard
    of cmdArgument: discard

  if bookPath == "":
    echo "Usage: datagen --book PATH [--output DIR] [--target N] [--workers N] [--nodes N] [--seed N]"
    quit(1)

  precomputeAttackTables()
  initMagicBitboards()
  initializeZobristKeys()
  initTT(16)
  initNNUE()
  createDir(outputDir)

  echo "Gyatso Datagen"
  echo "  Book:    ", bookPath
  echo "  Output:  ", outputDir
  echo "  Target:  ", fmtNum(targetPositions)
  echo "  Workers: ", numWorkers
  echo "  Nodes:   ", nodeLimit
  echo "  Seed:    ", seed
  echo "  NNUE:    embedded (", NNUE_EMBEDDED.len, " bytes)"
  when defined(avx512): echo "  SIMD:    AVX-512"
  elif defined(avx2):   echo "  SIMD:    AVX-2"
  else:                 echo "  SIMD:    scalar"

  let stateJson = loadState(outputDir)
  if stateJson != nil:
    stdout.write "Found previous state. Resume? (y/n): "
    let resp = stdin.readLine().strip().toLowerAscii()
    if resp == "y":
      gTotalPositions.store(stateJson["total_positions_written"].getBiggestInt().int64, moRelaxed)
      gTotalGames.store(stateJson["total_games_played"].getBiggestInt().int64, moRelaxed)
      echo "Resuming: ", fmtNum(gTotalPositions.load(moRelaxed)), " positions, ",
           fmtNum(gTotalGames.load(moRelaxed)), " games"

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
    args.threadId  = i
    args.outputDir = outputDir
    args.bookPath  = bookPath
    args.nodeLimit = nodeLimit
    args.seed      = seed + i.uint64 * 999983'u64
    args.shared    = shared
    createThread(threads[i], workerThread, args)

  var lastReportTime  = getMonoTime()
  var lastReportPos   = gTotalPositions.load(moRelaxed)
  var lastSaveGames   = 0'i64

  while not gStopFlag.load(moRelaxed):
    sleep(5000)

    let now        = getMonoTime()
    let totalPos   = gTotalPositions.load(moRelaxed)
    let totalGms   = gTotalGames.load(moRelaxed)
    let intervalMs = (now - lastReportTime).inMilliseconds
    let intervalPos = totalPos - lastReportPos
    let posPerSec  = if intervalMs > 0: (intervalPos.float * 1000.0 / intervalMs.float).int
                     else: 0
    let remaining  = targetPositions - totalPos
    let eta        = if posPerSec > 0: remaining div posPerSec.int64 else: 0'i64

    stdout.write "\rGames: " & fmtNum(totalGms) &
                 "  Pos: " & fmtNum(totalPos) &
                 "  pos/s: " & $posPerSec &
                 "  ETA: " & $(eta div 60) & "m" & $(eta mod 60) & "s    "
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
  echo ""
  echo "Done! ", fmtNum(gTotalPositions.load(moRelaxed)), " positions from ",
       fmtNum(gTotalGames.load(moRelaxed)), " games in ", elapsed, "s"