from multiprocessing import Array as TT
from collections import namedtuple
from sys import getsizeof

from defs import *
from position import *
from movegen import is_legal

# Bounds
UNKNOWN_BOUND = 0
LOWER_BOUND = 1
EXACT_BOUND = 2
UPPER_BOUND = 3

# Hash sizes (MB)
MIN_MB = 4
MAX_MB = 4096
DEFAULT_MB = 32
ENTRIES_PER_MB = 25000

TTEntry = namedtuple('TTEntry', 'value depth bound move')

def make_tt(mb: int) -> None:
    return TT('q', ENTRIES_PER_MB * mb, lock=False)

def tt_get(tt: TT, pos: Position) -> TTEntry:
    '''Gets entry from transposition table.'''

    key = pos.__hash__()
    short_key = key >> 45
    entry_llong = tt[key % len(tt)]

    if entry_llong == 0 or short_key != entry_llong & 0x7FFFF:
        return None
    
    return TTEntry((entry_llong >> 48),             # value
                   (entry_llong >> 42) & 0x3F,      # depth
                   (entry_llong >> 40) & 0x3,       # bound
                   (entry_llong >> 19) & 0x1fffff)  # move

def tt_put(tt: TT, pos: Position,
           value: Value, depth: int, bound: int, move: Move) -> None:
    '''
    Stores transposition table entry in the following format:

    bits [63-48] value
    bits [47-42] depth
    bits [41-40] bound
    bits [39-19] move
    bits [18-00] short_key
    '''

    key = pos.__hash__()
    short_key = key >> 45
    index = key % len(tt)
    entry_llong = tt[index]
    
    # Always overwrite except when for its the same position at higher
    # depth or it's an exact bound. Replacement scheme from Weiss.
    if move and (bound is EXACT_BOUND
                 or short_key != entry_llong & 0x7FFFF
                 or depth + 4 >= (entry_llong >> 42) & 0x3F): 
        # Write value to table
        tt[index] = ((value << 48) | (depth << 42) |
                     (bound << 40) | (move << 19) | (short_key))

def hash_full(tt: TT) -> int:
    '''Estimates load factor of transposition table (1 = 0.1%)'''
    raise NotImplementedError
