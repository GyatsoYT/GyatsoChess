# simd.nim — SIMD abstraction layer for NNUE inference
#
# Priority order (highest to lowest):
#   AVX512  (-d:avx512 -d:avx2)   — 32 × int16 per register
#   AVX2    (-d:avx2)              — 16 × int16 per register
#   NEON    (-d:neon  OR  aarch64) — 8  × int16 per register  (Apple Silicon / ARM64)
#   Scalar  (fallback)             — 1  element at a time

when defined(avx512) or defined(avx2):
    import nimsimd/avx2
    import nimsimd/avx
    import nimsimd/sse2


when defined(avx512):
    {.passC: "-mavx512f -mavx512bw".}
    when defined(avx512vnni):
        {.passC: "-mavx512vnni".}

    type
        M512i* {.importc: "__m512i", header: "immintrin.h", bycopy.} = object

    {.push header: "immintrin.h".}
    func mm512_add_epi32*(a, b: M512i): M512i {.importc: "_mm512_add_epi32".}
    func mm512_load_si512_impl(p: ptr M512i): M512i {.importc: "_mm512_load_si512".}
    func mm512_store_si512*(a: pointer, b: M512i) {.importc: "_mm512_store_si512".}
    func mm512_add_epi16*(a, b: M512i): M512i {.importc: "_mm512_add_epi16".}
    func mm512_sub_epi16*(a, b: M512i): M512i {.importc: "_mm512_sub_epi16".}
    func mm512_madd_epi16*(a, b: M512i): M512i {.importc: "_mm512_madd_epi16".}
    func mm512_max_epi16*(a, b: M512i): M512i {.importc: "_mm512_max_epi16".}
    func mm512_min_epi16*(a, b: M512i): M512i {.importc: "_mm512_min_epi16".}
    func mm512_mullo_epi16*(a, b: M512i): M512i {.importc: "_mm512_mullo_epi16".}
    func mm512_set1_epi16*(a: int16 | uint16): M512i {.importc: "_mm512_set1_epi16".}
    func mm512_setzero_si512*(): M512i {.importc: "_mm512_setzero_si512".}
    func mm512_reduce_add_epi32*(a: M512i): int32 {.importc: "_mm512_reduce_add_epi32".}
    {.pop.}

    template mm512_load_si512*(p: pointer): M512i =
        mm512_load_si512_impl(cast[ptr M512i](p))

    type
        VEPI16* = M512i
        VEPI32* = M512i

    const CHUNK_SIZE* = 32

    func vecZero16*(): VEPI16 {.inline.} = mm512_setzero_si512()
    func vecZero32*(): VEPI32 {.inline.} = mm512_setzero_si512()
    func vecSetOne16*(n: int16): VEPI16 {.inline.} = mm512_set1_epi16(n)
    func vecStore*(dst: pointer, vec: VEPI16) {.inline.} = mm512_store_si512(
            dst, vec)
    func vecLoad*(src: pointer): VEPI16 {.inline.} = mm512_load_si512(src)
    func vecMax16*(a, b: VEPI16): VEPI16 {.inline.} = mm512_max_epi16(a, b)
    func vecMin16*(a, b: VEPI16): VEPI16 {.inline.} = mm512_min_epi16(a, b)
    func vecMullo16*(a, b: VEPI16): VEPI16 {.inline.} = mm512_mullo_epi16(a, b)
    func vecMadd16*(a, b: VEPI16): VEPI32 {.inline.} = mm512_madd_epi16(a, b)
    func vecAdd16*(a, b: VEPI16): VEPI16 {.inline.} = mm512_add_epi16(a, b)
    func vecAdd32*(a, b: VEPI32): VEPI32 {.inline.} = mm512_add_epi32(a, b)
    func vecSub16*(a, b: VEPI16): VEPI16 {.inline.} = mm512_sub_epi16(a, b)
    func vecReduceAdd32*(vec: VEPI32): int32 {.inline.} = mm512_reduce_add_epi32(vec)

elif defined(avx2):
    {.passC: "-mavx2".}
    when defined(avxvnni):
        {.passC: "-mavxvnni".}


    type
        VEPI16* = M256i
        VEPI32* = M256i

    const CHUNK_SIZE* = 16

    func vecZero16*(): VEPI16 {.inline.} = mm256_setzero_si256()
    func vecZero32*(): VEPI32 {.inline.} = mm256_setzero_si256()
    func vecSetOne16*(n: int16): VEPI16 {.inline.} = mm256_set1_epi16(n)
    func vecStore*(dst: pointer, vec: VEPI16) {.inline.} = mm256_store_si256(
            dst, vec)
    func vecLoad*(src: pointer): VEPI16 {.inline.} = mm256_load_si256(src)
    func vecMax16*(a, b: VEPI16): VEPI16 {.inline.} = mm256_max_epi16(a, b)
    func vecMin16*(a, b: VEPI16): VEPI16 {.inline.} = mm256_min_epi16(a, b)
    func vecMullo16*(a, b: VEPI16): VEPI16 {.inline.} = mm256_mullo_epi16(a, b)
    func vecMadd16*(a, b: VEPI16): VEPI32 {.inline.} = mm256_madd_epi16(a, b)
    func vecAdd32*(a, b: VEPI32): VEPI32 {.inline.} = mm256_add_epi32(a, b)
    func vecAdd16*(a, b: VEPI16): VEPI16 {.inline.} = mm256_add_epi16(a, b)
    func vecSub16*(a, b: VEPI16): VEPI16 {.inline.} = mm256_sub_epi16(a, b)

    func vecReduceAdd32*(vec: VEPI32): int32 {.inline.} =
        var
            lo128 = mm256_castsi256_si128(vec)
            hi128 = mm256_extracti128_si256(vec, 1)
            sum128 = mm_add_epi32(lo128, hi128)
            hi64 = mm_unpackhi_epi64(sum128, sum128)
            sum64 = mm_add_epi32(hi64, sum128)
            hi32 = mm_shuffle_epi32(sum64, 1)
            sum32 = mm_add_epi32(hi32, sum64)
        mm_cvtsi128_si32(sum32)

elif defined(neon) or defined(arm64) or defined(aarch64):

    type
        int16x8 {.importc: "int16x8_t", header: "arm_neon.h", bycopy.} = object
        int16x4 {.importc: "int16x4_t", header: "arm_neon.h", bycopy.} = object
        int32x4 {.importc: "int32x4_t", header: "arm_neon.h", bycopy.} = object
        int32x2 {.importc: "int32x2_t", header: "arm_neon.h", bycopy.} = object

    {.push header: "arm_neon.h".}
    func vld1q_s16(p: ptr int16): int16x8 {.importc: "vld1q_s16".}
    func vst1q_s16(p: ptr int16, v: int16x8) {.importc: "vst1q_s16".}
    func vaddq_s16(a, b: int16x8): int16x8 {.importc: "vaddq_s16".}
    func vsubq_s16(a, b: int16x8): int16x8 {.importc: "vsubq_s16".}
    func vmaxq_s16(a, b: int16x8): int16x8 {.importc: "vmaxq_s16".}
    func vminq_s16(a, b: int16x8): int16x8 {.importc: "vminq_s16".}
    func vmulq_s16(a, b: int16x8): int16x8 {.importc: "vmulq_s16".}
    func vdupq_n_s16(v: int16): int16x8 {.importc: "vdupq_n_s16".}
    func vdupq_n_s32(v: int32): int32x4 {.importc: "vdupq_n_s32".}
    func vaddq_s32(a, b: int32x4): int32x4 {.importc: "vaddq_s32".}
    func vmull_s16(a, b: int16x4): int32x4 {.importc: "vmull_s16".}
    func vget_low_s16(v: int16x8): int16x4 {.importc: "vget_low_s16".}
    func vget_high_s16(v: int16x8): int16x4 {.importc: "vget_high_s16".}
    func vget_low_s32(v: int32x4): int32x2 {.importc: "vget_low_s32".}
    func vget_high_s32(v: int32x4): int32x2 {.importc: "vget_high_s32".}
    when defined(arm64) or defined(aarch64):
        func vpaddq_s32(a, b: int32x4): int32x4 {.importc: "vpaddq_s32".}
        func vgetq_lane_s32(v: int32x4, lane: static[int]): int32 {.importc: "vgetq_lane_s32".}
    else:
        func vpadd_s32(a, b: int32x2): int32x2 {.importc: "vpadd_s32".}
        func vcombine_s32(a, b: int32x2): int32x4 {.importc: "vcombine_s32".}
        func vget_lane_s32(v: int32x2, lane: static[int]): int32 {.importc: "vget_lane_s32".}
    {.pop.}

    type
        VEPI16* = int16x8
        VEPI32* = int32x4

    const CHUNK_SIZE* = 8 # 128-bit / 16-bit = 8 lanes

    func vecZero16*(): VEPI16 {.inline.} = vdupq_n_s16(0)
    func vecZero32*(): VEPI32 {.inline.} = vdupq_n_s32(0)
    func vecSetOne16*(n: int16): VEPI16 {.inline.} = vdupq_n_s16(n)

    func vecLoad*(src: pointer): VEPI16 {.inline.} =
        vld1q_s16(cast[ptr int16](src))

    func vecStore*(dst: pointer, vec: VEPI16) {.inline.} =
        vst1q_s16(cast[ptr int16](dst), vec)

    func vecAdd16*(a, b: VEPI16): VEPI16 {.inline.} = vaddq_s16(a, b)
    func vecSub16*(a, b: VEPI16): VEPI16 {.inline.} = vsubq_s16(a, b)
    func vecMax16*(a, b: VEPI16): VEPI16 {.inline.} = vmaxq_s16(a, b)
    func vecMin16*(a, b: VEPI16): VEPI16 {.inline.} = vminq_s16(a, b)
    func vecMullo16*(a, b: VEPI16): VEPI16 {.inline.} = vmulq_s16(a, b)
    func vecAdd32*(a, b: VEPI32): VEPI32 {.inline.} = vaddq_s32(a, b)

    func vecMadd16*(a, b: VEPI16): VEPI32 {.inline.} =
        ## Equivalent to _mm256_madd_epi16:
        ## result[j] = a[2j]*b[2j] + a[2j+1]*b[2j+1]  (4 int32 outputs from 8 int16 inputs)
        let lo = vmull_s16(vget_low_s16(a), vget_low_s16(b))
        let hi = vmull_s16(vget_high_s16(a), vget_high_s16(b))
        when defined(arm64) or defined(aarch64):
            vpaddq_s32(lo, hi)
        else:
            let loPairs = vpadd_s32(vget_low_s32(lo), vget_high_s32(lo))
            let hiPairs = vpadd_s32(vget_low_s32(hi), vget_high_s32(hi))
            vcombine_s32(loPairs, hiPairs)

    func vecReduceAdd32*(vec: VEPI32): int32 {.inline.} =
        when defined(arm64) or defined(aarch64):
            let pairSums = vpaddq_s32(vec, vec)
            vgetq_lane_s32(vpaddq_s32(pairSums, pairSums), 0)
        else:
            let pairSums = vpadd_s32(vget_low_s32(vec), vget_high_s32(vec))
            vget_lane_s32(vpadd_s32(pairSums, pairSums), 0)

else:
    # ── Scalar fallback ──────────────────────────────────────────────────────
    # Used when -d:simd is set but no supported SIMD ISA is selected/detected.
    # CHUNK_SIZE=1 means the SIMD loops in nnue.nim iterate one element at a
    # time — correct results, just without vectorisation.
    type
        VEPI16* = int16
        VEPI32* = int32

    const CHUNK_SIZE* = 1

    func vecZero16*(): VEPI16 {.inline.} = 0'i16
    func vecZero32*(): VEPI32 {.inline.} = 0'i32
    func vecSetOne16*(n: int16): VEPI16 {.inline.} = n

    func vecLoad*(src: pointer): VEPI16 {.inline.} =
        cast[ptr int16](src)[]

    func vecStore*(dst: pointer, vec: VEPI16) {.inline.} =
        cast[ptr int16](dst)[] = vec

    func vecAdd16*(a, b: VEPI16): VEPI16 {.inline.} = a + b
    func vecSub16*(a, b: VEPI16): VEPI16 {.inline.} = a - b
    func vecMax16*(a, b: VEPI16): VEPI16 {.inline.} = max(a, b)
    func vecMin16*(a, b: VEPI16): VEPI16 {.inline.} = min(a, b)
    func vecMullo16*(a, b: VEPI16): VEPI16 {.inline.} = a * b

    func vecMadd16*(a, b: VEPI16): VEPI32 {.inline.} =
        ## Scalar: with CHUNK_SIZE=1 there are no adjacent pairs to sum,
        ## so this is simply a widening multiply — equivalent total result.
        int32(a) * int32(b)

    func vecAdd32*(a, b: VEPI32): VEPI32 {.inline.} = a + b

    func vecReduceAdd32*(vec: VEPI32): int32 {.inline.} = vec

when defined(avx512):
  {.push header: "immintrin.h".}
  func mm512AddEpi64(a, b: M512i): M512i {.importc: "_mm512_add_epi64".}
  func mm512LoaduSi512(p: pointer): M512i {.importc: "_mm512_loadu_si512".}
  func mm512StoreuSi512(p: pointer, a: M512i) {.importc: "_mm512_storeu_si512".}
  func mm512Set1Epi32(a: int32): M512i {.importc: "_mm512_set1_epi32".}
  func mm512SlliEpi16(a: M512i, shift: int32): M512i {.importc: "_mm512_slli_epi16".}
  func mm512MulhiEpi16(a, b: M512i): M512i {.importc: "_mm512_mulhi_epi16".}
  func mm512Cvtepi16Epi8(a: M512i): M256i {.importc: "_mm512_cvtepi16_epi8".}
  func mm512MaddubsEpi16(a, b: M512i): M512i {.importc: "_mm512_maddubs_epi16".}
  func mm512DpbusdEpi32(acc, a, b: M512i): M512i {.importc: "_mm512_dpbusd_epi32".}
  func mm512MulEpi32(a, b: M512i): M512i {.importc: "_mm512_mul_epi32".}
  func mm512MulloEpi32(a, b: M512i): M512i {.importc: "_mm512_mullo_epi32".}
  func mm512SrliEpi64(a: M512i, shift: int32): M512i {.importc: "_mm512_srli_epi64".}
  func mm512MaxEpi32(a, b: M512i): M512i {.importc: "_mm512_max_epi32".}
  func mm512MinEpi32(a, b: M512i): M512i {.importc: "_mm512_min_epi32".}
  {.pop.}

when defined(avxvnni):
  {.push header: "immintrin.h".}
  func mm256DpbusdEpi32(acc, a, b: M256i): M256i {.importc: "_mm256_dpbusd_epi32".}
  {.pop.}

when defined(neon) or defined(arm64) or defined(aarch64):
  type
    MLInt16x8 {.importc: "int16x8_t", header: "arm_neon.h", bycopy.} = object
    MLInt8x16 {.importc: "int8x16_t", header: "arm_neon.h", bycopy.} = object
    MLInt32x4 {.importc: "int32x4_t", header: "arm_neon.h", bycopy.} = object
    MLUint32x4 {.importc: "uint32x4_t", header: "arm_neon.h", bycopy.} = object
    MLUint8x8 {.importc: "uint8x8_t", header: "arm_neon.h", bycopy.} = object
  {.push header: "arm_neon.h".}
  func neonLoadS16(p: ptr int16): MLInt16x8 {.importc: "vld1q_s16".}
  func neonStoreU8(p: ptr uint8, v: MLUint8x8) {.importc: "vst1_u8".}
  func neonDupS16(v: int16): MLInt16x8 {.importc: "vdupq_n_s16".}
  func neonDupS32(v: int32): MLInt32x4 {.importc: "vdupq_n_s32".}
  func neonMinS16(a, b: MLInt16x8): MLInt16x8 {.importc: "vminq_s16".}
  func neonMaxS16(a, b: MLInt16x8): MLInt16x8 {.importc: "vmaxq_s16".}
  func neonShiftLeftS16(a: MLInt16x8, shift: int32): MLInt16x8 {.importc: "vshlq_n_s16".}
  func neonDoublingMulHighS16(a, b: MLInt16x8): MLInt16x8 {.importc: "vqdmulhq_s16".}
  func neonNarrowUnsignedS16(a: MLInt16x8): MLUint8x8 {.importc: "vqmovun_s16".}
  when defined(neonDotProd):
    func neonDupU32(v: uint32): MLUint32x4 {.importc: "vdupq_n_u32".}
    func neonReinterpretS8(v: MLUint32x4): MLInt8x16 {.importc: "vreinterpretq_s8_u32".}
    func neonLoadS8(p: ptr int8): MLInt8x16 {.importc: "vld1q_s8".}
    func neonDotS32(acc: MLInt32x4, a, b: MLInt8x16): MLInt32x4 {.importc: "vdotq_s32".}
    func neonStoreS32(p: ptr int32, v: MLInt32x4) {.importc: "vst1q_s32".}
  {.pop.}

type
  U8Array = UncheckedArray[uint8]
  I8Array = UncheckedArray[int8]
  I16Array = UncheckedArray[int16]
  I32Array = UncheckedArray[int32]
  U16Array = UncheckedArray[uint16]

func packFourBytes(inputs: ptr U8Array, offset: int): uint32 {.inline.} =
  copyMem(addr result, addr inputs[offset], sizeof(result))

proc collectNonzeroBlocks(inputs: ptr U8Array, blocks: var array[256, uint16],
                          indexLut: ptr U16Array, countLut: ptr U8Array): int =
  var count = 0
  when defined(avx2) and not defined(avx512):
    let zero = mm256_setzero_si256()
    for base in countup(0, 248, 8):
      let values = mm256_loadu_si256(cast[ptr M256i](addr inputs[base * 4]))
      let equalZero = mm256_cmpeq_epi32(values, zero)
      let mask = (not mm256_movemask_ps(mm256_castsi256_ps(equalZero))) and 0xff
      let lutRow = mask * 8
      let indexes = mm_loadu_si128(cast[ptr M128i](addr indexLut[lutRow]))
      let baseVector = mm_set1_epi16(int16(base))
      mm_storeu_si128(cast[ptr M128i](addr blocks[count]),
        mm_add_epi16(indexes, baseVector))
      count += int(countLut[mask])
  else:
    for group in 0..<256:
      let offset = group * 4
      if inputs[offset] != 0 or inputs[offset + 1] != 0 or
         inputs[offset + 2] != 0 or inputs[offset + 3] != 0:
        blocks[count] = uint16(group)
        inc count
  count

proc gyatsoMultilayerL1*(rawInputs: ptr uint8, rawWeights: ptr int8,
                         rawSums: ptr int32, rawIndexLut: ptr uint16,
                         rawCountLut: ptr uint8) =
  let inputs = cast[ptr U8Array](rawInputs)
  let weights = cast[ptr I8Array](rawWeights)
  let sums = cast[ptr I32Array](rawSums)
  let indexLut = cast[ptr U16Array](rawIndexLut)
  let countLut = cast[ptr U8Array](rawCountLut)
  var nonzeroBlocks {.noinit.}: array[256, uint16]
  let nonzeroCount = collectNonzeroBlocks(inputs, nonzeroBlocks, indexLut, countLut)

  when defined(avx512) and defined(avx512vnni):
    var acc0 {.noinit.} = mm512SetzeroSi512()
    var acc1 {.noinit.} = mm512SetzeroSi512()
    var acc2 {.noinit.} = mm512SetzeroSi512()
    var acc3 {.noinit.} = mm512SetzeroSi512()
    var i = 0
    while i + 4 <= nonzeroCount:
      for j in 0..<4:
        let group = int(nonzeroBlocks[i + j])
        let x = mm512Set1Epi32(cast[int32](packFourBytes(inputs, group * 4)))
        let w = mm512LoaduSi512(addr weights[group * 64])
        case j
        of 0: acc0 = mm512DpbusdEpi32(acc0, x, w)
        of 1: acc1 = mm512DpbusdEpi32(acc1, x, w)
        of 2: acc2 = mm512DpbusdEpi32(acc2, x, w)
        else: acc3 = mm512DpbusdEpi32(acc3, x, w)
      inc i, 4
    while i < nonzeroCount:
      let group = int(nonzeroBlocks[i])
      let x = mm512Set1Epi32(cast[int32](packFourBytes(inputs, group * 4)))
      let w = mm512LoaduSi512(addr weights[group * 64])
      acc0 = mm512DpbusdEpi32(acc0, x, w)
      inc i
    let acc = mm512AddEpi32(mm512AddEpi32(acc0, acc1), mm512AddEpi32(acc2, acc3))
    mm512StoreuSi512(addr sums[0], acc)
  elif defined(avx2) and defined(avxvnni):
    var acc00 {.noinit.} = mm256_setzero_si256()
    var acc01 {.noinit.} = mm256_setzero_si256()
    var acc02 {.noinit.} = mm256_setzero_si256()
    var acc03 {.noinit.} = mm256_setzero_si256()
    var acc10 {.noinit.} = mm256_setzero_si256()
    var acc11 {.noinit.} = mm256_setzero_si256()
    var acc12 {.noinit.} = mm256_setzero_si256()
    var acc13 {.noinit.} = mm256_setzero_si256()
    var i = 0
    while i + 4 <= nonzeroCount:
      let group0 = int(nonzeroBlocks[i])
      let group1 = int(nonzeroBlocks[i + 1])
      let group2 = int(nonzeroBlocks[i + 2])
      let group3 = int(nonzeroBlocks[i + 3])
      let x0 = mm256_set1_epi32(cast[int32](packFourBytes(inputs, group0 * 4)))
      let x1 = mm256_set1_epi32(cast[int32](packFourBytes(inputs, group1 * 4)))
      let x2 = mm256_set1_epi32(cast[int32](packFourBytes(inputs, group2 * 4)))
      let x3 = mm256_set1_epi32(cast[int32](packFourBytes(inputs, group3 * 4)))
      let w00 = mm256_loadu_si256(cast[ptr M256i](addr weights[group0 * 64]))
      let w01 = mm256_loadu_si256(cast[ptr M256i](addr weights[group1 * 64]))
      let w02 = mm256_loadu_si256(cast[ptr M256i](addr weights[group2 * 64]))
      let w03 = mm256_loadu_si256(cast[ptr M256i](addr weights[group3 * 64]))
      let w10 = mm256_loadu_si256(cast[ptr M256i](addr weights[group0 * 64 + 32]))
      let w11 = mm256_loadu_si256(cast[ptr M256i](addr weights[group1 * 64 + 32]))
      let w12 = mm256_loadu_si256(cast[ptr M256i](addr weights[group2 * 64 + 32]))
      let w13 = mm256_loadu_si256(cast[ptr M256i](addr weights[group3 * 64 + 32]))
      acc00 = mm256DpbusdEpi32(acc00, x0, w00)
      acc01 = mm256DpbusdEpi32(acc01, x1, w01)
      acc02 = mm256DpbusdEpi32(acc02, x2, w02)
      acc03 = mm256DpbusdEpi32(acc03, x3, w03)
      acc10 = mm256DpbusdEpi32(acc10, x0, w10)
      acc11 = mm256DpbusdEpi32(acc11, x1, w11)
      acc12 = mm256DpbusdEpi32(acc12, x2, w12)
      acc13 = mm256DpbusdEpi32(acc13, x3, w13)
      inc i, 4
    while i < nonzeroCount:
      let group = int(nonzeroBlocks[i])
      let x = mm256_set1_epi32(cast[int32](packFourBytes(inputs, group * 4)))
      let w = addr weights[group * 64]
      acc00 = mm256DpbusdEpi32(acc00, x, mm256_loadu_si256(cast[ptr M256i](w)))
      acc10 = mm256DpbusdEpi32(acc10, x, mm256_loadu_si256(cast[ptr M256i](addr weights[group * 64 + 32])))
      inc i
    let acc0 = mm256_add_epi32(mm256_add_epi32(acc00, acc01), mm256_add_epi32(acc02, acc03))
    let acc1 = mm256_add_epi32(mm256_add_epi32(acc10, acc11), mm256_add_epi32(acc12, acc13))
    mm256_storeu_si256(cast[ptr M256i](addr sums[0]), acc0)
    mm256_storeu_si256(cast[ptr M256i](addr sums[8]), acc1)
  elif defined(avx512) or defined(avx2):
    let ones = when defined(avx512): mm512Set1Epi16(1) else: mm256_set1_epi16(1)
    when defined(avx512):
      var acc = mm512SetzeroSi512()
      for i in 0..<nonzeroCount:
        let group = int(nonzeroBlocks[i])
        let x = mm512Set1Epi32(cast[int32](packFourBytes(inputs, group * 4)))
        let w = mm512LoaduSi512(addr weights[group * 64])
        let pairs = mm512MaddubsEpi16(x, w)
        acc = mm512AddEpi32(acc, mm512MaddEpi16(pairs, ones))
      mm512StoreuSi512(addr sums[0], acc)
    else:
      var acc0 = mm256_setzero_si256()
      var acc1 = mm256_setzero_si256()
      for i in 0..<nonzeroCount:
        let group = int(nonzeroBlocks[i])
        let x = mm256_set1_epi32(cast[int32](packFourBytes(inputs, group * 4)))
        let w = addr weights[group * 64]
        let p0 = mm256_maddubs_epi16(x, mm256_loadu_si256(cast[ptr M256i](w)))
        let p1 = mm256_maddubs_epi16(x, mm256_loadu_si256(cast[ptr M256i](addr weights[group * 64 + 32])))
        acc0 = mm256_add_epi32(acc0, mm256_madd_epi16(p0, ones))
        acc1 = mm256_add_epi32(acc1, mm256_madd_epi16(p1, ones))
      mm256_storeu_si256(cast[ptr M256i](addr sums[0]), acc0)
      mm256_storeu_si256(cast[ptr M256i](addr sums[8]), acc1)
  elif defined(neonDotProd):
    var acc0 {.noinit.} = neonDupS32(0)
    var acc1 {.noinit.} = neonDupS32(0)
    var acc2 {.noinit.} = neonDupS32(0)
    var acc3 {.noinit.} = neonDupS32(0)
    for i in 0..<nonzeroCount:
      let group = int(nonzeroBlocks[i])
      let x = neonReinterpretS8(neonDupU32(packFourBytes(inputs, group * 4)))
      let w = addr weights[group * 64]
      acc0 = neonDotS32(acc0, x, neonLoadS8(w))
      acc1 = neonDotS32(acc1, x, neonLoadS8(addr weights[group * 64 + 16]))
      acc2 = neonDotS32(acc2, x, neonLoadS8(addr weights[group * 64 + 32]))
      acc3 = neonDotS32(acc3, x, neonLoadS8(addr weights[group * 64 + 48]))
    neonStoreS32(addr sums[0], acc0)
    neonStoreS32(addr sums[4], acc1)
    neonStoreS32(addr sums[8], acc2)
    neonStoreS32(addr sums[12], acc3)
  else:
    for output in 0..<16: sums[output] = 0
    for i in 0..<nonzeroCount:
      let group = int(nonzeroBlocks[i])
      let x = group * 4
      let w = group * 64
      for output in 0..<16:
        let wo = w + output * 4
        sums[output] += int32(inputs[x]) * int32(weights[wo]) +
          int32(inputs[x + 1]) * int32(weights[wo + 1]) +
          int32(inputs[x + 2]) * int32(weights[wo + 2]) +
          int32(inputs[x + 3]) * int32(weights[wo + 3])

func clampI64(value: int64, maximum: int32): int32 {.inline.} =
  if value < 0: 0
  elif value > int64(maximum): maximum
  else: int32(value)

proc gyatsoMultilayerL2*(rawInputs, rawWeights, rawBias, rawOutputs: ptr int32,
                         maxValue, useFastI32: int32) =
  let inputs = cast[ptr I32Array](rawInputs)
  let weights = cast[ptr I32Array](rawWeights)
  let bias = cast[ptr I32Array](rawBias)
  let outputs = cast[ptr I32Array](rawOutputs)
  when defined(avx512):
    if useFastI32 != 0:
      let zero = mm512SetzeroSi512()
      let maxVec = mm512Set1Epi32(maxValue)
      for outputBase in countup(0, 16, 16):
        var sum = zero
        for input in 0..<16:
          let activation = inputs[input]
          if activation != 0:
            let row = input * 32 + outputBase
            let w = mm512LoaduSi512(addr weights[row])
            sum = mm512AddEpi32(sum, mm512MulloEpi32(w, mm512Set1Epi32(activation)))
        sum = mm512AddEpi32(sum, mm512LoaduSi512(addr bias[outputBase]))
        sum = mm512MaxEpi32(mm512MinEpi32(sum, maxVec), zero)
        mm512StoreuSi512(addr outputs[outputBase], sum)
    else:
      for outputBase in countup(0, 16, 16):
        var even = mm512SetzeroSi512()
        var odd = mm512SetzeroSi512()
        for input in 0..<16:
          let row = input * 32 + outputBase
          let w = mm512LoaduSi512(addr weights[row])
          let x = mm512Set1Epi32(inputs[input])
          even = mm512AddEpi64(even, mm512MulEpi32(w, x))
          odd = mm512AddEpi64(odd, mm512MulEpi32(mm512SrliEpi64(w, 32), x))
        var evenLanes: array[8, int64]
        var oddLanes: array[8, int64]
        mm512StoreuSi512(addr evenLanes[0], even)
        mm512StoreuSi512(addr oddLanes[0], odd)
        for lane in 0..<8:
          outputs[outputBase + lane * 2] = clampI64(evenLanes[lane] + int64(bias[outputBase + lane * 2]), maxValue)
          outputs[outputBase + lane * 2 + 1] = clampI64(oddLanes[lane] + int64(bias[outputBase + lane * 2 + 1]), maxValue)
  elif defined(avx2):
    if useFastI32 != 0:
      let zero = mm256_setzero_si256()
      let maxVec = mm256_set1_epi32(maxValue)
      var sum0 {.noinit.} = zero
      var sum1 {.noinit.} = zero
      var sum2 {.noinit.} = zero
      var sum3 {.noinit.} = zero
      for input in 0..<16:
        let activation = inputs[input]
        if activation != 0:
          let x = mm256_set1_epi32(activation)
          let row = input * 32
          sum0 = mm256_add_epi32(sum0, mm256_mullo_epi32(mm256_loadu_si256(cast[ptr M256i](addr weights[row])), x))
          sum1 = mm256_add_epi32(sum1, mm256_mullo_epi32(mm256_loadu_si256(cast[ptr M256i](addr weights[row + 8])), x))
          sum2 = mm256_add_epi32(sum2, mm256_mullo_epi32(mm256_loadu_si256(cast[ptr M256i](addr weights[row + 16])), x))
          sum3 = mm256_add_epi32(sum3, mm256_mullo_epi32(mm256_loadu_si256(cast[ptr M256i](addr weights[row + 24])), x))
      sum0 = mm256_max_epi32(mm256_min_epi32(mm256_add_epi32(sum0, mm256_loadu_si256(cast[ptr M256i](addr bias[0]))), maxVec), zero)
      sum1 = mm256_max_epi32(mm256_min_epi32(mm256_add_epi32(sum1, mm256_loadu_si256(cast[ptr M256i](addr bias[8]))), maxVec), zero)
      sum2 = mm256_max_epi32(mm256_min_epi32(mm256_add_epi32(sum2, mm256_loadu_si256(cast[ptr M256i](addr bias[16]))), maxVec), zero)
      sum3 = mm256_max_epi32(mm256_min_epi32(mm256_add_epi32(sum3, mm256_loadu_si256(cast[ptr M256i](addr bias[24]))), maxVec), zero)
      mm256_storeu_si256(cast[ptr M256i](addr outputs[0]), sum0)
      mm256_storeu_si256(cast[ptr M256i](addr outputs[8]), sum1)
      mm256_storeu_si256(cast[ptr M256i](addr outputs[16]), sum2)
      mm256_storeu_si256(cast[ptr M256i](addr outputs[24]), sum3)
    else:
      for outputBase in countup(0, 24, 8):
        var even = mm256_setzero_si256()
        var odd = mm256_setzero_si256()
        for input in 0..<16:
          let row = input * 32 + outputBase
          let w = mm256_loadu_si256(cast[ptr M256i](addr weights[row]))
          let x = mm256_set1_epi32(inputs[input])
          even = mm256_add_epi64(even, mm256_mul_epi32(w, x))
          odd = mm256_add_epi64(odd, mm256_mul_epi32(mm256_srli_epi64(w, 32), x))
        var evenLanes: array[4, int64]
        var oddLanes: array[4, int64]
        mm256_storeu_si256(cast[ptr M256i](addr evenLanes[0]), even)
        mm256_storeu_si256(cast[ptr M256i](addr oddLanes[0]), odd)
        for lane in 0..<4:
          outputs[outputBase + lane * 2] = clampI64(evenLanes[lane] + int64(bias[outputBase + lane * 2]), maxValue)
          outputs[outputBase + lane * 2 + 1] = clampI64(oddLanes[lane] + int64(bias[outputBase + lane * 2 + 1]), maxValue)
  else:
    for output in 0..<32:
      var sum = int64(bias[output])
      for input in 0..<16:
        sum += int64(inputs[input]) * int64(weights[input * 32 + output])
      outputs[output] = clampI64(sum, maxValue)

proc gyatsoMultilayerOutput*(rawInputs, rawWeights: ptr int32,
                             bias: int32): int64 =
  let inputs = cast[ptr I32Array](rawInputs)
  let weights = cast[ptr I32Array](rawWeights)
  when defined(avx512):
    var even {.noinit.} = mm512SetzeroSi512()
    var odd {.noinit.} = mm512SetzeroSi512()
    for base in countup(0, 16, 16):
      let x = mm512LoaduSi512(addr inputs[base])
      let w = mm512LoaduSi512(addr weights[base])
      even = mm512AddEpi64(even, mm512MulEpi32(x, w))
      odd = mm512AddEpi64(odd,
        mm512MulEpi32(mm512SrliEpi64(x, 32), mm512SrliEpi64(w, 32)))
    var evenLanes {.noinit.}: array[8, int64]
    var oddLanes {.noinit.}: array[8, int64]
    mm512StoreuSi512(addr evenLanes[0], even)
    mm512StoreuSi512(addr oddLanes[0], odd)
    result = int64(bias)
    for lane in 0..<8:
      result += evenLanes[lane] + oddLanes[lane]
  elif defined(avx2):
    var even {.noinit.} = mm256_setzero_si256()
    var odd {.noinit.} = mm256_setzero_si256()
    for base in countup(0, 24, 8):
      let x = mm256_loadu_si256(cast[ptr M256i](addr inputs[base]))
      let w = mm256_loadu_si256(cast[ptr M256i](addr weights[base]))
      even = mm256_add_epi64(even, mm256_mul_epi32(x, w))
      odd = mm256_add_epi64(odd,
        mm256_mul_epi32(mm256_srli_epi64(x, 32), mm256_srli_epi64(w, 32)))
    var evenLanes {.noinit.}: array[4, int64]
    var oddLanes {.noinit.}: array[4, int64]
    mm256_storeu_si256(cast[ptr M256i](addr evenLanes[0]), even)
    mm256_storeu_si256(cast[ptr M256i](addr oddLanes[0]), odd)
    result = int64(bias)
    for lane in 0..<4:
      result += evenLanes[lane] + oddLanes[lane]
  else:
    result = int64(bias)
    for i in 0..<32:
      result += int64(inputs[i]) * int64(weights[i])

proc gyatsoPairwise*(rawStm, rawNstm: ptr int16, rawOutputs: ptr uint8) =
  let stm = cast[ptr I16Array](rawStm)
  let nstm = cast[ptr I16Array](rawNstm)
  let outputs = cast[ptr U8Array](rawOutputs)
  when defined(avx512):
    let zero = mm512SetzeroSi512()
    let maxVec = mm512Set1Epi16(255)
    for perspective in 0..<2:
      let acc = if perspective == 0: stm else: nstm
      let outBase = perspective * 512
      for i in countup(0, 480, 32):
        var a = mm512LoaduSi512(addr acc[i])
        var b = mm512LoaduSi512(addr acc[512 + i])
        a = mm512MaxEpi16(zero, mm512MinEpi16(maxVec, a))
        b = mm512MaxEpi16(zero, mm512MinEpi16(maxVec, b))
        let p = mm512MulhiEpi16(mm512SlliEpi16(a, 7), b)
        let bytes = mm512Cvtepi16Epi8(p)
        mm256_storeu_si256(cast[ptr M256i](addr outputs[outBase + i]), bytes)
  elif defined(avx2):
    let zero = mm256_setzero_si256()
    let maxVec = mm256_set1_epi16(255)
    for perspective in 0..<2:
      let acc = if perspective == 0: stm else: nstm
      let outBase = perspective * 512
      for i in countup(0, 480, 32):
        var a0 = mm256_loadu_si256(cast[ptr M256i](addr acc[i]))
        var b0 = mm256_loadu_si256(cast[ptr M256i](addr acc[512 + i]))
        var a1 = mm256_loadu_si256(cast[ptr M256i](addr acc[i + 16]))
        var b1 = mm256_loadu_si256(cast[ptr M256i](addr acc[512 + i + 16]))
        a0 = mm256_max_epi16(zero, mm256_min_epi16(maxVec, a0))
        b0 = mm256_max_epi16(zero, mm256_min_epi16(maxVec, b0))
        a1 = mm256_max_epi16(zero, mm256_min_epi16(maxVec, a1))
        b1 = mm256_max_epi16(zero, mm256_min_epi16(maxVec, b1))
        let p0 = mm256_mulhi_epi16(mm256_slli_epi16(a0, 7), b0)
        let p1 = mm256_mulhi_epi16(mm256_slli_epi16(a1, 7), b1)
        var bytes = mm256_packus_epi16(p0, p1)
        bytes = mm256_permute4x64_epi64(bytes, MM_SHUFFLE(3, 1, 2, 0))
        mm256_storeu_si256(cast[ptr M256i](addr outputs[outBase + i]), bytes)
  elif defined(neon) or defined(arm64) or defined(aarch64):
    let zero = neonDupS16(0)
    let maxVec = neonDupS16(255)
    for perspective in 0..<2:
      let acc = if perspective == 0: stm else: nstm
      let outBase = perspective * 512
      for i in countup(0, 504, 8):
        var a = neonLoadS16(addr acc[i])
        var b = neonLoadS16(addr acc[512 + i])
        a = neonMaxS16(zero, neonMinS16(maxVec, a))
        b = neonMaxS16(zero, neonMinS16(maxVec, b))
        let p = neonDoublingMulHighS16(neonShiftLeftS16(a, 6), b)
        neonStoreU8(addr outputs[outBase + i], neonNarrowUnsignedS16(p))
  else:
    for perspective in 0..<2:
      let acc = if perspective == 0: stm else: nstm
      let outBase = perspective * 512
      for i in 0..<512:
        let a = clamp(int(acc[i]), 0, 255)
        let b = clamp(int(acc[512 + i]), 0, 255)
        outputs[outBase + i] = uint8((a * b) shr 9)
