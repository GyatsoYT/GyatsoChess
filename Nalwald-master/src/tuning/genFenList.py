import chess.pgn
import sys

pgn = open(sys.argv[1])

i = 0
while True:
    game = chess.pgn.read_game(pgn)
    if game is None:
        break
    result = game.headers["Result"]
    # elo = min(int(game.headers["WhiteElo"]), int(game.headers["BlackElo"]))
    # time_control = game.headers["TimeControl"]
    # time_forfeit = game.headers["Termination"] == "Time forfeit"
    # if time_forfeit or elo < 2900:
    #     continue

    if result == "*":
        continue
    board = game.board()
    for move in game.mainline_moves():
        board.push(move)
        i += 1
        r = 0.5
        if result == "0-1":
            r = 0.0
        elif result == "1-0":
            r = 1.0
        else:
            assert(result == "1/2-1/2")
        print(board.fen(), r)
