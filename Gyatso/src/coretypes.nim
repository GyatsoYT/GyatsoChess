import std/monotimes, std/times, std/atomics

type
  SearchInfo* = object
    startTime*: MonoTime
    allocatedTime*: Duration
    depthLimit*: int
    nodes*: uint64
    stopFlag*: ptr Atomic[bool]
    threadID*: int
    numThreads*: int
    nodeCounts*: ptr UncheckedArray[uint64]
    ponderFlag*: ptr Atomic[bool]  
    ponderMove*: uint16  
    selDepth*: int       
    movesToGo*: int      
    increment*: Duration 
    nodeLimit*: uint64   


  Color* = enum
    White, Black, NoColor

  PieceType* = enum
    Pawn, Knight, Bishop, Rook, Queen, King, NoPieceType

  Piece* = enum
    WhitePawn, WhiteKnight, WhiteBishop, WhiteRook, WhiteQueen, WhiteKing,
    BlackPawn, BlackKnight, BlackBishop, BlackRook, BlackQueen, BlackKing,
    NoPiece

  Square* = range[0..63]

const
  MaxMoves* = 256
  MaxPly* = 512
  MateValue* = 29000
  UNKNOWN* = -32000 

const
  PawnValueMG* = 93
  PawnValueEG* = 119
  KnightValueMG* = 413
  KnightValueEG* = 458
  BishopValueMG* = 405
  BishopValueEG* = 482
  RookValueMG* = 546
  RookValueEG* = 820
  QueenValueMG* = 1300
  QueenValueEG* = 1533
  KingValue* = 20000

  
type
  StackEntry* = object
    evaluation*: int 
    move*: uint32     
    killers*: array[2, uint32]
    excluded*: uint32 
    ply*: int

func pieceColor*(p: Piece): Color =
  case p
  of WhitePawn..WhiteKing: White
  of BlackPawn..BlackKing: Black
  else: NoColor

func pieceType*(p: Piece): PieceType =
  case p
  of WhitePawn, BlackPawn: Pawn
  of WhiteKnight, BlackKnight: Knight
  of WhiteBishop, BlackBishop: Bishop
  of WhiteRook, BlackRook: Rook
  of WhiteQueen, BlackQueen: Queen
  of WhiteKing, BlackKing: King
  else: NoPieceType

func makePiece*(c: Color, pt: PieceType): Piece =
  if c == White:
    case pt
    of Pawn: WhitePawn
    of Knight: WhiteKnight
    of Bishop: WhiteBishop
    of Rook: WhiteRook
    of Queen: WhiteQueen
    of King: WhiteKing
    else: NoPiece
  elif c == Black:
    case pt
    of Pawn: BlackPawn
    of Knight: BlackKnight
    of Bishop: BlackBishop
    of Rook: BlackRook
    of Queen: BlackQueen
    of King: BlackKing
    else: NoPiece
  else:
    NoPiece
