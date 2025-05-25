import coretypes # For Square
import strutils # For toLowerAscii

# Helper functions will be implemented here.

proc fileOf*(sq: Square): int {.inline.} =
  ## Returns the file (column) of a square (0-7 for a-h).
  return int(sq) mod 8

proc rankOf*(sq: Square): int {.inline.} =
  ## Returns the rank (row) of a square (0-7 for 1-8).
  return int(sq) div 8

proc squareFromCoords*(rank, file: int): Square {.inline.} =
  ## Creates a square from rank (0-7) and file (0-7).
  ## A1 = rank 0, file 0. H8 = rank 7, file 7.
  assert(rank >= 0 and rank <= 7, "Rank out of bounds")
  assert(file >= 0 and file <= 7, "File out of bounds")
  return Square(rank * 8 + file)

proc squareToAlgebraic*(sq: Square): string {.inline.} =
  ## Converts a square to its algebraic notation (e.g., "a1", "h8").
  let f = fileOf(sq)
  let r = rankOf(sq)
  result = ""
  result.add(char('a'.ord + f))
  result.add(char('1'.ord + r))

proc algebraicToSquare*(s: string): Square {.inline.} =
  ## Converts an algebraic square notation (e.g., "a1") to a Square.
  ## Assumes input is a valid 2-character algebraic string (e.g., "a1"-"h8").
  assert(s.len == 2, "Algebraic notation must be 2 characters long")
  
  let fileChar = s[0].toLowerAscii
  let rankChar = s[1]

  let file = int(fileChar) - int('a')
  let rank = int(rankChar) - int('1')

  assert(file >= 0 and file <= 7, "Invalid file character: " & $fileChar)
  assert(rank >= 0 and rank <= 7, "Invalid rank character: " & $rankChar)
  
  return squareFromCoords(rank, file) 