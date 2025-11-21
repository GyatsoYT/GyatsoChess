import ../position, ../positionUtils

import std/[os, streams]

doAssert commandLineParams().len == 1, "Need file as commandline argument"

let fileName = commandLineParams()[0]

doAssert fileExists fileName, "File should exist"

var
  inFileStream = newFileStream(fileName, fmRead)
  content: seq[(Position, float32)]
  numSamples = 0

const numExamples = 10

while not inFileStream.atEnd:
  let
    position = inFileStream.readMinimalPosition.toPosition
    value = inFileStream.readFloat32
  content.add (position, value)
  numSamples += 1

  if content.len >= numExamples + 10_000:
    content = content[^numExamples ..^ 1]

for (position, value) in content[^min(numExamples, content.len - 1) ..^ 1]:
  echo "--------------"
  echo position
  echo value

echo numSamples, " positions"
