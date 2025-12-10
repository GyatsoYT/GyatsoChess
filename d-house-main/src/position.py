from dataclasses import dataclass
from functools import cached_property

from bitboard import *
from defs import *
from move import *
from nnue import *
from movegen import gen_perft

STARTING_FEN = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq -'

MATERIAL_KEYS = (
    0, 0, 
    1 << 0,   # White Pawn
    1 << 4,   # Black Pawn
    1 << 8,   # White Knight
    1 << 12,  # Black Knight
    1 << 16,  # White Bishop
    1 << 20,  # Black Bishop
    1 << 24,  # White Rook
    1 << 28,  # Black Rook
    1 << 32,  # White Queen
    1 << 36,  # Black Queen
    0, 0,
)

UPDATE_CASTLING_KEYS = (
     7, 15, 15, 15,  3, 15, 15, 11,
    15, 15, 15, 15, 15, 15, 15, 15,
    15, 15, 15, 15, 15, 15, 15, 15,
    15, 15, 15, 15, 15, 15, 15, 15,
    15, 15, 15, 15, 15, 15, 15, 15,
    15, 15, 15, 15, 15, 15, 15, 15,
    15, 15, 15, 15, 15, 15, 15, 15,
    13, 15, 15, 15, 12, 15, 15, 14,
)

INSUFFICIENT_MATERIAL = {
    MATERIAL_KEYS[0],  # Kk
    MATERIAL_KEYS[WHITE_KNIGHT],  # KNk
    MATERIAL_KEYS[WHITE_BISHOP],  # KBk
    MATERIAL_KEYS[BLACK_KNIGHT],  # Kkn
    MATERIAL_KEYS[BLACK_BISHOP],  # Kkb
    MATERIAL_KEYS[WHITE_KNIGHT] + MATERIAL_KEYS[BLACK_KNIGHT],  # KNkn
    MATERIAL_KEYS[WHITE_KNIGHT] + MATERIAL_KEYS[BLACK_BISHOP],  # KNkb
    MATERIAL_KEYS[WHITE_BISHOP] + MATERIAL_KEYS[BLACK_KNIGHT],  # KBkn
    MATERIAL_KEYS[WHITE_BISHOP] + MATERIAL_KEYS[BLACK_BISHOP],  # KBkb
}

@dataclass
class Position:
    '''Class for storing information regarding board representation.'''

    # Board representation
    board: list[Piece]
    bitboards: list[Bitboard]
    side: Color
    castling: Key
    ep_square: Square

    # Used for the engine
    material_key: Key
    previous: set
    accumulator: list[list[int]]

    @property
    def occupied(self) -> Bitboard:
        return self.bitboards[WHITE] | self.bitboards[BLACK]

    @property
    def rule_50(self) -> int:
        return len(self.previous)

    @property
    def is_repeated(self) -> bool:
        return self.__hash__() in self.previous

    @property
    def is_material_draw(self) -> bool:
        return self.material_key in INSUFFICIENT_MATERIAL
    
    @property
    def in_check(self) -> bool:
        return self.attacked & self.bitboards[KING + self.side]
        
    @cached_property
    def attacked(self) -> Bitboard:
        '''Which squares the side not to move attacks.'''
        
        side = self.side
        xside = not side
        bitboards = self.bitboards
        no_king_occupancy = self.occupied ^ bitboards[KING + side]
        attacked = 0

        # Squares attacked by enemy pawns
        if side == WHITE:
            attacked |= (bitboards[BLACK_PAWN] << 7) & ~H_FILE 
            attacked |= (bitboards[BLACK_PAWN] << 9) & ~A_FILE 
        else:
            attacked |= (bitboards[WHITE_PAWN] >> 7) & ~A_FILE 
            attacked |= (bitboards[WHITE_PAWN] >> 9) & ~H_FILE 

        # Squares attacked by enemy knights
        bitboard = bitboards[KNIGHT + xside]
        while bitboard:
            square = msb(bitboard)
            attacked |= KNIGHT_ATTACKS[square]
            bitboard ^= 1 << square

        # Squares attacked by enemy king
        attacked |= KING_ATTACKS[msb(bitboards[KING + xside])]

        # Squares attacked by enemy diagonal sliders
        bitboard = bitboards[BISHOP + xside] | bitboards[QUEEN + xside]
        while bitboard:
            square = msb(bitboard)
            attacked |= bishop_attacks(square, no_king_occupancy)
            bitboard ^= 1 << square

        # Squares attacked by enemy straight sliders
        bitboard = bitboards[ROOK + xside] | bitboards[QUEEN + xside]
        while bitboard:
            square = msb(bitboard)
            attacked |= rook_attacks(square, no_king_occupancy)
            bitboard ^= 1 << square

        return attacked

    @cached_property
    def checkers(self) -> Bitboard:
        '''Squares of pieces that are giving check.'''
        
        if self.in_check:

            side = self.side
            xside = not side
            bitboards = self.bitboards
            occupied = self.occupied
            king_sq = msb(bitboards[KING + side])

            return (PAWN_ATTACKS[side][king_sq] & bitboards[PAWN + xside]
                    | KNIGHT_ATTACKS[king_sq] & bitboards[KNIGHT + xside]
                    | bishop_attacks(king_sq, occupied)
                    & (bitboards[BISHOP + xside] | bitboards[QUEEN + xside])
                    | rook_attacks(king_sq, occupied)
                    & (bitboards[ROOK + xside] | bitboards[QUEEN + xside]))

        return 0

    @cached_property
    def check_mask(self) -> Bitboard:
        '''Used to mask out illegal moves when in check.'''
        
        checkers = self.checkers
        
        if checkers:
            king = KING + self.side
            return BETWEEN[msb(checkers)][msb(self.bitboards[king])] | checkers
        
        return -1

    @cached_property
    def pin_masks(self) -> list[Bitboard]:
        '''
        Masks out illegal moves for pinned pieces. This idea was
        inspired by Gigantua.
        '''
        
        side = self.side
        xside = not side
        bitboards = self.bitboards
        occupied = self.occupied
        king_sq = msb(bitboards[KING + side])
        pin_masks = [-1]*64

        # Horizontal and vertical pins
        pinners = (
            rook_attacks(king_sq, occupied & ~rook_attacks(king_sq, occupied))
            & (bitboards[ROOK + xside] | bitboards[QUEEN + xside])
        )
        while pinners:
            pinner_sq = msb(pinners)
            betweens = BETWEEN[king_sq][pinner_sq]
            pin_masks[msb(betweens & occupied)] = betweens | (1 << pinner_sq)                                                
            pinners ^= 1 << pinner_sq

        # Diagonal pins
        pinners = (
            bishop_attacks(king_sq, occupied & ~bishop_attacks(king_sq, occupied))
            & (bitboards[BISHOP + xside] | bitboards[QUEEN + xside])
        )
        while pinners:
            pinner_sq = msb(pinners)
            betweens = BETWEEN[king_sq][pinner_sq]
            pin_masks[msb(betweens & occupied)] = betweens | (1 << pinner_sq)                                                     
            pinners ^= 1 << pinner_sq    
        
        return pin_masks

    def __hash__(self) -> Key:
        return hash((*self.bitboards, not self.side, self.castling,
                     self.ep_square)) & 0xFFFFFFFFFFFFFFFF

    def __str__(self) -> str:
        
        string = ''
        for square in range(64):
            if square & 7 == 0:
                string += ' ' + str(8 - (square >> 3)) + ' '
            if self.board[square] == NO_PIECE:
                string += ' .'
            else:
                string += ' ' + PIECE_NAMES[self.board[square]]
            if square & 7 == 7:
                string += '\n'

        string += '\n    a b c d e f g h\n'
        string += '\n Side:     ' + ('Black' if self.side else 'White')
        string += '\n Castling: ' + bin(self.castling)[2:]
        string += '\n Key:      ' + hex(self.__hash__())

        return string + '\n'

def as_fen(pos: Position) -> str:
    '''Creates fen from Position.'''

    fen = ''
    empty_spaces = 0

    # Board
    for square, piece in enumerate(pos.board):
        # New rank
        if (1 << square) & A_FILE:
            fen += '/'
        # No piece
        if piece is NO_PIECE:
            empty_spaces += 1
            if empty_spaces and (1 << square) & H_FILE:
                fen += str(empty_spaces)
                empty_spaces = 0
        # Piece
        else:
            if empty_spaces:
                fen += str(empty_spaces)
                empty_spaces = 0
            fen += PIECE_NAMES[piece]

    # Side
    fen += ' b ' if pos.side else ' w '

    # Castling
    castling = ''
    if pos.castling & 1: castling += 'K'
    if pos.castling & 2: castling += 'Q'
    if pos.castling & 4: castling += 'k'
    if pos.castling & 8: castling += 'q'
    fen += castling if castling else '-'
    fen += ' '

    # En passant square
    fen += SQUARE_NAMES[pos.ep_square] if pos.ep_square else '-'
    fen += ' '

    # Move clocks
    fen += str(len(pos.previous)) + ' 1'

    return fen[1:]

def parse_fen(fen: str=STARTING_FEN) -> Position:
    '''Creates a position from a FEN.'''
    
    board = zeros(64)
    bitboards = zeros(14)
    side = WHITE
    castling = 0
    ep_square = 0
    material_key = 0
    previous = set()
    accumulator = zeros(2)

    fen += ' 0 1'
    tokens = fen.split()

    # Put pieces on board
    i = 0
    for char in tokens[0]:
        if char.isalpha():
            piece = PIECE_NAMES.index(char)
            board[i] = piece
        elif char.isnumeric():
            for j in range(int(char)):
                board[i + j] = NO_PIECE
            i += int(char) - 1
        elif char == '/':
            i -= 1
        i += 1

    # Side
    side = WHITE if tokens[1] == 'w' else BLACK

    # Castling
    if 'K' in tokens[2]: castling += 1
    if 'Q' in tokens[2]: castling += 2
    if 'k' in tokens[2]: castling += 4
    if 'q' in tokens[2]: castling += 8

    # En passant square
    ep_square = 0 if tokens[3] == '-' else SQUARE_NAMES.index(tokens[3])

    # Add invalid keys (negative numbers) to previous for rule_50 
    previous = {-k - 1 for k in range(int(tokens[4]))}

    # Initialize piece bitboards
    for square, piece in enumerate(board):
        if piece != NO_PIECE:
            bitboards[piece] |= 1 << square
    # Initialize color bitboards
    for bitboard in bitboards[BLACK::2]: bitboards[BLACK] |= bitboard
    for bitboard in bitboards[WHITE::2]: bitboards[WHITE] |= bitboard

    # Set material key
    for square, piece in enumerate(board):
        if piece != NO_PIECE:
            material_key += MATERIAL_KEYS[piece]

    # Initialize accumulator
    accumulator = make_accumulator(board)

    return Position(board, bitboards, side,
                    castling, ep_square, material_key, previous, accumulator)

def has_non_pawn(pos: Position, side: Color) -> bool:
    '''Used for null-move pruning.'''
    
    return (pos.bitboards[side]
            ^ pos.bitboards[side + KING]
            ^ pos.bitboards[side + PAWN])

def do_null_move(pos: Position) -> Position:
    '''Does a null move on the position using copy/make.'''
    
    return Position([*pos.board], [*pos.bitboards], not pos.side, pos.castling,
                    0, pos.material_key, set(), deepcopy(pos.accumulator))
    
def do_move(pos: Position, move: Move) -> Position:
    '''Does a legal move on the position using copy/make.'''

    # Decode move
    start = move_start(move)
    end = move_end(move)
    piece = move_piece(move)
    flag = move_flag(move)
    capture = is_capture(move)
    
    # New attributes
    board = [*pos.board]
    bitboards = [*pos.bitboards]
    castling = pos.castling
    material_key = pos.material_key
    ep_square = 0
    
    # For NNUE updating
    accumulator = [*pos.accumulator]
    dirty_pieces = [(piece, end), (piece, start)]
    
    # Side is side making the move. We will switch sides later
    side = pos.side
    xside = not side

    # Update previous
    if piece & ~0x1 is PAWN or capture:
        previous = set()
    else:
        previous = {pos.__hash__()}.union(pos.previous)

    # Remove captured piece
    if capture:
        # En passant capture
        if flag is ENPASSANT:
            ep_pawn_square = pos.ep_square + (NORTH, SOUTH)[xside]
            ep_pawn = PAWN + xside
            board[ep_pawn_square] = NO_PIECE
            bitboards[ep_pawn] ^= 1 << ep_pawn_square
            bitboards[xside] ^= 1 << ep_pawn_square
            material_key -= MATERIAL_KEYS[ep_pawn]
            dirty_pieces.append((ep_pawn, ep_pawn_square))
        # Regular capture
        else:
            captured = board[end]
            bitboards[captured] ^= 1 << end
            bitboards[xside] ^= 1 << end
            material_key -= MATERIAL_KEYS[captured]
            dirty_pieces.append((captured, end))

    # Remove moving piece from start 
    board[start] = NO_PIECE
    bitboards[piece] ^= 1 << start
    bitboards[side] ^= 1 << start
    material_key -= MATERIAL_KEYS[piece]
    # Place piece on end
    if is_promotion(move):
        piece = flag
        dirty_pieces[0] = (piece, end) 
    board[end] = piece
    bitboards[piece] |= 1 << end
    bitboards[side] |= 1 << end
    material_key += MATERIAL_KEYS[piece]

    # Update accumulator for captures
    if capture:
        # Update white accumulation
        acc = accumulator[WHITE]
        vec0 = FW_VECTORS[WHITE][dirty_pieces[0]]
        vec1 = FW_VECTORS[WHITE][dirty_pieces[1]]
        vec2 = FW_VECTORS[WHITE][dirty_pieces[2]]
        accumulator[WHITE] = [a + v0 - v1 - v2 for a, v0, v1, v2
                              in zip(acc, vec0, vec1, vec2)]
        # Update black accumulation
        acc = accumulator[BLACK]
        vec0 = FW_VECTORS[BLACK][dirty_pieces[0]]
        vec1 = FW_VECTORS[BLACK][dirty_pieces[1]]
        vec2 = FW_VECTORS[BLACK][dirty_pieces[2]]
        accumulator[BLACK] = [a + v0 - v1 - v2 for a, v0, v1, v2
                              in zip(acc, vec0, vec1, vec2)]

    # Update accumulator for normal move
    else:
        # Update white accumulation
        acc = accumulator[WHITE]
        vec0 = FW_VECTORS[WHITE][dirty_pieces[0]]
        vec1 = FW_VECTORS[WHITE][dirty_pieces[1]]
        accumulator[WHITE] = [a + v0 - v1 for a, v0, v1
                              in zip(acc, vec0, vec1)]
        # Update black accumulation
        acc = accumulator[BLACK]
        vec0 = FW_VECTORS[BLACK][dirty_pieces[0]]
        vec1 = FW_VECTORS[BLACK][dirty_pieces[1]]
        accumulator[BLACK] = [a + v0 - v1 for a, v0, v1
                              in zip(acc, vec0, vec1)]

    # Exit early for normal move
    if not flag:
        pass

    # Double pawn push
    elif flag is DOUBLE:
        ep_square = (start + end) // 2

    # Castling
    elif flag is CASTLE:
        # White Kingside castle
        if end == G1:
            rook_start = H1
            rook_end = F1
            rook = WHITE_ROOK
        # Black Kingside castle
        elif end == G8:
            rook_start = H8
            rook_end = F8            
            rook = BLACK_ROOK
        # White Queenside castle
        elif end == C1:
            rook_start = A1
            rook_end = D1            
            rook = WHITE_ROOK            
        # Black Queenside castle
        elif end == C8:
            rook_start = A8
            rook_end = D8
            rook = BLACK_ROOK

        # Remove rook to rook_start
        board[rook_start] = NO_PIECE
        bitboards[rook] ^= 1 << rook_start
        bitboards[side] ^= 1 << rook_start
        # Place rook to rook_end
        board[rook_end] = rook
        bitboards[rook] |= 1 << rook_end
        bitboards[side] |= 1 << rook_end

        # Update white accumulation
        acc = accumulator[WHITE]
        vec0 = FW_VECTORS[WHITE][(rook, rook_end)]
        vec1 = FW_VECTORS[WHITE][(rook, rook_start)]
        accumulator[WHITE] = [a + v0 - v1 for a, v0, v1
                              in zip(acc, vec0, vec1)]
        # Update black accumulation
        acc = accumulator[BLACK]
        vec0 = FW_VECTORS[BLACK][(rook, rook_end)]
        vec1 = FW_VECTORS[BLACK][(rook, rook_start)]
        accumulator[BLACK] = [a + v0 - v1 for a, v0, v1
                              in zip(acc, vec0, vec1)]
        
    # Update castling rights
    castling &= UPDATE_CASTLING_KEYS[start] & UPDATE_CASTLING_KEYS[end]
            
    return Position(board, bitboards, xside,
                    castling, ep_square, material_key, previous, accumulator)

def see(pos: Position, move: Move, max=max):
    '''Static exchange evaluation.'''

    flag = move_flag(move)
    
    if flag is CASTLE:
        return 0

    if move_piece(move) & ~0x1 is KING and not is_capture(move):
        return 0

    side = pos.side
    board = pos.board
    occupied = pos.occupied
    bitboards = pos.bitboards

    # Swap list
    gain = [0]*32
    count = 1

    end = move_end(move)
    start = move_start(move)

    # Initial attackers to square
    attackers = (
        (PAWN_ATTACKS[WHITE][end] & bitboards[BLACK_PAWN]) |
        (PAWN_ATTACKS[BLACK][end] & bitboards[WHITE_PAWN]) |
        (KING_ATTACKS[end] & (bitboards[WHITE_KING] |
                              bitboards[BLACK_KING])) |
        (KNIGHT_ATTACKS[end] & (bitboards[WHITE_KNIGHT] |
                                bitboards[BLACK_KNIGHT])) |
        (rook_attacks(end, occupied) & (bitboards[WHITE_ROOK] |
                                        bitboards[BLACK_ROOK] |
                                        bitboards[WHITE_QUEEN] |
                                        bitboards[BLACK_QUEEN])) |
        (bishop_attacks(end, occupied) & (bitboards[WHITE_QUEEN] |
                                          bitboards[BLACK_QUEEN] |
                                          bitboards[WHITE_BISHOP] |
                                          bitboards[BLACK_BISHOP]))
    )
    
    attacked_value = PIECE_VALUES[
        PAWN if flag is ENPASSANT else board[end]
    ]

    occupied ^= 1 << start
    if flag is ENPASSANT:
        occupied ^= 1 << (end + (SOUTH if side == WHITE else NORTH))

    # Add initial attacked piece value to swap list and switch side
    side = not side
    gain[0] = attacked_value
    
    # After initial capture, the piece that did the capture is now the
    # attacked piece
    piece = board[start]
    attacked_value = PIECE_VALUES[piece]
    
    # Recalculate attackers in case of an x-ray attack
    if piece & ~0x1 in (PAWN, BISHOP, QUEEN):
        attackers |= (
            bishop_attacks(end, occupied) & (bitboards[WHITE_QUEEN] |
                                             bitboards[BLACK_QUEEN] |
                                             bitboards[WHITE_BISHOP] |
                                             bitboards[BLACK_BISHOP])
        )
    if piece & ~0x1 in (ROOK, QUEEN):
        attackers |= (
            rook_attacks(end, occupied) & (bitboards[WHITE_ROOK] |
                                           bitboards[BLACK_ROOK] |
                                           bitboards[WHITE_QUEEN] |
                                           bitboards[BLACK_QUEEN])
        )

    attacked = 0
    attackers &= occupied

    # Loop through the rest of the attackers
    while attackers:
        
        # Find the least valuable attacker for one side and assume it
        # does the capture. So, it is now the new attacked piece.
        for piece in PIECES[PAWN + side::2]:
            attacked = bitboards[piece] & attackers
            if attacked:
                break

        occupied ^= attacked & -attacked
        
        # Recalculate attackers in case of an x-ray attack
        if piece & ~0x1 in (PAWN, BISHOP, QUEEN):
            attackers |= (
                bishop_attacks(end, occupied) & (bitboards[WHITE_QUEEN] |
                                                 bitboards[BLACK_QUEEN] |
                                                 bitboards[WHITE_BISHOP] |
                                                 bitboards[BLACK_BISHOP])
            )
        if piece & ~0x1 in (ROOK, QUEEN):
            attackers |= (
                rook_attacks(end, occupied) & (bitboards[WHITE_ROOK] |
                                               bitboards[BLACK_ROOK] |
                                               bitboards[WHITE_QUEEN] |
                                               bitboards[BLACK_QUEEN])
            )
            
        # Update swap list
        gain[count] = -gain[count - 1] + attacked_value
        attacked_value = PIECE_VALUES[piece]
        
        # Standing pat
        count += 1
        if gain[count - 1] - attacked_value > 0:
            break
        
        # Switch side
        side = not side
        attackers &= occupied

    # Unwind the swap list to calculate final gain/loss
    while count:
        count -= 1
        gain[count - 1] = -max(-gain[count - 1], gain[count])
        
    return gain[0]
