proc calcMoveTime*(myTime, myInc, movestogo: int): int =
  ## Returns allocated milliseconds for this move.
  let mtg = if movestogo > 0: min(movestogo, 50) else: 30
  max(10, (myTime div mtg) + myInc - 50)   # 50 ms overhead
