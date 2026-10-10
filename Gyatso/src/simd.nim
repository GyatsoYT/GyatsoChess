import nnuetypes

when defined(avx512):
    {.passc: "-mavx512f -mavx512bw".}
    when defined(avx512vnni):
        {.passc: "-mavx512vnni".}

    type
        M512i* {.importc: "__m512i", header: "immintrin.h", bycopy.} = object
        M256i {.importc: "__m256i", header: "immintrin.h", bycopy.} = object

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
    func mm512_loadu_si512_impl(p: ptr M512i): M512i {.importc: "_mm512_loadu_si512".}
    func mm512_storeu_si512*(p: pointer, a: M512i) {.importc: "_mm512_storeu_si512".}
    func mm512_set1_epi32*(a: int32): M512i {.importc: "_mm512_set1_epi32".}
    func mm512_maddubs_epi16*(a, b: M512i): M512i {.importc: "_mm512_maddubs_epi16".}
    func mm512_srli_epi16*(a: M512i, n: int32): M512i {.importc: "_mm512_srli_epi16".}
    func mm512_cvtusepi16_epi8_impl(a: M512i): M256i {.importc: "_mm512_cvtusepi16_epi8".}
    func mm256_storeu_si256*(p: ptr M256i, a: M256i) {.importc: "_mm256_storeu_si256".}
    func mm512_dpbusd_epi32*(acc, a, b: M512i): M512i {.importc: "_mm512_dpbusd_epi32".}
    {.pop.}

    template mm512_load_si512*(p: pointer): M512i =
        mm512_load_si512_impl(cast[ptr M512i](p))

    template mm512_loadu_si512*(p: pointer): M512i =
        mm512_loadu_si512_impl(cast[ptr M512i](p))

    type
        VEPI16* = M512i
        VEPI32* = M512i

    const CHUNK_SIZE* = 32
    const PAIRWISE_LANES* = 32

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

    func vecPairwisePack*(dst: ptr uint8, a, b: ptr int16) {.inline.} =
        let zero = mm512_setzero_si512()
        let qa = mm512_set1_epi16(QA.int16)
        let va = mm512_load_si512(a)
        let vb = mm512_load_si512(b)
        let ca = mm512_max_epi16(mm512_min_epi16(va, qa), zero)
        let cb = mm512_max_epi16(mm512_min_epi16(vb, qa), zero)
        let product = mm512_srli_epi16(mm512_mullo_epi16(ca, cb), 8)
        mm256_storeu_si256(cast[ptr M256i](dst), mm512_cvtusepi16_epi8_impl(product))

    func vecDotTile*(acc: VEPI32, packed: uint32, weights: pointer): VEPI32 {.inline.} =
        let inputs = mm512_set1_epi32(cast[int32](packed))
        let w = mm512_loadu_si512(weights)
        when defined(avx512vnni):
            mm512_dpbusd_epi32(acc, inputs, w)
        else:
            let pairs = mm512_maddubs_epi16(inputs, w)
            mm512_add_epi32(acc, mm512_madd_epi16(pairs, mm512_set1_epi16(1)))

    func vecLoadI32*(src: pointer): VEPI32 {.inline.} = mm512_loadu_si512(src)
    func vecStoreI32*(dst: pointer, vec: VEPI32) {.inline.} = mm512_storeu_si512(dst, vec)
    func vecZeroI32*(): VEPI32 {.inline.} = mm512_setzero_si512()

elif defined(avx2):
    {.passc: "-mavx2".}
    when defined(avxvnni):
        {.passc: "-mavxvnni".}

    import nimsimd/avx2

    func mm256_dpbusd_epi32*(acc, a, b: M256i): M256i
        {.importc: "_mm256_dpbusd_epi32", header: "immintrin.h".}

    type
        VEPI16* = M256i
        VEPI32* = M256i

    const CHUNK_SIZE* = 16
    const PAIRWISE_LANES* = 32

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

    func vecPairwisePack*(dst: ptr uint8, a, b: ptr int16) {.inline.} =
        let zero = mm256_setzero_si256()
        let qa = mm256_set1_epi16(QA.int16)
        let a0 = vecLoad(a)
        let a1 = vecLoad(cast[ptr int16](cast[uint](a) + uint(CHUNK_SIZE * sizeof(int16))))
        let b0 = vecLoad(b)
        let b1 = vecLoad(cast[ptr int16](cast[uint](b) + uint(CHUNK_SIZE * sizeof(int16))))
        let c0 = mm256_max_epi16(mm256_min_epi16(a0, qa), zero)
        let c1 = mm256_max_epi16(mm256_min_epi16(a1, qa), zero)
        let d0 = mm256_max_epi16(mm256_min_epi16(b0, qa), zero)
        let d1 = mm256_max_epi16(mm256_min_epi16(b1, qa), zero)
        let p0 = mm256_srli_epi16(mm256_mullo_epi16(c0, d0), 8)
        let p1 = mm256_srli_epi16(mm256_mullo_epi16(c1, d1), 8)
        let packed = mm256_packus_epi16(p0, p1)
        mm256_storeu_si256(cast[ptr M256i](dst), mm256_permute4x64_epi64(packed, 0xd8))

    func vecDotTile*(acc: VEPI32, packed: uint32, weights: pointer): VEPI32 {.inline.} =
        let inputs = mm256_set1_epi32(cast[int32](packed))
        let w = mm256_loadu_si256(cast[ptr M256i](weights))
        when defined(avxvnni):
            mm256_dpbusd_epi32(acc, inputs, w)
        else:
            let pairs = mm256_maddubs_epi16(inputs, w)
            mm256_add_epi32(acc, mm256_madd_epi16(pairs, mm256_set1_epi16(1)))

    func vecDotTilePair*(acc0, acc1: VEPI32, packed: uint32,
                         weights0, weights1: pointer): tuple[a, b: VEPI32] {.inline.} =
        let inputs = mm256_set1_epi32(cast[int32](packed))
        when defined(avxvnni):
            result.a = mm256_dpbusd_epi32(acc0, inputs, mm256_loadu_si256(cast[ptr M256i](weights0)))
            result.b = mm256_dpbusd_epi32(acc1, inputs, mm256_loadu_si256(cast[ptr M256i](weights1)))
        else:
            let pair0 = mm256_maddubs_epi16(inputs, mm256_loadu_si256(cast[ptr M256i](weights0)))
            let pair1 = mm256_maddubs_epi16(inputs, mm256_loadu_si256(cast[ptr M256i](weights1)))
            let ones = mm256_set1_epi16(1)
            result.a = mm256_add_epi32(acc0, mm256_madd_epi16(pair0, ones))
            result.b = mm256_add_epi32(acc1, mm256_madd_epi16(pair1, ones))

    func vecLoadI32*(src: pointer): VEPI32 {.inline.} = mm256_loadu_si256(cast[ptr M256i](src))
    func vecStoreI32*(dst: pointer, vec: VEPI32) {.inline.} = mm256_storeu_si256(cast[ptr M256i](dst), vec)
    func vecZeroI32*(): VEPI32 {.inline.} = mm256_setzero_si256()

elif defined(neon) or defined(arm64) or defined(aarch64):
    # ARM NEON — Apple Silicon (M1/M2/M3/M4) and other AArch64 targets
    # vaddvq_s32 / vpaddq_s32 / vget_low|high_s16 are all AArch64-only, which
    # is fine because arm64 / aarch64 implies a 64-bit ARM core.
    when defined(neonDotprod):
        {.passC: "-march=armv8.2-a+dotprod".}
    else:
        {.passC: "-march=armv8-a+simd".}

    type
        int16x8 {.importc: "int16x8_t", header: "arm_neon.h", bycopy.} = object
        int16x4 {.importc: "int16x4_t", header: "arm_neon.h", bycopy.} = object
        int32x4 {.importc: "int32x4_t", header: "arm_neon.h", bycopy.} = object
        int32x2 {.importc: "int32x2_t", header: "arm_neon.h", bycopy.} = object
        int8x16 {.importc: "int8x16_t", header: "arm_neon.h", bycopy.} = object
        int8x8 {.importc: "int8x8_t", header: "arm_neon.h", bycopy.} = object
        uint8x16 {.importc: "uint8x16_t", header: "arm_neon.h", bycopy.} = object
        uint8x8 {.importc: "uint8x8_t", header: "arm_neon.h", bycopy.} = object
        uint16x8 {.importc: "uint16x8_t", header: "arm_neon.h", bycopy.} = object
        uint32x4 {.importc: "uint32x4_t", header: "arm_neon.h", bycopy.} = object

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
    func vld1q_s8(p: ptr int8): int8x16 {.importc: "vld1q_s8".}
    func vld1q_s32(p: ptr int32): int32x4 {.importc: "vld1q_s32".}
    func vdupq_n_u32(v: uint32): uint32x4 {.importc: "vdupq_n_u32".}
    func vreinterpretq_u8_u32(v: uint32x4): uint8x16 {.importc: "vreinterpretq_u8_u32".}
    func vget_low_s8(v: int8x16): int8x8 {.importc: "vget_low_s8".}
    func vget_high_s8(v: int8x16): int8x8 {.importc: "vget_high_s8".}
    func vget_low_u8(v: uint8x16): uint8x8 {.importc: "vget_low_u8".}
    func vget_high_u8(v: uint8x16): uint8x8 {.importc: "vget_high_u8".}
    func vmovl_s8(v: int8x8): int16x8 {.importc: "vmovl_s8".}
    func vmovl_u8(v: uint8x8): uint16x8 {.importc: "vmovl_u8".}
    func vreinterpretq_s16_u16(v: uint16x8): int16x8 {.importc: "vreinterpretq_s16_u16".}
    func vpaddlq_s16(v: int16x8): int32x4 {.importc: "vpaddlq_s16".}
    func vget_low_s32(v: int32x4): int32x2 {.importc: "vget_low_s32".}
    func vget_high_s32(v: int32x4): int32x2 {.importc: "vget_high_s32".}
    func vadd_s32(a, b: int32x2): int32x2 {.importc: "vadd_s32".}
    func vcombine_s32(a, b: int32x2): int32x4 {.importc: "vcombine_s32".}
    func vld1_s16(p: ptr int16): int16x4 {.importc: "vld1_s16".}
    func vshrn_n_s32(a: int32x4, n: int32): int16x4 {.importc: "vshrn_n_s32".}
    func vcombine_s16(a, b: int16x4): int16x8 {.importc: "vcombine_s16".}
    func vqmovun_s16(a: int16x8): uint8x8 {.importc: "vqmovun_s16".}
    func vst1_u8(p: ptr uint8, a: uint8x8) {.importc: "vst1_u8".}
    func vdotq_s32(acc: int32x4, a: uint8x16, b: int8x16): int32x4 {.importc: "vdotq_s32".}
    func vst1q_s32(p: ptr int32, v: int32x4) {.importc: "vst1q_s32".}
    {.pop.}

    type
        VEPI16* = int16x8
        VEPI32* = int32x4

    const CHUNK_SIZE* = 8 # 128-bit / 16-bit = 8 lanes
    const PAIRWISE_LANES* = 8

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

    func vecPairwisePack*(dst: ptr uint8, a, b: ptr int16) {.inline.} =
        let p0 = vshrn_n_s32(vmull_s16(vld1_s16(a), vld1_s16(b)), 8)
        let a1 = cast[ptr int16](cast[uint](a) + uint(4 * sizeof(int16)))
        let b1 = cast[ptr int16](cast[uint](b) + uint(4 * sizeof(int16)))
        let p1 = vshrn_n_s32(vmull_s16(vld1_s16(a1), vld1_s16(b1)), 8)
        vst1_u8(dst, vqmovun_s16(vcombine_s16(p0, p1)))

    func vecDotTile*(acc: VEPI32, packed: uint32, weights: pointer): VEPI32 {.inline.} =
        let inputs = vreinterpretq_u8_u32(vdupq_n_u32(packed))
        let w = vld1q_s8(cast[ptr int8](weights))
        when defined(neonDotprod):
            vdotq_s32(acc, inputs, w)
        else:
            let alo = vreinterpretq_s16_u16(vmovl_u8(vget_low_u8(inputs)))
            let ahi = vreinterpretq_s16_u16(vmovl_u8(vget_high_u8(inputs)))
            let wlo = vmovl_s8(vget_low_s8(w))
            let whi = vmovl_s8(vget_high_s8(w))
            let plo = vmulq_s16(alo, wlo)
            let phi = vmulq_s16(ahi, whi)
            let loPairs = vpaddlq_s16(plo)
            let hiPairs = vpaddlq_s16(phi)
            let out01 = vadd_s32(vget_low_s32(loPairs), vget_high_s32(loPairs))
            let out23 = vadd_s32(vget_low_s32(hiPairs), vget_high_s32(hiPairs))
            vaddq_s32(acc, vcombine_s32(out01, out23))

    func vecLoadI32*(src: pointer): VEPI32 {.inline.} = vld1q_s32(cast[ptr int32](src))
    func vecStoreI32*(dst: pointer, vec: VEPI32) {.inline.} = vst1q_s32(cast[ptr int32](dst), vec)
    func vecZeroI32*(): VEPI32 {.inline.} = vdupq_n_s32(0)

else:
    # ── Scalar fallback ──────────────────────────────────────────────────────
    # Used when -d:simd is set but no supported SIMD ISA is selected/detected.
    # CHUNK_SIZE=1 means the SIMD loops in nnue.nim iterate one element at a
    # time — correct results, just without vectorisation.
    type
        VEPI16* = int16
        VEPI32* = int32

    const CHUNK_SIZE* = 1
    const PAIRWISE_LANES* = 1

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

    func vecPairwisePack*(dst: ptr uint8, a, b: ptr int16) {.inline.} =
        let x = max(0'i32, min(QA.int32, a[].int32))
        let y = max(0'i32, min(QA.int32, b[].int32))
        dst[] = uint8((x * y) shr 8)
