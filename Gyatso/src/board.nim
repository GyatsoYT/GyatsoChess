import coretypes
import bitboard
import zobrist
import attacks
import std/strutils

type
  CastlingRights* = distinct uint8

func hasWK*(cr: CastlingRights): bool {.inline.} = (cast[uint8](cr) and 1'u8) != 0
func hasWQ*(cr: CastlingRights): bool {.inline.} = (cast[uint8](cr) and 2'u8) != 0
func hasBK*(cr: CastlingRights): bool {.inline.} = (cast[uint8](cr) and 4'u8) != 0
func hasBQ*(cr: CastlingRights): bool {.inline.} = (cast[uint8](cr) and 8'u8) != 0

func revokeWK*(cr: CastlingRights): CastlingRights {.inline.} = CastlingRights(cast[uint8](cr) and (not 1'u8))
func revokeWQ*(cr: CastlingRights): CastlingRights {.inline.} = CastlingRights(cast[uint8](cr) and (not 2'u8))
func revokeBK*(cr: CastlingRights): CastlingRights {.inline.} = CastlingRights(cast[uint8](cr) and (not 4'u8))
func revokeBQ*(cr: CastlingRights): CastlingRights {.inline.} = CastlingRights(cast[uint8](cr) and (not 8'u8))

func `==`*(a, b: CastlingRights): bool {.borrow, inline.}

type
  UndoInfo* = object
    hash*:     ZobristKey
    castling*: CastlingRights
    epSquare*: Square
    halfmove*: uint8
    captured*: Piece
    checkers*: Bitboard
    pinHV*:    Bitboard
    pinD12*:   Bitboard
    threats*:  Bitboard

  Board* = object
    byPiece*:   array[12, Bitboard]
    byColor*:   array[2, Bitboard]
    occupied*:  Bitboard
    mailbox*:   array[64, Piece]
    stm*:       Color
    castling*:  CastlingRights
    epSquare*:  Square
    halfmove*:  uint8
    fullmove*:  uint16
    hash*:      ZobristKey
    gamePly*:   int
    checkers*:  Bitboard
    pinHV*:     Bitboard
    pinD12*:    Bitboard
    threats*:   Bitboard
    history*:   array[1024, UndoInfo]
    histLen*:   int

func pieceOn*(b: Board, sq: Square): Piece {.inline.} =
  b.mailbox[sq.int]

func pieces*(b: Board, p: Piece): Bitboard {.inline.} =
  if p == NoPiece: Bitboard(0)
  else: b.byPiece[p.ord]

func pieces*(b: Board, pt: PieceType, c: Color): Bitboard {.inline.} =
  if pt == NoPieceType: Bitboard(0)
  else:
    let p = makePiece(c, pt)
    b.byPiece[p.ord]

func kingSquare*(b: Board, c: Color): Square {.inline.} =
  let kingPiece = makePiece(c, King)
  b.byPiece[kingPiece.ord].lsb()

func isOccupied*(b: Board, sq: Square): bool {.inline.} =
  b.occupied.hasSq(sq)

proc putPiece(b: var Board, p: Piece, sq: Square) {.inline.} =
  let sqBit = bit(sq)
  b.byPiece[p.ord] = b.byPiece[p.ord] or sqBit
  b.byColor[p.color.ord] = b.byColor[p.color.ord] or sqBit
  b.occupied = b.occupied or sqBit
  b.mailbox[sq.int] = p
  b.hash = b.hash xor pieceKeys[p.ord][sq.int]

proc removePiece(b: var Board, sq: Square) {.inline.} =
  let p = b.mailbox[sq.int]
  if p != NoPiece:
    let sqBit = bit(sq)
    b.byPiece[p.ord] = b.byPiece[p.ord] and not sqBit
    b.byColor[p.color.ord] = b.byColor[p.color.ord] and not sqBit
    b.occupied = b.occupied and not sqBit
    b.mailbox[sq.int] = NoPiece
    b.hash = b.hash xor pieceKeys[p.ord][sq.int]

proc movePiece(b: var Board, fromSq, toSq: Square) {.inline.} =
  let p = b.mailbox[fromSq.int]
  if p != NoPiece:
    let fromBit = bit(fromSq)
    let toBit = bit(toSq)
    let combined = fromBit or toBit
    
    b.byPiece[p.ord] = b.byPiece[p.ord] xor combined
    b.byColor[p.color.ord] = b.byColor[p.color.ord] xor combined
    b.occupied = b.occupied xor combined
    
    b.mailbox[fromSq.int] = NoPiece
    b.mailbox[toSq.int] = p
    
    b.hash = b.hash xor pieceKeys[p.ord][fromSq.int] xor pieceKeys[p.ord][toSq.int]

proc attackersTo*(b: Board, sq: Square, occ: Bitboard, them: Color): Bitboard =
  let offset       = them.ord * 6
  let enemyPawns   = b.byPiece[offset + Pawn.ord]
  let enemyKnights = b.byPiece[offset + Knight.ord]
  let enemyBishops = b.byPiece[offset + Bishop.ord]
  let enemyRooks   = b.byPiece[offset + Rook.ord]
  let enemyQueens  = b.byPiece[offset + Queen.ord]
  let enemyKing    = b.byPiece[offset + King.ord]

  (getPawnAttacks(sq, them.opposite()) and enemyPawns) or
  (getKnightAttacks(sq)                and enemyKnights) or
  (getBishopAttacks(sq, occ)           and (enemyBishops or enemyQueens)) or
  (getRookAttacks(sq, occ)             and (enemyRooks or enemyQueens)) or
  (getKingAttacks(sq)                  and enemyKing)

proc attackersTo*(b: Board, sq: Square, occ: Bitboard): Bitboard {.inline.} =
  b.attackersTo(sq, occ, White) or b.attackersTo(sq, occ, Black)

func pawnAttackLeft(bb: Bitboard, c: Color): Bitboard {.inline.} =
  if c == White: (bb and not FileA) shl 7
  else:          (bb and not FileH) shr 7

func pawnAttackRight(bb: Bitboard, c: Color): Bitboard {.inline.} =
  if c == White: (bb and not FileH) shl 9
  else:          (bb and not FileA) shr 9

proc updateAttackState*(b: var Board) =
  let us   = b.stm
  let them = us.opposite()
  let kingSq = b.byPiece[us.ord * 6 + King.ord].lsb()
  let occ = b.occupied

  b.checkers = b.attackersTo(kingSq, occ, them)

  b.pinHV  = Bitboard(0)
  b.pinD12 = Bitboard(0)

  let offset = them.ord * 6
  let enemyRooks   = b.byPiece[offset + Rook.ord]
  let enemyBishops = b.byPiece[offset + Bishop.ord]
  let enemyQueens  = b.byPiece[offset + Queen.ord]

  let enemyHV  = enemyRooks or enemyQueens
  let enemyD12 = enemyBishops or enemyQueens

  if not enemyHV.isEmpty():
    var candidates = getRookAttacks(kingSq, b.byColor[them.ord]) and enemyHV
    for pinner in candidates:
      let ray = rayBetween(kingSq, pinner) or pinner.bit
      if (ray and b.byColor[us.ord]).popcount() == 1:
        b.pinHV = b.pinHV or ray

  if not enemyD12.isEmpty():
    var candidates = getBishopAttacks(kingSq, b.byColor[them.ord]) and enemyD12
    for pinner in candidates:
      let ray = rayBetween(kingSq, pinner) or pinner.bit
      if (ray and b.byColor[us.ord]).popcount() == 1:
        b.pinD12 = b.pinD12 or ray

  let occNoKing = occ and not kingSq.bit

  # 1. Pawn threats
  let enemyPawns = b.byPiece[offset + Pawn.ord]
  b.threats = pawnAttackLeft(enemyPawns, them) or pawnAttackRight(enemyPawns, them)

  # 2. King threats
  let enemyKingSq = b.byPiece[offset + King.ord].lsb()
  b.threats = b.threats or getKingAttacks(enemyKingSq)

  # 3. Knight threats
  var enemyKnights = b.byPiece[offset + Knight.ord]
  for sq in enemyKnights:
    b.threats = b.threats or getKnightAttacks(sq)

  # 4. Rook / Queen threats (HV)
  var enemyRooksAndQueens = enemyRooks or enemyQueens
  for sq in enemyRooksAndQueens:
    b.threats = b.threats or getRookAttacks(sq, occNoKing)

  # 5. Bishop / Queen threats (diagonal)
  var enemyBishopsAndQueens = enemyBishops or enemyQueens
  for sq in enemyBishopsAndQueens:
    b.threats = b.threats or getBishopAttacks(sq, occNoKing)

func pinRayOf*(b: Board, sq: Square): Bitboard {.inline.} =
  if b.pinHV.hasSq(sq):  return b.pinHV
  if b.pinD12.hasSq(sq): return b.pinD12
  return AllSquares


proc parseFen*(fen: string): Board =
  for i in 0..63:
    result.mailbox[i] = NoPiece
  
  let parts = fen.split(' ')
  
  # 1. Piece placement
  if parts.len > 0:
    var rank = 7
    var file = 0
    for c in parts[0]:
      if c == '/':
        dec rank
        file = 0
      elif c in '1'..'8':
        file += ord(c) - ord('0')
      else:
        let piece = case c
          of 'P': WhitePawn
          of 'N': WhiteKnight
          of 'B': WhiteBishop
          of 'R': WhiteRook
          of 'Q': WhiteQueen
          of 'K': WhiteKing
          of 'p': BlackPawn
          of 'n': BlackKnight
          of 'b': BlackBishop
          of 'r': BlackRook
          of 'q': BlackQueen
          of 'k': BlackKing
          else: NoPiece
        if piece != NoPiece:
          let sq = makeSquare(rank, file)
          result.mailbox[sq.int] = piece
          inc file
          
  # 2. Active color
  if parts.len > 1:
    if parts[1] == "w":
      result.stm = White
    elif parts[1] == "b":
      result.stm = Black
  else:
    result.stm = White
    
  # 3. Castling availability
  var castlingVal = 0'u8
  if parts.len > 2 and parts[2] != "-":
    for c in parts[2]:
      case c
      of 'K': castlingVal = castlingVal or 1'u8
      of 'Q': castlingVal = castlingVal or 2'u8
      of 'k': castlingVal = castlingVal or 4'u8
      of 'q': castlingVal = castlingVal or 8'u8
      else: discard
  result.castling = CastlingRights(castlingVal)
  
  # 4. En passant target square
  if parts.len > 3:
    result.epSquare = parseSquare(parts[3])
  else:
    result.epSquare = NoSquare
    
  # 5. Halfmove clock
  if parts.len > 4:
    try:
      result.halfmove = uint8(parseInt(parts[4]))
    except ValueError:
      result.halfmove = 0
  else:
    result.halfmove = 0
    
  # 6. Fullmove number
  if parts.len > 5:
    try:
      result.fullmove = uint16(parseInt(parts[5]))
    except ValueError:
      result.fullmove = 1
  else:
    result.fullmove = 1
    
  # Compute occupied, byColor, and hash from scratch
  for i in 0..11:
    result.byPiece[i] = Bitboard(0)
  result.byColor[0] = Bitboard(0)
  result.byColor[1] = Bitboard(0)
  result.occupied = Bitboard(0)
  result.hash = ZobristKey(0)
  
  for sq in 0..63:
    let p = result.mailbox[sq]
    if p != NoPiece:
      let sqBit = bit(Square(sq))
      result.byPiece[p.ord] = result.byPiece[p.ord] or sqBit
      result.byColor[p.color.ord] = result.byColor[p.color.ord] or sqBit
      result.occupied = result.occupied or sqBit
      result.hash = result.hash xor pieceKeys[p.ord][sq]
      
  if result.stm == Black:
    result.hash = result.hash xor sideKey
    
  result.hash = result.hash xor castlingKeys[system.int(cast[uint8](result.castling))]
  
  if result.epSquare != NoSquare:
    result.hash = result.hash xor epKeys[result.epSquare.file]
    
  updateAttackState(result)

const StartPos* = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"

func toFen*(b: Board): string =
  var placement = ""
  for rank in countdown(7, 0):
    var emptyCount = 0
    for file in 0..7:
      let sq = makeSquare(rank, file)
      let p = b.mailbox[sq.int]
      if p == NoPiece:
        inc emptyCount
      else:
        if emptyCount > 0:
          placement.add($emptyCount)
          emptyCount = 0
        let c = case p
          of WhitePawn: 'P'
          of WhiteKnight: 'N'
          of WhiteBishop: 'B'
          of WhiteRook: 'R'
          of WhiteQueen: 'Q'
          of WhiteKing: 'K'
          of BlackPawn: 'p'
          of BlackKnight: 'n'
          of BlackBishop: 'b'
          of BlackRook: 'r'
          of BlackQueen: 'q'
          of BlackKing: 'k'
          else: ' '
        placement.add(c)
    if emptyCount > 0:
      placement.add($emptyCount)
    if rank > 0:
      placement.add("/")
      
  result.add(placement)
  result.add(" ")
  result.add(if b.stm == White: "w" else: "b")
  result.add(" ")
  
  var castlingStr = ""
  if b.castling.hasWK: castlingStr.add('K')
  if b.castling.hasWQ: castlingStr.add('Q')
  if b.castling.hasBK: castlingStr.add('k')
  if b.castling.hasBQ: castlingStr.add('q')
  if castlingStr == "":
    result.add("-")
  else:
    result.add(castlingStr)
    
  result.add(" ")
  
  if b.epSquare == NoSquare:
    result.add("-")
  else:
    result.add(toAlgebraic(b.epSquare))
    
  result.add(" ")
  result.add($b.halfmove)
  result.add(" ")
  result.add($b.fullmove)

proc makeMove*(b: var Board, m: Move) =
  doAssert b.histLen < 1024
  
  let fromSq = m.fromSq
  let toSq = m.toSq
  let movingPiece = b.mailbox[fromSq.int]
  
  # Determine captured piece
  var captured = NoPiece
  if m.isEnPassant:
    captured = if b.stm == White: BlackPawn else: WhitePawn
  else:
    captured = b.mailbox[toSq.int]
    
  # Save to history
  b.history[b.histLen] = UndoInfo(
    hash: b.hash,
    castling: b.castling,
    epSquare: b.epSquare,
    halfmove: b.halfmove,
    captured: captured,
    checkers: b.checkers,
    pinHV: b.pinHV,
    pinD12: b.pinD12,
    threats: b.threats
  )
  inc b.histLen
  
  # XOR out old castling and EP contributions from hash
  b.hash = b.hash xor castlingKeys[system.int(cast[uint8](b.castling))]
  if b.epSquare != NoSquare:
    b.hash = b.hash xor epKeys[b.epSquare.file]
    
  # Reverse piece movements / place pieces
  if m.isPromotion:
    let pt = case m.promoType
      of PromoKnight: PieceType.Knight
      of PromoBishop: PieceType.Bishop
      of PromoRook: PieceType.Rook
      of PromoQueen: PieceType.Queen
    b.removePiece(fromSq)
    if captured != NoPiece:
      b.removePiece(toSq)
    b.putPiece(makePiece(b.stm, pt), toSq)
    
  elif m.isCastling:
    b.movePiece(fromSq, toSq)
    if toSq == G1: b.movePiece(H1, F1)
    elif toSq == C1: b.movePiece(A1, D1)
    elif toSq == G8: b.movePiece(H8, F8)
    elif toSq == C8: b.movePiece(A8, D8)
    
  elif m.isEnPassant:
    let capSq = toSq + (if b.stm == White: -8 else: 8)
    b.removePiece(capSq)
    b.movePiece(fromSq, toSq)
    
  else:
    if captured != NoPiece:
      b.removePiece(toSq)
    b.movePiece(fromSq, toSq)
    
  # Update Castling Rights
  if fromSq == E1:
    b.castling = b.castling.revokeWK().revokeWQ()
  elif fromSq == E8:
    b.castling = b.castling.revokeBK().revokeBQ()
    
  if fromSq == H1 or toSq == H1:
    b.castling = b.castling.revokeWK()
  if fromSq == A1 or toSq == A1:
    b.castling = b.castling.revokeWQ()
  if fromSq == H8 or toSq == H8:
    b.castling = b.castling.revokeBK()
  if fromSq == A8 or toSq == A8:
    b.castling = b.castling.revokeBQ()
    
  # Update EP target square
  b.epSquare = NoSquare
  if movingPiece == WhitePawn and rank(fromSq) == 1 and rank(toSq) == 3:
    b.epSquare = makeSquare(2, file(fromSq))
  elif movingPiece == BlackPawn and rank(fromSq) == 6 and rank(toSq) == 4:
    b.epSquare = makeSquare(5, file(fromSq))
    
  # Update halfmove clock
  if movingPiece == WhitePawn or movingPiece == BlackPawn or captured != NoPiece:
    b.halfmove = 0
  else:
    inc b.halfmove
    
  # Update STM, gamePly, fullmove
  if b.stm == Black:
    inc b.fullmove
  b.stm = b.stm.opposite()
  inc b.gamePly
  
  # XOR in new castling, EP, and side keys
  b.hash = b.hash xor castlingKeys[system.int(cast[uint8](b.castling))]
  if b.epSquare != NoSquare:
    b.hash = b.hash xor epKeys[b.epSquare.file]
  b.hash = b.hash xor sideKey
  
  # Call updateAttackState
  updateAttackState(b)

proc unmakeMove*(b: var Board, m: Move) =
  dec b.histLen
  let undo = b.history[b.histLen]
  
  let fromSq = m.fromSq
  let toSq = m.toSq
  
  # Restore STM, gamePly, fullmove
  b.stm = b.stm.opposite()
  if b.stm == Black:
    dec b.fullmove
  dec b.gamePly
  
  # Reverse piece movements
  if m.isPromotion:
    b.removePiece(toSq)
    b.putPiece(makePiece(b.stm, Pawn), fromSq)
    if undo.captured != NoPiece:
      b.putPiece(undo.captured, toSq)
      
  elif m.isCastling:
    b.movePiece(toSq, fromSq)
    if toSq == G1: b.movePiece(F1, H1)
    elif toSq == C1: b.movePiece(D1, A1)
    elif toSq == G8: b.movePiece(F8, H8)
    elif toSq == C8: b.movePiece(D8, A8)
    
  elif m.isEnPassant:
    b.movePiece(toSq, fromSq)
    let capSq = toSq + (if b.stm == White: -8 else: 8)
    b.putPiece(undo.captured, capSq)
    
  else:
    b.movePiece(toSq, fromSq)
    if undo.captured != NoPiece:
      b.putPiece(undo.captured, toSq)
      
  # Restore remaining fields
  b.castling = undo.castling
  b.epSquare = undo.epSquare
  b.halfmove = undo.halfmove
  b.hash = undo.hash
  b.checkers = undo.checkers
  b.pinHV = undo.pinHV
  b.pinD12 = undo.pinD12
  b.threats = undo.threats

proc makeNullMove*(b: var Board) =
  doAssert b.histLen < 1024
  
  # Save to history
  b.history[b.histLen] = UndoInfo(
    hash: b.hash,
    castling: b.castling,
    epSquare: b.epSquare,
    halfmove: b.halfmove,
    captured: NoPiece,
    checkers: b.checkers,
    pinHV: b.pinHV,
    pinD12: b.pinD12,
    threats: b.threats
  )
  inc b.histLen
  
  if b.epSquare != NoSquare:
    b.hash = b.hash xor epKeys[b.epSquare.file]
    
  # Clear EP square
  b.epSquare = NoSquare
    
  # Update STM, gamePly, fullmove
  if b.stm == Black:
    inc b.fullmove
  b.stm = b.stm.opposite()
  inc b.gamePly

  b.hash = b.hash xor sideKey

  updateAttackState(b)

proc unmakeNullMove*(b: var Board) =
  dec b.histLen
  let undo = b.history[b.histLen]
  
  # Restore simple fields
  b.castling = undo.castling
  b.epSquare = undo.epSquare
  b.halfmove = undo.halfmove
  b.hash = undo.hash
  b.checkers = undo.checkers
  b.pinHV = undo.pinHV
  b.pinD12 = undo.pinD12
  b.threats = undo.threats
  
  # Restore STM, gamePly, fullmove
  b.stm = b.stm.opposite()
  if b.stm == Black:
    dec b.fullmove
  dec b.gamePly

func isRepetition*(b: Board): bool {.inline.} =
  let limit = max(0, b.histLen - system.int(b.halfmove))
  var i = b.histLen - 2
  while i >= limit:
    if b.history[i].hash == b.hash:
      return true
    dec(i, 2)
  return false

func isFiftyMove*(b: Board): bool {.inline.} =
  b.halfmove >= 100

func isInsufficientMaterial*(b: Board): bool =
  # No pawns, rooks, or queens anywhere
  if not (b.pieces(WhitePawn) or b.pieces(BlackPawn) or 
          b.pieces(WhiteRook) or b.pieces(BlackRook) or 
          b.pieces(WhiteQueen) or b.pieces(BlackQueen)).isEmpty:
    return false

  let wk = b.pieces(WhiteKnight).popcount()
  let bk = b.pieces(BlackKnight).popcount()
  let wb = b.pieces(WhiteBishop).popcount()
  let bb = b.pieces(BlackBishop).popcount()
  let totalMinors = wk + bk + wb + bb

  if totalMinors == 0:
    return true # KvK
  elif totalMinors == 1:
    return true # KNvK or KBvK
  elif totalMinors == 2:
    # KBvKB same-color bishops
    if wb == 1 and bb == 1:
      let wSq = b.pieces(WhiteBishop).lsb()
      let bSq = b.pieces(BlackBishop).lsb()
      if ((wSq.rank + wSq.file) and 1) == ((bSq.rank + bSq.file) and 1):
        return true
  return false

func isDraw*(b: Board): bool {.inline.} =
  b.isFiftyMove() or b.isInsufficientMaterial() or b.isRepetition()

func isGameOver*(b: var Board): bool =
  b.isDraw()