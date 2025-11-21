import version, printMarkdownSubset

import std/[terminal, strformat]

proc printSeperatorLine() =
  styledEcho {styleDim}, "-----------------------------------------"

proc help*(params: openArray[string]) =
  if params.len == 0:
    printSeperatorLine()
    #!fmt: off
    printMarkdownSubset(
      "Possible commands\n",
      "- *uci*\n",
      "- *setoption*\n",
      "- *isready*\n",
      "- *position*\n",
      "- *go*\n",
      "- *stop*\n",
      "- *quit*\n",
      "- *ucinewgame*\n",
      "- *moves*\n",
      "- *multipv*\n",
      "- *hash*\n",
      "- *threads*\n",
      "- *print*\n",
      "- *fen*\n",
      "- *perft*\n",
      "- *test*\n",
      "- *speedtest*\n",
      "- *eval*\n",
      "- *flip*\n",
      "- *piecevalues*\n",
      "- *poem*\n",
      "- *about*\n",
      "- *help*\n",
      "Use `help <command>` to get info about a specific command",
    )
    #!fmt: on
    printSeperatorLine()
  else:
    printSeperatorLine()
    case params[0]
    of "uci":
      printMarkdownSubset(
        "Tells engine to use the uci (universal chess interface). ",
        "After receiving the uci command the engine will identify itself with the `id` command ",
        "and send the `option` commands to inform which settings the engine supports if any. ",
        "After that the engine will sent `uciok` to acknowledge the uci mode.",
      )
    of "setoption":
      printMarkdownSubset "**setoption name <id> [value <x>]**"
      printMarkdownSubset(
        "This can be used to change the internal setting `<id>` to ",
        "the value `<x>`. For a setting with the `button` type no value is needed. ",
        "Some examples:```\n", "setoption name Hash value 512\n",
        "setoption name Threads value 8\n", "setoption name UCI_Chess960 value true```",
      )
    of "isready":
      printMarkdownSubset(
        "Sends a ping to the engine that will be shortly answered with `readyok` if the engine is still alive."
      )
    of "position":
      printMarkdownSubset "**position [fen <fenstring> | startpos] moves <move_1> ... <move_i>**"
      printMarkdownSubset(
        "Sets up the position described in by `<fenstring>` on the internal board and ",
        "plays the moves `<move_1>` to `<move_i>` on the internal chess board. ",
        "To start from the start position the string `startpos` must be sent instead of `fen <fenstring>`. ",
        "If this position is from a different game than ",
        "the last position sent to the engine, the command `ucinewgame` should be sent inbetween.",
      )
    of "go":
      printMarkdownSubset "**go [wtime|btime|winc|binc|movestogo|movetime|depth|infinite [<x>]]...**"
      printMarkdownSubset(
        "Starts calculating on the current position set up with the `position` command. ",
        "There are a number of commands that can follow this command, all will be sent as arguments ",
        "of the same command. ",
        "If one command is not sent its value will not influence the search.\n",
        "- *wtime <x>*\n", "    White has `<x>` msec left on the clock.\n",
        "- *btime <x>*\n", "    Black has `<x>` msec left on the clock.\n",
        "- *winc <x>*\n", "    White has `<x>` msec increment per move.\n",
        "- *binc <x>*\n", "    Black has `<x>` msec increment per move.\n",
        "- *movestogo <x>*\n",
        "    There are `<x>` moves to the next time control. If this is not sent sudden death is assumed.\n",
        "- *depth <x>*\n", "    Search to `<x>` plies only.\n", "- *movetime <x>*\n",
        "    Search for exactly `<x>` msec.\n", "- *infinite*\n",
        "    Search until the `stop` or `quit` command.\n", "Example:```\n",
        "go depth 35 wtime 60000 btime 60000 winc 1000 binc 1000```\n",
        "(Starts a search to a maximum of depth 35 and assumes that the ",
        "time control is 1 min + 1 second per move.)",
      )
    of "stop":
      echo "Stops the calculation as soon as possible."
    of "quit":
      echo "Quits the program as soon as possible."
    of "ucinewgame":
      echo "This is sent to the engine when the next search should be assumed to be from a different game."
    of "moves":
      printMarkdownSubset "**moves <move_1> ... <move_i>**"
      printMarkdownSubset(
        "Plays the moves `<move_1>` to `<move_i>` on the internal chess board. The keyword `moves` can also be",
        " omitted: If all moves are detected to be legal they will be played on the internal board. ",
        "Example:\n",
        "`e2e4 c7c6 d2d4 d7d5` will have the same effect as `moves e2e4 c7c6 d2d4 d7d5`",
      )
    of "multipv", "hash", "threads":
      printMarkdownSubset "**multipv|hash|threads <x>**"
      printMarkdownSubset(
        "Sets the respective option \"MultiPV\", \"Hash\", or \"Threads\" with value `<x>`. ",
        "Shortcut for the longer `setoption name <Option> value <x>`.",
      )
    of "print":
      printMarkdownSubset "**print [debug]**"
      printMarkdownSubset(
        "Prints the current internal board. If `debug` is added, a debug representation of the board is printed."
      )
    of "fen":
      echo "Prints the FEN notation of the current internal board."
    of "perft":
      printMarkdownSubset "**perft <x>**"
      printMarkdownSubset "Calculates the perft of the current position to depth `<x>`."
    of "test":
      echo "Runs a number of tests (can take some time)."
    of "speedtest":
      echo "Runs a speed tests to determine the NPS metric for move generation."
    of "eval":
      echo "Prints the static evaluation value for the current internal position."
    of "piecevalues":
      echo "Prints the values for each piece type."
    of "flip":
      printMarkdownSubset "**flip [horizontally|vertically]**"
      printMarkdownSubset(
        "Flips the current board. If `horizontally` is used, then the pieces will be mirrored from left to right, when ",
        "`vertically` is selected, pieces are mirrored from top to bottom and additionally the colors of pieces are swapped.",
      )
    of "about":
      printMarkdownSubset "**about [extra]**"
      printMarkdownSubset(
        "Prints some info about the program. When `extra` is added, additional information will be provided."
      )
    of "help":
      printMarkdownSubset "**help [<command>]**"
      printMarkdownSubset(
        "Prints all possible commands, or if `<command>` is given, then help about `<command>` is printed."
      )
    of "poem":
      printMarkdownSubset("*Try it* :)")
    else:
      echo "Unknown command: ", params[0]

    printSeperatorLine()

proc printLogo*() =
  echo fmt"---------------- Nalwald ----------------"
  echo fmt"       __,      o     n_n_n   ooooo    + "
  echo fmt" o    // o\    ( )    \   /    \ /    \ /"
  echo fmt"( )   \  \_>   / \    |   |    / \    ( )"
  echo fmt"|_|   /__\    /___\   /___\   /___\   /_\"
  echo fmt"------------ by Jost Triller ------------"

proc about*(extra = true) =
  const readme = readFile("README.md")
  printSeperatorLine()
  echo "Nalwald ", versionOrId()
  echo "Compiled at ", compileDate()
  echo "Copyright © 2016-", compileYear(), " by Jost Triller"
  echo "git hash: ", commitHash()
  printSeperatorLine()
  if extra:
    printMarkdownSubset readme
    printSeperatorLine()
