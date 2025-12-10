from multiprocessing import Array
from multiprocessing import Process as PseudoThread
from multiprocessing import Value as SharedInt

from defs import *
from position import *
from transposition import *

MIN_THREADS = 1
MAX_THREADS = 8
DEFAULT_THREADS = 1

class SharedMemory:

    def __init__(self) -> None:

        self.search_flag = SharedInt('b', lock=False)
        self.bestmove = SharedInt('L')
        self.nodes = SharedInt('L')
        
        self.limits = Array('L', 5, lock=False)
        self.pos_repr = Array('u', 65535, lock=False)
    
    def set_limits(self, depth: int,
                   movetime: int, time: int, inc: int, movestogo: int) -> None:

        self.limits[0] = min(MAX_DEPTH, depth) if depth else MAX_DEPTH
        self.limits[1] = movetime
        self.limits[2] = time
        self.limits[3] = inc
        self.limits[4] = movestogo

    def set_pos(self, pos: Position) -> None:

        for i in range(len(self.pos_repr)):
            self.pos_repr[i] = '\x00'
        
        for i, char in enumerate(str(repr(pos))):
            self.pos_repr[i] = char
        
    @property
    def pos(self) -> Position:
        return eval(''.join(self.pos_repr).replace('\x00', ''))      
        
def init_pool(pool: list[PseudoThread], threads: int,
              func: callable, shared: SharedMemory, tt: TT) -> None:

    setattr(shared, 'tt', tt)

    for thread in pool:
        thread.terminate()

    pool.clear()

    for thread in range(threads):
        thread = PseudoThread(target=func, args=[thread, shared])
        thread.start()
        pool.append(thread)
    
