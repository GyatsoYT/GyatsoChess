import types

import std/[options, strutils, times, os, osproc, math, macros]

const megaByteToByte* = 1_048_576

func boardString*(f: proc(square: Square): Option[string] {.noSideEffect.}): string =
  result = " _ _ _ _ _ _ _ _\n"
  for rank in countdown(7, 0):
    for file in 0 .. 7:
      result &= "|"
      let s = f((8 * rank + file).Square)
      if s.isSome:
        result &= s.get()
      else:
        result &= "_"
    result &= "|" & intToStr(rank + 1) & "\n"
  result &= " A B C D E F G H"

func notation*(piece: Piece): string =
  case piece
  of pawn: "p"
  of knight: "n"
  of bishop: "b"
  of rook: "r"
  of queen: "q"
  of king: "k"
  of noPiece: "-"

func notation*(coloredPiece: ColoredPiece): string =
  result = coloredPiece.piece.notation
  if coloredPiece.color == white:
    result = result.toUpperAscii

func `$`*(coloredPiece: ColoredPiece): string =
  const t = [
    white: [
      pawn: "♟", knight: "♞", bishop: "♝", rook: "♜", queen: "♛", king: "♚"
    ],
    black: [
      pawn: "♙", knight: "♘", bishop: "♗", rook: "♖", queen: "♕", king: "♔"
    ],
  ]
  if coloredPiece.piece == noPiece or coloredPiece.color == noColor:
    return " "
  return t[coloredPiece.color][coloredPiece.piece]

func toColoredPiece*(s: char): ColoredPiece =
  var piece: Piece
  case s
  of 'P', 'p':
    piece = pawn
  of 'N', 'n':
    piece = knight
  of 'B', 'b':
    piece = bishop
  of 'R', 'r':
    piece = rook
  of 'Q', 'q':
    piece = queen
  of 'K', 'k':
    piece = king
  else:
    raise newException(ValueError, "Piece notation doesn't exists: " & s)

  let color = if s.isLowerAscii: black else: white
  ColoredPiece(color: color, piece: piece)

func interpolate*[T](gamePhase: GamePhase, forOpening, forEndgame: T): T =
  type I = (when T is SomeInteger: BiggestInt else: float)

  var tmp: I
  tmp =
    forOpening.I * (gamePhase - GamePhase.low).I +
    forEndgame.I * (GamePhase.high - gamePhase).I
  when T is SomeInteger:
    tmp = tmp div (GamePhase.high - GamePhase.low).I
  else:
    tmp = tmp / (GamePhase.high - GamePhase.low).T

  result = tmp.T

func clampToType*[In, Out](x: In, OutType: typedesc[Out]): Out =
  x.clamp(OutType.low.In, OutType.high.In).Out

proc getCpuInfo*(): string =
  when defined(posix):
    var cpuName = execCmdEx(
      """
        cat /proc/cpuinfo | awk -F '\\s*: | @' '/model name|Hardware|Processor|^cpu model|chip type|^cpu type/ { cpu=$2; if ($1 == "Hardware") exit } END { print cpu }' "$cpu_file"
        """
    ).output
    return cpuName.strip

proc askYesNo*(question: string): bool =
  while true:
    stdout.write question, " [y/n] "
    stdout.flushFile
    let answer = readLine(stdin).strip.toLowerAscii
    if answer == "y":
      return true
    if answer == "n":
      return false
  false

func error*(outcome, estimate: float): float =
  (outcome - estimate) ^ 2

func errorDerivative*(outcome, estimate: float): float =
  2.0 * (outcome - estimate)

type Seconds* = distinct float

func `$`*(a: Seconds): string =
  $a.float & " s"

func high*(T: typedesc[Seconds]): Seconds =
  float.high.Seconds
func low*(T: typedesc[Seconds]): Seconds =
  float.low.Seconds

func `==`*(a, b: Seconds): bool {.borrow.}
func `<=`*(a, b: Seconds): bool {.borrow.}
func `<`*(a, b: Seconds): bool {.borrow.}

func `-`*(a, b: Seconds): Seconds {.borrow.}
func `+`*(a, b: Seconds): Seconds {.borrow.}
func `*`*(a: Seconds, b: SomeNumber): Seconds =
  Seconds(a.float * b.float)
func `*`*(a: SomeNumber, b: Seconds): Seconds =
  Seconds(a.float * b.float)
func `/`*(a: Seconds, b: SomeNumber): Seconds =
  Seconds(a.float / b.float)

func `+=`*(a: var Seconds, b: Seconds) =
  a = a + b
func `-=`*(a: var Seconds, b: Seconds) =
  a = a - b
func `*=`*(a: var Seconds, b: SomeNumber) =
  a = a * b
func `/=`*(a: var Seconds, b: SomeNumber) =
  a = a / b

func secondsSince1970*(): Seconds =
  {.cast(noSideEffect).}:
    epochTime().Seconds

macro lazyEval*(assignmentStmt: untyped): untyped =
  expectKind(assignmentStmt, nnkStmtList)
  expectLen(assignmentStmt, 1)

  let assignment = assignmentStmt[0]
  expectKind(assignment, nnkAsgn)

  let
    identifier = assignment[0]
    initExpr = assignment[1]
    storageIdent = genSym(nskVar, "lazy_" & $identifier)

  quote:
    var `storageIdent` = none(type(`initExpr`))
    template `identifier`(): auto =
      if `storageIdent`.isNone:
        `storageIdent` = some `initExpr`
      `storageIdent`.get()
