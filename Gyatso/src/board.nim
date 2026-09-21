import coretypes
import bitboard
import zobrist
import attacks
import std/strutils

var gChess960*: bool = false

type
  CastlingRooks* = object
    wk*, wq*, bk*, bq*: Square

func rightsMask*(cr: CastlingRooks): int {.inline.} =
  (if cr.wk != NoSquare: 1 else: 0) or
  (if cr.wq != NoSquare: 2 else: 0) or
  (if cr.bk != NoSquare: 4 else: 0) or
  (if cr.bq != NoSquare: 8 else: 0)

func unsetRook*(cr: var CastlingRooks, sq: Square) {.inline.} =
  if   cr.wk == sq: cr.wk = NoSquare
  elif cr.wq == sq: cr.wq = NoSquare
  elif cr.bk == sq: cr.bk = NoSquare
  elif cr.bq == sq: cr.bq = NoSquare

func rook*(cr: CastlingRooks, us: Color, kingside: bool): Square {.inline.} =
  if us == White: (if kingside: cr.wk else: cr.wq)
  else:           (if kingside: cr.bk else: cr.bq)

type
  UndoInfo* = object
    hash*: ZobristKey
    pawnHash*: ZobristKey
    nonPawnHash*: array[2, ZobristKey]
    castlingRooks*: CastlingRooks
    epSquare*: Square
    halfmove*: uint8
    captured*: Piece
    checkers*: Bitboard
    pinHV*: Bitboard
    pinD12*: Bitboard
    threats*: Bitboard

  Board* = object
    byPiece*: array[12, Bitboard]
    byColor*: array[2, Bitboard]
    occupied*: Bitboard
    mailbox*: array[64, Piece]
    stm*: Color
    castlingRooks*: CastlingRooks
    epSquare*: Square
    halfmove*: uint8
    fullmove*: uint16
    hash*: ZobristKey
    pawnHash*: ZobristKey
    nonPawnHash*: array[2, ZobristKey]
    gamePly*: int
    checkers*: Bitboard
    pinHV*: Bitboard
    pinD12*: Bitboard
    threats*: Bitboard
    history*: array[1024, UndoInfo]
    histLen*: int

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
  if p == WhitePawn or p == BlackPawn:
    b.pawnHash = b.pawnHash xor pieceKeys[p.ord][sq.int]
  else:
    b.nonPawnHash[p.color.ord] = b.nonPawnHash[p.color.ord] xor pieceKeys[
        p.ord][sq.int]

proc removePiece(b: var Board, sq: Square) {.inline.} =
  let p = b.mailbox[sq.int]
  if p != NoPiece:
    let sqBit = bit(sq)
    b.byPiece[p.ord] = b.byPiece[p.ord] and not sqBit
    b.byColor[p.color.ord] = b.byColor[p.color.ord] and not sqBit
    b.occupied = b.occupied and not sqBit
    b.mailbox[sq.int] = NoPiece
    b.hash = b.hash xor pieceKeys[p.ord][sq.int]
    if p == WhitePawn or p == BlackPawn:
      b.pawnHash = b.pawnHash xor pieceKeys[p.ord][sq.int]
    else:
      b.nonPawnHash[p.color.ord] = b.nonPawnHash[p.color.ord] xor pieceKeys[
          p.ord][sq.int]

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

    let delta = pieceKeys[p.ord][fromSq.int] xor pieceKeys[p.ord][toSq.int]
    b.hash = b.hash xor delta
    if p == WhitePawn or p == BlackPawn:
      b.pawnHash = b.pawnHash xor delta
    else:
      b.nonPawnHash[p.color.ord] = b.nonPawnHash[p.color.ord] xor delta

proc attackersTo*(b: Board, sq: Square, occ: Bitboard, them: Color): Bitboard =
  let offset = them.ord * 6
  let enemyPawns = b.byPiece[offset + Pawn.ord]
  let enemyKnights = b.byPiece[offset + Knight.ord]
  let enemyBishops = b.byPiece[offset + Bishop.ord]
  let enemyRooks = b.byPiece[offset + Rook.ord]
  let enemyQueens = b.byPiece[offset + Queen.ord]
  let enemyKing = b.byPiece[offset + King.ord]

  (getPawnAttacks(sq, them.opposite()) and enemyPawns) or
  (getKnightAttacks(sq) and enemyKnights) or
  (getBishopAttacks(sq, occ) and (enemyBishops or enemyQueens)) or
  (getRookAttacks(sq, occ) and (enemyRooks or enemyQueens)) or
  (getKingAttacks(sq) and enemyKing)

proc attackersTo*(b: Board, sq: Square, occ: Bitboard): Bitboard {.inline.} =
  b.attackersTo(sq, occ, White) or b.attackersTo(sq, occ, Black)

func pawnAttackLeft(bb: Bitboard, c: Color): Bitboard {.inline.} =
  if c == White: (bb and not FileA) shl 7
  else: (bb and not FileH) shr 7

func pawnAttackRight(bb: Bitboard, c: Color): Bitboard {.inline.} =
  if c == White: (bb and not FileH) shl 9
  else: (bb and not FileA) shr 9

proc updateAttackState*(b: var Board) =
  let us = b.stm
  let them = us.opposite()
  let kingSq = b.byPiece[us.ord * 6 + King.ord].lsb()
  let occ = b.occupied

  b.checkers = b.attackersTo(kingSq, occ, them)

  b.pinHV = Bitboard(0)
  b.pinD12 = Bitboard(0)

  let offset = them.ord * 6
  let enemyRooks = b.byPiece[offset + Rook.ord]
  let enemyBishops = b.byPiece[offset + Bishop.ord]
  let enemyQueens = b.byPiece[offset + Queen.ord]

  let enemyHV = enemyRooks or enemyQueens
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
  if b.pinHV.hasSq(sq): return b.pinHV
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
  result.castlingRooks.wk = NoSquare
  result.castlingRooks.wq = NoSquare
  result.castlingRooks.bk = NoSquare
  result.castlingRooks.bq = NoSquare

  # Find king files from mailbox
  var wKingFile = -1
  var bKingFile = -1
  for f in 0..7:
    if result.mailbox[makeSquare(0, f).int] == WhiteKing: wKingFile = f
    if result.mailbox[makeSquare(7, f).int] == BlackKing: bKingFile = f

  if parts.len > 2 and parts[2] != "-":
    if gChess960:
      for c in parts[2]:
        if c in 'A'..'H':
          let f = ord(c) - ord('A')
          if f < wKingFile: result.castlingRooks.wq = makeSquare(0, f)
          else:             result.castlingRooks.wk = makeSquare(0, f)
        elif c in 'a'..'h':
          let f = ord(c) - ord('a')
          if f < bKingFile: result.castlingRooks.bq = makeSquare(7, f)
          else:             result.castlingRooks.bk = makeSquare(7, f)
        elif c in {'K', 'Q', 'k', 'q'}:
          let (rank, kf, forward) = case c
            of 'K': (0, wKingFile, true)
            of 'Q': (0, wKingFile, false)
            of 'k': (7, bKingFile, true)
            else:   (7, bKingFile, false)
          let rookPiece = if rank == 0: WhiteRook else: BlackRook
          var f = if forward: kf + 1 else: kf - 1
          while f >= 0 and f <= 7:
            let sq = makeSquare(rank, f)
            if result.mailbox[sq.int] == rookPiece:
              case c
              of 'K': result.castlingRooks.wk = sq
              of 'Q': result.castlingRooks.wq = sq
              of 'k': result.castlingRooks.bk = sq
              else:   result.castlingRooks.bq = sq
              break
            f += (if forward: 1 else: -1)
    else:
      for c in parts[2]:
        case c
        of 'K': result.castlingRooks.wk = H1
        of 'Q': result.castlingRooks.wq = A1
        of 'k': result.castlingRooks.bk = H8
        of 'q': result.castlingRooks.bq = A8
        else: discard

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

  for i in 0..11:
    result.byPiece[i] = Bitboard(0)
  result.byColor[0] = Bitboard(0)
  result.byColor[1] = Bitboard(0)
  result.occupied = Bitboard(0)
  result.hash = ZobristKey(0)
  result.pawnHash = ZobristKey(0)
  result.nonPawnHash[0] = ZobristKey(0)
  result.nonPawnHash[1] = ZobristKey(0)

  for sq in 0..63:
    let p = result.mailbox[sq]
    if p != NoPiece:
      let sqBit = bit(Square(sq))
      result.byPiece[p.ord] = result.byPiece[p.ord] or sqBit
      result.byColor[p.color.ord] = result.byColor[p.color.ord] or sqBit
      result.occupied = result.occupied or sqBit
      result.hash = result.hash xor pieceKeys[p.ord][sq]
      if p == WhitePawn or p == BlackPawn:
        result.pawnHash = result.pawnHash xor pieceKeys[p.ord][sq]
      else:
        result.nonPawnHash[p.color.ord] = result.nonPawnHash[
            p.color.ord] xor pieceKeys[p.ord][sq]

  if result.stm == Black:
    result.hash = result.hash xor sideKey

  result.hash = result.hash xor castlingKeys[result.castlingRooks.rightsMask]

  if result.epSquare != NoSquare:
    result.hash = result.hash xor epKeys[result.epSquare.file]

  updateAttackState(result)

const StartPos* = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"

proc toFen*(b: Board): string =
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
  if gChess960:
    if b.castlingRooks.wk != NoSquare: castlingStr.add(char(ord('A') + b.castlingRooks.wk.file))
    if b.castlingRooks.wq != NoSquare: castlingStr.add(char(ord('A') + b.castlingRooks.wq.file))
    if b.castlingRooks.bk != NoSquare: castlingStr.add(char(ord('a') + b.castlingRooks.bk.file))
    if b.castlingRooks.bq != NoSquare: castlingStr.add(char(ord('a') + b.castlingRooks.bq.file))
  else:
    if b.castlingRooks.wk != NoSquare: castlingStr.add('K')
    if b.castlingRooks.wq != NoSquare: castlingStr.add('Q')
    if b.castlingRooks.bk != NoSquare: castlingStr.add('k')
    if b.castlingRooks.bq != NoSquare: castlingStr.add('q')
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

  b.history[b.histLen] = UndoInfo(
    hash: b.hash,
    pawnHash: b.pawnHash,
    nonPawnHash: b.nonPawnHash,
    castlingRooks: b.castlingRooks,
    epSquare: b.epSquare,
    halfmove: b.halfmove,
    captured: captured,
    checkers: b.checkers,
    pinHV: b.pinHV,
    pinD12: b.pinD12,
    threats: b.threats
  )
  inc b.histLen

  b.hash = b.hash xor castlingKeys[b.castlingRooks.rightsMask]
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
    let rookSq = toSq
    let kingDst = if fromSq.file < rookSq.file: fromSq.withFile(6) else: fromSq.withFile(2)
    let rookDst = if fromSq.file < rookSq.file: fromSq.withFile(5) else: fromSq.withFile(3)
    b.removePiece(fromSq)
    b.removePiece(rookSq)
    b.putPiece(makePiece(b.stm, King), kingDst)
    b.putPiece(makePiece(b.stm, Rook), rookDst)

  elif m.isEnPassant:
    let capSq = toSq + (if b.stm == White: -8 else: 8)
    b.removePiece(capSq)
    b.movePiece(fromSq, toSq)

  else:
    if captured != NoPiece:
      b.removePiece(toSq)
    b.movePiece(fromSq, toSq)

  if movingPiece.pieceType == King:
    if b.stm == White: b.castlingRooks.wk = NoSquare; b.castlingRooks.wq = NoSquare
    else:              b.castlingRooks.bk = NoSquare; b.castlingRooks.bq = NoSquare
  elif movingPiece.pieceType == Rook:
    b.castlingRooks.unsetRook(fromSq)

  if captured.pieceType == Rook:
    b.castlingRooks.unsetRook(toSq)

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

  b.hash = b.hash xor castlingKeys[b.castlingRooks.rightsMask]
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
    let rookSq = toSq
    let kingDst = if fromSq.file < rookSq.file: fromSq.withFile(6) else: fromSq.withFile(2)
    let rookDst = if fromSq.file < rookSq.file: fromSq.withFile(5) else: fromSq.withFile(3)
    b.removePiece(kingDst)
    b.removePiece(rookDst)
    b.putPiece(makePiece(b.stm, King), fromSq)
    b.putPiece(makePiece(b.stm, Rook), rookSq)

  elif m.isEnPassant:
    b.movePiece(toSq, fromSq)
    let capSq = toSq + (if b.stm == White: -8 else: 8)
    b.putPiece(undo.captured, capSq)

  else:
    b.movePiece(toSq, fromSq)
    if undo.captured != NoPiece:
      b.putPiece(undo.captured, toSq)

  b.castlingRooks = undo.castlingRooks
  b.epSquare = undo.epSquare
  b.halfmove = undo.halfmove
  b.hash = undo.hash
  b.pawnHash = undo.pawnHash
  b.nonPawnHash = undo.nonPawnHash
  b.checkers = undo.checkers
  b.pinHV = undo.pinHV
  b.pinD12 = undo.pinD12
  b.threats = undo.threats

proc makeNullMove*(b: var Board) =
  doAssert b.histLen < 1024

  b.history[b.histLen] = UndoInfo(
    hash: b.hash,
    pawnHash: b.pawnHash,
    nonPawnHash: b.nonPawnHash,
    castlingRooks: b.castlingRooks,
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

  b.castlingRooks = undo.castlingRooks
  b.epSquare = undo.epSquare
  b.halfmove = undo.halfmove
  b.hash = undo.hash
  b.pawnHash = undo.pawnHash
  b.nonPawnHash = undo.nonPawnHash
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

proc scharnaglToBackrank*(n: uint32): array[8, PieceType] =
  const kN5 = [(0,0),(0,1),(0,2),(0,3),(1,1),(1,2),(1,3),(2,2),(2,3),(3,3)]
  doAssert n < 960
  for i in 0..7: result[i] = NoPieceType

  proc placeNthFree(res: var array[8, PieceType], n: int, pt: PieceType) =
    var free = 0
    for i in 0..7:
      if res[i] == NoPieceType:
        if free == n: res[i] = pt; return
        inc free

  proc placeFirstFree(res: var array[8, PieceType], pt: PieceType) =
    for i in 0..7:
      if res[i] == NoPieceType: res[i] = pt; return

  let n2 = n div 4;  let b1 = n mod 4
  let n3 = n2 div 4; let b2 = n2 mod 4
  let n4 = n3 div 6; let q  = n3 mod 6

  result[system.int(b1) * 2 + 1] = Bishop
  result[system.int(b2) * 2]     = Bishop
  result.placeNthFree(system.int(q), Queen)
  let (k1, k2) = kN5[n4]
  result.placeNthFree(k1, Knight)
  result.placeNthFree(k2, Knight)
  result.placeFirstFree(Rook)
  result.placeFirstFree(King)
  result.placeFirstFree(Rook)

proc buildFrcBoard(whiteBack, blackBack: array[8, PieceType]): Board =
  for i in 0..63: result.mailbox[i] = NoPiece
  result.stm = White
  result.halfmove = 0
  result.fullmove = 1
  result.epSquare = NoSquare

  for f in 0..7:
    result.mailbox[makeSquare(0, f).int] = makePiece(White, whiteBack[f])
    result.mailbox[makeSquare(1, f).int] = WhitePawn
    result.mailbox[makeSquare(6, f).int] = BlackPawn
    result.mailbox[makeSquare(7, f).int] = makePiece(Black, blackBack[f])

  result.castlingRooks.wk = NoSquare
  result.castlingRooks.wq = NoSquare
  result.castlingRooks.bk = NoSquare
  result.castlingRooks.bq = NoSquare

  var seenWRook = false
  var seenBRook = false
  for f in 0..7:
    if whiteBack[f] == Rook:
      if not seenWRook: result.castlingRooks.wq = makeSquare(0, f); seenWRook = true
      else:             result.castlingRooks.wk = makeSquare(0, f)
    if blackBack[f] == Rook:
      if not seenBRook: result.castlingRooks.bq = makeSquare(7, f); seenBRook = true
      else:             result.castlingRooks.bk = makeSquare(7, f)

  for sq in 0..63:
    let p = result.mailbox[sq]
    if p != NoPiece:
      let sqBit = bit(Square(sq))
      result.byPiece[p.ord] = result.byPiece[p.ord] or sqBit
      result.byColor[p.color.ord] = result.byColor[p.color.ord] or sqBit
      result.occupied = result.occupied or sqBit
      result.hash = result.hash xor pieceKeys[p.ord][sq]
      if p == WhitePawn or p == BlackPawn:
        result.pawnHash = result.pawnHash xor pieceKeys[p.ord][sq]
      else:
        result.nonPawnHash[p.color.ord] = result.nonPawnHash[p.color.ord] xor pieceKeys[p.ord][sq]

  result.hash = result.hash xor castlingKeys[result.castlingRooks.rightsMask]
  updateAttackState(result)

proc fromFrcIndex*(n: uint32): Board =
  doAssert n < 960
  let back = scharnaglToBackrank(n)
  buildFrcBoard(back, back)

proc fromDfrcIndex*(n: uint32): Board =
  doAssert n < 960 * 960
  let whiteBack = scharnaglToBackrank(n mod 960)
  let blackBack  = scharnaglToBackrank(n div 960)
  buildFrcBoard(whiteBack, blackBack)
