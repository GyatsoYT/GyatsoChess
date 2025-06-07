import types, position, bitboard

# Material values for each piece type
const pieceValues*: array[Piece, Value] = [
  pawn: 100.Value,
  knight: 320.Value,
  bishop: 330.Value,
  rook: 500.Value,
  queen: 900.Value,
  king: valueInfinity,
  noPiece: 0.Value
]

# Piece square tables for opening phase
const pawnTableOpening*: array[Square, Value] = [
  # a1-h1
  0, 0, 0, 0, 0, 0, 0, 0,
  # a2-h2
  50, 50, 50, 50, 50, 50, 50, 50,
  # a3-h3
  10, 10, 20, 30, 30, 20, 10, 10,
  # a4-h4
  5, 5, 10, 25, 25, 10, 5, 5,
  # a5-h5
  0, 0, 0, 20, 20, 0, 0, 0,
  # a6-h6
  5, -5, -10, 0, 0, -10, -5, 5,
  # a7-h7
  5, 10, 10, -20, -20, 10, 10, 5,
  # a8-h8
  0, 0, 0, 0, 0, 0, 0, 0,
  # noSquare
  0
]

const knightTableOpening*: array[Square, Value] = [
  # a1-h1
  -50, -40, -30, -30, -30, -30, -40, -50,
  # a2-h2
  -40, -20, 0, 0, 0, 0, -20, -40,
  # a3-h3
  -30, 0, 10, 15, 15, 10, 0, -30,
  # a4-h4
  -30, 5, 15, 20, 20, 15, 5, -30,
  # a5-h5
  -30, 0, 15, 20, 20, 15, 0, -30,
  # a6-h6
  -30, 5, 10, 15, 15, 10, 5, -30,
  # a7-h7
  -40, -20, 0, 5, 5, 0, -20, -40,
  # a8-h8
  -50, -40, -30, -30, -30, -30, -40, -50,
  # noSquare
  0
]

const bishopTableOpening*: array[Square, Value] = [
  # a1-h1
  -20, -10, -10, -10, -10, -10, -10, -20,
  # a2-h2
  -10, 0, 0, 0, 0, 0, 0, -10,
  # a3-h3
  -10, 0, 10, 10, 10, 10, 0, -10,
  # a4-h4
  -10, 5, 5, 10, 10, 5, 5, -10,
  # a5-h5
  -10, 0, 5, 10, 10, 5, 0, -10,
  # a6-h6
  -10, 5, 5, 5, 5, 5, 5, -10,
  # a7-h7
  -10, 0, 0, 0, 0, 0, 0, -10,
  # a8-h8
  -20, -10, -10, -10, -10, -10, -10, -20,
  # noSquare
  0
]

const rookTableOpening*: array[Square, Value] = [
  # a1-h1
  0, 0, 0, 0, 0, 0, 0, 0,
  # a2-h2
  5, 10, 10, 10, 10, 10, 10, 5,
  # a3-h3
  -5, 0, 0, 0, 0, 0, 0, -5,
  # a4-h4
  -5, 0, 0, 0, 0, 0, 0, -5,
  # a5-h5
  -5, 0, 0, 0, 0, 0, 0, -5,
  # a6-h6
  -5, 0, 0, 0, 0, 0, 0, -5,
  # a7-h7
  -5, 0, 0, 0, 0, 0, 0, -5,
  # a8-h8
  0, 0, 0, 5, 5, 0, 0, 0,
  # noSquare
  0
]

const queenTableOpening*: array[Square, Value] = [
  # a1-h1
  -20, -10, -10, -5, -5, -10, -10, -20,
  # a2-h2
  -10, 0, 0, 0, 0, 0, 0, -10,
  # a3-h3
  -10, 0, 5, 5, 5, 5, 0, -10,
  # a4-h4
  -5, 0, 5, 5, 5, 5, 0, -5,
  # a5-h5
  0, 0, 5, 5, 5, 5, 0, -5,
  # a6-h6
  -10, 5, 5, 5, 5, 5, 0, -10,
  # a7-h7
  -10, 0, 5, 0, 0, 0, 0, -10,
  # a8-h8
  -20, -10, -10, -5, -5, -10, -10, -20,
  # noSquare
  0
]

const kingTableOpening*: array[Square, Value] = [
  # a1-h1
  -30, -40, -40, -50, -50, -40, -40, -30,
  # a2-h2
  -30, -40, -40, -50, -50, -40, -40, -30,
  # a3-h3
  -30, -40, -40, -50, -50, -40, -40, -30,
  # a4-h4
  -30, -40, -40, -50, -50, -40, -40, -30,
  # a5-h5
  -20, -30, -30, -40, -40, -30, -30, -20,
  # a6-h6
  -10, -20, -20, -20, -20, -20, -20, -10,
  # a7-h7
  20, 20, 0, 0, 0, 0, 20, 20,
  # a8-h8
  20, 30, 10, 0, 0, 10, 30, 20,
  # noSquare
  0
]

# Piece square tables for endgame phase
const pawnTableEndgame*: array[Square, Value] = [
  # a1-h1
  0, 0, 0, 0, 0, 0, 0, 0,
  # a2-h2
  50, 50, 50, 50, 50, 50, 50, 50,
  # a3-h3
  10, 10, 20, 30, 30, 20, 10, 10,
  # a4-h4
  5, 5, 10, 25, 25, 10, 5, 5,
  # a5-h5
  0, 0, 0, 20, 20, 0, 0, 0,
  # a6-h6
  5, -5, -10, 0, 0, -10, -5, 5,
  # a7-h7
  5, 10, 10, -20, -20, 10, 10, 5,
  # a8-h8
  0, 0, 0, 0, 0, 0, 0, 0,
  # noSquare
  0
]

const knightTableEndgame*: array[Square, Value] = [
  # a1-h1
  -50, -40, -30, -30, -30, -30, -40, -50,
  # a2-h2
  -40, -20, 0, 0, 0, 0, -20, -40,
  # a3-h3
  -30, 0, 10, 15, 15, 10, 0, -30,
  # a4-h4
  -30, 5, 15, 20, 20, 15, 5, -30,
  # a5-h5
  -30, 0, 15, 20, 20, 15, 0, -30,
  # a6-h6
  -30, 5, 10, 15, 15, 10, 5, -30,
  # a7-h7
  -40, -20, 0, 5, 5, 0, -20, -40,
  # a8-h8
  -50, -40, -30, -30, -30, -30, -40, -50,
  # noSquare
  0
]

const bishopTableEndgame*: array[Square, Value] = [
  # a1-h1
  -20, -10, -10, -10, -10, -10, -10, -20,
  # a2-h2
  -10, 0, 0, 0, 0, 0, 0, -10,
  # a3-h3
  -10, 0, 10, 10, 10, 10, 0, -10,
  # a4-h4
  -10, 5, 5, 10, 10, 5, 5, -10,
  # a5-h5
  -10, 0, 5, 10, 10, 5, 0, -10,
  # a6-h6
  -10, 5, 5, 5, 5, 5, 5, -10,
  # a7-h7
  -10, 0, 0, 0, 0, 0, 0, -10,
  # a8-h8
  -20, -10, -10, -10, -10, -10, -10, -20,
  # noSquare
  0
]

const rookTableEndgame*: array[Square, Value] = [
  # a1-h1
  0, 0, 0, 0, 0, 0, 0, 0,
  # a2-h2
  5, 10, 10, 10, 10, 10, 10, 5,
  # a3-h3
  -5, 0, 0, 0, 0, 0, 0, -5,
  # a4-h4
  -5, 0, 0, 0, 0, 0, 0, -5,
  # a5-h5
  -5, 0, 0, 0, 0, 0, 0, -5,
  # a6-h6
  -5, 0, 0, 0, 0, 0, 0, -5,
  # a7-h7
  -5, 0, 0, 0, 0, 0, 0, -5,
  # a8-h8
  0, 0, 0, 5, 5, 0, 0, 0,
  # noSquare
  0
]

const queenTableEndgame*: array[Square, Value] = [
  # a1-h1
  -20, -10, -10, -5, -5, -10, -10, -20,
  # a2-h2
  -10, 0, 0, 0, 0, 0, 0, -10,
  # a3-h3
  -10, 0, 5, 5, 5, 5, 0, -10,
  # a4-h4
  -5, 0, 5, 5, 5, 5, 0, -5,
  # a5-h5
  0, 0, 5, 5, 5, 5, 0, -5,
  # a6-h6
  -10, 5, 5, 5, 5, 5, 0, -10,
  # a7-h7
  -10, 0, 5, 0, 0, 0, 0, -10,
  # a8-h8
  -20, -10, -10, -5, -5, -10, -10, -20,
  # noSquare
  0
]

const kingTableEndgame*: array[Square, Value] = [
  # a1-h1
  -50, -40, -30, -20, -20, -30, -40, -50,
  # a2-h2
  -30, -20, -10, 0, 0, -10, -20, -30,
  # a3-h3
  -30, -10, 20, 30, 30, 20, -10, -30,
  # a4-h4
  -30, -10, 30, 40, 40, 30, -10, -30,
  # a5-h5
  -30, -10, 30, 40, 40, 30, -10, -30,
  # a6-h6
  -30, -10, 20, 30, 30, 20, -10, -30,
  # a7-h7
  -30, -30, 0, 0, 0, 0, -30, -30,
  # a8-h8
  -50, -30, -30, -30, -30, -30, -30, -50,
  # noSquare
  0
]

# Arrays of piece square tables for each phase
const pieceTablesOpening*: array[Piece, array[Square, Value]] = [
  pawn: pawnTableOpening,
  knight: knightTableOpening,
  bishop: bishopTableOpening,
  rook: rookTableOpening,
  queen: queenTableOpening,
  king: kingTableOpening,
  noPiece: default(array[Square, Value])
]

const pieceTablesEndgame*: array[Piece, array[Square, Value]] = [
  pawn: pawnTableEndgame,
  knight: knightTableEndgame,
  bishop: bishopTableEndgame,
  rook: rookTableEndgame,
  queen: queenTableEndgame,
  king: kingTableEndgame,
  noPiece: default(array[Square, Value])
]

# Calculate game phase based on remaining material
func calculateGamePhase*(position: Position): GamePhase =
  var phase: GamePhase = 0
  
  # Count material for phase calculation
  # Knights and bishops count as 1, rooks as 2, queens as 4
  phase += position[knight, white].countSetBits + position[knight, black].countSetBits
  phase += position[bishop, white].countSetBits + position[bishop, black].countSetBits
  phase += 2 * (position[rook, white].countSetBits + position[rook, black].countSetBits)
  phase += 4 * (position[queen, white].countSetBits + position[queen, black].countSetBits)
  
  # Clamp to valid range
  if phase > 32:
    phase = 32
  
  return phase

# Evaluate position from perspective of current player
func evaluate*(position: Position): Value =
  var score: Value = 0
  let gamePhase = position.calculateGamePhase()
  
  # Material evaluation
  for piece in pawn .. king:
    # Count material for current player
    let ourPieces = position[piece, position.us].countSetBits
    let theirPieces = position[piece, position.enemy].countSetBits
    
    # Add material value
    score += ourPieces.Value * pieceValues[piece]
    score -= theirPieces.Value * pieceValues[piece]
    
    # Add piece square table values
    for square in position[piece, position.us]:
      # For white pieces, use the table as is
      if position.us == white:
        # Interpolate between opening and endgame values based on game phase
        let openingValue = pieceTablesOpening[piece][square]
        let endgameValue = pieceTablesEndgame[piece][square]
        score += openingValue * gamePhase.Value div 32.Value + 
                endgameValue * (32.Value - gamePhase.Value) div 32.Value
      # For black pieces, mirror the square vertically (a1->a8, etc.)
      else:
        let mirroredSquare = (63 - square.int8).Square
        let openingValue = pieceTablesOpening[piece][mirroredSquare]
        let endgameValue = pieceTablesEndgame[piece][mirroredSquare]
        score += openingValue * gamePhase.Value div 32.Value + 
                endgameValue * (32.Value - gamePhase.Value) div 32.Value
    
    # Subtract opponent's piece square table values
    for square in position[piece, position.enemy]:
      # For white opponent pieces
      if position.enemy == white:
        let openingValue = pieceTablesOpening[piece][square]
        let endgameValue = pieceTablesEndgame[piece][square]
        score -= openingValue * gamePhase.Value div 32.Value + 
                endgameValue * (32.Value - gamePhase.Value) div 32.Value
      # For black opponent pieces
      else:
        let mirroredSquare = (63 - square.int8).Square
        let openingValue = pieceTablesOpening[piece][mirroredSquare]
        let endgameValue = pieceTablesEndgame[piece][mirroredSquare]
        score -= openingValue * gamePhase.Value div 32.Value + 
                endgameValue * (32.Value - gamePhase.Value) div 32.Value
  
  return score

# Evaluate position from white's perspective
func evaluateAbsolute*(position: Position): Value =
  var score = position.evaluate()
  if position.us == black:
    score = -score
  return score