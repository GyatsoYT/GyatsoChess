from defs import *
from bitboard import *
from position import *

# Manhattan distance
DISTANCE = zeros(64, 64)
for start in range(64):
    for end in range(64):
        DISTANCE[start][end] += abs(rank_of(end) - rank_of(start))
        DISTANCE[start][end] += abs(file_of(end) - file_of(start))

class NoMopUpEvaluation(Exception): pass
             
def mop_up_evaluation(pos: Position) -> Value:
    '''
    For finding mate in positions with lone king.
    Not perfect but works in most cases.
    '''

    # Weaker side and stronger side
    bitboards = pos.bitboards
    ws = bits(bitboards[WHITE]) > 1
    ss = not ws    

    # No lone king or stronger side has no pieces
    if bits(bitboards[ws]) > 1 or not has_non_pawn(pos, ss):
        raise NoMopUpEvaluation

    _, pawns, knights, bishops, rooks, queens, _ = bitboards[ss::2]

    # Material
    v = TB_WIN if (rooks or queens) else 0
    v += bits(pawns) * PIECE_VALUES[PAWN]
    v += bits(knights) * PIECE_VALUES[KNIGHT]
    v += bits(bishops) * PIECE_VALUES[BISHOP]
    v += bits(rooks) * PIECE_VALUES[ROOK]
    v += bits(queens) * PIECE_VALUES[QUEEN]

    # Greater bonus for pawns further down the board
    while pawns:
        sq = msb(pawns)
        pawns ^= 1 << sq
        v += 6 * rank_of(sq ^ (56, 0)[ss])**2

    if not bishops:
        corners = A1, H8, A8, H1
    else:
        corners = (A1, H8) if bishops & DARK_SQUARES else (A8, H1)
    
    king_distance = DISTANCE[msb(bitboards[KING + ss])][msb(bitboards[ws])]
    corner_distance = min(DISTANCE[KING + ws][corner] for corner in corners)

    # Push king to corner
    v += 3 * (14 - king_distance) + 2 * (6 - corner_distance)
    
    return v if pos.side == ss else -v
