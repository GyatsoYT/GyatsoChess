
import coretypes

func squareFromCoords*(rank, file: int): Square {.inline.} =
  ## Rank and file are 0-indexed.
  ## Rank 0 is 1st rank, File 0 is A file.
  ## Square = rank * 8 + file
  (rank * 8 + file).Square

func fileOf*(sq: Square): int {.inline.} =
  sq mod 8

func rankOf*(sq: Square): int {.inline.} =
  sq div 8

func squareToAlgebraic*(sq: Square): string =
  let f = fileOf(sq)
  let r = rankOf(sq)
  result = ""
  result.add(char('a'.ord + f))
  result.add(char('1'.ord + r))

func algebraicToSquare*(s: string): Square =
  if s.len != 2: return 0.Square # Should probably raise or handle error
  let f = s[0].ord - 'a'.ord
  let r = s[1].ord - '1'.ord
  squareFromCoords(r, f)

func rankToChar*(rank: int): char =
  char('1'.ord + rank)

func fileToChar*(file: int): char =
  char('a'.ord + file)
