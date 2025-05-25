import coretypes

const
  FlagNone* = 0
  FlagCapture* = 1      # 1 shl 0
  FlagEnPassant* = 2   # 1 shl 1
  FlagCastle* = 4      # 1 shl 2
  FlagPromotion* = 8   # 1 shl 3

type
  Move* = object
    fromSquare*: Square
    toSquare*: Square
    promotionPiece*: PieceType # Stores the piece type to promote to (Knight, Bishop, Rook, Queen).
                               # Meaningful only if FlagPromotion is set in flags. Defaults to NoPieceType.
    flags*: int              # Bitmask using FlagCapture, FlagEnPassant, FlagCastle, FlagPromotion.
    capturedPiece*: Piece     # ADDED: Stores the actual piece captured, Piece.Empty if no capture.

  MoveList* = object
    count*: int
    moves*: array[MaxMoves, Move] # MaxMoves is from coretypes (usually 256)

proc addMove*(ml: var MoveList; fromSq: Square; toSq: Square; promP: PieceType = PieceType.NoPieceType; moveFlags: int = 0; capP: Piece = Piece.Empty) =
  # Adds a move to the move list if there's space.
  # Manages consistency of the FlagPromotion based on promP.
  # Sets the capturedPiece field.
  if ml.count < MaxMoves:
    var currentFlags = moveFlags
    
    if promP != PieceType.NoPieceType:
      # If a specific promotion piece is provided (e.g., Knight, Queen),
      # ensure the promotion flag is set in the move's flags.
      currentFlags = currentFlags or FlagPromotion
    else:
      # If no specific promotion piece is provided (i.e., promP is NoPieceType),
      # ensure the promotion flag is NOT set in the move's flags,
      # regardless of whether the caller set it in moveFlags.
      currentFlags = currentFlags and (not FlagPromotion)

    # Assign the move details to the next available slot in the array.
    ml.moves[ml.count].fromSquare = fromSq
    ml.moves[ml.count].toSquare = toSq
    # The promotionPiece field stores the piece passed in by promP.
    # Its interpretation depends on whether FlagPromotion is set in currentFlags.
    # If FlagPromotion is true, promP should be an actual piece (Knight, Queen, etc.).
    # If FlagPromotion is false, this field is effectively ignored (and promP would be NoPieceType due to the logic above).
    ml.moves[ml.count].promotionPiece = promP 
    ml.moves[ml.count].flags = currentFlags
    ml.moves[ml.count].capturedPiece = capP # Store the captured piece
    
    ml.count += 1
  # else: The MoveList is full. The move is not added.
  # In a minimal implementation, no error is raised or logged here. 