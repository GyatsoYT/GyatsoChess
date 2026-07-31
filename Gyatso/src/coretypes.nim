
type
  Square* = distinct int8

const
  A1* = Square(0)
  B1* = Square(1)
  C1* = Square(2)
  D1* = Square(3)
  E1* = Square(4)
  F1* = Square(5)
  G1* = Square(6)
  H1* = Square(7)
  A2* = Square(8)
  B2* = Square(9)
  C2* = Square(10)
  D2* = Square(11)
  E2* = Square(12)
  F2* = Square(13)
  G2* = Square(14)
  H2* = Square(15)
  A3* = Square(16)
  B3* = Square(17)
  C3* = Square(18)
  D3* = Square(19)
  E3* = Square(20)
  F3* = Square(21)
  G3* = Square(22)
  H3* = Square(23)
  A4* = Square(24)
  B4* = Square(25)
  C4* = Square(26)
  D4* = Square(27)
  E4* = Square(28)
  F4* = Square(29)
  G4* = Square(30)
  H4* = Square(31)
  A5* = Square(32)
  B5* = Square(33)
  C5* = Square(34)
  D5* = Square(35)
  E5* = Square(36)
  F5* = Square(37)
  G5* = Square(38)
  H5* = Square(39)
  A6* = Square(40)
  B6* = Square(41)
  C6* = Square(42)
  D6* = Square(43)
  E6* = Square(44)
  F6* = Square(45)
  G6* = Square(46)
  H6* = Square(47)
  A7* = Square(48)
  B7* = Square(49)
  C7* = Square(50)
  D7* = Square(51)
  E7* = Square(52)
  F7* = Square(53)
  G7* = Square(54)
  H7* = Square(55)
  A8* = Square(56)
  B8* = Square(57)
  C8* = Square(58)
  D8* = Square(59)
  E8* = Square(60)
  F8* = Square(61)
  G8* = Square(62)
  H8* = Square(63)
  NoSquare* = Square(-1)

# Comparisons and operations on Square
func `==`*(a, b: Square): bool {.borrow.}
func `<`*(a, b: Square): bool {.borrow.}
func `<=`*(a, b: Square): bool {.borrow.}
func `>`*(a, b: Square): bool {.inline.} = not (a <= b)
func `>=`*(a, b: Square): bool {.inline.} = not (a < b)

func `+`*(a: Square, b: int): Square {.inline.} = Square(int8(a) + int8(b))
func `-`*(a: Square, b: int): Square {.inline.} = Square(int8(a) - int8(b))
func `+`*(a: Square, b: Square): Square {.inline.} = Square(int8(a) + int8(b))
func `-`*(a: Square, b: Square): Square {.inline.} = Square(int8(a) - int8(b))

# Rank and File accessors
func rank*(sq: Square): int {.inline.} =
  int(sq) div 8

func file*(sq: Square): int {.inline.} =
  int(sq) mod 8

func makeSquare*(rank, file: int): Square {.inline.} =
  Square(int8(rank * 8 + file))

func toAlgebraic*(sq: Square): string {.inline.} =
  if sq == NoSquare: return "-"
  let f = char(ord('a') + file(sq))
  let r = char(ord('1') + rank(sq))
  result = ""
  result.add(f)
  result.add(r)

func parseSquare*(s: string): Square {.inline.} =
  if s == "-" or s.len != 2: return NoSquare
  let f = ord(s[0]) - ord('a')
  let r = ord(s[1]) - ord('1')
  if f < 0 or f > 7 or r < 0 or r > 7: return NoSquare
  makeSquare(r, f)

func flipRank*(sq: Square): Square {.inline.} =
  Square(int8(sq) xor 56)

func flipFile*(sq: Square): Square {.inline.} =
  Square(int8(sq) xor 7)

func isValid*(sq: Square): bool {.inline.} =
  int8(sq) >= 0 and int8(sq) <= 63

# Colors
type
  Color* = enum
    White
    Black

func opposite*(c: Color): Color {.inline.} =
  Color(ord(c) xor 1)

# PieceTypes and Pieces
type
  PieceType* = enum
    Pawn
    Knight
    Bishop
    Rook
    Queen
    King
    NoPieceType

  Piece* = enum
    WhitePawn
    WhiteKnight
    WhiteBishop
    WhiteRook
    WhiteQueen
    WhiteKing
    BlackPawn
    BlackKnight
    BlackBishop
    BlackRook
    BlackQueen
    BlackKing
    NoPiece

func color*(p: Piece): Color {.inline, noSideEffect.} =
  if ord(p) < 6: White else: Black

func pieceType*(p: Piece): PieceType {.inline, noSideEffect.} =
  if p == NoPiece: NoPieceType
  else: PieceType(ord(p) mod 6)

func makePiece*(c: Color, pt: PieceType): Piece {.inline, noSideEffect.} =
  if pt == NoPieceType: NoPiece
  else: Piece(ord(c) * 6 + ord(pt))

# MoveType and PromoType
type
  MoveType* = enum
    Normal = 0
    Promotion = 1
    Castling = 2
    EnPassant = 3

  PromoType* = enum
    PromoKnight = 0
    PromoBishop = 1
    PromoRook = 2
    PromoQueen = 3

# Move Representation
# bits  0-1  : MoveType
# bits  2-3  : PromoType
# bits  4-9  : to square (6 bits)
# bits 10-15 : from square (6 bits)
type Move* = distinct uint16

func `==`*(a, b: Move): bool {.borrow.}

# Move Constructor Functions
func makeMove*( `from`, to: Square): Move {.inline.} =
  Move((uint16(`from`) shl 10) or (uint16(to) shl 4) or uint16(Normal))

func makePromo*( `from`, to: Square, promo: PromoType): Move {.inline.} =
  Move((uint16(`from`) shl 10) or (uint16(to) shl 4) or (uint16(promo) shl 2) or uint16(Promotion))

func makeCastle*( `from`, to: Square): Move {.inline.} =
  Move((uint16(`from`) shl 10) or (uint16(to) shl 4) or uint16(Castling))

func makeEnPassant*( `from`, to: Square): Move {.inline.} =
  Move((uint16(`from`) shl 10) or (uint16(to) shl 4) or uint16(EnPassant))

# Move Accessor Functions
func fromSq*(m: Move): Square {.inline, noSideEffect.} =
  Square((uint16(m) shr 10) and 0x3F)

func toSq*(m: Move): Square {.inline, noSideEffect.} =
  Square((uint16(m) shr 4) and 0x3F)

func moveType*(m: Move): MoveType {.inline, noSideEffect.} =
  MoveType(uint16(m) and 0x3)

func promoType*(m: Move): PromoType {.inline, noSideEffect.} =
  PromoType((uint16(m) shr 2) and 0x3)

func isPromotion*(m: Move): bool {.inline, noSideEffect.} =
  moveType(m) == Promotion

func isCastling*(m: Move): bool {.inline, noSideEffect.} =
  moveType(m) == Castling

func isEnPassant*(m: Move): bool {.inline, noSideEffect.} =
  moveType(m) == EnPassant

func isQuiet*(m: Move): bool {.inline, noSideEffect.} =
  let mt = moveType(m)
  mt == Normal or mt == Castling

# Null Move Constant
const NullMove* = Move(0)

# MoveList Object
type
  MoveList* = object
    moves*: array[256, Move]
    len*: int

func add*(ml: var MoveList, m: Move) {.inline.} =
  ml.moves[ml.len] = m
  inc(ml.len)

func clear*(ml: var MoveList) {.inline.} =
  ml.len = 0

iterator items*(ml: MoveList): Move {.inline.} =
  for i in 0 ..< ml.len:
    yield ml.moves[i]

func len*(ml: MoveList): int {.inline.} =
  ml.len

func `[]`*(ml: MoveList, idx: int): Move {.inline.} =
  ml.moves[idx]

# Constants
const
  MaxPly*           = 128
  MaxMoves*         = 256
  Infinity*         = 32000
  MateValue*        = 30000
  MateThreshold*    = MateValue - MaxPly
  MaxSearchThreads* = 512

var gSmpThreadCount*: int = 1
