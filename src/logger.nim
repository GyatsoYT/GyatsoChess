import std/times
import std/locks
import std/strformat
import std/strutils # For toUpperAscii

type
  LogLevel* = enum
    Debug, Info, Warn, Error, Fatal

var
  logFile*: File
  logLock*: Lock
  currentLogLevel*: LogLevel = Info # Default verbosity
  logFilePath*: string = "engine.log"
  logToConsole*: bool = true
  logToFile*: bool = true

proc initLogger*(path: string = "engine.log"; verbosity: LogLevel = Info; console: bool = true; file: bool = true) =
  logFilePath = path
  currentLogLevel = verbosity
  logToConsole = console
  logToFile = file
  initLock(logLock)
  if logToFile:
    logFile = open(logFilePath, fmAppend)
    if logFile == nil:
      echo &"Warning: Could not open log file {logFilePath}. Logging to file will be disabled."
      logToFile = false

proc deinitLogger*() =
  if logToFile and logFile != nil:
    close(logFile)
    logFile = nil # Mark as closed

proc log*(message: string; level: LogLevel = Info) =
  if level < currentLogLevel: # Only log if the message level is at or above the current verbosity
    return

  let timeAsDateTime = fromUnixFloat(epochTime())
  let timeStr = timeAsDateTime.format("yyyy-MM-dd HH:mm:ss")
  let levelStr = $level
  let formattedMessage = &"[{timeStr}] [{levelStr.toUpperAscii()}] {message}"

  acquire(logLock)
  try:
    if logToConsole:
      echo formattedMessage
    if logToFile and logFile != nil:
      logFile.writeLine(formattedMessage)
      logFile.flushFile() # Ensure it's written immediately, important for debugging crashes
  finally:
    release(logLock)

# Example of usage (can be removed or kept for testing):
when isMainModule:
  initLogger(verbosity = LogLevel.Debug)
  log("This is a debug message.", LogLevel.Debug)
  log("This is an info message.") # Defaults to Info
  log("This is a warning.", LogLevel.Warn)
  log("This is an error!", LogLevel.Error)
  log("This is fatal!!!", LogLevel.Fatal)
  deinitLogger() 