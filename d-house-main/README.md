# Introduction
D-house is a UCI-compliant chess engine written in Python.

# UCI configurations

**Hash**

Size of the hash table in megabytes.

**Threads**

Number of threads used in searching. Set this to the number of CPU cores available for best performance.

**OnlineSyzygy**

Allow D-house to probe the online [lichess](https://tablebase.lichess.ovh) 7-man Syzygy tablebase.

# Run it
D-house only uses the Python standard library, so you only need a working version of Python 3.9 or above.
However, you will need to install a program such as 
[pyinstaller](https://pypi.org/project/pyinstaller/), or [py2exe](https://pypi.org/project/py2exe/) if you wish to create an executable. 
```
pyinstaller --onefile main.py --name=d-house
```
Currently only tested on Windows but may work on other operating systems.

# Influences
D-house is derived from Berserk. This chess engine would not have been possible without the following resources:
* [Jay Honnold - Berserk](https://github.com/jhonnold/berserk)<br/>
* [Chess Programming Wiki](https://www.chessprogramming.org/Main_Page)<br/>
* [Andy Grant - Ethereal](https://github.com/AndyGrant/Ethereal)<br/>
* [Daniel Inführ - Gigantua](https://github.com/Gigantua/Gigantua)<br/>
* [Erik Madsen - MadChess](https://www.madchess.net/)<br/>
* [Maksim Korzh - BBC](https://github.com/maksimKorzh/bbc)<br/>
* [Stockfish Team - Stockfish](https://github.com/official-stockfish/Stockfish)<br/>
* [Terje Kirstihagen - Weiss](https://github.com/TerjeKir/weiss)<br/>
* [Thomas Ahle - Sunfish](https://github.com/thomasahle/sunfish)<br/>
