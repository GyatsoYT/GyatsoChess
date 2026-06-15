# simd.nim — SIMD abstraction layer for NNUE inference
#
# Priority order (highest to lowest):
#   AVX512  (-d:avx512 -d:avx2)   — 32 × int16 per register
#   AVX2    (-d:avx2)              — 16 × int16 per register
#   NEON    (-d:neon  OR  aarch64) — 8  × int16 per register  (Apple Silicon / ARM64)
#   Scalar  (fallback)             — 1  element at a time

when defined(avx512):
    {.passC: "-mavx512f -mavx512bw".}

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

    import nimsimd/avx2

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
    # ARM NEON — Apple Silicon (M1/M2/M3/M4) and other AArch64 targets
    # vaddvq_s32 / vpaddq_s32 / vget_low|high_s16 are all AArch64-only, which
    # is fine because arm64 / aarch64 implies a 64-bit ARM core.
    {.passC: "-march=armv8-a+simd".}

    type
        int16x8 {.importc: "int16x8_t", header: "arm_neon.h", bycopy.} = object
        int16x4 {.importc: "int16x4_t", header: "arm_neon.h", bycopy.} = object
        int32x4 {.importc: "int32x4_t", header: "arm_neon.h", bycopy.} = object

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
    func vaddvq_s32(a: int32x4): int32 {.importc: "vaddvq_s32".}
    func vmull_s16(a, b: int16x4): int32x4 {.importc: "vmull_s16".}
    func vget_low_s16(v: int16x8): int16x4 {.importc: "vget_low_s16".}
    func vget_high_s16(v: int16x8): int16x4 {.importc: "vget_high_s16".}
    func vpaddq_s32(a, b: int32x4): int32x4 {.importc: "vpaddq_s32".}
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
        vpaddq_s32(lo, hi) # pairwise add within each half, then interleave

    func vecReduceAdd32*(vec: VEPI32): int32 {.inline.} =
        ## Horizontal sum of all four int32 lanes.
        vaddvq_s32(vec)

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
