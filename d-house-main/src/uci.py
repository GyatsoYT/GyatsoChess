from defs import *
from perft import *
from search import *
from syzygy import *
from transposition import *

def print_options():
    '''Prints available engine configurations.'''
    
    print(f'id name D-House {VERSION}')
    print('id author Alvin Peng')
    print('option name Threads type spin default 1 min 1 max 8')
    print('option name Hash type spin default 32 min 4 max 4096')
    print('option name Clear Hash type button')
    print('option name OnlineSyzygy type check default false')
    print('uciok')
        
def uci_loop() -> None:

    online_syzygy = False

    # Init startpos and shared memory object
    pos = parse_fen()
    shared = SharedMemory()
    shared.set_pos(pos)

    # Init transposition table
    mb = DEFAULT_MB
    tt = make_tt(mb)

    # Init pool
    threads = 1
    pool = []
    init_pool(pool, threads, spin, shared, tt)
    
    while True:
        string = input()

        if string == 'uci':
            print_options()

        if string == 'isready':
            for thread in pool:
                assert thread.exitcode is None, f'Exitcode {thread.exitcode}'
            print('readyok')

        if 'setoption name' in string:
            tokens = string.split()
            
            # Set thread count
            if 'setoption name Threads value' in string:
                threads = min(MAX_THREADS, max(MIN_THREADS, int(tokens[-1])))
                init_pool(pool, threads, spin, shared, tt)
                print(f'info string Number of threads set to {threads}')
                
            # Set hash table size
            if 'setoption name Hash value' in string:
                mb = min(MAX_MB, max(MIN_MB, int(tokens[-1])))
                init_pool(pool, threads, spin, shared, tt)
                print(f'info string Size of Hashtable set to {mb}')
                
            # Clear hash
            if 'setoption name Clear Hash' in string:
                tt = make_tt(mb)
                init_pool(pool, threads, spin, shared, tt)
                
            # OnlineSyzygy
            if 'setoption name OnlineSyzygy value' in string:
                online_syzygy = True if 'true' in string else False
                print(f'info string Online Syzygy Tablebase '
                      f'Probing set to {online_syzygy}')

        if string == 'ucinewgame':
            tt = make_tt(mb)
            init_pool(pool, threads, spin, shared, tt)

        if 'position' in string:
            
            # Start position
            if 'startpos' in string:
                pos = parse_fen()
                string = string.replace('position startpos ', '')
                tokens = string.split()
                
            # Specific fen
            elif 'fen' in string:
                if 'move' not in string:
                    string += ' move'
                string = string.replace('position fen ', '')
                fen_end = string.index('move') 
                tokens = string.split()
                pos = parse_fen(string[:fen_end].replace('moves', ''))
                
            # Moves after given position
            tokens = string.split()
            for token in tokens:
                for move in gen_perft(pos):
                    if move_to_str(move) == token:
                        pos = do_move(pos, move)
                        
            shared.set_pos(pos)
                
        if 'go' in string:
            tokens = string.split()
            tokens.remove('go')
            
            # Perft test
            if tokens and tokens[0] == 'perft':
                perft_divide(pos, int(tokens[1]))
                
            # Search
            else:
                depth = 0
                movetime = 0
                time = 0
                inc = 0
                movestogo = 0

                if 'depth' in string:
                    depth = int(tokens[tokens.index('depth') + 1])
                if 'movetime' in string:
                    movetime = int(tokens[tokens.index('movetime') + 1])
                if 'wtime' in string and pos.side == WHITE:
                    time = int(tokens[tokens.index('wtime') + 1])
                if 'btime' in string and pos.side == BLACK:
                    time = int(tokens[tokens.index('btime') + 1])
                if 'movestogo' in string:
                    movestogo = int(tokens[tokens.index('movestogo') + 1])

                # Probe tablebase at root
                if online_syzygy and bits(pos.occupied) <= 7:
                    # Probe success
                    if probe_root(pos):
                        continue
                    # Probing timed out or failed. Need to search
                    else:
                        time = max(0, time - TB_OVERHEAD * 1e3)
                        movetime = max(0, movetime - TB_OVERHEAD * 1e3)

                shared.set_limits(depth, movetime, time, inc, movestogo)
                shared.search_flag.value = True

        if string == 'stop':
            shared.search_flag.value = False

        if string == 'quit':
            for thread in pool:
                thread.terminate()
            quit()
