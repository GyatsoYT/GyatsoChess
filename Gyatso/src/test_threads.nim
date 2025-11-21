
# No import

proc foo() {.thread.} =
  echo "Hello from thread"

when isMainModule:
  var t: Thread[void]
  createThread(t, foo)
  joinThread(t)
