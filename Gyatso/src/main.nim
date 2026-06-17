import attacks
import zobrist
import evaluate
import uci
import tt
import searchparams

when isMainModule:
  initZobrist()
  initAttacks()
  initThreadAttacks()
  initTT(16)
  initTables()
  initNNUE()
  runUciLoop()
