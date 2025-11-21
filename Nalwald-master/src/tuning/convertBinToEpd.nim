import ../position, ../positionUtils

import std/[strformat, os, streams]

proc binToEpd*(inFileName, outFileName: string, maxLen = int.high) =
  doAssert fileExists inFileName, "Input file should exist"
  doAssert not fileExists outFileName, "Output file should not exist"

  var
    inFileStream = newFileStream(inFileName, fmRead)
    outFileStream = open(outFileName, fmWrite)
    numEntries = 0

  while not inFileStream.atEnd:
    let
      position = inFileStream.readMinimalPosition.toPosition
      value = inFileStream.readFloat32

    if position[king, white].countSetBits != 1 or position[king, black].countSetBits != 1:
      continue

    outFileStream.writeLine fmt"{position.fen} {value}"
    numEntries += 1

    if numEntries >= maxLen:
      break

  outFileStream.close()
  inFileStream.close()

  debugEcho outFileName & ": ", numEntries, " entries"

binToEpd "trainingSets/trainingSet_2023-12-22-19-19-13.bin",
  "trainingSets/trainingSet_2023-12-22-19-19-13.epd"
