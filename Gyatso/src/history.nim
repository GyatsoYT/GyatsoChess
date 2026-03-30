import move

type
  HistoryTables* = object
    mainHistory*: array[2, array[4096, int16]]

template historyIndex*(m: Move): int =
  ## Butterfly index: (fromSq << 6) | toSq
  (m.fromSquare.int shl 6) or m.toSquare.int

template updateHistoryStat*(stat: var int16, bonus: int) =
  var s = stat.int
  let gravityDiv = 512 + (abs(bonus) shr 4)
  s += (32 * bonus) - (s * abs(bonus)) div gravityDiv
  stat = clamp(s, -16384, 16384).int16

proc initHistory*(ht: var HistoryTables) =
  zeroMem(addr ht, sizeof(ht))
