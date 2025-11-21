import types, move, position

import std/[tables, locks]

type
  HashTableEntry* {.packed.} = object
    upperZobristKeyAndNodeTypeAndValue: uint64
    depth*: Ply
    bestMove*: Move

  CountedHashTableEntry = object
    entry: HashTableEntry
    lookupCounter: uint32

  HashTable* {.requiresInit.} = object
    nonPvNodes: seq[HashTableEntry]
    hashFullCounter: int
    pvNodes: Table[ZobristKey, CountedHashTableEntry]
    pvTableMutex: Lock

const
  noEntry = HashTableEntry(
    upperZobristKeyAndNodeTypeAndValue: 0, depth: 0.Ply, bestMove: noMove
  )
  sixteenBitMask = 0b1111_1111_1111_1111'u64
  eighteenBitMask = 0b11_1111_1111_1111_1111'u64
  minHashSize = eighteenBitMask.int + 1

static:
  doAssert minHashSize * sizeof(HashTableEntry) <= 16_000_000
  # 16 MB

func value*(entry: HashTableEntry): Value =
  cast[int16](entry.upperZobristKeyAndNodeTypeAndValue and sixteenBitMask).Value

func nodeType*(entry: HashTableEntry): NodeType =
  cast[int8]((entry.upperZobristKeyAndNodeTypeAndValue and eighteenBitMask) shr 16).NodeType

func sameUpperZobristKey(a: uint64, b: uint64): bool =
  (a and not eighteenBitMask) == (b and not eighteenBitMask)

func clear*(ht: var HashTable) =
  ht.pvNodes.clear
  ht.hashFullCounter = 0
  for entry in ht.nonPvNodes.mitems:
    entry = noEntry

func setLen*(ht: var HashTable, newLen: int) =
  ht.nonPvNodes.setLen(max(newLen, minHashSize))
  ht.clear

func setByteSize*(ht: var HashTable, sizeInBytes: int) =
  let numEntries = sizeInBytes div sizeof(HashTableEntry)
  ht.setLen numEntries

func newHashTable*(len = 0): HashTable =
  result = HashTable(
    nonPvNodes: newSeq[HashTableEntry](0),
    hashFullCounter: 0,
    pvNodes: Table[ZobristKey, CountedHashTableEntry](),
    pvTableMutex: Lock(),
  )
  initLock result.pvTableMutex
  result.setLen len

template isEmpty*(entry: HashTableEntry): bool =
  entry == noEntry

func age*(ht: var HashTable) =
  var deleteQueue: seq[ZobristKey] = @[]
  for (key, entry) in ht.pvNodes.mpairs:
    if entry.lookupCounter <= 0:
      deleteQueue.add(key)
    else:
      entry.lookupCounter = 0
  for key in deleteQueue:
    ht.pvNodes.del(key)

func remove*(ht: var HashTable, zobristKey: ZobristKey) =
  withLock ht.pvTableMutex:
    if ht.pvNodes.hasKey(zobristKey):
      ht.pvNodes.del(zobristKey)

  let i = zobristKey mod ht.nonPvNodes.len.ZobristKey
  ht.nonPvNodes[i] = noEntry

func add*(
    ht: var HashTable,
    zobristKey: ZobristKey,
    nodeType: NodeType,
    value: Value,
    depth: Ply,
    bestMove: Move,
) =
  let entry = HashTableEntry(
    upperZobristKeyAndNodeTypeAndValue: (
      (zobristKey and not eighteenBitMask) or
      ((cast[uint64](nodeType.int64) shl 16) and eighteenBitMask and not sixteenBitMask) or
      (cast[uint64](value.int64) and sixteenBitMask)
    ),
    depth: depth,
    bestMove: bestMove,
  )
  doAssert entry.value == value
  doAssert entry.nodeType == nodeType
  doAssert sameUpperZobristKey(entry.upperZobristKeyAndNodeTypeAndValue, zobristKey)

  static:
    doAssert (valueInfinity <= int16.high.Value and -valueInfinity >= int16.low.Value)

  if nodeType == pvNode:
    withLock ht.pvTableMutex:
      if not ht.pvNodes.hasKey(zobristKey) or ht.pvNodes[zobristKey].entry.depth <= depth:
        ht.pvNodes[zobristKey] = CountedHashTableEntry(entry: entry, lookupCounter: 1)
  else:
    doAssert ht.nonPvNodes.len > 0
    let i = zobristKey mod ht.nonPvNodes.len.ZobristKey
    if ht.nonPvNodes[i].isEmpty:
      ht.hashFullCounter += 1
    ht.nonPvNodes[i] = entry

func get*(ht: var HashTable, zobristKey: ZobristKey): HashTableEntry =
  if ht.pvNodes.hasKey(zobristKey):
    withLock ht.pvTableMutex:
      if ht.pvNodes.hasKey(zobristKey):
        ht.pvNodes[zobristKey].lookupCounter += 1
        return ht.pvNodes[zobristKey].entry

  doAssert ht.nonPvNodes.len > 0
  let i = zobristKey mod ht.nonPvNodes.len.ZobristKey
  if not ht.nonPvNodes[i].isEmpty and
      sameUpperZobristKey(
        zobristKey, ht.nonPvNodes[i].upperZobristKeyAndNodeTypeAndValue
      ):
    return ht.nonPvNodes[i]

  noEntry

func hashFull*(ht: HashTable): int =
  (ht.hashFullCounter * 1000) div ht.nonPvNodes.len

func getPv*(ht: var HashTable, position: Position): seq[Move] =
  result = @[]

  var
    encounteredZobristKeys: seq[ZobristKey] = @[]
    currentPosition = position
  while true:
    if currentPosition.zobristKey in encounteredZobristKeys:
      return result
    encounteredZobristKeys.add(currentPosition.zobristKey)
    let entry = ht.get(currentPosition.zobristKey)

    if entry.isEmpty or not currentPosition.isLegal(entry.bestMove) or currentPosition.halfmoveClock >= 100:
      return result
    result.add(entry.bestMove)
    currentPosition = currentPosition.doMove(entry.bestMove)
