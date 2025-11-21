import mergeDuplicateAndSelect

import std/[osproc, strformat, times, os]

doAssert commandLineParams().len > 0,
  fmt"Usage: {getAppFilename()} input1.pgn input2.pgn ... inputN.pgn"

const
  workDir = "src/tuning/dataFromPGNsWorkDir/"
  outDir = "res/trainingSets/fens/"
  pgnExtractPath = "res/pgn-extract"

let
  startDate = now().format("yyyy-MM-dd-HH-mm-ss")
  outputFilename = fmt"{outDir}trainingSet_{startDate}.epd"

createDir outDir
doAssert not fileExists outputFilename,
  fmt"Can't overwrite existing file: {outputFilename}"

echo fmt"{outputFilename = }"

for pgnFilename in commandLineParams():
  doAssert not dirExists workDir,
    fmt"Temporary work directory already exists: {workDir}"
  createDir workDir

  echo "Using file: ", pgnFilename

  doAssert execCmd(
    fmt"./{pgnExtractPath} -s -Wepd {pgnFilename} -o {workDir}extracted.epd"
  ) == 0

  mergeDuplicateAndSelect(
    readFilename = workDir & "extracted.epd",
    writeFilename = outputFilename,
    selectFactor = 0.1,
    outFileMode = fmAppend,
  )
  removeDir workDir

echo "Finished :D"
