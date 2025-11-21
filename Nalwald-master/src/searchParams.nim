import types

import std/[tables, macros, typetraits, json, strformat]

const
  tunableSearchParams {.booldefine.} = false
  floatQuantizer = 1_000.0

type ParamEntry = object
  address: ptr int
  min: int
  max: int
  step: int

var paramTable: OrderedTable[string, ParamEntry]

proc getVarName(name: NimNode): NimNode =
  parseExpr($toStrLit(name) & "Var")

proc getVarString(name: NimNode): NimNode =
  parseExpr("\"" & $toStrLit(name) & "\"")

func getAsInt[T](a: T): int =
  when distinctBase(T) is SomeFloat:
    (a.float * floatQuantizer).int
  else:
    a.int

macro addParam[T](
    name: untyped, default, min, max, step: T, tunable: bool = true
): untyped =
  let
    varName: NimNode = getVarName(name)
    varString: NimNode = getVarString(name)
  quote:
    var `varName`: int = `default`.getAsInt

    if `tunable` and tunableSearchParams:
      paramTable[`varString`] = ParamEntry(
        address: addr `varName`,
        min: `min`.getAsInt,
        max: `max`.getAsInt,
        step: `step`.getAsInt,
      )

    func `name`*(): auto =
      type R = typeof(`default`)
      {.cast(noSideEffect).}:
        when distinctBase(R) is SomeFloat:
          R(R(`varName`).float / floatQuantizer)
        else:
          R(`varName`)

proc hasSearchOption*(name: string): bool =
  name in paramTable

proc setSearchOption*(name: string, value: int) =
  if name in paramTable:
    let allowedRange = paramTable[name].min .. paramTable[name].max
    if value notin allowedRange:
      raise newException(
        KeyError,
        "Parameter '" & name & "' doesn't allow values outside " & $allowedRange &
          " but value is '" & $value & "'",
      )
    paramTable[name].address[] = value
  else:
    raise newException(KeyError, "Parameter '" & name & "' doesn't exist")

proc printUciSearchParams*() =
  for name, param in paramTable:
    echo "option name ",
      name,
      " type spin default ",
      param.address[],
      " min ",
      param.min,
      " max ",
      param.max

#!fmt: off
addParam(deltaMargin, default = 41, min = 30, max = 300, step = 20)
addParam(failHighDeltaMargin, default = 73, min = 10, max = 200, step = 20)

addParam(aspirationWindowStartingOffset, default = 7, min = 2, max = 100, step = 3)
addParam(aspirationWindowMultiplier, default = 1.95, min = 1.1, max = 10.0, step = 0.2)

addParam(iirMinDepth, default = 4.Ply, min = 0.Ply, max = 12.Ply, step = 1.Ply)

addParam(futilityReductionDiv, default = 77, min = 10, max = 500, step = 30)
addParam(minMoveCounterFutility, default = 2, min = 1, max = 10, step = 1)

addParam(hashResultFutilityMarginMul, default = 298, min = 50, max = 1000, step = 30)

addParam(nullMoveDepthSub, default = 3.Ply, min = 0.Ply, max = 10.Ply, step = 1.Ply)
addParam(nullMoveDepthDiv, default = 3, min = 1, max = 15, step = 1)

addParam(rfpMarginMultiplier, default = 90, min = 10, max = 1000, step = 30)

addParam(minMoveCounterLmr, default = 4, min = 1, max = 15, step = 1)
addParam(lmrAddition, default = 1.73, min = -100.0, max = 100.0, step = 0.8)
addParam(lmrDivisor, default = 2.03, min = 0.1, max = 100.0, step = 0.5)

addParam(maxHistoryTableValue, default = 135000, min = 1000, max = 10000000, step = 40000)
addParam(historyTableBadMoveDivider, default = 24.0, min = 1.0, max = 100.0, step = 10.0)
addParam(historyTableCounterMul, default = 85.0, min = 1.0, max = 200.0, step = 20.0)
addParam(historyTableShrinkDiv, default = 2.2, min = 1.1, max = 10.0, step = 0.5)
addParam(historyTableUnexpectedDivider, default = 0.949, min = 0.1, max = 1.0, step = 0.1)
#!fmt: on

proc getWeatherFactoryConfig*(): string =
  result = "{"
  for name, param in paramTable:
    result &= "\"" & name & "\": {"
    result &=
      fmt"""
          "value": {param.address[]},
          "min_value": {param.min},
          "max_value": {param.max},
          "step": {param.step}
          """
    result &= "},"
  result &= "}"
  result = result.parseJson.pretty
