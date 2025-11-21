import
  position, types, bitboard, evalParameters, utils, pieceValues, positionUtils,
  zobristBitmasks

import std/[algorithm, macros, math]

export pieceValues

func cp*(cp: int): Value {.inline.} =
  (pawn.value * cp.Value) div 100.Value

func toCp*(value: Value): int {.inline.} =
  (100 * value.int) div pawn.value.int

const k = 1.0

func winningProbability*(centipawn: Value): float =
  1.0 / (1.0 + pow(10.0, -((k * centipawn.float) / 400.0)))

func winningProbabilityDerivative*(centipawn: Value): float =
  (
    ln(10.0) * pow(2.0, -2.0 - ((k * centipawn.float) / 400.0)) *
    pow(5.0, -((k * centipawn.float) / 400.0))
  ) / pow(1.0 + pow(10.0, -((k * centipawn.float) / 400.0)), 2.0)

func material*(position: Position): Value =
  result = 0
  for piece in pawn .. king:
    result +=
      (position[piece] and position[position.us]).countSetBits.Value * piece.value
    result -=
      (position[piece] and position[position.enemy]).countSetBits.Value * piece.value

func absoluteMaterial*(position: Position): Value =
  result = position.material
  if position.us == black:
    result = -result

func colorConditionalMirrorVertically(x: Square or Bitboard, color: Color): auto =
  if color == black: x.mirrorVertically else: x

type
  Gradient* {.requiresInit.} = object
    gradient*: ptr EvalParameters
    g*: float32
    gamePhaseFactor*: float32

  EvalValue {.requiresInit.} = object
    params: ptr EvalParameters
    absoluteValue: ptr array[Phase, float32]

  EvalState = Gradient or EvalValue

macro getParameter(structName, parameter: untyped): untyped =
  let s = $structName.toStrLit & "." & $parameter.toStrLit
  parseExpr(s)

template addValue(evalState: EvalState, goodFor: static Color, parameter: untyped) =
  when evalState is Gradient:
    let f = (if goodFor == black: -1.0 else: 1.0) * evalState.g
    getParameter(evalState.gradient[][opening.int], parameter) +=
      f * evalState.gamePhaseFactor
    getParameter(evalState.gradient[][endgame.int], parameter) +=
      f * (1.0 - evalState.gamePhaseFactor)
  else:
    static:
      doAssert evalState is EvalValue
    for phase {.inject.} in Phase:
      var value = getParameter(evalState.params[][phase.int], parameter)
      when goodFor == black:
        value = -value
      evalState.absoluteValue[phase] += value

# TODO remove side effects (think about multithreading ...)
type HashEntry = object
  key: ZobristKey
  value: array[Phase, float32]

var
  pawnPatternHash = default(array[65536, HashEntry])
  pawnRelativityHash = default(array[65536, HashEntry])

func pieceRelativePstForOtherPiece(
    evalState: EvalState,
    position: Position,
    ourPiece: static Piece,
    ourSquare: Square,
    us: static Color,
    otherPieces: array[Relativity, Bitboard],
    enemyKingSquare: Square,
    roughEnemyKingFile: int,
    roughEnemyKingRank: int,
    otherPiece: Piece,
) =
  for relativity in relativeToUs .. relativeToEnemy:
    for otherSquare in otherPieces[relativity] and position[otherPiece]:
      let otherSquare = otherSquare.colorConditionalMirrorVertically(us)
      evalState.addValue(
        goodFor = us,
        pieceRelativePst[roughEnemyKingRank][roughEnemyKingFile][relativity][ourPiece][
          ourSquare
        ][otherPiece][otherSquare],
      )

      when evalState is Gradient:
        # TODO check this (params is not defined anywhere???)´
        let
          flippedOurSquare = ourSquare.mirrorHorizontally
          flippedOtherSquare = otherSquare.mirrorHorizontally
          flippedKingFile = 3 - roughEnemyKingFile
        evalState.addValue(
          goodFor = us,
          pieceRelativePst[roughEnemyKingRank][flippedKingFile][relativity][ourPiece][
            flippedOurSquare
          ][otherPiece][flippedOtherSquare],
        )

func pieceRelativePst(
    evalState: EvalState,
    position: Position,
    ourPiece: static Piece,
    ourSquare: Square,
    us: static Color,
) =
  let
    ourSquare = ourSquare.colorConditionalMirrorVertically(us)
    otherPieces = [relativeToUs: position[us], relativeToEnemy: position[us.opposite]]
    # we do it just relative to the enemy king, as that's faster
    enemyKingSquare =
      position[us.opposite, king].toSquare.colorConditionalMirrorVertically(us)
    roughEnemyKingFile = (enemyKingSquare.int mod 8) div 2
    roughEnemyKingRank = (enemyKingSquare.int div 8) div 4

  const pieceRange =
    when ourPiece in [pawn, king]:
      knight .. king
    elif ourPiece == queen:
      knight .. queen
    elif ourPiece == knight:
      [knight, bishop, rook]
    elif ourPiece == bishop:
      [bishop, rook]
    elif ourPiece == rook:
      [rook]

  for otherPiece in pieceRange:
    evalState.pieceRelativePstForOtherPiece(
      position = position,
      ourPiece = ourPiece,
      ourSquare = ourSquare,
      us = us,
      otherPieces = otherPieces,
      enemyKingSquare = enemyKingSquare,
      roughEnemyKingFile = roughEnemyKingFile,
      roughEnemyKingRank = roughEnemyKingRank,
      otherPiece = otherPiece,
    )

func pawnRelativePstWithInfo(
    evalState: EvalState,
    position: Position,
    ourPiece: static Piece,
    ourSquare: Square,
    us: static Color,
    otherPieces: array[Relativity, Bitboard],
    enemyKingSquare: Square,
    roughEnemyKingFile: int,
    roughEnemyKingRank: int,
) =
  for relativityMode, (relativity1, relativity2) in [
    (relativeToUs, relativeToEnemy),
    (relativeToUs, relativeToUs),
    (relativeToEnemy, relativeToEnemy),
  ].pairs:
    for otherSquare1 in otherPieces[relativity1] and position[pawn]:
      let otherSquare1 = otherSquare1.colorConditionalMirrorVertically(us)

      for otherSquare2 in otherPieces[relativity2] and position[pawn]:
        let otherSquare2 = otherSquare2.colorConditionalMirrorVertically(us)
        evalState.addValue(
          goodFor = us,
          pawnRelativePst[roughEnemyKingRank][roughEnemyKingFile][ourPiece][ourSquare][
            relativityMode
          ][otherSquare1][otherSquare2],
        )

        when evalState is Gradient:
          let
            flippedOurSquare = ourSquare.mirrorHorizontally
            flippedOtherSquare1 = otherSquare1.mirrorHorizontally
            flippedOtherSquare2 = otherSquare2.mirrorHorizontally
            flippedKingFile = 3 - roughEnemyKingFile
          evalState.addValue(
            goodFor = us,
            pawnRelativePst[roughEnemyKingRank][flippedKingFile][ourPiece][
              flippedOurSquare
            ][relativityMode][flippedOtherSquare1][flippedOtherSquare2],
          )

func pawnRelativePst(
    evalState: EvalState,
    position: Position,
    ourPiece: static Piece,
    ourSquare: Square,
    us: static Color,
) =
  let
    ourSquare = ourSquare.colorConditionalMirrorVertically(us)
    otherPieces = [relativeToUs: position[us], relativeToEnemy: position[us.opposite]]
    # we do it just relative to the enemy king, as that's faster
    enemyKingSquare =
      position[us.opposite, king].toSquare.colorConditionalMirrorVertically(us)
    roughEnemyKingFile = (enemyKingSquare.int mod 8) div 2
    roughEnemyKingRank = (enemyKingSquare.int div 8) div 4

  when evalState is Gradient:
    evalState.pawnRelativePstWithInfo(
      position = position,
      ourPiece = ourPiece,
      ourSquare = ourSquare,
      us = us,
      otherPieces = otherPieces,
      enemyKingSquare = enemyKingSquare,
      roughEnemyKingFile = roughEnemyKingFile,
      roughEnemyKingRank = roughEnemyKingRank,
    )
  else:
    {.cast(noSideEffect).}:
      let key = (
        position.pawnKey xor
        (zobristPieceBitmasks[white][knight][roughEnemyKingRank.Square] shr 32) xor
        (zobristPieceBitmasks[black][knight][roughEnemyKingFile.Square] shr 32) xor
        zobristPieceBitmasks[us][ourPiece][ourSquare]
      )
      let index = (key.uint64 mod pawnRelativityHash.len.uint64).int

      if pawnRelativityHash[index].key != key:
        pawnRelativityHash[index].value = default(array[Phase, float32])
        let middleManEvalValue = EvalValue(
          params: evalState.params, absoluteValue: addr pawnRelativityHash[index].value
        )

        middleManEvalValue.pawnRelativePstWithInfo(
          position = position,
          ourPiece = ourPiece,
          ourSquare = ourSquare,
          us = us,
          otherPieces = otherPieces,
          enemyKingSquare = enemyKingSquare,
          roughEnemyKingFile = roughEnemyKingFile,
          roughEnemyKingRank = roughEnemyKingRank,
        )

      pawnRelativityHash[index].key = key

      for phase in Phase:
        evalState.absoluteValue[][phase] += pawnRelativityHash[index].value[phase]

func evaluatePiece(
    evalState: EvalState,
    position: Position,
    piece: static Piece,
    square: Square,
    pieceColor: static Color,
) {.inline.} =
  static:
    doAssert piece != noPiece

  when piece == pawn:
    if position.isPassedPawn(pieceColor, square):
      evalState.pieceRelativePst(position, pawn, square, pieceColor)
  else:
    evalState.pieceRelativePst(position, piece, square, pieceColor)
    evalState.pawnRelativePst(position, piece, square, pieceColor)

func evaluatePieceTypeFromWhitesPerspective(
    evalState: EvalState, position: Position, piece: static Piece
) {.inline.} =
  for pieceColor in (white, black).fields:
    for square in (position[piece] and position[pieceColor]):
      evalState.evaluatePiece(position, piece, square, pieceColor)

func pawnMaskIndex*(position: Position, square: static Square): int =
  result = 0

  assert not square.isEdge
  assert square >= b2

  let
    whitePawns = position[white, pawn] shr (square.int8 - b2.int8)
    blackPawns = position[black, pawn] shr (square.int8 - b2.int8)

  var counter = 1

  for bit in [
    a3.toBitboard, b3.toBitboard, c3.toBitboard, a2.toBitboard, b2.toBitboard,
    c2.toBitboard, a1.toBitboard, b1.toBitboard, c1.toBitboard,
  ]:
    if not empty(whitePawns and bit):
      result += counter * 2
    elif not empty(blackPawns and bit):
      result += counter * 1
    counter *= 3

func evaluate3x3PawnStructureFromWhitesPerspective(
    evalState: EvalState, position: Position
) =
  when evalState is Gradient:
    let flippedPosition = position.mirrorVertically

  for square in (
    b3, c3, d3, e3, f3, g3, b4, c4, d4, e4, f4, g4, b5, c5, d5, e5, f5, g5, b6, c6, d6,
    e6, f6, g6,
  ).fields:
    if (mask3x3[square] and position[pawn]).countSetBits >= 2:
      let index = position.pawnMaskIndex(square)
      evalState.addValue(goodFor = white, pawnStructureBonus[square][index])

      when evalState is Gradient:
        const flippedSquare = square.mirrorVertically
        let flippedIndex = flippedPosition.pawnMaskIndex(flippedSquare)

        evalState.addValue(
          goodFor = black, pawnStructureBonus[flippedSquare][flippedIndex]
        )

func pieceComboIndex(position: Position): int =
  result = 0
  var counter = 1
  for color in white .. black:
    for piece in pawn .. queen:
      let pieceCount = min(2, position[color, piece].countSetBits)
      result += pieceCount * counter
      counter *= 3

func pieceComboBonusWhitePerspective(evalState: EvalState, position: Position) =
  if max(position[pawn, white].countSetBits, position[pawn, black].countSetBits) <= 2:
    let index = position.pieceComboIndex
    evalState.addValue(goodFor = white, pieceComboBonus[index])

    when evalState is Gradient:
      let
        flippedPosition = position.mirrorVertically
        flippedIndex = flippedPosition.pieceComboIndex
      evalState.addValue(goodFor = black, pieceComboBonus[flippedIndex])

func absoluteEvaluate*(position: Position, evalState: EvalState) {.inline.} =
  # TODO try to add more draw conditions (insufficient material), it might make training easier
  if position.halfmoveClock >= 100:
    return

  # evaluating pieces
  for piece in (pawn, knight, bishop, rook, queen, king).fields:
    evalState.evaluatePieceTypeFromWhitesPerspective(position, piece)

  # evaluating 3x3 pawn patters
  when evalState is Gradient:
    evalState.evaluate3x3PawnStructureFromWhitesPerspective(position)
  else:
    {.cast(noSideEffect).}:
      let index = (position.pawnKey.uint64 mod pawnPatternHash.len.uint64).int
      if pawnPatternHash[index].key != position.pawnKey:
        pawnPatternHash[index].value = default(array[Phase, float32])
        let middleManEvalValue = EvalValue(
          params: evalState.params, absoluteValue: addr pawnPatternHash[index].value
        )
        middleManEvalValue.evaluate3x3PawnStructureFromWhitesPerspective(position)

      pawnPatternHash[index].key = position.pawnKey

      for phase in Phase:
        evalState.absoluteValue[][phase] += pawnPatternHash[index].value[phase]

  # piece combo bonus
  evalState.pieceComboBonusWhitePerspective(position)

func absoluteEvaluate*(position: Position, params: EvalParameters): Value {.inline.} =
  var value = default(array[Phase, float32])
  let evalValue = EvalValue(params: addr params, absoluteValue: addr value)
  position.absoluteEvaluate(evalValue)

  result = position.gamePhase.interpolate(
    forOpening = value[opening].Value, forEndgame = value[endgame].Value
  )

  # doAssert result.abs < valueCheckmate # TODO add this again, or add clamping

func absoluteEvaluate*(position: Position): Value =
  position.absoluteEvaluate(defaultEvalParameters)

func perspectiveEvaluate*(position: Position): Value =
  result = position.absoluteEvaluate
  if position.us == black:
    result = -result

func addGradient*(
    params: var EvalParameters, lr: float, position: Position, outcome: float
) =
  let currentValue = position.absoluteEvaluate(params)
  var currentGradient = Gradient(
    gamePhaseFactor: position.gamePhase.interpolate(forOpening = 1.0, forEndgame = 0.0),
    g:
      errorDerivative(outcome, currentValue.winningProbability) *
      currentValue.winningProbabilityDerivative * lr,
    gradient: addr params,
  )
  position.absoluteEvaluate(currentGradient)
