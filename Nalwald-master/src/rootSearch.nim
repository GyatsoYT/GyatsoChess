import types, position, positionUtils, move, search, hashTable, searchUtils, utils

import malebolgia

import std/[atomics, strformat, sets]

func launchSearch(position: Position, state: ptr SearchState, depth: Ply) =
  discard position.search(state[], depth = depth)
  state[].threadStop[].store(true)

type Pv* = object
  value*: Value
  pv*: seq[Move]

iterator iterativeDeepeningSearch*(
    positionHistory: seq[Position],
    hashTable: var HashTable,
    externalStopFlag: ptr Atomic[bool],
    targetDepth: Ply = Ply.high,
    numThreads = 1,
    maxNodes = int.high,
    stopTime = Seconds.high,
    multiPv = 1,
    searchMoves = initHashSet[Move](),
    evaluation: proc(position: Position): Value {.noSideEffect.},
): tuple[pvList: seq[Pv], nodes: int, canStop: bool] {.noSideEffect.} =
  {.cast(noSideEffect).}:
    doAssert positionHistory.len >= 1,
      "Need at least the current position in positionHistory"

    let
      position = positionHistory[^1]
      legalMoves = position.legalMoves

    if legalMoves.len == 0:
      yield (pvList: @[], nodes: 0'i64, canStop: true)
    elif empty(position[king, white]) or empty(position[king, black]):
      yield (
        pvList: @[Pv(value: 0.Value, pv: @[legalMoves[0]])], nodes: 0'i64, canStop: true
      )
    else:
      let
        numThreads = max(1, numThreads)
        gameHistory = newGameHistory(positionHistory)
      var
        totalNodes = 0'i64
        searchStates: seq[SearchState] = @[]
        threadpool = createMaster()
        threadStop = default(Atomic[bool])

      for _ in 0 ..< numThreads:
        searchStates.add SearchState(
          externalStopFlag: externalStopFlag,
          threadStop: addr threadStop,
          hashTable: addr hashTable,
          historyTable: newHistoryTable(),
          corrHist: newCorrHistory(),
          gameHistory: gameHistory,
          maxNodes: maxNodes,
          stopTime: stopTime,
          skipMovesAtRoot: @[],
          evaluation: evaluation,
        )

      hashTable.age()

      for depth in 1.Ply .. targetDepth:
        var
          foundCheckmate = false
          pvList: seq[Pv] = @[]
          skipMoves: seq[Move] = @[]
          multiPvNodes = 0'i64

        for move in position.legalMoves:
          if move notin searchMoves and searchMoves.len > 0:
            skipMoves.add move

        for multiPvNumber in 1 .. multiPv:
          for move in skipMoves:
            doAssert move in position.legalMoves

          if skipMoves.len == position.legalMoves.len:
            break

          if multiPvNumber > 1:
            let hashResult = hashTable.get(position.zobristKey)
            hashTable.remove(position.zobristKey)

          threadStop.store(false)

          for searchState in searchStates.mitems:
            searchState.skipMovesAtRoot = skipMoves
            searchState.countedNodes = 0
            searchState.maxNodes = (maxNodes - totalNodes) div numThreads

          if numThreads == 1:
            launchSearch(position, addr searchStates[0], depth)
          else:
            threadpool.awaitAll:
              for i in 0 ..< numThreads:
                threadpool.spawn launchSearch(position, addr searchStates[i], depth)

          for state in searchStates:
            totalNodes += state.countedNodes
            multiPvNodes += state.countedNodes

          var
            pv = hashTable.getPv(position)
            value = hashTable.get(position.zobristKey).value

          if pv.len == 0:
            debugEcho &"WARNING: Couldn't find PV at root node.\n{position.fen = }"
            doAssert position.legalMoves.len > 0
            pv = @[position.legalMoves[0]]

          skipMoves.add pv[0]

          pvList.add Pv(value: value, pv: pv)

          foundCheckmate = abs(value) >= valueCheckmate

          if externalStopFlag[].load or totalNodes >= maxNodes:
            break

        if pvList.len >= min(multiPv, legalMoves.len):
          yield (
            pvList: pvList,
            nodes: multiPvNodes,
            canStop: legalMoves.len == 1 or foundCheckmate,
          )

        if externalStopFlag[].load or totalNodes >= maxNodes:
          break
