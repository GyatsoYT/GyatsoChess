import socket
import ssl
from urllib import request, error

from move import move_to_str
from defs import *
from position import *
from pseudothread import *

TB_OVERHEAD = 100 / 1e3

url = 'https://tablebase.lichess.ovh/standard?fen=' 
ssl._create_default_https_context = ssl._create_unverified_context

def probe_root(pos: Position) -> int:
    '''Probes online tablebase at root.'''

    fen = as_fen(pos).replace(' ', '_')
    null, true, false = None, True, False
    
    try:
        with request.urlopen(url + fen, timeout=TB_OVERHEAD) as response:
            info = eval(response.read().decode('utf-8'))

            moves_info = info['moves']
            category = info['category']
            dtm = info['dtm'] or 100
            
            # No legal moves
            if not moves_info:
                return False

            bestmove = moves_info[0]['uci']
            if category == 'draw':
                score = f'cp 0'
            else:
                score = f'cp {TB_WIN if category == "win" else -TB_WIN}'

            print(f'info '
                  f'depth 1 '
                  f'score {score} '
                  f'nodes 0 '
                  f'nps 0 '
                  f'time 0 '
                  f'pv {bestmove}')            
            print('bestmove ' + bestmove)
            return True

    except socket.timeout:
        pass

    except error.URLError:
        pass

    return False
