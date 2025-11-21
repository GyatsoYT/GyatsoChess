import ../searchParams

import std/[osproc, os, strformat]

const
  minNumGames = 24
  tc = 8
  hash = 32
  weatherFactoryUrl = "https://github.com/tsoj/weather-factory.git"
  weatherFactoryCommit = "patch-3"
  workDir = "src/tuning/weather-factory/"
  useFastchess = true
  openingBook = "Pohl.epd"

let
  outGamesFile = getCurrentDir() & "/res/pgns/weatherReport.pgn"
  numThreads = max(1, ((countProcessors() - 2) div 2) * 2)
  numGames = block:
    var numGames = 0
    while numGames < minNumGames:
      numGames += numThreads
    numGames

if not dirExists workDir:
  doAssert execCmd(&"git clone \"{weatherFactoryUrl}\" {workDir}") == 0
  doAssert execCmd(fmt"git -C {workDir} checkout {weatherFactoryCommit}") == 0

removeDir workDir & "tuner"
createDir workDir & "tuner"

doAssert execCmd("nim native -f -d:tunableSearchParams Nalwald") == 0
copyFileWithPermissions "bin/Nalwald-native", workDir & "tuner/Nalwald-native"

copyFile "res/openings/" & openingBook, workDir & "tuner/" & openingBook

setCurrentDir workDir

writeFile "config.json", getWeatherFactoryConfig()

writeFile "cutechess.json",
  fmt"""{{
    "engine": "Nalwald-native",
    "book": "{openingBook}",
    "games": {numGames},
    "tc": {tc},
    "hash": {hash},
    "threads": {numThreads},
    "pgnout": "{outGamesFile}",
    "use_fastchess": {useFastchess}
  }}"""

writeFile "spsa.json",
  fmt"""{{
      "a": 1.0,
      "c": 1.0,
      "A": 10000,
      "alpha": 0.601,
      "gamma": 0.102
  }}"""

doAssert execCmd(fmt"python3 main.py") == 0
