from defs import *

NULL_MOVE = 0

NO_FLAG = 0
CASTLE = 1
DOUBLE = 2
ENPASSANT = 3

def make_move(start: int, end: int, piece: Piece, capture: bool=False,
              flag: int=NO_FLAG) -> Move:
    '''
    Move is encoded as a 21-bit integer:

    0b000_000_000_000_000_111_111 start
    0b000_000_000_111_111_000_000 end
    0b000_001_111_000_000_000_000 piece
    0b000_010_000_000_000_000_000 capture
    0b111_100_000_000_000_000_000 flag
    '''
    return start | (end << 6) | (piece << 12) | (capture << 16) | (flag << 17) 

def move_start(move: Move) -> int:
    return move & 0b000_000_000_000_000_111_111

def move_end(move: Move) -> int:
    return move >> 6 & 0b000_000_000_111_111

def move_start_end(move: Move) -> int:
    return move & 0b000_000_000_111_111_111_111

def move_piece(move: Move) -> Piece:
    return move >> 12 & 0b000_001_111

def move_flag(move: Move) -> int:
    return move >> 17 

def is_capture(move: Move) -> bool:
    return move & 0b000_010_000_000_000_000_000

def is_promotion(move: Move) -> bool:
    return (move >> 17) >= WHITE_KNIGHT

def is_tactical(move: Move) -> bool:
    return (move >> 17) >= WHITE_KNIGHT or move & 0b000_010_000_000_000_000_000

def move_to_str(move: Move) -> str:
    start = move_start(move)
    end = move_end(move)
    flag = move_flag(move)

    promo = ''
    if is_promotion(move):
        promo = PIECE_NAMES[flag].lower()
    
    return SQUARE_NAMES[start] + SQUARE_NAMES[end] + promo
