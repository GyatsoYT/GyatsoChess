from time import perf_counter

from defs import *
from pseudothread import SharedInt

MOVE_OVERHEAD = 100 / 1e3

class TimeManager:

    def __init__(self, search_flag: SharedInt,
                 movetime: int, time: int, inc: int, movestogo: int) -> None:

        self.depth = 0
        self.stability = 0

        self.start = perf_counter()
        self.search_flag = search_flag
        self.movestogo = min(40, movestogo) if movestogo else 30

        # Convert from ms to s
        self.movetime = movetime / 1e3
        self.time = time / 1e3
        self.inc = inc / 1e3
    
        if self.movetime:
            self.alloc = self.movetime - MOVE_OVERHEAD

        elif self.time:
            self.alloc = min(self.time / self.movestogo + self.inc,
                             self.time - MOVE_OVERHEAD)
            self.ideal_alloc = self.alloc

        else:
            self.alloc = float('inf')

    def time_elapsed(self):
        return perf_counter() - self.start

    def out_of_time(self) -> bool:
        '''Check if we are out of time.'''

        if self.depth and self.time_elapsed() >= self.alloc:
            self.search_flag.value = False
            return True
        
        return False

    def keep_searching(self) -> None:

        if not self.time:
            return

        # alloc is all the remaining time for movestogo == 1 and
        # scales down to half of remaining time at higher movestogo
        self.alloc = min(self.time * (0.5 / self.movestogo + 0.5) + self.inc,
                         self.time - MOVE_OVERHEAD)

    def update(self, values: list[Value], best_moves: list[Move]) -> None:
        '''Recalculates allocated time.'''

        self.depth += 1

        if not self.time:
            return

        if best_moves[-1] == best_moves[-2]:
            self.stability = min(1, self.stability + 0.1)
        else:
            self.stability = 0

        difference = values[-1] - values[-2]

        if abs(difference) <= WINDOW:
            self.alloc = self.ideal_alloc
            return

        if difference < 0:
            self.ideal_alloc *= min(1.16, 1.04 * (-difference // WINDOW))
        else:
            self.ideal_alloc *= min(1.04, 1.02 * (difference // WINDOW))

        self.ideal_alloc = min(self.ideal_alloc, self.time - MOVE_OVERHEAD)
        self.alloc = self.ideal_alloc

        if self.time_elapsed() > (2 - self.stability) * self.alloc / 2:
            self.search_flag.value = False
            
