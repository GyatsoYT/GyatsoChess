import types, move, position, searchParams, utils, evaluation

import std/[math, algorithm, sugar]

#-------------- correction heuristic --------------#

type CorrHistory* = seq[array[white .. black, float]]

func newCorrHistory*(): CorrHistory =
  newSeq[array[white .. black, float]](65536)

func update*(
    h: var CorrHistory,
    position: Position,
    rawEval: Value,
    searchEval: Value,
    nodeType: NodeType,
    depth: Ply,
) =
  let diff = searchEval - rawEval

  if (nodeType == upperBound and searchEval >= rawEval) or
      (nodeType == lowerBound and searchEval <= rawEval) or
      searchEval.abs >= valueCheckmate or position.inCheck(position.us):
    # or diff.abs >= 200.cp:
    return

  let
    key = position.pawnKey
    index = key.uint64 mod h.len.uint64
    weight = min(depth.float + 1.0, 16.0)
    decay = 1.0 - weight / 256.0

  doAssert 0.0 < decay and decay < 1.0

  # debugEcho decay

  template entry(): auto =
    h[index][position.us]

  entry *= decay
  entry += (1.0 - decay) * diff.float

func getCorrEval*(h: CorrHistory, position: Position, rawEval: Value): Value =
  let
    key = position.pawnKey
    index = key.uint64 mod h.len.uint64

  template entry(): auto =
    h[index][position.us]

  result = clampToType(rawEval.int + (entry / 2.0).int, Value)
  # debugEcho "result: ", result, ", rawEval: ", rawEval, ", entry: ", entry

#-------------- history heuristic --------------#

type
  HistoryArray = array[white .. black, array[pawn .. king, array[a1 .. h8, float]]]
  HistoryTable* = object
    table: HistoryArray
    counterTable: ref array[pawn .. king, array[a1 .. h8, HistoryArray]]

func newHistoryTable*(): HistoryTable =
  result = default(HistoryTable)
  # allocating this on the heap, as it is too big for the stack
  result.counterTable = new array[pawn .. king, array[a1 .. h8, HistoryArray]]

func halve(table: var HistoryArray, color: Color) =
  for piece in pawn .. king:
    for square in a1 .. h8:
      table[color][piece][square] /= historyTableShrinkDiv()

func update*(
    historyTable: var HistoryTable,
    move, previous: Move,
    color: Color,
    depth: Ply,
    raisedAlpha: bool,
) =
  if move.isTactical:
    return

  doAssert move.moved in pawn .. king, "Is move a noMove? " & $(move == noMove)
  doAssert historyTable.counterTable != nil

  func add(table: var HistoryArray, color: Color, move: Move, addition: float) =
    template entry(): auto =
      table[color][move.moved][move.target]

    if (entry >= 0) != (addition >= 0):
      entry *= historyTableUnexpectedDivider()
      discard

    entry = clamp(
      entry + addition, -maxHistoryTableValue().float, maxHistoryTableValue().float
    )

    if entry.abs >= maxHistoryTableValue().float:
      table.halve(color)

  let addition =
    (if raisedAlpha: 1.0 else: -1.0 / historyTableBadMoveDivider()) * depth.float ^ 2

  historyTable.table.add(color, move, addition)

  if previous.moved in pawn .. king and previous.target in a1 .. h8:
    historyTable.counterTable[][previous.moved][previous.target].add(
      color, move, addition * historyTableCounterMul()
    )

func get*(historyTable: HistoryTable, move, previous: Move, color: Color): -1.0 .. 1.0 =
  var sum = historyTable.table[color][move.moved][move.target]

  if previous.moved in pawn .. king and previous.target in a1 .. h8:
    sum +=
      historyTable.counterTable[][previous.moved][previous.target][color][move.moved][
        move.target
      ]

  sum / (2 * maxHistoryTableValue().float)

#-------------- killer heuristic --------------#

type KillerTable* = object
  table: array[Ply, Move]

func update*(killerTable: var KillerTable, height: Ply, move: Move) =
  if move.isTactical:
    return

  killerTable.table[height] = move

func get*(killerTable: var KillerTable, height: Ply): Move =
  killerTable.table[height]


#-------------- repetition detection --------------#

type GameHistory* = object
  staticHistory: seq[ZobristKey]
  dynamicHistory: array[Ply, ZobristKey]

func newGameHistory*(staticHistory: seq[Position]): GameHistory =
  result = default(GameHistory)
  for position in staticHistory:
    doAssert position.zobristKeysAreOk
    result.staticHistory.add(position.zobristKey)

func checkForRepetitionAndAdd*(
    gameHistory: var GameHistory, position: Position, height: Ply
): bool =
  gameHistory.dynamicHistory[height] = position.zobristKey

  var count = position.halfmoveClock
  for i in countdown(height - 1.Ply, 1.Ply):
    if count <= 0:
      return false
    if position.zobristKey == gameHistory.dynamicHistory[i]:
      return true
    count -= 1

  for i in countdown(gameHistory.staticHistory.len - 1, 0):
    if count <= 0:
      return false
    if position.zobristKey == gameHistory.staticHistory[i]:
      return true
    count -= 1
  false
