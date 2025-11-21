import
  ../evalParameters,
  ../evaluation,
  dataUtils,
  calculatePieceValue

import std/[times, strformat, random, math, os]

proc optimize(
    start: EvalParameters,
    data: var seq[Entry],
    maxNumEpochs = 30,
    startLr = 10.0,
    finalLr = 0.05,
): EvalParameters =
  var solution = start

  echo "starting error: ", fmt"{solution.error(data):>9.7f}", ", starting lr: ", startLr

  let lrDecay = pow(finalLr / startLr, 1.0 / float(maxNumEpochs * data.len))
  doAssert startLr > finalLr,
    "Starting learning rate must be strictly bigger than the final learning rate"
  doAssert finalLr == startLr or lrDecay < 1.0,
    "lrDecay should be smaller than one if the learning rate should decrease"

  var lr = startLr

  for epoch in 1 .. maxNumEpochs:
    let startTime = now()
    data.shuffle

    for entry in data:
      solution.addGradient(lr, entry.position, entry.outcome)
      lr *= lrDecay

    let
      error = solution.error(data[0 ..< min(data.len, 1_000_000)])
      passedTime = now() - startTime
    echo fmt"Epoch {epoch}, error: {error:>9.7f}, lr: {lr:.3f}, time: {passedTime.inSeconds} s"

  let finalError = solution.error(data)
  echo fmt"Final error: {finalError:>9.7f}"

  solution

let startTime = now()

var data: seq[Entry]
data.loadDataEpd "res/trainingSets/fens/quietSetNalwald.epd"
data.loadDataEpd "res/trainingSets/fens/quietSetCombinedCCRL4040.epd"
data.loadDataEpd "res/trainingSets/fens/quietSmallPoolGamesNalwald.epd"
data.loadDataEpd "res/trainingSets/fens/quietSetNalwald2.epd"
data.loadDataEpd "res/trainingSets/fens/quietLeavesSmallPoolGamesNalwaldSearchLabeled.epd"
data.loadDataEpd "res/trainingSets/fens/quietSmallPoolGamesNalwald2Labeled.epd"
data.loadDataEpd "res/trainingSets/fens/gamesNalwald.epd"

data.loadDataBin "res/trainingSets/trainingSet_2023-10-03-18-29-44.bin"
data.loadDataBin "res/trainingSets/trainingSet_2023-10-03-18-30-48.bin"
data.loadDataBin "res/trainingSets/trainingSet_2023-10-03-23-14-51.bin"
data.loadDataBin "res/trainingSets/trainingSet_2023-10-03-23-35-01.bin"
data.loadDataBin "res/trainingSets/trainingSet_2023-10-04-00-47-53.bin"
data.loadDataBin "res/trainingSets/trainingSet_2023-10-06-17-43-01.bin"

data.loadDataBin "res/trainingSets/trainingSet_2023-12-22-16-08-28.bin"
data.loadDataBin "res/trainingSets/trainingSet_2023-12-22-16-15-24.bin"
data.loadDataBin "res/trainingSets/trainingSet_2023-12-22-16-16-28.bin"
data.loadDataBin "res/trainingSets/trainingSet_2023-12-22-19-19-13.bin"
data.loadDataBin "res/trainingSets/trainingSet_2023-12-24-02-31-35.bin"
data.loadDataBin "res/trainingSets/trainingSet_2023-12-28-11-23-21.bin"

data.loadDataBin "res/trainingSets/trainingSet_2024-07-06-23-33-31_6000_427d23b.bin"
data.loadDataBin "res/trainingSets/trainingSet_2024-07-06-23-29-46_6000_427d23b.bin"
data.loadDataBin "res/trainingSets/trainingSet_2024-07-06-23-34-08_6000_427d23b.bin"
data.loadDataBin "res/trainingSets/trainingSet_2024-07-06-23-31-51_6000_427d23b.bin"

data.shuffle

echo "Total number of entries: ", data.len

var startEvalParams = newEvalParameters()
let ep = startEvalParams.optimize(data)

const
  epDir = "res/params/"
  epFileName = epDir & "default.bin"
  pieceValueFileName = "src/pieceValues.nim"

createDir epDir

let
  pieceValueString = ep.pieceValuesAsString(data[0 ..< min(data.len, 10_000_000)])
  pieceValueFileContent =
    &"""
import evalParameters

func value*(piece: Piece): Value =
  const table = [{pieceValueString}king: valueCheckmate, noPiece: 0.Value]
  table[piece]
"""

writeFile pieceValueFileName, pieceValueFileContent
echo "Wrote to: ", pieceValueFileName

writeFile epFileName, ep.toString
echo "Wrote to: ", epFileName

echo "Total time: ", now() - startTime
