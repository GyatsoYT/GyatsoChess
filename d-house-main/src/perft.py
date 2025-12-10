from time import perf_counter as time

from defs import *
from movegen import *
from position import *

def perft(pos: Position, depth: int) -> int:

    nodes = 0

    if depth == 1:
        return len(list(gen_perft(pos)))
    if depth == 0:
        return 1

    for move in gen_perft(pos):
        nodes += perft(do_move(pos, move), depth - 1)

    return nodes

def perft_divide(pos: Position, depth: int) -> None:

    start = time()
    nodes = 0

    assert depth >= 1

    for move in gen_perft(pos):
        count = perft(do_move(pos, move), depth - 1)
        nodes += count
        print(f'{move_to_str(move)}: {count}')

    t = round(time() - start, 3)
    
    print()
    print(f'Nodes: {nodes}')
    print(f'Time:  {round(t * 1e3)}ms')
    print(f'NPS:   {round(nodes / t)}')
    print()
