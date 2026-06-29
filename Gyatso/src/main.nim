import attacks
import evaluate
import uci
import tt
import searchparams

when isMainModule:
  initAttacks()
  initThreadAttacks()
  initTT(16)
  initTables()
  initNNUE()
  runUciLoop()
