from __future__ import annotations

from bitboard import *
from defs import *
from move import *

SLIDERS = (
    (WHITE_BISHOP, WHITE_ROOK, WHITE_QUEEN),
    (BLACK_BISHOP, BLACK_ROOK, BLACK_QUEEN),
)
SLIDER_ATTACKS = bishop_attacks, rook_attacks, queen_attacks

def gen_tacticals(pos: Position) -> iter:
    '''Generates tactical moves (promotions & captures).'''

    board = pos.board
    bitboards = pos.bitboards
    side = pos.side
    xside = not side
    ep_square = pos.ep_square
    occupied = pos.occupied
    attacked = pos.attacked
    checkers = pos.checkers
        
    # Only king moves if more than one checker
    if bits(checkers) > 1:
        
        # Get king square
        king = KING + side
        start = msb(bitboards[king])
        # King attacks bitboard
        attacks = KING_ATTACKS[start] & bitboards[xside] & ~attacked
        # Loop through king attacks
        while attacks:
            end = msb(attacks)
            attacks ^= 1 << end
            yield make_move(start, end, king, True)
        
        return

    check_mask = pos.check_mask
    pin_masks = pos.pin_masks

    # White pawn tacticals
    if side == WHITE:

        # Get white pawn bitboard
        bitboard = bitboards[WHITE_PAWN]
        # Loop through pawn bitboard
        while bitboard:
            start = msb(bitboard)
            end = start - 8
            pawn_push = (bitboard >> 8) & ~occupied
            bitboard ^= 1 << start

            # Single pawn push promotion
            if ((1 << end) & RANK_8 & pawn_push
                & pin_masks[start] & check_mask):
                #assert start != F7 and end != E8, print(pos)
                yield make_move(start, end, WHITE_PAWN, flag=WHITE_QUEEN)
                yield make_move(start, end, WHITE_PAWN, flag=WHITE_KNIGHT)
                yield make_move(start, end, WHITE_PAWN, flag=WHITE_ROOK)
                yield make_move(start, end, WHITE_PAWN, flag=WHITE_BISHOP)

            # Get pawn attacks bitboard
            attacks = (
                PAWN_ATTACKS[WHITE][start] & bitboards[BLACK]
                & pin_masks[start] & check_mask
            )
            # Loop through attacks bitboard
            while attacks:
                end = msb(attacks)
                attacks ^= 1 << end
                # Promoting captures
                if (1 << end) & RANK_8:
                    yield make_move(start, end, WHITE_PAWN, True, WHITE_QUEEN)
                    yield make_move(start, end, WHITE_PAWN, True, WHITE_KNIGHT)
                    yield make_move(start, end, WHITE_PAWN, True, WHITE_ROOK)
                    yield make_move(start, end, WHITE_PAWN, True, WHITE_BISHOP)
                # Non-promoting captures
                else:
                    yield make_move(start, end, WHITE_PAWN, True)
                    
            # En passant
            ep_bb = 1 << ep_square
            if (ep_square
                and pin_masks[ep_square] == -1
                and bitboards[BLACK_PAWN] & check_mask
                and PAWN_ATTACKS[WHITE][start] & pin_masks[start] & ep_bb):
                # Get king square and potential horizontal pinners
                king_sq = msb(bitboards[WHITE_KING])
                horizontal_sliders = (
                    (bitboards[BLACK_ROOK] | bitboards[BLACK_QUEEN])
                    & RANK_MASKS[rank_of(king_sq)] & RANK_5
                )
                # Check if there is a horizontal pin
                while horizontal_sliders:
                    slider_sq = msb(horizontal_sliders)
                    if bits(BETWEEN[king_sq][slider_sq] & occupied) == 2:
                        break
                    horizontal_sliders ^= 1 << slider_sq
                # There is no en passant pin
                else:
                    end = msb(PAWN_ATTACKS[WHITE][start] & ep_bb)
                    yield make_move(start, end, WHITE_PAWN, True, ENPASSANT)

    # Black pawn tacticals
    else:

        # Get black pawn bitboard
        bitboard = bitboards[BLACK_PAWN]
        # Loop through pawn bitboard
        while bitboard:
            start = msb(bitboard)
            end = start + 8
            pawn_push = (bitboard << 8) & ~occupied
            bitboard ^= 1 << start 

            # Single pawn push promotion
            if ((1 << end) & RANK_1 & pawn_push
                & pin_masks[start] & check_mask):
                yield make_move(start, end, BLACK_PAWN, flag=BLACK_QUEEN)
                yield make_move(start, end, BLACK_PAWN, flag=BLACK_KNIGHT)
                yield make_move(start, end, BLACK_PAWN, flag=BLACK_ROOK)
                yield make_move(start, end, BLACK_PAWN, flag=BLACK_BISHOP)

            # Get pawn attacks bitboard
            attacks = (
                PAWN_ATTACKS[BLACK][start] & bitboards[WHITE]
                & pin_masks[start] & check_mask
            )
            # Loop through attacks bitboard
            while attacks:
                end = msb(attacks)
                attacks ^= 1 << end
                # Promoting captures
                if (1 << end) & RANK_1:
                    yield make_move(start, end, BLACK_PAWN, True, BLACK_QUEEN)
                    yield make_move(start, end, BLACK_PAWN, True, BLACK_KNIGHT)
                    yield make_move(start, end, BLACK_PAWN, True, BLACK_ROOK)
                    yield make_move(start, end, BLACK_PAWN, True, BLACK_BISHOP)
                # Non-promoting capture
                else:
                    yield make_move(start, end, BLACK_PAWN, True)
                    
            # En passant
            ep_bb = 1 << ep_square
            if (ep_square
                and pin_masks[ep_square] == -1
                and bitboards[WHITE_PAWN] & check_mask
                and PAWN_ATTACKS[BLACK][start] & pin_masks[start] & ep_bb):
                # Get king square and potential pinners
                king_sq = msb(bitboards[BLACK_KING])
                horizontal_sliders = (
                    (bitboards[WHITE_ROOK] | bitboards[WHITE_QUEEN])
                    & RANK_MASKS[rank_of(king_sq)] & RANK_4
                )
                # Check if there is a horizontal pin
                while horizontal_sliders:
                    slider_sq = msb(horizontal_sliders)
                    if bits(BETWEEN[king_sq][slider_sq] & occupied) == 2:
                        break
                    horizontal_sliders ^= 1 << slider_sq
                # There is no en passant pin
                else:
                    end = msb(PAWN_ATTACKS[BLACK][start] & ep_bb)
                    yield make_move(start, end, BLACK_PAWN, True, ENPASSANT)           

    # Get knight bitboard
    knight = KNIGHT + side
    bitboard = bitboards[knight]
    # Loop through knight bitboard
    while bitboard:
        start = msb(bitboard)
        bitboard ^= 1 << start
        # Knight attacks bitboard
        attacks = (
            KNIGHT_ATTACKS[start] & bitboards[xside]
            & pin_masks[start] & check_mask
        )
        # Loop through knight attacks
        while attacks:
            end = msb(attacks)
            attacks ^= 1 << end
            yield make_move(start, end, knight, True)
    
    # Loop through slider types
    for piece, piece_attacks in zip(SLIDERS[side], SLIDER_ATTACKS):
        bitboard = bitboards[piece]
        # Loop through slider bitboard
        while bitboard:
            start = msb(bitboard)
            bitboard ^= 1 << start
            # Slider attacks bitboard
            attacks = (
                piece_attacks(start, occupied) & bitboards[xside]
                & pin_masks[start] & check_mask
            )
            # Loop through slider attacks
            while attacks:
                end = msb(attacks)
                attacks ^= 1 << end
                yield make_move(start, end, piece, True)
                
    # Get king square
    king = KING + side
    start = msb(bitboards[king])
    # King attacks bitboard
    attacks = KING_ATTACKS[start] & bitboards[xside] & ~attacked
    # Loop through king attacks
    while attacks:
        end = msb(attacks)
        attacks ^= 1 << end
        yield make_move(start, end, king, True)
                
def gen_quiets(pos: Position) -> iter:
    '''Generate quiet moves.'''

    board = pos.board
    bitboards = pos.bitboards
    side = pos.side
    xside = not side
    castling = pos.castling
    occupied = pos.occupied
    attacked = pos.attacked
    checkers = pos.checkers
        
    # Only king moves if more than one checker
    if bits(checkers) > 1:
        
        # Get king square
        king = KING + side
        start = msb(bitboards[king])
        # King attacks bitboard
        attacks = KING_ATTACKS[start] & ~occupied & ~attacked
        # Loop through king attacks
        while attacks:
            end = msb(attacks)
            attacks ^= 1 << end
            yield make_move(start, end, king)
        
        return

    check_mask = pos.check_mask
    pin_masks = pos.pin_masks

    # White pawn and castle moves
    if side == WHITE:

        # White kingside castle
        if (castling & 0x1
            and not 0x7000000000000000 & attacked
            and not ((1 << F1) | (1 << G1)) & occupied):
            yield make_move(E1, G1, WHITE_KING, flag=CASTLE)
        # White queenside castle
        if (castling & 0x2
            and not 0x1c00000000000000 & attacked
            and not ((1 << B1) | (1 << C1) | (1 << D1)) & occupied):
            yield make_move(E1, C1, WHITE_KING, flag=CASTLE)

        # Get white pawn bitboard
        bitboard = bitboards[WHITE_PAWN]
        # Loop through white pawn bitboard
        while bitboard:
            start = msb(bitboard)
            end = start - 8
            # Single pawn push
            pawn_push = (bitboard >> 8) & ~occupied & ~RANK_8
            bitboard ^= 1 << start
            if (1 << end) & pawn_push & pin_masks[start] & check_mask:
                yield make_move(start, end, WHITE_PAWN)
            # Double pawn push
            end = max(start - 16, 0)
            double_pawn_push = (pawn_push >> 8) & ~occupied & RANK_4
            if (1 << end) & double_pawn_push & pin_masks[start] & check_mask:
                yield make_move(start, end, WHITE_PAWN, flag=DOUBLE)

    # Black pawn and castle moves
    else:

        # Black kingside castle
        if (castling & 0x4
            and not 0x70 & attacked
            and not ((1 << F8) | (1 << G8)) & occupied):
            yield make_move(E8, G8, BLACK_KING, flag = CASTLE)
        # Black queenside castle
        if (castling & 0x8
            and not 0x1c & attacked
            and not ((1 << B8) | (1 << C8) | (1 << D8)) & occupied):
            yield make_move(E8, C8, BLACK_KING, flag=CASTLE)
        
        # Get black pawn bitboard
        bitboard = bitboards[BLACK_PAWN]
        # Loop through black pawn bitboard
        while bitboard:
            start = msb(bitboard)
            # Single pawn push
            end = start + 8
            pawn_push = (bitboard << 8) & ~occupied & ~RANK_1
            bitboard ^= 1 << start
            if (1 << end) & pawn_push & pin_masks[start] & check_mask:
                yield make_move(start, end, BLACK_PAWN)
            # Double pawn push
            end = start + 16
            double_pawn_push = (pawn_push << 8) & ~occupied & RANK_5
            if (1 << end) & double_pawn_push & pin_masks[start] & check_mask:
                yield make_move(start, end, BLACK_PAWN, flag=DOUBLE)

    # Get knight bitboard
    knight = KNIGHT + side
    bitboard = bitboards[knight]
    # Loop through knights
    while bitboard:
        start = msb(bitboard)
        bitboard ^= 1 << start
        # Knight attacks bitboard
        attacks = (
            KNIGHT_ATTACKS[start] & ~occupied
            & pin_masks[start] & check_mask
        )
        # Loop through knight attacks
        while attacks:
            end = msb(attacks)
            attacks ^= 1 << end
            yield make_move(start, end, knight)

    # Loop through slider types
    for piece, piece_attacks in zip(SLIDERS[side], SLIDER_ATTACKS):
        bitboard = bitboards[piece]
        # Loop through sliders
        while bitboard:
            start = msb(bitboard)
            bitboard ^= 1 << start
            # Slider attacks bitboard
            attacks = (
                piece_attacks(start, occupied) & ~occupied
                & pin_masks[start] & check_mask
            )
            # Loop through slider attacks
            while attacks:
                end = msb(attacks)
                attacks ^= 1 << end
                yield make_move(start, end, piece)
             
    # Get king square
    king = KING + side
    start = msb(bitboards[king])
    # King attacks bitboard
    attacks = KING_ATTACKS[start] & ~occupied & ~attacked
    # Loop through king attacks
    while attacks:
        end = msb(attacks)
        attacks ^= 1 << end
        yield make_move(start, end, king)
                
def gen_perft(pos: Position):
    '''Generate all moves for perft purposes.'''

    # Tacticals
    for move in gen_tacticals(pos):
        yield move
    # Quiets
    for move in gen_quiets(pos):
        yield move

def is_legal(pos, move):

    if move is NULL_MOVE:
        return False

    board = pos.board
    piece = move_piece(move)
    start = move_start(move)
    end = move_end(move)

    if piece != board[start] or piece % 2 != pos.side:
        return False

    if move_flag(move):
        gen_moves = gen_tacticals if is_tactical(move) else gen_quiets
        for legal_move in gen_moves(pos):
            if move == legal_move:
                return True
        return False

    if bool(is_capture(move)) != bool(board[end]):
        return False

    piece_type = piece & ~0x1

    if piece_type is KING:
        return (1 << end) & ~pos.bitboards[pos.side] & ~pos.attacked

    if piece_type is PAWN:
        if is_capture(move):
            return ((1 << end) & pos.bitboards[not pos.side]
                    & pos.pin_masks[start] & pos.check_mask)
        else:
            return ((1 << end) & ~pos.occupied
                    & pos.pin_masks[start] & pos.check_mask)

    if piece_type is KNIGHT:
        return ((1 << end) & ~pos.bitboards[pos.side]
                & pos.pin_masks[start] & pos.check_mask)

    if piece_type is BISHOP:
        return (bishop_attacks(start, pos.occupied) & ~pos.bitboards[pos.side]
                & pos.pin_masks[start] & pos.check_mask & (1 << end))

    if piece_type is ROOK:
        return (rook_attacks(start, pos.occupied) & ~pos.bitboards[pos.side]
                & pos.pin_masks[start] & pos.check_mask & (1 << end))

    if piece_type is QUEEN:
        return (queen_attacks(start, pos.occupied) & ~pos.bitboards[pos.side]
                & pos.pin_masks[start] & pos.check_mask & (1 << end))

