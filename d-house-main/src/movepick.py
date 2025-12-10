from __future__ import annotations
from functools import cached_property, partial

from defs import *
from move import *
from history import *
from movegen import *
from position import *

PHASES = (
    INIT_MOVE_PICKER,
    PLAY_TT_MOVE,
    PLAY_GOOD_TACTICALS,
    PLAY_QUIETS,
    PLAY_BAD_TACTICALS,
) = range(5)

sort_scored = partial(sorted, key=lambda scored: scored[1], reverse=True)

class MovePicker:

    def __init__(self, pos: Position, data: SearchData):

        self.phase = INIT_MOVE_PICKER
        
        self.pos = pos
        self.data = data

        # Killers
        self.k1 = data.stack[0].killers[0]
        self.k2 = data.stack[0].killers[1]

        # Counter move
        parent = data.stack[-1].move
        if parent:
            self.counter = data.counters[move_start_end(parent)]
        else:
            self.counter = NULL_MOVE

    def __call__(self, quiescence: bool=False,
                 cutoff: Value=0, tt_move: Move=NULL_MOVE) -> iter:

        pos = self.pos
        data = self.data
        board = pos.board
        in_check = pos.in_check

        # Transposition table move phase
        self.phase = PLAY_TT_MOVE
        
        if not quiescence and is_legal(pos, tt_move):
            yield tt_move

        # Play good tactical phase
        self.phase = PLAY_GOOD_TACTICALS
        
        bad_tacticals = []
        
        # Loop through all tacticals
        for move, _ in self.scored_tacticals:
            # Calculate static exchange evaluation
            see_value = see(pos, move)
            # Add bad tactical to bad_tacticals
            if see_value < cutoff:
                if cutoff <= 0:
                    attacker = move_piece(move) & ~0x1
                    if move_flag(move) is ENPASSANT:
                        victim = PAWN
                    elif is_capture(move):
                        victim = board[move_end(move)] & ~0x1
                    else:
                        victim = -1
                    if attacker > victim:
                        bad_tacticals.insert(0, (move, see_value))
                    else:
                        yield move
                else:
                    bad_tacticals.insert(0, (move, see_value))
            # Play good tactical move
            else:
                yield move

        # Play quiets phase
        self.phase = PLAY_QUIETS

        if not quiescence:
            # Killer 1
            k1 = self.k1
            if k1 != tt_move and is_legal(pos, k1):
                yield k1
            # Killer 2
            k2 = self.k2
            if k2 != tt_move and is_legal(pos, k2):
                yield k2
            # Play counter
            counter = self.counter
            if counter not in (tt_move, k1, k2) and is_legal(pos, counter):
                yield counter

        if not quiescence or in_check:
            # Loop through scored quiets
            for move, _ in self.scored_quiets:
                # Play quiet if it is not a killer/counter/tt_move
                if (in_check
                    or move not in (self.k1, self.k2, self.counter, tt_move)):
                    yield move

        # Play bad tacticals phase
        self.phase = PLAY_BAD_TACTICALS
        
        # Loop through bad tacticals
        for move, _ in sort_scored(bad_tacticals):
            if in_check or move is not tt_move:
                yield move
        
    @property
    def scored_quiets(self) -> list:
        '''Sorted quiets based on history.'''

        pos = self.pos
        data = self.data
        
        scored_quiets = []  # (move, score)
        
        for move in gen_quiets(pos):
            score = get_quiet_history(pos, data, move)
            scored_quiets.append((move, score))

        return sort_scored(scored_quiets)

    @cached_property
    def scored_tacticals(self) -> list:
        '''Sorted tacticals based on history.'''

        pos = self.pos
        data = self.data
        board = pos.board

        scored_tacticals = []  # (move, score)

        for move in gen_tacticals(pos):
            score = (PIECE_VALUES[board[move_end(move)]] * 32
                     + get_tactical_history(pos, data, move))
            scored_tacticals.append((move, score))

        return sort_scored(scored_tacticals)       
