import
  types, move, position, positionUtils, timeManagedSearch, hashTable, evaluation, utils

import std/[terminal, strformat, strutils, algorithm, sugar, random]

func stringForHuman(time: Seconds): string =
  if time < 1.Seconds:
    fmt"{int(time * 1000.0)} ms"
  elif time < 10.Seconds:
    fmt"{time.float:.1f} s"
  elif time < 300.Seconds:
    fmt"{int(time)} s"
  else:
    fmt"{int(time / 60.0)} min"

func stringForHuman(n: SomeInteger): string =
  if n < 100_000: # up to 99,999
    $n
  elif n < 10_000_000: # up to 10,000k
    $(n div 1000) & "k"
  elif n < 10_000_000_000: # up to 10,000M
    $(n div 1_000_000) & "M"
  else:
    $(n div 1_000_000_000) & "G"

type ScoreType = enum
  centipawnScore
  mating
  mated

func mateOrScore(value: Value): (ScoreType, int) =
  if abs(value) >= valueCheckmate:
    ((if value < 0: mated else: mating), (value.plysUntilCheckmate.float / 2.0).int)
  else:
    (centipawnScore, value.toCp)

proc printBeautifulSingleInfoString(
    value: Value,
    nodes: int,
    position: Position,
    pv: seq[Move],
    time: Seconds,
    hashFull: int,
    multiPvIndex = -1,
) =
  if multiPvIndex != -1:
    stdout.styledWrite fmt"{multiPvIndex+1:>2}. "

  let
    color =
      if value.abs <= 10.cp:
        fgDefault
      elif value > 0:
        fgGreen
      else:
        fgRed
    style: set[Style] =
      if value.abs >= 100.cp:
        {styleBright}
      elif value.abs <= 20.cp:
        {styleDim}
      else:
        {}
    (scoreType, scoreValue) = value.mateOrScore

  if scoreType == centipawnScore:
    let scoreString =
      (if scoreValue > 0: "+" else: "") & fmt"{scoreValue.float / 100.0:.2f}"
    stdout.styledWrite style, color, fmt"{scoreString:>10} "
  else:
    let extra = if scoreType == mating: ":D" else: ":("
    stdout.styledWrite styleBright,
      color, fmt"    #{scoreValue}  ", resetStyle, color, styleDim, extra

  stdout.styledWrite "    ", styleBright, styleItalic, pv[0].toSAN(position)
  if pv.len > 1:
    stdout.styledWrite " ", pv[1 ..^ 1].notationSAN(position.doMove pv[0])

proc printBeautifulInfoString(
    iteration: int,
    position: Position,
    pvList: seq[Pv],
    nodes: int,
    time: Seconds,
    hashFull: int,
) =
  let kiloNps = (nodes.float / max(0.0001, time.float)).int div 1_000

  stdout.styledWrite styleDim,
    "iteration ", resetStyle, styleBright, fmt"{iteration+1:>3} "

  stdout.styledWrite styleDim, fmt"{time.stringForHuman:>10} "
  stdout.styledWrite styleDim, styleBright, fmt"{nodes.stringForHuman:>9}"
  stdout.styledWrite styleDim, " nodes "
  stdout.styledWrite styleDim, styleBright, fmt"{kiloNps:>7}"
  stdout.styledWrite styleDim, " knps "
  stdout.styledWrite styleDim, fmt"    TT: {hashFull div 10:>3}% "

  if pvList.len > 1:
    for i, pv in pvList:
      stdout.write "\n  "
      printBeautifulSingleInfoString(
        value = pv.value,
        nodes = nodes,
        position = position,
        pv = pv.pv,
        time = time,
        hashFull = hashFull,
        multiPvIndex = i,
      )
  else:
    doAssert pvList.len >= 1
    printBeautifulSingleInfoString(
      value = pvList[0].value,
      nodes = nodes,
      position = position,
      pv = pvList[0].pv,
      time = time,
      hashFull = hashFull,
    )

  echo ""

proc printInfoString(
    iteration: int,
    value: Value,
    nodes: int,
    position: Position,
    pv: seq[Move],
    time: Seconds,
    hashFull: int,
    multiPvIndex: int,
) =
  proc printKeyValue(key, value: string) =
    stdout.write " ", key, " ", value

  stdout.write "info"

  if multiPvIndex != -1:
    printKeyValue "multipv", fmt"{multiPvIndex:>2}"
  printKeyValue "depth", fmt"{iteration+1:>2}"
  printKeyValue "time", fmt"{int(time * 1000.0):>6}"
  printKeyValue "nodes", fmt"{nodes:>9}"

  let nps = int(nodes.float / max(0.0001, time.float))
  printKeyValue "nps", fmt"{nps:>7}"

  printKeyValue "hashfull", fmt"{hashFull:>4}"

  let (scoreType, scoreValue) = value.mateOrScore

  if scoreType == centipawnScore:
    printKeyValue "score cp", fmt"{scoreValue:>4}"
  else:
    stdout.write " ", (if scoreType == mated: "score mate -" else: "score mate "), scoreValue

  printKeyValue "pv", pv.notation(position)

  echo ""

proc printInfoString(
    iteration: int,
    position: Position,
    pvList: seq[Pv],
    nodes: int,
    time: Seconds,
    hashFull: int,
    beautiful: bool,
) =
  doAssert pvList.isSorted((x, y) => cmp(x.value, y.value), Descending)

  if beautiful:
    printBeautifulInfoString(
      iteration = iteration,
      position = position,
      pvList = pvList,
      nodes = nodes,
      time = time,
      hashFull = hashFull,
    )
  else:
    for i, pv in pvList:
      printInfoString(
        iteration = iteration,
        value = pv.value,
        position = position,
        pv = pv.pv,
        nodes = nodes,
        time = time,
        hashFull = hashFull,
        multiPvIndex =
          if pvList.len > 1:
            i + 1
          else:
            -1,
      )

proc bestMoveString(move: Move, position: Position): string =
  # king's gambit
  var r = initRand(secondsSince1970().int64)
  if r.rand(1.0) < 0.5:
    if "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1".toPosition == position:
      return "bestmove e2e4"
    if "rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq e6 0 2".toPosition ==
        position:
      return "bestmove f2f4"

  let moveNotation = move.notation(position)
  if move in position.legalMoves:
    return "bestmove " & moveNotation
  else:
    result = "info string found illegal move: " & moveNotation & "\n"
    if position.legalMoves.len > 0:
      result &= "bestmove " & position.legalMoves[0].notation(position)
    else:
      result &= "info string no legal move available"

proc uciSearch*(searchInfo: SearchInfo, uciCompatibleOutput: bool) =
  doAssert searchInfo.multiPv > 0
  doAssert searchInfo.positionHistory.len >= 1,
    "Need at least the current position in positionHistory"

  let position = searchInfo.positionHistory[^1]

  var
    bestMove = noMove
    iteration = 0

  if position.legalMoves.len == 0:
    echo "info string why are you asking me this, the game is LITERALLY OVER what do you want from me"
    echo "0000"
    return

  for (pvList, nodes, passedTime) in searchInfo.iterativeTimeManagedSearch():
    let pvList = pvList.sorted((x, y) => cmp(x.value, y.value), Descending)
    doAssert pvList.len >= 1
    doAssert pvList[0].pv.len >= 1
    bestMove = pvList[0].pv[0]

    # uci info
    printInfoString(
      iteration = iteration,
      position = position,
      pvList = pvList,
      nodes = nodes,
      time = passedTime,
      hashFull = searchInfo.hashTable[].hashFull,
      beautiful = not uciCompatibleOutput,
    )

    iteration += 1

  echo bestMove.bestMoveString(position)
