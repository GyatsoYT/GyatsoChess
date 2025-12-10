from defs import *
from move import *
from position import *
from search_data import *

def get_counter_history(data: SearchData, move: Move) -> int:

    parent = data.stack[-1].move

    if parent:
        return data.ch[move_piece(parent) // 2 - 1] \
                      [move_end(parent)] \
                      [move_piece(move) // 2 - 1] \
                      [move_end(move)] \
                      [0]
    return 0
    

def get_quiet_history(pos: Position, data: SearchData, move: Move) -> int:
    
    side = pos.side
    stack = data.stack
    
    hh = data.hh  # History heuristic
    ch = data.ch  # Counter history
    fh = data.fh  # Follow-up history

    parent = stack[-1].move
    grandparent = stack[-2].move

    score = hh[side][move_start_end(move)][0]

    if parent:
        score += ch[move_piece(parent) // 2 - 1] \
                   [move_end(parent)] \
                   [move_piece(move) // 2 - 1] \
                   [move_end(move)] \
                   [0]

    if grandparent:
        score += fh[move_piece(grandparent) // 2 - 1] \
                   [move_end(grandparent)] \
                   [move_piece(move) // 2 - 1] \
                   [move_end(move)] \
                   [0]

    return score

def get_tactical_history(pos: Position, data: SearchData, move: Move) -> int:

    board = pos.board

    end = move_end(move)
    
    if is_promotion(move) or move_flag(move) is ENPASSANT:
        captured = PAWN
    else:
        captured = board[end]

    return data.th[move_piece(move) // 2 - 1][end][captured // 2 - 1][0]

def update_stat(stat: list[int], bonus: int, abs=abs) -> None:
    stat[0] += 64 * bonus - stat[0] * abs(bonus) // 1024

def update_histories(pos: Position, data: SearchData, best: Move, depth: int,
                     tacticals: list[Move], quiets: list[Move]) -> None:

    side = pos.side
    board = pos.board
    stack = data.stack

    bonus = min(depth**2, 576)

    parent = stack[-1].move
    grandparent = stack[-2].move

    if is_tactical(best):

        end = move_end(best)

        if is_promotion(best) or move_flag(best) is ENPASSANT:
            captured = PAWN
        else:
            captured = board[end]

        # Update tactical history stat
        update_stat(data.th[move_piece(best) // 2 - 1] \
                           [end] \
                           [captured // 2 - 1],
                    bonus)

    else:
        
        # Add killer move
        killers = stack[0].killers
        if killers[0] != best:
            killers[1] = killers[0]
        killers[0] = best

        # Update history heuristic stat
        update_stat(data.hh[side][move_start_end(best)], bonus)

        if parent:

            # Add counter move
            data.counters[move_start_end(parent)] = best

            # Update counter history stat
            update_stat(data.ch[move_piece(parent) // 2 - 1] \
                               [move_end(parent)] \
                               [move_piece(best) // 2 - 1] \
                               [move_end(best)],
                        bonus)

        if grandparent:

            # Update follow-up history stat
            update_stat(data.fh[move_piece(grandparent) // 2 - 1] \
                               [move_end(grandparent)] \
                               [move_piece(best) // 2 - 1] \
                               [move_end(best)],
                        bonus)

        # Penalize quiets that are not the best move
        for move in quiets:
            if move != best:

                update_stat(data.hh[side][move_start_end(move)], -bonus)
                
                if parent:
                    
                    update_stat(data.ch[move_piece(parent) // 2 - 1] \
                                       [move_end(parent)] \
                                       [move_piece(move) // 2 - 1] \
                                       [move_end(move)],
                                -bonus)

                if grandparent:

                    update_stat(data.fh[move_piece(grandparent) // 2 - 1] \
                                       [move_end(grandparent)] \
                                       [move_piece(move) // 2 - 1] \
                                       [move_end(move)],
                                -bonus)

    # Penalize tacticals that are not the best move
    for move in tacticals:
        if move != best:
            
            end = move_end(move)

            if is_promotion(move) or move_flag(move) is ENPASSANT:
                captured = PAWN
            else:
                captured = board[end]

            update_stat(data.th[move_piece(move) // 2 - 1] \
                               [end] \
                               [captured // 2 - 1],
                        -bonus)
