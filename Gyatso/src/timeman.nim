import searchparams

type TimeInfo* = object
  softLimit*: int64
  hardLimit*: int64

proc calcTimeInfo*(myTime, myInc, movestogo: int): TimeInfo =
  ## Returns allocated soft and hard limits in milliseconds for this move.
  let timeBase = myTime div TmTimeDiv + myInc * TmIncNum div TmIncDen
  let hard = int64(timeBase * TmHardNum div TmHardDen)
  let soft = int64(timeBase * TmSoftNum div TmSoftDen)
  TimeInfo(
    softLimit: max(10'i64, soft),
    hardLimit: max(10'i64, hard)
  )
