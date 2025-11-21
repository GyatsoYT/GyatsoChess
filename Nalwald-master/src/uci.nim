import
  types,
  move,
  position,
  positionUtils,
  hashTable,
  uciSearch,
  uciInfos,
  perft,
  evaluation,
  version,
  utils,
  searchParams,
  timeManagedSearch,
  printMarkdownSubset,
  poem,
  testing/tests

import std/[strutils, strformat, atomics, sets]

import malebolgia

const
  defaultHashSizeMB = 4
  maxHashSizeMB = 1_048_576
  defaultNumThreads = 1

type
  SearchThreadInput =
    tuple[
      searchInfo: SearchInfo,
      uciCompatibleOutput: bool,
      searchRunningFlag: ptr Atomic[bool],
    ]
  SearchThread = Thread[SearchThreadInput]
  UciState = object
    history: seq[Position]
    hashTable: HashTable
    stopFlag: Atomic[bool]
    searchRunningFlag: Atomic[bool]
    numThreads: int
    multiPv: int
    uciCompatibleOutput: bool = false
    searchThread: ref SearchThread

func currentPosition(uciState: UciState): Position =
  doAssert uciState.history.len >= 1, "Need at least the current position in history"
  uciState.history[^1]

proc info(uciState: UciState, s: string) =
  if not uciState.uciCompatibleOutput:
    printMarkdownSubset s
  else:
    echo "info string ", s

proc uci(uciState: var UciState) =
  uciState.uciCompatibleOutput = true
  echo "id name Nalwald " & versionOrId()
  echo "id author Jost Triller"
  echo "option name Hash type spin default ",
    defaultHashSizeMB, " min 1 max ", maxHashSizeMB
  echo "option name Threads type spin default ",
    defaultNumThreads, " min 1 max ", ThreadPoolSize
  echo "option name MultiPV type spin default 1 min 1 max 1000"
  echo "option name UCI_Chess960 type check default false"
  printUciSearchParams()
  echo "uciok"

proc setOption(uciState: var UciState, params: seq[string]) =
  if uciState.searchRunningFlag.load:
    uciState.info "*Can't set options when search is running*"
    return

  if params.len == 4 and params[0] == "name" and params[2] == "value":
    case params[1].toLowerAscii
    of "Hash".toLowerAscii:
      let newHashSizeMB = params[3].parseInt
      if newHashSizeMB < 1 or newHashSizeMB > maxHashSizeMB:
        uciState.info "*Invalid value*"
      else:
        uciState.hashTable.setByteSize(sizeInBytes = newHashSizeMB * megaByteToByte)
        uciState.info fmt"*Set hash size to* **{newHashSizeMB} MB**"
    of "UCI_Chess960".toLowerAscii:
      discard
    of "Threads".toLowerAscii:
      let newNumThreads = params[3].parseInt
      if newNumThreads < 1 or newNumThreads > ThreadPoolSize:
        uciState.info "*Invalid value*"
      else:
        uciState.numThreads = newNumThreads
        uciState.info fmt"*Set number of search threads to* **{newNumThreads}**"
    of "MultiPV".toLowerAscii:
      let newMultiPv = params[3].parseInt
      if newMultiPv < 1 or newMultiPv > 1000:
        uciState.info "*Invalid value*"
      else:
        uciState.multiPv = newMultiPv
        uciState.hashTable.clear()
        uciState.info fmt"*Set multi pv to* **{newMultiPv}**"
    else:
      if hasSearchOption(params[1]):
        setSearchOption(params[1], params[3].parseInt)
      else:
        uciState.info fmt"Unknown option: {params[1]}"
  else:
    uciState.info "Unknown parameters"

proc stop(uciState: var UciState) =
  uciState.stopFlag.store(true)
  if uciState.searchThread != nil:
    joinThread uciState.searchThread[]
  uciState.searchThread = nil

proc moves(
    history: seq[Position], params: seq[string], sanMoves = false
): seq[Position] =
  if params.len < 1:
    echo "Missing moves"

  doAssert history.len > 0

  result = history

  for i in 0 ..< params.len:
    let
      position = result[^1]
      move =
        if sanMoves:
          params[i].toMoveFromSAN(position)
        else:
          params[i].toMove(position)
    result.add position.doMove move

proc setPosition(uciState: var UciState, params: seq[string]) =
  var
    index = 0
    position: Position
  if params.len >= 1 and params[0] == "startpos":
    position = startpos
    index = 1
  elif params.len >= 1 and params[0] == "fen":
    var fen = ""
    index = 1
    var numFenWords = 0
    while params.len > index and params[index] != "moves":
      if numFenWords < 6:
        numFenWords += 1
        fen &= " " & params[index]
      index += 1
    position = fen.toPosition
  else:
    uciState.info "*Unknown parameters*"
    return

  if params.len > index and params[index] == "moves":
    index += 1
    uciState.history = moves(@[position], params[index ..^ 1])
  else:
    uciState.history = @[position]

proc runSearch(searchThreadInput: SearchThreadInput) {.thread, nimcall.} =
  searchThreadInput.searchRunningFlag[].store(true)
  uciSearch(searchThreadInput.searchInfo, searchThreadInput.uciCompatibleOutput)
  searchThreadInput.searchRunningFlag[].store(false)

proc go(uciState: var UciState, params: seq[string]) =
  var searchInfo = SearchInfo(
    positionHistory: uciState.history,
    hashTable: addr uciState.hashTable,
    targetDepth: Ply.high,
    stopFlag: addr uciState.stopFlag,
    movesToGo: int.high,
    increment: [white: 0.Seconds, black: 0.Seconds],
    timeLeft: [white: Seconds.high, black: Seconds.high],
    moveTime: Seconds.high,
    multiPv: uciState.multiPv,
    numThreads: uciState.numThreads,
    maxNodes: int.high,
  )

  for i in 0 ..< params.len:
    if i + 1 < params.len:
      case params[i]
      of "depth":
        searchInfo.targetDepth = params[i + 1].parseInt.clampToType(Ply)
      of "movestogo":
        searchInfo.movesToGo = params[i + 1].parseInt
      of "winc":
        searchInfo.increment[white] = Seconds(params[i + 1].parseFloat / 1000.0)
      of "binc":
        searchInfo.increment[black] = Seconds(params[i + 1].parseFloat / 1000.0)
      of "wtime":
        searchInfo.timeLeft[white] = Seconds(params[i + 1].parseFloat / 1000.0)
      of "btime":
        searchInfo.timeLeft[black] = Seconds(params[i + 1].parseFloat / 1000.0)
      of "movetime":
        searchInfo.moveTime = Seconds(params[i + 1].parseFloat / 1000.0)
      of "nodes":
        searchInfo.maxNodes = params[i + 1].parseBiggestInt
      else:
        discard
    try:
      let move = params[i].toMove(uciState.currentPosition)
      searchInfo.searchMoves.incl move
    except CatchableError:
      discard

  uciState.stop()

  doAssert uciState.searchThread == nil
  uciState.stopFlag.store(false)
  uciState.searchThread = new SearchThread
  createThread(
    uciState.searchThread[],
    runSearch,
    (
      searchInfo: searchInfo,
      uciCompatibleOutput: uciState.uciCompatibleOutput,
      searchRunningFlag: addr uciState.searchRunningFlag,
    ),
  )

proc uciNewGame(uciState: var UciState) =
  if uciState.searchRunningFlag.load:
    uciState.info "*Can't start new UCI game when search is still running*"
  else:
    uciState.hashTable.clear()

proc perft(uciState: UciState, params: seq[string]) =
  if params.len >= 1:
    let
      start = secondsSince1970()
      nodes =
        uciState.currentPosition.perft(params[0].parseInt, printRootMoveNodes = true)
      s = secondsSince1970() - start
    uciState.info fmt"**{nodes}** nodes in **{s.float:0.3f}** seconds"
    uciState.info fmt"**{(nodes.float / s.float).int}** nodes per second"
  else:
    uciState.info "*Missing depth parameter*"

proc uciLoop*() =
  printLogo()

  var uciState = UciState(
    history: @[startpos],
    hashtable: newHashTable(),
    numThreads: defaultNumThreads,
    multiPv: 1,
  )
  uciState.searchRunningFlag.store(false)
  uciState.hashTable.setByteSize(sizeInBytes = defaultHashSizeMB * megaByteToByte)

  while true:
    try:
      let command = readLine(stdin)
      let params = command.splitWhitespace()
      if params.len == 0 or params[0] == "":
        continue
      case params[0]
      of "uci":
        uciState.uci()
      of "setoption":
        uciState.setOption(params[1 ..^ 1])
      of "isready":
        echo "readyok"
      of "position":
        uciState.setPosition(params[1 ..^ 1])
      of "go":
        uciState.go(params[1 ..^ 1])
      of "stop":
        uciState.stop()
      of "quit":
        uciState.stop()
        break
      of "ucinewgame":
        uciState.uciNewGame()
      of "moves":
        uciState.history = moves(uciState.history, params[1 ..^ 1])
      of "multipv", "hash", "threads":
        if params.len >= 2:
          uciState.setOption(@["name", params[0], "value", params[1]])
        else:
          uciState.info "*Missing value parameter*"
      of "print":
        if params.len >= 2 and params[1] == "debug":
          echo uciState.currentPosition.debugString
        else:
          echo uciState.currentPosition
      of "fen":
        uciState.info uciState.currentPosition.fen
      of "perft":
        uciState.perft(params[1 ..^ 1])
      of "test":
        discard runTests()
      of "speedtest":
        speedPerftTest()
      of "eval":
        if params.len >= 2 and params[1] == "raw":
          uciState.info fmt"**{uciState.currentPosition.absoluteEvaluate}** from whites perspective"
        else:
          uciState.info fmt"**{uciState.currentPosition.absoluteEvaluate.toCp}** centipawns from whites perspective"
      of "piecevalues":
        for p in pawn .. queen:
          uciState.info fmt"{p}: **{p.value.toCp}** cp `({p.value})`"
      of "flip":
        if params.len <= 1:
          uciState.info "*Need additionaly parameter*"
        elif params[1] in "horizontally":
          uciState.history = @[uciState.currentPosition.mirrorHorizontally]
        elif params[1] in "vertically":
          uciState.history = @[uciState.currentPosition.mirrorVertically]
        else:
          uciState.info fmt"*Unknown parameter:* {params[1]}"
      of "about":
        about(extra = params.len >= 1 and "extra" in params)
      of "poem":
        printPoem()
      of "help":
        help(params[1 ..^ 1])
      else:
        try:
          uciState.history = moves(uciState.history, params)
        except CatchableError:
          try:
            uciState.history = moves(uciState.history, params, sanMoves = true)
          except CatchableError:
            try:
              uciState.setPosition(@["fen"] & params)
            except CatchableError:
              uciState.info fmt"*Unknown command:* {params[0]}"
              uciState.info "*Use* `help`"
    except EOFError:
      uciState.info "*Quitting because of reaching end of file*"
      break
    except CatchableError:
      uciState.info fmt"*Error:* {getCurrentExceptionMsg()}"

  doAssert uciState.searchThread == nil
