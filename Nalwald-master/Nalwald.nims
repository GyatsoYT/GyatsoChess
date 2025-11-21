import src/version

import std/[strutils, strformat]

#!fmt: off

# Default flags
--mm:arc
--define:useMalloc
--cc:clang
--threads:on
--styleCheck:hint

var threadPoolSize = 128

doAssert defined(linux) or not (defined(halfCPU) or defined(almostFullCPU)), "Switches halfCPU and almostFullCPU are only supported on Linux"

if defined(halfCPU):
  threadPoolSize = max(1, staticExec("nproc").parseInt div 2)
elif defined(almostFullCPU):
  threadPoolSize = max(1, staticExec("nproc").parseInt - 2)

switch("define", fmt"ThreadPoolSize={threadPoolSize}")

func lto() =
  --passC:"-flto"
  --passL:"-flto"

  if defined(windows):
    --passL:"-fuse-ld=lld"

func highPerformance() =
  --panics:on
  --define:danger
  lto()

func lightDebuggerInfo() =
  --passC:"-fno-omit-frame-pointer -g"

func fullDebuggerInfo() =
  lightDebuggerInfo()
  --debugger:native

let
  projectNimFile = "src/Nalwald.nim"
  suffix = if defined(windows): ".exe" else: ""
  binDir = "bin/"

proc setBinaryName(name: string) =
  switch("o", binDir & name & suffix)

task debug, "debug compile":
  --define:debug
  --passC:"-O2"
  fullDebuggerInfo()
  setBinaryName(projectName() & "-debug")
  setCommand "c", projectNimFile

task checks, "checks compile":
  --define:release
  fullDebuggerInfo()
  setBinaryName(projectName() & "-checks")
  setCommand "c", projectNimFile

task profile, "profile compile":
  highPerformance()
  fullDebuggerInfo()
  setBinaryName(projectName() & "-profile")
  setCommand "c", projectNimFile

task default, "default compile":
  lightDebuggerInfo()
  highPerformance()
  setBinaryName(projectName())
  setCommand "c", projectNimFile

task native, "native compile":
  highPerformance()
  --passC:"-march=native"
  --passC:"-mtune=native"
  setBinaryName(projectName() & "-native")
  setCommand "c", projectNimFile

task modern, "BMI2 and POPCNT compile":
  highPerformance()
  --passC:"-mbmi2"
  --passC:"-mpopcnt"
  setBinaryName(projectName() & "-modern")
  setCommand "c", projectNimFile

task genData, "Generates training data by playing games":
  highPerformance()
  --passC:"-march=native"
  --passC:"-mtune=native"
  # --define:release
  setBinaryName("genData")
  setCommand "c", "src/tuning/generateTrainingData.nim"

task dataFromPGNs, "Converts a number of PGN files into training data":
  highPerformance()
  setBinaryName("dataFromPGNs")
  setCommand "c", "src/tuning/trainingDataFromPGNs.nim"

task tuneEvalParams, "Optimizes eval parameters":
  highPerformance()
  --passC:"-march=native"
  --passC:"-mtune=native"
  setBinaryName("tuneEvalParams")
  setCommand "c", "src/tuning/optimization.nim"

task checkTuneEvalParams, "Optimizes eval parameters":
  --define:release
  setBinaryName("tuneEvalParams")
  setCommand "c", "src/tuning/optimization.nim"

task runWeatherFactory, "Optimizes search parameters":
  --define:tunableSearchParams
  --define:release
  setBinaryName("runWeatherFactory")
  setCommand "c", "src/tuning/runWeatherFactory.nim"

task sprt, "Runs an SPRT test of the current branch against the main branch":
  --define:release
  setBinaryName("sprt")
  setCommand "c", "src/testing/runSprtTest.nim"

task bench, "Runs a bench test of the current branch against a selected branch or commit":
  --define:release
  setBinaryName("bench")
  setCommand "c", "src/testing/runBenchTestAgainstBranch.nim"

task tests, "Runs tests in release mode":
  --define:release
  switch("define", "maxNumPerftNodes=1_000_000")
  setBinaryName("tests")
  setCommand "c", "src/testing/tests.nim"

task testsDanger, "Runs tests in danger mode":
  highPerformance()
  --passC:"-march=native"
  --passC:"-mtune=native"
  switch("define", "maxNumPerftNodes=10_000_000")
  setBinaryName("testsDanger")
  setCommand "c", "src/testing/tests.nim"

#!fmt: on
