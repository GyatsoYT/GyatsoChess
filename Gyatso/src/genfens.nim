import std/[strutils, os, times, monotimes, atomics]
import coretypes
import board
import bitboard
import movegen
import search
import tt
import history

type
  SplitMix64* = object
    state*: uint64

proc initSplitMix64*(seed: uint64): SplitMix64 =
  result.state = seed
  # Burn 64 iterations so nearby seeds diverge
  for _ in 0 ..< 64:
    result.state += 0x9e3779b97f4a7c15'u64
    var z = result.state
    z = (z xor (z shr 30)) * 0xbf58476d1ce4e5b9'u64
    z = (z xor (z shr 27)) * 0x94d049bb133111eb'u64
    discard z xor (z shr 31)

proc nextU64*(rng: var SplitMix64): uint64 {.inline.} =
  rng.state += 0x9e3779b97f4a7c15'u64
  var z = rng.state
  z = (z xor (z shr 30)) * 0xbf58476d1ce4e5b9'u64
  z = (z xor (z shr 27)) * 0x94d049bb133111eb'u64
  return z xor (z shr 31)

proc randInt*(rng: var SplitMix64, maxExclusive: int): int {.inline.} =
  if maxExclusive <= 1: return 0
  return system.int(rng.nextU64() mod system.uint64(maxExclusive))

type
  GenfensOptions* = object
    n*: int
    seed*: uint64
    bookPath*: string
    usingBook*: bool
    customMoves*: int
    maxScore*: int
    depth*: int
    hardNodes*: uint64

const KnownKeywords = [
  "seed", "book", "random", "moves", "randommoves",
  "threshold", "eval", "maxeval", "maxscore",
  "depth", "nodes", "hn", "quit"
]

proc stripQuotes(s: string): string =
  result = s.strip(chars = {' ', '\t', '"', '\''})
  while result.len >= 2 and (
    (result.startsWith("\"") and result.endsWith("\"")) or
    (result.startsWith("'") and result.endsWith("'"))
  ):
    result = result[1 .. ^2].strip(chars = {' ', '\t', '"', '\''})

proc parseGenfensArgs*(cmd: string): GenfensOptions =
  result.n = 0
  result.seed = 42'u64
  result.bookPath = "None"
  result.usingBook = false
  result.customMoves = -1
  result.maxScore = 1000
  result.depth = 8
  result.hardNodes = 1_000_000'u64

  let tokens = cmd.strip().splitWhitespace()
  var i = 0
  while i < tokens.len:
    let tok = tokens[i].toLowerAscii()
    if tok == "genfens":
      inc i
      if i < tokens.len:
        try: result.n = parseInt(tokens[i])
        except ValueError: discard
    elif tok == "seed":
      inc i
      if i < tokens.len:
        try: result.seed = parseBiggestUInt(tokens[i])
        except ValueError: discard
    elif tok == "book":
      inc i
      if i < tokens.len:
        var rawBook = tokens[i]
        if rawBook.startsWith("\"") or rawBook.startsWith("'"):
          let quoteChar = rawBook[0]
          rawBook = rawBook[1..^1]
          while not rawBook.endsWith($quoteChar) and i + 1 < tokens.len and tokens[i + 1].toLowerAscii() notin KnownKeywords:
            inc i
            rawBook.add(" " & tokens[i])
          if rawBook.endsWith($quoteChar):
            rawBook = rawBook[0 .. ^2]
        else:
          # Consume following tokens that aren't keywords to support paths with spaces
          while i + 1 < tokens.len and tokens[i + 1].toLowerAscii() notin KnownKeywords:
            inc i
            rawBook.add(" " & tokens[i])

        rawBook = stripQuotes(rawBook)
        result.bookPath = rawBook
        result.usingBook = result.bookPath.toLowerAscii() != "none" and result.bookPath.len > 0
    elif tok in ["random", "moves", "randommoves"]:
      inc i
      if i < tokens.len:
        try: result.customMoves = parseInt(tokens[i])
        except ValueError: discard
    elif tok in ["threshold", "eval", "maxeval", "maxscore"]:
      inc i
      if i < tokens.len:
        try: result.maxScore = parseInt(tokens[i])
        except ValueError: discard
    elif tok == "depth":
      inc i
      if i < tokens.len:
        try: result.depth = parseInt(tokens[i])
        except ValueError: discard
    elif tok in ["nodes", "hn"]:
      inc i
      if i < tokens.len:
        try: result.hardNodes = parseBiggestUInt(tokens[i])
        except ValueError: discard
    inc i

proc loadBook(path: string): seq[string] =
  if not fileExists(path):
    return @[]
  for line in lines(path):
    var s = line.strip()
    if s.len == 0 or s[0] == '#': continue
    if ';' in s:
      s = s[0 ..< s.find(';')].strip()
    if s.len > 0:
      result.add(s)

proc playRandomMoves(b: var Board, rng: var SplitMix64, count: int): bool =
  for step in 0 ..< count:
    var ml: MoveList
    generateMoves(b, ml)
    if ml.len == 0:
      return false
    let mv = ml.moves[rng.randInt(ml.len)]
    b.makeMove(mv)

  if not b.checkers.isEmpty():
    return false
  if b.isFiftyMove() or b.isInsufficientMaterial() or b.isRepetition():
    return false
  var finalMl: MoveList
  generateMoves(b, finalMl)
  if finalMl.len == 0:
    return false
  return true

proc verificationSearch(b: var Board, depth: int, hardNodes: uint64): (Move, int) =
  var stopFlag: Atomic[bool]
  stopFlag.store(false, moRelaxed)

  newTTGeneration()
  clearAllHistory()

  var info: SearchInfo
  info.id = 0
  info.startTime = getMonoTime()
  info.softLimitMs = int64(high(int32))
  info.hardLimitMs = int64(high(int32))
  info.depthLimit = depth
  info.nodeLimit = hardNodes
  info.softNodeLimit = 0
  info.nodes = 0
  info.selDepth = 0
  info.silent = true
  info.stopFlag = addr stopFlag

  var searchBoard = b
  return iterativeDeepening(searchBoard, info)

proc runGenfens*(cmd: string) =
  let opts = parseGenfensArgs(cmd)
  if opts.n <= 0:
    stdout.writeLine("info string usage: genfens <N> [seed <S>] [book <None|path>] [random <moves>] [threshold <score>] [depth <d>]")
    stdout.flushFile()
    return

  var rng = initSplitMix64(opts.seed)
  var book: seq[string] = @[]

  if opts.usingBook:
    book = loadBook(opts.bookPath)
    if book.len == 0:
      stdout.writeLine("info string unable to open book " & opts.bookPath)
      stdout.flushFile()
      return
    stdout.writeLine("info string found " & $book.len & " book lines")
    stdout.flushFile()
  else:
    stdout.writeLine("info string found 0 book lines")
    stdout.flushFile()

  let bookOffset = uint32(opts.seed and 0xFFFFFFFF'u64)
  var generated = 0
  var lastGenTime = getMonoTime()

  while generated < opts.n:
    var b: Board
    if opts.usingBook:
      let bookIdx = if opts.customMoves == 0:
                      (system.int(bookOffset) + generated) mod book.len
                    else:
                      (system.int(bookOffset) + rng.randInt(book.len)) mod book.len
      try:
        b = parseFen(book[bookIdx])
      except:
        b = parseFen(StartPos)
    else:
      b = parseFen(StartPos)

    let randomCount = if opts.customMoves >= 0:
                        opts.customMoves
                      elif opts.usingBook:
                        6 + rng.randInt(4)
                      else:
                        8 + rng.randInt(2)

    if not playRandomMoves(b, rng, randomCount):
      continue

    # Verification search
    let (bestMove, score) = verificationSearch(b, opts.depth, opts.hardNodes)
    if bestMove == NullMove:
      continue

    let elapsedSinceLast = (getMonoTime() - lastGenTime).inMilliseconds
    let threshold = if elapsedSinceLast > 10_000: opts.maxScore * 2 else: opts.maxScore
    if abs(score) > threshold:
      continue

    let fen = b.toFen()
    stdout.writeLine("info string genfens " & fen)
    stdout.flushFile()
    inc generated
    lastGenTime = getMonoTime()
