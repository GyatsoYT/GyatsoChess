import coretypes, utils

type
  # Move encoding:
  # 0-5: From Square (6 bits)
  # 6-11: To Square (6 bits)
  # 12-14: Promotion Piece Type (3 bits) - 0: None, 1: Knight, 2: Bishop, 3: Rook, 4: Queen
  # 15-18: Move Flags (4 bits)
  Move* = distinct uint32

func `==`*(a, b: Move): bool {.borrow.}

type
  MoveFlag* = enum
    Quiet = 0
    DoublePawnPush = 1
    KingCastle = 2
    QueenCastle = 3
    Capture = 4
    EpCapture = 5
    Promotion = 8
    CapturePromotion = 12

  MoveList* = object
    moves*: array[MaxMoves, Move]
    scores*: array[MaxMoves, int]
    count*: int

const
  FromMask = 0x3F
  ToMask = 0xFC0
  PromoMask = 0x7000
  FlagMask = 0xF0000 

  # Shift amounts
  ToShift = 6
  PromoShift = 12
  FlagShift = 16

func makeMove*(fromSq, toSq: Square, promo: PieceType = NoPieceType, flag: int = 0): Move =
  var m: uint32 = fromSq.uint32
  m = m or (toSq.uint32 shl ToShift)
  
  # Map PieceType to 3-bit value (1-4)
  var pVal: uint32 = 0
  case promo
  of Knight: pVal = 1
  of Bishop: pVal = 2
  of Rook: pVal = 3
  of Queen: pVal = 4
  else: pVal = 0
  
  m = m or (pVal shl PromoShift)
  m = m or (flag.uint32 shl FlagShift)
  
  return Move(m)

func fromSquare*(m: Move): Square {.inline.} =
  Square(uint32(m) and FromMask)

func toSquare*(m: Move): Square {.inline.} =
  Square((uint32(m) and ToMask) shr ToShift)

func promotion*(m: Move): PieceType {.inline.} =
  let pVal = (uint32(m) and PromoMask) shr PromoShift
  case pVal
  of 1: Knight
  of 2: Bishop
  of 3: Rook
  of 4: Queen
  else: NoPieceType

func flags*(m: Move): int {.inline.} =
  int((uint32(m) and FlagMask) shr FlagShift)

func isCapture*(m: Move): bool {.inline.} =
  (flags(m) and 4) != 0 # 4 is bit 2 of flag (FlagCapture=4, FlagEpCapture=5, etc)

func isPromotion*(m: Move): bool {.inline.} =
  (flags(m) and 8) != 0

func isEnPassant*(m: Move): bool {.inline.} =
  flags(m) == 5

func isCastle*(m: Move): bool {.inline.} =
  let f = flags(m)
  f == 2 or f == 3

func addMove*(ml: var MoveList, m: Move) {.inline.} =
  ml.moves[ml.count] = m
  inc(ml.count)

func clear*(ml: var MoveList) {.inline.} =
  ml.count = 0

func toAlgebraic*(m: Move): string =
  result = squareToAlgebraic(m.fromSquare) & squareToAlgebraic(m.toSquare)
  if m.isPromotion:
    case m.promotion
    of Knight: result.add('n')
    of Bishop: result.add('b')
    of Rook: result.add('r')
    of Queen: result.add('q')
    else: discard
