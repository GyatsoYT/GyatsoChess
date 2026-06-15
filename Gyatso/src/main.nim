import attacks
import zobrist
import evaluate
import uci
import tt

when isMainModule:
  initZobrist()
  initAttacks()
  initThreadAttacks()
  initTT(16)
  initNNUE()
  runUciLoop()
