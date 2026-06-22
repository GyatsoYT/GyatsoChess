import coretypes

const
  BoundExact* = 0'u8
  BoundAlpha* = 1'u8
  BoundBeta*  = 2'u8

type
  TTEntry* = object
    key*: uint64
    data*: uint64

var
  ttTable*: ptr UncheckedArray[TTEntry] = nil
  ttMask*: uint64 = 0

func prefetch(p: pointer; rw: cint = 0; locality: cint = 3) {.importc: "__builtin_prefetch", nodecl, varargs, inline.}

proc prefetchTT*(key: uint64) {.inline.} =
  if ttTable != nil and ttMask != 0:
    prefetch(addr ttTable[key and ttMask], 0, 3)

func packData*(move: Move, score: int16, depth: int8, bound: uint8): uint64 {.inline.} =
  result = (uint64(uint16(move)) shl 0) or
           (uint64(cast[uint16](score)) shl 16) or
           (uint64(cast[uint8](depth)) shl 32) or
           (uint64(bound) shl 40)

func unpackData*(data: uint64, move: var Move, score: var int16, depth: var int8, bound: var uint8) {.inline.} =
  move = Move(uint16(data and 0xFFFF'u64))
  score = cast[int16](uint16((data shr 16) and 0xFFFF'u64))
  depth = cast[int8](uint8((data shr 32) and 0xFF'u64))
  bound = uint8((data shr 40) and 0xFF'u64)

proc initTT*(sizeMB: int) =
  if ttTable != nil:
    deallocShared(ttTable)
    ttTable = nil
  
  if sizeMB <= 0:
    ttMask = 0
    return

  let entrySize = sizeof(TTEntry)
  let bytes = sizeMB * 1024 * 1024
  
  var numEntries = 1'u64
  while numEntries * uint64(entrySize) * 2'u64 <= uint64(bytes):
    numEntries = numEntries shl 1
    
  if numEntries == 0:
    numEntries = 1024
    
  ttMask = numEntries - 1
  ttTable = cast[ptr UncheckedArray[TTEntry]](allocShared0(numEntries * uint64(entrySize)))

proc probeTT*(key: uint64, ply: int, move: var Move, score: var int, depth: var int, bound: var uint8): bool =
  if ttTable == nil or ttMask == 0: return false
  
  let idx = key and ttMask
  let dataVal = ttTable[idx].data
  let keyVal = ttTable[idx].key
  
  if (keyVal xor dataVal) == key:
    var m: Move
    var s: int16
    var d: int8
    var b: uint8
    unpackData(dataVal, m, s, d, b)
    
    move = m
    depth = int(d)
    bound = b
    
    var finalScore = int(s)
    if finalScore > MateThreshold:
      finalScore = finalScore - ply
    elif finalScore < -MateThreshold:
      finalScore = finalScore + ply
    score = finalScore
    return true
    
  return false

proc storeTT*(key: uint64, move: Move, score: int16, depth: int8, bound: uint8, ply: int) =
  if ttTable == nil or ttMask == 0: return
  
  let idx = key and ttMask
  var storedScore = score
  if score > MateThreshold:
    storedScore = score + int16(ply)
  elif score < -MateThreshold:
    storedScore = score - int16(ply)
    
  let dataVal = packData(move, storedScore, depth, bound)
  
  ttTable[idx].data = dataVal
  ttTable[idx].key = key xor dataVal
