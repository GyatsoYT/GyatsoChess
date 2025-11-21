import
  ../position,
  ../types,
  ../perft,
  ../hashTable,
  ../positionUtils,
  ../evaluation,
  ../utils,
  ../see,
  ../game,
  ../version,
  exampleFens,
  testPerft

import std/[strutils, terminal, options, strformat, streams]

const maxNumPerftNodes {.intdefine.} = int.high

proc testFen(): Option[string] =
  for fen in someFens:
    let
      position = fen.toPosition
      fenTestLen =
        if position.isChess960:
          fen.splitWhitespace()[0].len
        else:
          fen.len
    if fen[0 ..< fenTestLen] != position.fen[0 ..< fenTestLen]:
      return some fmt"{fen} != {fen.toPosition.fen}"

  const
    frcFen1 = "qrrk1bnn/8/4b3/pppppppp/PPPPPPPP/4B3/8/QRRK1BNN w Qq - 8 13"
    frcFen2 = "qrrk1bnn/8/4b3/pppppppp/PPPPPPPP/4B3/8/QRRK1BNN w Bb - 8 13"
  if frcFen1.toPosition(suppressWarnings = true).fen != frcFen2:
    return some fmt"{frcFen1} should be converted to {frcFen2}"

  none string

proc perftAndTestPerft(): Option[string] =
  const weirdFen = "QQQQQQBk/Q6B/Q6Q/Q6Q/Q6Q/Q6Q/Q6Q/KQQQQQQQ w - - 0 1"

  var
    hashTable = newHashTable()
    testPerftState = newTestPerftState(addr hashTable)

  hashTable.setByteSize(megaByteToByte * 16)

  for (fen, trueNumNodesList) in perftFens:
    let position = fen.toPosition

    for depth in 1 .. trueNumNodesList.len:
      let trueNumNodes = trueNumNodesList[depth - 1]

      if trueNumNodes > maxNumPerftNodes:
        break

      let fastPerftResult = position.perft(depth.Ply)
      if fastPerftResult != trueNumNodes:
        return some &"Fast perft to depth {depth} for \"{fen}\" should be {trueNumNodes} but is {fastPerftResult}"

      try:
        let
          testPseudoLegality = trueNumNodes < 20_000 and position.legalMoves.len <= 256
          testPerftResult = position.runTestPerft(
            testPerftState, depth = depth.Ply, testPseudoLegality = testPseudoLegality
          )

        if testPerftResult != trueNumNodes and fen != weirdFen:
          return some &"Test perft to depth {depth} for \"{fen}\" should be {trueNumNodes} but is {testPerftResult}"
      except Exception:
        return some getCurrentExceptionMsg()
  none string

proc testZobristKeys(): Option[string] =
  for fen1 in someFens:
    for fen2 in someFens:
      var
        p1 = fen1.toPosition
        p2 = fen2.toPosition
      p1.halfmoveClock = p2.halfmoveClock
      p1.halfmovesPlayed = p2.halfmovesPlayed
      if p1.fen != p2.fen and p1.zobristKey == p2.zobristKey:
          return some &"Zobrist key for both \"{fen1}\" and \"{fen2}\" is the same ({fen1.toPosition.zobristKey})"
      if (p1[pawn] == p2[pawn] and p1[white, pawn] == p2[white, pawn]) != (p1.pawnKey == p2.pawnKey):
        return some &"Pawn key for both \"{fen1}\" and \"{fen2}\" is the same ({fen1.toPosition.pawnKey})"
  none string

proc playGames(): Option[string] =
  for fen in someFens:
    try:
      var game = newGame(fen.toPosition, maxNodes = 2_000)
      discard game.playGame()
    except Exception:
      return some &"Encountered error while playing a game from start position \"{fen}\": {getCurrentExceptionMsg()}"
  none string

proc positionStreams(): Option[string] =
  for fen in someFens:
    let position = fen.toPosition

    var strm = newStringStream()
    strm.write position.toMinimal
    strm.setPosition(0)
    let position2 = strm.readMinimalPosition.toPosition
    strm.close()
    if position2 != position:
      return some &"Failed to convert to binary stream and back for \"{fen}\""
  none string

proc positionTransforms(): Option[string] =
  for fen in someFens:
    for i, transform in [
      (
        proc(position: Position): Position =
          position.rotate.rotate
      ),
      (
        proc(position: Position): Position =
          position.mirrorHorizontally
          .mirrorVertically(swapColors = false).mirrorHorizontally
          .mirrorVertically(swapColors = false)
      ),
      (
        proc(position: Position): Position =
          position.rotate.mirrorVertically.rotate.mirrorVertically
      ),
      (
        proc(position: Position): Position =
          position.mirrorVertically.mirrorHorizontally.rotate
          .mirrorVertically(swapColors = false).rotate.mirrorVertically
          .mirrorVertically(swapColors = false).mirrorHorizontally
      ),
    ]:
      let
        position = fen.toPosition
        transformed = transform(position)

      if position != transformed:
        echo "position: ", position.fen
        echo "transformed: ", transformed.fen

        return some &"Failed position transform number {i} for position {fen}"

    for i, transform in [
      (
        proc(position: Position): Position =
          position.mirrorVertically
      ),
      (
        proc(position: Position): Position =
          position.mirrorHorizontally
      ),
      (
        proc(position: Position): Position =
          position.rotate
      ),
    ]:
      let
        position = fen.toPosition
        transformed = transform(position)

      if transformed.fen.toPosition != transformed:
        return some &"Transform number {i} for position {fen} is causing corrupt position state"
  none string

proc seeTest(): Option[string] =
  #!fmt: off
  const data =
    [
      ("4R3/2r3p1/5bk1/1p1r3p/p2PR1P1/P1BK1P2/1P6/8 b - - 0 1", "h5g4", 0.Value),
      ("4R3/2r3p1/5bk1/1p1r1p1p/p2PR1P1/P1BK1P2/1P6/8 b - - 0 1", "h5g4", 0.Value),
      ("4r1k1/5pp1/nbp4p/1p2p2q/1P2P1b1/1BP2N1P/1B2QPPK/3R4 b - - 0 1", "g4f3", knight.value - bishop.value),
      ("2r1r1k1/pp1bppbp/3p1np1/q3P3/2P2P2/1P2B3/P1N1B1PP/2RQ1RK1 b - - 0 1", "d6e5", pawn.value),
      ("7r/5qpk/p1Qp1b1p/3r3n/BB3p2/5p2/P1P2P2/4RK1R w - - 0 1", "e1e8", 0.Value),
      ("6rr/6pk/p1Qp1b1p/2n5/1B3p2/5p2/P1P2P2/4RK1R w - - 0 1", "e1e8", -rook.value),
      ("7r/5qpk/2Qp1b1p/1N1r3n/BB3p2/5p2/P1P2P2/4RK1R w - - 0 1", "e1e8", -rook.value),
      ("6RR/4bP2/8/8/5r2/3K4/5p2/4k3 w - - 0 1", "f7f8q", bishop.value-pawn.value),
      ("6RR/4bP2/8/8/5r2/3K4/5p2/4k3 w - - 0 1", "f7f8n", knight.value-pawn.value),
      ("7R/4bP2/8/8/1q6/3K4/5p2/4k3 w - - 0 1", "f7f8r", -pawn.value),
      ("8/4kp2/2npp3/1Nn5/1p2PQP1/7q/1PP1B3/4KR1r b - - 0 1", "h1f1", 0.Value),
      ("8/4kp2/2npp3/1Nn5/1p2P1P1/7q/1PP1B3/4KR1r b - - 0 1", "h1f1", 0.Value),
      ("2r2r1k/6bp/p7/2q2p1Q/3PpP2/1B6/P5PP/2RR3K b - - 0 1", "c5c1", 2*rook.value-queen.value),
      ("r2qk1nr/pp2ppbp/2b3p1/2p1p3/8/2N2N2/PPPP1PPP/R1BQR1K1 w qk - 0 1", "f3e5", pawn.value),
      ("6r1/4kq2/b2p1p2/p1pPb3/p1P2B1Q/2P4P/2B1R1P1/6K1 w - - 0 1", "f4e5", 0.Value),
      ("3q2nk/pb1r1p2/np6/3P2Pp/2p1P3/2R4B/PQ3P1P/3R2K1 w - h6 0 1", "g5h6", 0.Value),
      ("3q2nk/pb1r1p2/np6/3P2Pp/2p1P3/2R1B2B/PQ3P1P/3R2K1 w - h6 0 1", "g5h6", pawn.value),
      ("2r4r/1P4pk/p2p1b1p/7n/BB3p2/2R2p2/P1P2P2/4RK2 w - - 0 1", "c3c8", rook.value),
      ("2r5/1P4pk/p2p1b1p/5b1n/BB3p2/2R2p2/P1P2P2/4RK2 w - - 0 1", "c3c8", rook.value),
      ("2r4k/2r4p/p7/2b2p1b/4pP2/1BR5/P1R3PP/2Q4K w - - 0 1", "c3c5", bishop.value),
      ("8/pp6/2pkp3/4bp2/2R3b1/2P5/PP4B1/1K6 w - - 0 1", "g2c6", pawn.value-bishop.value),
      ("4q3/1p1pr1k1/1B2rp2/6p1/p3PP2/P3R1P1/1P2R1K1/4Q3 b - - 0 1", "e6e4", pawn.value-rook.value),
      ("4q3/1p1pr1kb/1B2rp2/6p1/p3PP2/P3R1P1/1P2R1K1/4Q3 b - - 0 1", "h7e4", pawn.value),
      ("r1q1r1k1/pb1nppbp/1p3np1/1Pp1N3/3pNP2/B2P2PP/P3P1B1/2R1QRK1 w - c6 0 11", "b5c6", pawn.value),
      ("r3k2r/p1ppqpb1/Bn2pnp1/3PN3/1p2P3/2N2Q2/PPPB1PpP/R3K2R w QKqk - 0 2", "a6f1", pawn.value - bishop.value)
    ]
  #!fmt: on
  for (fen, moveString, seeValue) in data:
    var position = fen.toPosition
    let move = moveString.toMove(position)
    let seeResult = position.see(move)
    if seeResult != seeValue:
      return some fmt"Failed SEE test. Position: {fen}, move: {moveString}, target value {seeValue}, see value: {seeResult}"
  none string

proc chess960DetectionTest*(): Option[string] =
  for fen in classicalFens:
    if fen.toPosition.isChess960:
      return some fmt"Failed Chess960 detection test. {fen} is detected as Chess960 position."
  for fen in chess960Fens:
    if not fen.toPosition.isChess960:
      return some fmt"Failed Chess960 detection test. {fen} is not detected as Chess960 position."
  none string

proc moveToSAN*(): Option[string] =
  const testCases = [
    ("r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 1 1", "e1g1", "O-O"),
    ("r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 1 1", "e1c1", "O-O-O"),
    ("r3k2r/8/8/8/8/8/8/R3K2R b KQkq - 1 1", "e8g8", "O-O"),
    ("r3k2r/8/8/8/8/8/8/R3K2R b KQkq - 1 1", "e8c8", "O-O-O"),
    ("3r1k1r/4pp2/8/8/8/8/8/4RKR1 w Gd - 1 1", "f1g1", "O-O"),
    ("6bk/7b/8/3pP3/8/8/8/Q3K3 w - d6 0 2", "e5d6", "exd6#"),
    ("N3k2N/8/8/3N4/N4N1N/2R5/1R6/4K3 w - - 0 1", "e1f1", "Kf1"),
    ("N3k2N/8/8/3N4/N4N1N/2R5/1R6/4K3 w - - 0 1", "c3c2", "Rcc2"),
    ("N3k2N/8/8/3N4/N4N1N/2R5/1R6/4K3 w - - 0 1", "b2c2", "Rbc2"),
    ("N3k2N/8/8/3N4/N4N1N/2R5/1R6/4K3 w - - 0 1", "a4b6", "N4b6"),
    ("N3k2N/8/8/3N4/N4N1N/2R5/1R6/4K3 w - - 0 1", "h8g6", "N8g6"),
    ("N3k2N/8/8/3N4/N4N1N/2R5/1R6/4K3 w - - 0 1", "h4g6", "Nh4g6"),
    ("8/2KN1p2/5p2/3N1B1k/5PNp/7P/7P/8 w - -", "d5f6", "N5xf6#"),
    ("8/8/8/R2nkn2/8/8/2K5/8 b - - 0 1", "f5e3", "Ne3+"),
    ("7k/1p2Npbp/8/2P5/1P1r4/3b2QP/3q1pPK/2RB4 b - - 1 29", "f2f1q", "f1=Q"),
    ("7k/1p2Npbp/8/2P5/1P1r4/3b2QP/3q1pPK/2RB4 b - - 1 29", "f2f1n", "f1=N+"),
    ("4r3/3k4/8/8/8/8/q5PP/1R1KR3 w Q - 2 2", "d1b1", "O-O-O+"),
    ("8/8/8/B2p3Q/2qPp1P1/b7/2P2PkP/4K2R b K - 0 1", "g2h1", "Kxh1"),
    ("8/8/rk6/8/8/6KR/8/8 w - - 100 10", "h3h6", "Rh6+ 1/2-1/2"),
    ("8/8/rk6/8/8/6KR/8/8 w - - 100 10", "h3h5", "Rh5 1/2-1/2"),
    ("8/8/8/8/8/1k6/3r4/K7 b - - 31 117", "d2b2", "Rb2 1/2-1/2"),
  ]

  for (fen, uciMove, sanMove) in testCases:
    let
      position = fen.toPosition
      claimedSAN = uciMove.toMove(position).toSAN(position)
      claimedUCI = sanMove.toMoveFromSAN(position).notation(position)

    if claimedSAN != sanMove:
      return some fmt"Failed SAN test. {uciMove} is converted to {claimedSAN} instead of {sanMove} in the position {fen}"

    if claimedUCI != uciMove:
      return some fmt"Failed SAN test. {sanMove} is converted to {claimedUCI} instead of {uciMove} in the position {fen}"
  none string

proc speedPerftTest*() =
  var nodes = 0
  let start = secondsSince1970()
  for (fen, numNodeList) in perftFens:
    let position = fen.toPosition
    var depth = 0
    while depth + 1 < numNodeList.len and numNodeList[depth] <= maxNumPerftNodes:
      depth += 1
    nodes += position.perft(depth.Ply)
  let time = secondsSince1970() - start
  let nps = nodes.float / max(0.00001, time.float)

  styledEcho styleBright,
    "Speed perft test: ", resetStyle, $int(nps / 1000.0), styleItalic, " knps"
  echo getCpuInfo()

proc runTests*(): bool =
  const tests = [
    (testFen, "FEN parsing"),
    (chess960DetectionTest, "Detecting Chess960 positions"),
    (moveToSAN, "Algebraic notation"),
    (seeTest, "Static exchange evaluation"),
    (positionTransforms, "Position transform"),
    (positionStreams, "Binary position streams"),
    (testZobristKeys, "Zobrist key collisions"),
    (perftAndTestPerft, "Perft and more"),
    (playGames, "Playing games"),
  ]

  var failedTests = 0

  for (test, testDescription) in tests:
    stdout.styledWrite fgWhite, testDescription, styleDim, " ... "
    stdout.flushFile
    let r = test()
    if r.isNone:
      stdout.styledWriteLine fgGreen, styleBright, "Done"
    else:
      stdout.styledWriteLine fgRed, styleBright, "Failed: ", resetStyle, r.get
      failedTests += 1

  if failedTests == 0:
    styledEcho fgGreen, styleBright, "Finished all tests successfully"
    true
  else:
    styledEcho fgRed, styleBright, fmt"Failed {failedTests} of {tests.len} tests"
    false

when isMainModule:
  echo "Version ", versionOrId()

  if not runTests():
    quit(QuitFailure)

  speedPerftTest()
