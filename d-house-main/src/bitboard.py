import itertools
import sys

from defs import *

def uint64(x: int) -> int:
    return x & 0xFFFFFFFFFFFFFFFF

PAWN_ATTACKS = zeros(2, 64)
KNIGHT_ATTACKS = zeros(64)
KING_ATTACKS = zeros(64)

BISHOP_MASKS = zeros(64)
ROOK_MASKS = zeros(64)
BISHOP_ATTACKS = [dict() for _ in range(64)]
ROOK_ATTACKS = [dict() for _ in range(64)]

BETWEEN = zeros(64, 64)

def file_of(square: Square) -> int:
    return square & 7

def rank_of(square: Square) -> int:
    return square >> 3

def relative_rank(side: Color, rank: int) -> int:
    return (7 - rank) if side else rank

A_FILE = 0x101010101010101
B_FILE = 0x202020202020202
C_FILE = 0x404040404040404
D_FILE = 0x808080808080808
E_FILE = 0x1010101010101010
F_FILE = 0x2020202020202020
G_FILE = 0x4040404040404040
H_FILE = 0x8080808080808080

RANK_1 = 0xFF00000000000000
RANK_2 = 0x00FF000000000000
RANK_3 = 0x0000FF0000000000
RANK_4 = 0x000000FF00000000
RANK_5 = 0x00000000FF000000
RANK_6 = 0x0000000000FF0000
RANK_7 = 0x000000000000FF00
RANK_8 = 0x00000000000000FF

DARK_SQUARES = 0x55AA55AA55AA55AA

FILE_MASKS = A_FILE, B_FILE, C_FILE, D_FILE, E_FILE, F_FILE, G_FILE, H_FILE

RANK_MASKS = RANK_8, RANK_7, RANK_6, RANK_5, RANK_4, RANK_3, RANK_2, RANK_1

# Popcount function
if sys.version_info < (3, 10):
    bits = lambda bb: bin(bb).count('1')
else:
    bits = int.bit_count
    
def msb(bb: Bitboard) -> int:
    return bb.bit_length() - 1

def lsb(bb: Bitboard) -> int:
    if bb:
        return bits((bb & -bb) - 1)
    else:
        return -1

def bishop_attacks(square: Square, occupied: Bitboard) -> Bitboard:
    return BISHOP_ATTACKS[square][occupied & BISHOP_MASKS[square]]

def rook_attacks(square: Square, occupied: Bitboard) -> Bitboard:
    return ROOK_ATTACKS[square][occupied & ROOK_MASKS[square]]

def queen_attacks(square: Square, occupied: Bitboard) -> Bitboard:
    return (BISHOP_ATTACKS[square][occupied & BISHOP_MASKS[square]]
            | ROOK_ATTACKS[square][occupied & ROOK_MASKS[square]])

def print_bb(bb: Bitboard) -> None:
    print()
    for r in range(8):
        for f in range(8):
            sq = r * 8 + f
            if not f:
                print(' ' + str(8 - r) + ' ', end = '')
            print(' 1' if bb & (1 << sq) else ' 0', end = '')
        print()
    print('\n    a b c d e f g h')
    print('\n    Bitboard: ' + str(bb))

def relevant_bishop_bits(square: Square) -> Bitboard:
    
    mask, tr, tf = 0, int(square / 8), square % 8
    
    for r, f in zip(range(tr + 1, 7), range(tf + 1, 7)):
        mask |= uint64(1 << (r * 8 + f))
    for r, f in zip(range(tr - 1, 0, -1), range(tf + 1, 7)):
        mask |= uint64(1 << (r * 8 + f))
    for r, f in zip(range(tr + 1, 7), range(tf - 1, 0, -1)):
        mask |= uint64(1 << (r * 8 + f))
    for r, f in zip(range(tr - 1, 0, -1), range(tf - 1, 0, -1)):
        mask |= uint64(1 << (r * 8 + f))

    return mask

def relevant_rook_bits(square: Square) -> Bitboard:

    mask, tr, tf = 0, int(square / 8), square % 8
    
    for r in range(tr + 1, 7): mask |= uint64(1 << (r * 8 + tf))
    for r in range(1, tr): mask |= uint64(1 << (r * 8 + tf))
    for f in range(tf + 1, 7): mask |= uint64(1 << (tr * 8 + f))
    for f in range(1, tf): mask |= uint64(1 << (tr * 8 + f))
    
    return mask

def bishop_attack_mask(square: Square, blockers: Bitboard) -> Bitboard:

    mask, tr, tf = 0, int(square / 8), square % 8
    
    for r, f in zip(range(tr + 1, 8), range(tf + 1, 8)):
        mask |= uint64(1 << (r * 8 + f))
        if uint64(1 << (r * 8 + f)) & blockers: break
    for r, f in zip(range(tr - 1, -1, -1), range(tf + 1, 8)):
        mask |= uint64(1 << (r * 8 + f))
        if uint64(1 << (r * 8 + f)) & blockers: break
    for r, f in zip(range(tr + 1, 8), range(tf - 1, -1, -1)):
        mask |= uint64(1 << (r * 8 + f))
        if uint64(1 << (r * 8 + f)) & blockers: break
    for r, f in zip(range(tr - 1, -1, -1), range(tf - 1, -1, -1)):
        mask |= uint64(1 << (r * 8 + f))
        if uint64(1 << (r * 8 + f)) & blockers: break

    return mask

def rook_attack_mask(square: Square, blockers: Bitboard) -> Bitboard:
    
    mask, tr, tf = 0, int(square / 8), square % 8
    
    for r in range(tr + 1, 8):
        mask |= uint64(1 << (r * 8 + tf))
        if uint64(1 << (r * 8 + tf)) & blockers: break
    for r in range(tr - 1, -1, -1):
        mask |= uint64(1 << (r * 8 + tf))
        if uint64(1 << (r * 8 + tf)) & blockers: break
    for f in range(tf + 1, 8):
        mask |= uint64(1 << (tr * 8 + f))
        if uint64(1 << (tr * 8 + f)) & blockers: break
    for f in range(tf - 1, -1, -1):
        mask |= uint64(1 << (tr * 8 + f))
        if uint64(1 << (tr * 8 + f)) & blockers: break
        
    return mask

def occupied_combinations(bitboard: Bitboard) -> iter:

    bit_indices = []
    
    while bitboard:
        square = msb(bitboard)
        bit_indices.append(square)
        bitboard ^= 1 << square

    for count in range(len(bit_indices) + 1):
        for occupied_squares in itertools.combinations(bit_indices, count):
            occupied_mask = 0
            for square in occupied_squares:
                occupied_mask |= 1 << square
            yield occupied_mask

# Initialize between squares
for start in range(64):
    for end in range(start + 1, 64):
        
        if rank_of(start) == rank_of(end):
            square = end + WEST
            while square > start:
                BETWEEN[start][end] |= uint64(1 << square)
                square += WEST
                
        elif file_of(start) == file_of(end):
            square = end + NORTH
            while square > start:
                BETWEEN[start][end] |= uint64(1 << square)
                square += NORTH
                
        elif (end - start) % 9 == 0 and file_of(end) > file_of(start):
            square = end + NORTH + WEST
            while square > start:
                BETWEEN[start][end] |= uint64(1 << square)
                square += NORTH + WEST
                
        elif (end - start) % 7 == 0 and file_of(end) < file_of(start):
            square = end + NORTH + EAST
            while square > start:
                BETWEEN[start][end] |= uint64(1 << square)
                square += NORTH + EAST

for start in range(64):
    for end in range(start):
        BETWEEN[start][end] = BETWEEN[end][start]

for square in range(64):

    # Pawn attack masks
    PAWN_ATTACKS[WHITE][square] |= uint64((1 << square) >> 7) & uint64(~A_FILE)
    PAWN_ATTACKS[WHITE][square] |= uint64((1 << square) >> 9) & uint64(~H_FILE)
    PAWN_ATTACKS[BLACK][square] |= uint64((1 << square) << 7) & uint64(~H_FILE)
    PAWN_ATTACKS[BLACK][square] |= uint64((1 << square) << 9) & uint64(~A_FILE)

    # Knight attack masks
    KNIGHT_ATTACKS[square] = (0
        | (uint64((1 << square) >> 6) & uint64(~(A_FILE | B_FILE)))
        | (uint64((1 << square) << 6) & uint64(~(G_FILE | H_FILE)))
        | (uint64((1 << square) >> 10) & uint64(~(G_FILE | H_FILE)))
        | (uint64((1 << square) << 10) & uint64(~(A_FILE | B_FILE)))
        | (uint64((1 << square) >> 15) & uint64(~A_FILE))
        | (uint64((1 << square) << 15) & uint64(~H_FILE))
        | (uint64((1 << square) >> 17) & uint64(~H_FILE))
        | (uint64((1 << square) << 17) & uint64(~A_FILE)))

    # King attack masks
    KING_ATTACKS[square] = (0
        | (uint64((1 << square) >> 8))
        | (uint64((1 << square) << 8))
        | (uint64((1 << square) >> 1) & uint64(~H_FILE))
        | (uint64((1 << square) << 1) & uint64(~A_FILE))
        | (uint64((1 << square) >> 7) & uint64(~A_FILE))
        | (uint64((1 << square) << 7) & uint64(~H_FILE))
        | (uint64((1 << square) >> 9) & uint64(~H_FILE))
        | (uint64((1 << square) << 9) & uint64(~A_FILE)))

    # Bishop attack masks
    BISHOP_MASKS[square] = relevant_bishop_bits(square)
    for occupied in occupied_combinations(BISHOP_MASKS[square]):
        BISHOP_ATTACKS[square][occupied] = bishop_attack_mask(square, occupied)

    # Rook attack masks
    ROOK_MASKS[square] = relevant_rook_bits(square)
    for occupied in occupied_combinations(ROOK_MASKS[square]):
        ROOK_ATTACKS[square][occupied] = rook_attack_mask(square, occupied)
