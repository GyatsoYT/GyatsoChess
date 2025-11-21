import ../utils, ../types, exampleFens

import std/[osproc, os, strutils, strformat]

const
  mainBranch = "master"
  workDir = "src/testing/benchWorkdir/"
  minDepth = 12.Ply
  approxTimePerPosition = 3.Seconds

let otherBranch =
  if commandLineParams().len >= 1:
    commandLineParams()[0].strip
  else:
    if not askYesNo(
      question =
        "You have not specified a branch or commit to bench test against. Do you want to compare against the main branch?"
    ):
      quit(QuitFailure)
    mainBranch

let gitStatus = execProcess("git status")

doAssert "git version" in execProcess("git --version")
doAssert execProcess("git rev-parse --is-inside-work-tree").strip == "true"

doAssert "git version" in execProcess("git --version")
doAssert "not a git repository" notin gitStatus

let
  gitHasUnstagedChanges = execProcess("git status -suno").strip != ""
  currentBranch = execProcess("git rev-parse --abbrev-ref HEAD").strip

doAssert not gitHasUnstagedChanges, "Shouldn't do SPRT with unstaged changes"

if currentBranch == otherBranch:
  if not askYesNo(
    question =
      "You are about to bench test a branch against itself. Are you sure you want to do this?"
  ):
    quit(QuitFailure)

discard existsOrCreateDir workDir

proc benchTestBinaryFile(branch: string): string =
  fmt"{workDir}benchTest-{branch}"

try:
  for branch in [otherBranch, currentBranch]:
    if execCmd("git checkout " & branch) != 0:
      raise newException(CatchableError, "Failed to switch to branch " & branch)
    if execCmd(
      fmt"nim c -d:release -f -o:{benchTestBinaryFile(branch)} src/testing/benchTest.nim"
    ) != 0:
      raise newException(
        CatchableError, "Failed to compile bench test binary for branch " & branch
      )
finally:
  doAssert execCmd("git switch " & currentBranch) == 0

for fen in someFens:
  let start = secondsSince1970()
  stdout.write fen, " "
  stdout.flushFile
  for depth in 1.Ply .. Ply.high:
    stdout.write "."
    stdout.flushFile
    let nodesCurrent = execProcess(
      benchTestBinaryFile(currentBranch) & fmt" {depth} {fen}"
    ).strip.parseInt
    let nodesOther =
      execProcess(benchTestBinaryFile(otherBranch) & fmt" {depth} {fen}").strip.parseInt

    if nodesCurrent != nodesOther:
      echo &"\nNodes don't match for \"{fen}\".\n{currentBranch}: {nodesCurrent}\n{otherBranch}: {nodesOther}"
      quit(QuitFailure)

    if secondsSince1970() - start >= approxTimePerPosition and depth >= minDepth:
      break
  echo ""

echo "\nFinished bench test\n"
