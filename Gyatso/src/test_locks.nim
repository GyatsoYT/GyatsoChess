
import std/locks

when isMainModule:
  var L: Lock
  initLock(L)
  echo "Locks working"
