from copy import deepcopy

VERSION = '1.2.0'

MAX_DEPTH = 60
MAX_PLY = 120

Bitboard = int
Value = int
Move = int
Square = int
Piece = int
Color = int
Key = int

NORTH, SOUTH, EAST, WEST = -8, 8, 1, -1

SQUARE_NAMES = [f + r for r in '87654321' for f in 'abcdefgh']

SQUARES = (
    A8, B8, C8, D8, E8, F8, G8, H8,
    A7, B7, C7, D7, E7, F7, G7, H7,
    A6, B6, C6, D6, E6, F6, G6, H6,
    A5, B5, C5, D5, E5, F5, G5, H5,
    A4, B4, C4, D4, E4, F4, G4, H4,
    A3, B3, C3, D3, E3, F3, G3, H3,
    A2, B2, C2, D2, E2, F2, G2, H2,
    A1, B1, C1, D1, E1, F1, G1, H1,
) = range(64)

PIECE_NAMES = '. PpNnBbRrQqKk'

PIECES = (
    WHITE, BLACK,
    WHITE_PAWN, BLACK_PAWN,
    WHITE_KNIGHT, BLACK_KNIGHT,
    WHITE_BISHOP, BLACK_BISHOP,
    WHITE_ROOK, BLACK_ROOK,
    WHITE_QUEEN, BLACK_QUEEN,
    WHITE_KING, BLACK_KING,
) = range(14)

PIECE_TYPES = (
    NO_PIECE,
    PAWN,
    KNIGHT,
    BISHOP,
    ROOK,
    QUEEN,
    KING,
) = range(0, 14, 2)

PIECE_VALUES = (
    0, 0,
    100, 100,      # White/Black Pawn
    565, 565,      # White/Black Knight
    565, 565,      # White/Black Bishop  
    705, 705,      # White/Black Rook
    1000, 1000,    # White/Black Queen 
    30000, 30000,  # White/Black King
)

WINDOW = 8

UNKNOWN = 32257
CHECKMATE = 32256
MATE_BOUND = 30000
TB_WIN = 20000

class SearchStopped(Exception): pass

def zeros(*args):
    a = 0
    for n in reversed(args):
        a = [deepcopy(a) for _ in range(n)]
    return a
