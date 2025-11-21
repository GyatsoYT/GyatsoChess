import ../search, ../positionUtils, ../evaluation

import std/[tables, strutils, random, os]

const maxTableSize = 100_000_000 # TODO rather base it of available RAM

proc mergeDuplicateAndSelect*(
    readFilename: string,
    writeFilename: string,
    selectFactor: 0.0 .. 1.0,
    outFileMode: FileMode = fmWrite,
    useOnlyQuiet: bool = false,
) =
  doAssert selectFactor in 0.0 .. 1.0

  doAssert fileExists readFilename
  doAssert outFileMode == fmAppend or not fileExists writeFilename

  let f = open(readFilename)
  let g = open(writeFilename, outFileMode)

  var
    line = ""
    totalPositions = 0
    totalSelectedPositions = 0
  while not f.endOfFile:
    var
      table = default(Table[string, tuple[count: float, sum: float]])
      numInputPositions = 0

    while f.readLine(line):
      if line.isEmptyOrWhitespace:
        continue
      let words = line.splitWhitespace()
      doAssert words.len >= 7

      if words[^1] == "*;":
        continue
      let
        fen = words[0] & " " & words[1] & " " & words[2] & " " & words[3] & " 0 1"
        outcome =
          if words[^1] == "0-1;":
            0.0
          elif words[^1] == "1-0;":
            1.0
          elif words[^1] == "1/2-1/2;":
            0.5
          else:
            words[6].parseFloat
        position = fen.toPosition

      if useOnlyQuiet:
        if position.material != position.materialQuiesce:
          continue

        if position.legalMoves.len == 0:
          continue

      if fen in table:
        table[fen].count += 1
        table[fen].sum += outcome
      else:
        table[fen] = (count: 1.0, sum: outcome)
      numInputPositions += 1

      if (numInputPositions mod 100_000) == 0 or table.len >= maxTableSize:
        stdout.write "\rNum input positions: " & $numInputPositions
        stdout.flushFile

      if table.len >= maxTableSize:
        break

    echo "\nNum unique positions: ", table.len

    var numSelectedPositions = 0
    for fen, (count, sum) in table:
      if rand(1.0) <= selectFactor:
        numSelectedPositions += 1
        g.writeLine(fen & " " & $(sum / count))

    echo "Num selected positions: ", numSelectedPositions

    totalPositions += numInputPositions
    totalSelectedPositions += numSelectedPositions

  echo "Num total input positions: ", totalPositions
  echo "Num total selected positions: ", totalSelectedPositions

  f.close
  g.close
