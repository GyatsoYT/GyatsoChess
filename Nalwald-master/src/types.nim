#!fmt: off
type Square* = enum
  a1, b1, c1, d1, e1, f1, g1, h1,
  a2, b2, c2, d2, e2, f2, g2, h2,
  a3, b3, c3, d3, e3, f3, g3, h3,
  a4, b4, c4, d4, e4, f4, g4, h4,
  a5, b5, c5, d5, e5, f5, g5, h5,
  a6, b6, c6, d6, e6, f6, g6, h6,
  a7, b7, c7, d7, e7, f7, g7, h7,
  a8, b8, c8, d8, e8, f8, g8, h8,
  noSquare
#!fmt: on

type
  Color* = enum
    white
    black
    noColor

  Piece* = enum
    pawn
    knight
    bishop
    rook
    queen
    king
    noPiece

  ColoredPiece* = object
    piece*: Piece
    color*: Color

  Ply* = 0.int8 .. int8.high
  Value* = int32
  NodeType* = enum
    pvNode
    allNode
    cutNode

  GamePhase* = 0 .. 32
  Phase* = enum
    opening
    endgame

  ZobristKey* = uint64

template isLeftEdge*(square: Square): bool =
  square.int8 mod 8 == 0

template isRightEdge*(square: Square): bool =
  square.int8 mod 8 == 7

template isUpperEdge*(square: Square): bool =
  square >= a8

template isLowerEdge*(square: Square): bool =
  square <= h1

template isEdge*(square: Square): bool =
  square.isLeftEdge or square.isRightEdge or square.isUpperEdge or square.isLowerEdge

func color*(square: Square): Color =
  if (square.int8 div 8) mod 2 == (square.int8 mod 8) mod 2:
    return black
  white

template up*(square: Square): Square =
  (square.int8 + 8).Square

template down*(square: Square): Square =
  (square.int8 - 8).Square

template left*(square: Square): Square =
  (square.int8 - 1).Square

template right*(square: Square): Square =
  (square.int8 + 1).Square

template up*(square: Square, color: Color): Square =
  if color == white: square.up else: square.down

func goUp*(square: var Square): bool =
  if square.isUpperEdge or square == noSquare:
    return false
  square = square.up
  true
func goDown*(square: var Square): bool =
  if square.isLowerEdge or square == noSquare:
    return false
  square = square.down
  true
func goLeft*(square: var Square): bool =
  if square.isLeftEdge or square == noSquare:
    return false
  square = square.left
  true
func goRight*(square: var Square): bool =
  if square.isRightEdge or square == noSquare:
    return false
  square = square.right
  true
func goNothing*(square: var Square): bool =
  true

func mirrorVertically*(square: Square): Square =
  (square.int8 xor 56).Square

func mirrorHorizontally*(square: Square): Square =
  (square.int8 xor 7).Square

func opposite*(color: Color): Color =
  (color.uint8 xor 1).Color

func `-`*(a: Ply, b: SomeNumber or Ply): Ply =
  max(a.BiggestInt - b.BiggestInt, Ply.low.BiggestInt).Ply
func `-`*(a: SomeNumber, b: Ply): Ply =
  max(a.BiggestInt - b.BiggestInt, Ply.low.BiggestInt).Ply

func `+`*(a: Ply, b: SomeNumber or Ply): Ply =
  min(a.BiggestInt + b.BiggestInt, Ply.high.BiggestInt).Ply
func `+`*(a: SomeNumber, b: Ply): Ply =
  min(a.BiggestInt + b.BiggestInt, Ply.high.BiggestInt).Ply

func `-=`*(a: var Ply, b: Ply or SomeNumber) =
  a = a - b
func `+=`*(a: var Ply, b: Ply or SomeNumber) =
  a = a + b

const
  valueInfinity* = min(-(int16.low.Value), int16.high.Value)
  valueCheckmate* = valueInfinity - Ply.high.Value - 1.Value

func checkmateValue*(height: Ply): Value =
  valueCheckmate + (Ply.high - height).Value

func plysUntilCheckmate*(value: Value): Ply =
  (-(((abs(value.int32) - (valueCheckmate.int32 + Ply.high.int32))))).Ply

static:
  doAssert -valueInfinity <= valueInfinity
  doAssert Ply.high.checkmateValue >= valueCheckmate
  doAssert Ply.low.checkmateValue < valueInfinity
  doAssert 0.Ply.checkmateValue.plysUntilCheckmate == 0.Ply and
    1.Ply.checkmateValue.plysUntilCheckmate == 1.Ply and
    9.Ply.checkmateValue.plysUntilCheckmate == 9.Ply and
    10.Ply.checkmateValue.plysUntilCheckmate == 10.Ply and
    100.Ply.checkmateValue.plysUntilCheckmate == 100.Ply and
    100.Ply.checkmateValue < 99.Ply.checkmateValue

func `^=`*(a: var ZobristKey, b: ZobristKey) =
  a = a xor b

const
  exact* = pvNode
  upperBound* = allNode
  lowerBound* = cutNode
