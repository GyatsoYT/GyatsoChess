from defs import *

STACK_OFFSET = 2

class StackEntry:

    def __init__(self):
        
        self.move = 0            # Move at given ply
        self.excluded = 0        # For singular search
        self.evaluation = 0      # Static evaluation
        self.killers = zeros(2)  # Killer moves

class Stack:

    def __init__(self):
        
        self.ply = 0  # Search ply 
        self.entries = [StackEntry() for _ in range(MAX_PLY + 2 + 1)]

    def __getitem__(self, delta: int) -> StackEntry:
        return self.entries[self.ply + delta + STACK_OFFSET]
    
class SearchData:

    def __init__(self):

        self.nodes = 0
        self.seldepth = 0

        self.stack = Stack()
        self.counters = zeros(64 * 64)
        
        self.th = zeros(6, 64, 6, 1)       # Tactical history
        self.hh = zeros(2, 64 * 64, 1)     # History heuristic
        self.ch = zeros(6, 64, 6, 64, 1)   # Counter move history
        self.fh = zeros(6, 64, 6, 64, 1)   # Follow up history
