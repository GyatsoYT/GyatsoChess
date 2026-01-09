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
  PawnValueMG* = 108
  PawnValueEG* = 100
  KnightValueMG* = 492
  KnightValueEG* = 415
  BishopValueMG* = 469
  BishopValueEG* = 413
  RookValueMG* = 647
  RookValueEG* = 721
  QueenValueMG* = 1362
  QueenValueEG* = 1431
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
