var hugePagesActive* = false

func roundUp(x, a: int): int {.inline.} =
  (x + a - 1) div a * a

when defined(windows):
  import std/locks

  type
    Luid {.pure.} = object
      lowPart: uint32
      highPart: int32
    LuidAndAttributes {.pure.} = object
      luid: Luid
      attributes: uint32
    TokenPrivileges {.pure.} = object
      privilegeCount: uint32
      privileges: array[1, LuidAndAttributes]

  const
    MemCommit = 0x1000'u32
    MemReserve = 0x2000'u32
    MemRelease = 0x8000'u32
    MemLargePages = 0x20000000'u32
    PageReadWrite = 0x04'u32
    TokenAdjustPrivileges = 0x0020'u32
    TokenQuery = 0x0008'u32
    SePrivilegeEnabled = 0x00000002'u32

  proc getLargePageMinimum(): csize_t
    {.stdcall, dynlib: "kernel32", importc: "GetLargePageMinimum".}
  proc virtualAlloc(p: pointer, size: csize_t, allocType, protect: uint32): pointer
    {.stdcall, dynlib: "kernel32", importc: "VirtualAlloc".}
  proc virtualFree(p: pointer, size: csize_t, freeType: uint32): int32
    {.stdcall, dynlib: "kernel32", importc: "VirtualFree".}
  proc getCurrentProcess(): pointer
    {.stdcall, dynlib: "kernel32", importc: "GetCurrentProcess".}
  proc getLastError(): uint32
    {.stdcall, dynlib: "kernel32", importc: "GetLastError".}
  proc closeHandle(h: pointer): int32
    {.stdcall, dynlib: "kernel32", importc: "CloseHandle".}
  proc openProcessToken(proc0: pointer, access: uint32, token: ptr pointer): int32
    {.stdcall, dynlib: "advapi32", importc: "OpenProcessToken".}
  proc lookupPrivilegeValueA(system, name: cstring, luid: ptr Luid): int32
    {.stdcall, dynlib: "advapi32", importc: "LookupPrivilegeValueA".}
  proc adjustTokenPrivileges(token: pointer, disableAll: int32,
      newState: ptr TokenPrivileges, bufLen: uint32,
      prevState: ptr TokenPrivileges, retLen: ptr uint32): int32
    {.stdcall, dynlib: "advapi32", importc: "AdjustTokenPrivileges".}

  var gPrivLock: Lock
  initLock(gPrivLock)

  proc allocLarge(bytes: int): pointer =
    let pageSize = int(getLargePageMinimum())
    if pageSize == 0 or bytes < pageSize: return nil
    let size = roundUp(bytes, pageSize)

    withLock gPrivLock:
      var token: pointer = nil
      if openProcessToken(getCurrentProcess(),
          TokenAdjustPrivileges or TokenQuery, addr token) == 0:
        return nil

      var req: TokenPrivileges
      req.privilegeCount = 1
      req.privileges[0].attributes = SePrivilegeEnabled
      if lookupPrivilegeValueA(nil, cstring"SeLockMemoryPrivilege",
          addr req.privileges[0].luid) == 0:
        discard closeHandle(token)
        return nil

      var prev: TokenPrivileges
      var prevSize = uint32(sizeof(prev))
      let adjusted = adjustTokenPrivileges(token, 0, addr req, prevSize,
          addr prev, addr prevSize) != 0
      let err = getLastError()

      var mem: pointer = nil
      if adjusted and err == 0:
        mem = virtualAlloc(nil, csize_t(size),
            MemReserve or MemCommit or MemLargePages, PageReadWrite)

      if adjusted and prev.privilegeCount != 0:
        discard adjustTokenPrivileges(token, 0, addr prev, 0, nil, nil)
      discard closeHandle(token)
      return mem

  proc osAlloc*(bytes: int): pointer =
    if bytes <= 0: return nil
    hugePagesActive = false
    result = allocLarge(bytes)
    if result != nil:
      hugePagesActive = true
      return
    result = virtualAlloc(nil, csize_t(bytes), MemReserve or MemCommit,
        PageReadWrite)

  proc osFree*(p: pointer, bytes: int) =
    if p != nil: discard virtualFree(p, 0, MemRelease)

elif defined(linux):
  import std/[posix, math, strutils]

  const MadvHugepage = 14.cint

  proc madvise(adr: pointer, len: csize_t, advice: cint): cint
    {.importc, header: "<sys/mman.h>".}

  let normalPageSize: int = block:
    let v = sysconf(SC_PAGESIZE)
    if v > 0: int(v) else: 4096

  let hugePageSize: int = block:
    var v = 0
    try:
      v = parseInt(readFile(
          "/sys/kernel/mm/transparent_hugepage/hpage_pmd_size").strip())
    except CatchableError:
      v = 0
    if v >= normalPageSize and isPowerOfTwo(v): v else: normalPageSize

  proc osAlloc*(bytes: int): pointer =
    if bytes <= 0: return nil
    hugePagesActive = false
    let size = roundUp(bytes, normalPageSize)
    let align = hugePageSize
    var mem: pointer = MAP_FAILED

    let mapping = mmap(nil, size + align, PROT_READ or PROT_WRITE,
        MAP_PRIVATE or MAP_ANONYMOUS, -1.cint, 0)
    if mapping != MAP_FAILED:
      let base = cast[uint](mapping)
      let offset = int((uint(align) - base mod uint(align)) mod uint(align))
      let aligned = cast[pointer](base + uint(offset))
      var ok = true
      if offset > 0 and munmap(mapping, offset) != 0: ok = false
      let tail = cast[pointer](cast[uint](aligned) + uint(size))
      if munmap(tail, align - offset) != 0: ok = false
      if ok: mem = aligned

    if mem == MAP_FAILED:
      mem = mmap(nil, size, PROT_READ or PROT_WRITE,
          MAP_PRIVATE or MAP_ANONYMOUS, -1.cint, 0)
    if mem == MAP_FAILED: return nil

    discard madvise(mem, csize_t(size), MadvHugepage)
    hugePagesActive = align > normalPageSize
    return mem

  proc osFree*(p: pointer, bytes: int) =
    if p != nil: discard munmap(p, roundUp(bytes, normalPageSize))

else:
  proc osAlloc*(bytes: int): pointer = nil
  proc osFree*(p: pointer, bytes: int) = discard
