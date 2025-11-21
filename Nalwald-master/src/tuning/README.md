##### Generate positions
```
nim r generatePositions.nim
```

##### Merge duplicates and select random subset
```
nim r mergeDuplicateAndSelect.nim <input.epd> <output.epd> <selection_ratio, e.g. 0.05> <useOnlyQuiet, true or false>
```

##### Label positions

Create an empty file called `quietSetNalwald.epd`.

```
mv quietSetNalwald.epd quietSetNalwald.epd.backup
touch quietSetNalwald.epd
```

Label positions.

```
nim r labelPositions.nim
```

##### Run optimization
```
nim r optimization.nim
```

##### Get piece values
```
nim r calculatePieceValue.nim
```

##### Generate positions and create label
```
nim r generateTrainingData.nim
```

##### Create epds with label from PGNs
```
./trainingDataFromPGNs.sh <output.epd> <input1.pgn> <input2.pgn> ... <inputN.pgn>
```

##### How data sets are generated

###### quietSetNalwald.epd

- a number of random games are played, at random evaluation calls the positions are collected
- non-quiet and positions without legal moves are removed
- from the remaining games will be played one game each with Nalwald at ~80ms per move
- the result of that game will be the target value of the position

###### quietSmallNalwaldCCRL4040.epd

- a number of positions from CCRL4040 games are randomly selected (without early opening positions)
- non-quiet and positions without legal moves are removed
- from the remaining games will be played one game each with Nalwald at ~80ms per move
- the result of that game will be the target value of the position

###### quietSetCombinedCCRL4040.epd

- the target value of the positions of `quietSmallNalwaldCCRL4040.epd` will be averaged over the results of the respective CCRL4040 games (of players with Elo 2700 and higher) and the games that Nalwald played

###### quietLeavesSmallPoolGamesNalwaldSearchLabeled.epd
- randomly selected number of positions from games between Nalwald and other engines
- for each position made a search with 5000 nodes and selected ~2 leave node positions
- removed all non-quiet positions
- labeled positions with result of Nalwald search with 2,000,000 nodes

###### quietSmallPoolGamesNalwald2Labeled.epd
- removed non-quiet positions from games played between Nalwald and other engines
- randomly select 4,000,000 positions
- three copies of that set: labeled with original game result, labeled with Nalwald self-play result, labeled with search
- merge three copies

###### gamesNalwald.epd
- Used [`trainingDataFromPGNs.sh`](./trainingDataFromPGNs.sh) to extract positions from games played between Nalwald and other engines

###### trainingSet_*.bin
- Self-play games using [`generateTrainingData.nim`](./generateTrainingData.nim)
- 2023-10-03-18-29-44 to 2023-10-06-17-43-01 with cdd26b330c8d1c6ab765363d662a44c04087cb40
- 2023-12-22-16-08-28 to 2023-12-28-11-23-21 with 65aa2f153635ab204d180f16199bed34b022f39b