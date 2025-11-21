import ../timeManagedSearch, ../hashTable, ../utils, ../positionUtils

import std/[os, strutils]

doAssert commandLineParams().len == 7,
  "Need the following parameters in that order: depth fen"

let
  depth = commandLineParams()[0].parseInt.clampToType(Ply)
  fen = block:
    var fen = ""
    for i in 1 .. 6:
      fen &= commandLineParams()[i] & " "
    fen

const
  hashSizeMB = 32
  hardTimeLimit = 100.Seconds

var ht = newHashTable()

ht.setByteSize megaByteToByte * hashSizeMB

var totalNodes = 0
for (pvList, nodes, passedTime) in iterativeTimeManagedSearch(
  SearchInfo(
    positionHistory: @[fen.toPosition],
    hashTable: addr ht,
    moveTime: hardTimeLimit,
    targetDepth: depth,
  )
):
  totalNodes += nodes

echo totalNodes
