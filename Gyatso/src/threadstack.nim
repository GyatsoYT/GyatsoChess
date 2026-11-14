when defined(linux):
  proc realPthreadAttrSetstacksize(attr: pointer, stackSize: csize_t): cint {.
      importc: "__real_pthread_attr_setstacksize", cdecl.}

  proc wrapPthreadAttrSetstacksize(attr: pointer, stackSize: csize_t): cint {.
      exportc: "__wrap_pthread_attr_setstacksize", cdecl, used.} =
    const MinThreadStack = csize_t(8 * 1024 * 1024)
    let size = if stackSize < MinThreadStack: MinThreadStack else: stackSize
    realPthreadAttrSetstacksize(attr, size)
