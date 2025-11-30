
import threading
import std/strutils
import std/times
import std/locks

type
  LogLevel* = enum
    Debug, Info, Warn, Error

var
  logLock: Lock
  logFile: File

proc initLogger*(filename: string = "engine.log") =
  initLock(logLock)
  try:
    logFile = open(filename, fmAppend)
  except IOError:
    stderr.writeLine("Failed to open log file: " & filename)

proc log*(msg: string, level: LogLevel = Info) =
  let timestamp = now().format("yyyy-MM-dd HH:mm:ss")
  let logMsg = "[$1] [$2] $3".format(timestamp, $level, msg)
  
  withLock logLock:
    if logFile != nil:
      try:
        logFile.writeLine(logMsg)
        logFile.flushFile()
      except IOError:
        discard
    # Optionally print to stderr for debugging, but UCI relies on stdout for commands
    # stderr.writeLine(logMsg)

proc closeLogger*() =
  if logFile != nil:
    logFile.close()
  deinitLock(logLock)
