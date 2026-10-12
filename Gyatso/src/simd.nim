# simd.nim — SIMD abstraction layer for NNUE inference
#
# Priority order (highest to lowest):
#   AVX512  (-d:avx512 -d:avx2)   — 32 × int16 per register
#   AVX2    (-d:avx2)              — 16 × int16 per register
#   NEON    (-d:neon  OR  aarch64) — 8  × int16 per register  (Apple Silicon / ARM64)
#   Scalar  (fallback)             — 1  element at a time

{.emit: """
#include <stdint.h>
#include <string.h>

#if defined(__AVX512VNNI__) && defined(__AVX512BW__)
#include <immintrin.h>
void gyatso_multilayer_l1(const uint8_t *inputs, const int8_t *weights, int32_t *sums) {
    __m512i acc = _mm512_setzero_si512();
    for (int group = 0; group < 256; ++group) {
        uint32_t packed;
        memcpy(&packed, inputs + group * 4, sizeof(packed));
        const __m512i x = _mm512_set1_epi32((int) packed);
        const __m512i w = _mm512_loadu_si512((const void *) (weights + group * 64));
        acc = _mm512_dpbusd_epi32(acc, x, w);
    }
    _mm512_storeu_si512((void *) sums, acc);
}
#elif defined(__AVXVNNI__) && defined(__AVX2__)
#include <immintrin.h>
void gyatso_multilayer_l1(const uint8_t *inputs, const int8_t *weights, int32_t *sums) {
    __m256i acc0 = _mm256_setzero_si256();
    __m256i acc1 = _mm256_setzero_si256();
    for (int group = 0; group < 256; ++group) {
        uint32_t packed;
        memcpy(&packed, inputs + group * 4, sizeof(packed));
        const __m256i x = _mm256_set1_epi32((int) packed);
        const int8_t *w = weights + group * 64;
        acc0 = _mm256_dpbusd_epi32(acc0, x, _mm256_loadu_si256((const __m256i *) w));
        acc1 = _mm256_dpbusd_epi32(acc1, x, _mm256_loadu_si256((const __m256i *) (w + 32)));
    }
    _mm256_storeu_si256((__m256i *) sums, acc0);
    _mm256_storeu_si256((__m256i *) (sums + 8), acc1);
}
#elif defined(__AVX512BW__)
#include <immintrin.h>
void gyatso_multilayer_l1(const uint8_t *inputs, const int8_t *weights, int32_t *sums) {
    const __m512i ones = _mm512_set1_epi16(1);
    __m512i acc = _mm512_setzero_si512();
    for (int group = 0; group < 256; ++group) {
        uint32_t packed;
        memcpy(&packed, inputs + group * 4, sizeof(packed));
        const __m512i x = _mm512_set1_epi32((int) packed);
        const __m512i w = _mm512_loadu_si512((const void *) (weights + group * 64));
        const __m512i pairs = _mm512_maddubs_epi16(x, w);
        acc = _mm512_add_epi32(acc, _mm512_madd_epi16(pairs, ones));
    }
    _mm512_storeu_si512((void *) sums, acc);
}
#elif defined(__AVX2__)
#include <immintrin.h>
void gyatso_multilayer_l1(const uint8_t *inputs, const int8_t *weights, int32_t *sums) {
    const __m256i ones = _mm256_set1_epi16(1);
    __m256i acc0 = _mm256_setzero_si256();
    __m256i acc1 = _mm256_setzero_si256();
    for (int group = 0; group < 256; ++group) {
        uint32_t packed;
        memcpy(&packed, inputs + group * 4, sizeof(packed));
        const __m256i x = _mm256_set1_epi32((int) packed);
        const int8_t *w = weights + group * 64;
        const __m256i p0 = _mm256_maddubs_epi16(x, _mm256_loadu_si256((const __m256i *) w));
        const __m256i p1 = _mm256_maddubs_epi16(x, _mm256_loadu_si256((const __m256i *) (w + 32)));
        acc0 = _mm256_add_epi32(acc0, _mm256_madd_epi16(p0, ones));
        acc1 = _mm256_add_epi32(acc1, _mm256_madd_epi16(p1, ones));
    }
    _mm256_storeu_si256((__m256i *) sums, acc0);
    _mm256_storeu_si256((__m256i *) (sums + 8), acc1);
}
#elif defined(__ARM_FEATURE_DOTPROD)
#include <arm_neon.h>
void gyatso_multilayer_l1(const uint8_t *inputs, const int8_t *weights, int32_t *sums) {
    int32x4_t acc0 = vdupq_n_s32(0);
    int32x4_t acc1 = vdupq_n_s32(0);
    int32x4_t acc2 = vdupq_n_s32(0);
    int32x4_t acc3 = vdupq_n_s32(0);
    for (int group = 0; group < 256; ++group) {
        uint32_t packed;
        memcpy(&packed, inputs + group * 4, sizeof(packed));
        const int8x16_t x = vreinterpretq_s8_u32(vdupq_n_u32(packed));
        const int8_t *w = weights + group * 64;
        acc0 = vdotq_s32(acc0, x, vld1q_s8(w));
        acc1 = vdotq_s32(acc1, x, vld1q_s8(w + 16));
        acc2 = vdotq_s32(acc2, x, vld1q_s8(w + 32));
        acc3 = vdotq_s32(acc3, x, vld1q_s8(w + 48));
    }
    vst1q_s32(sums, acc0);
    vst1q_s32(sums + 4, acc1);
    vst1q_s32(sums + 8, acc2);
    vst1q_s32(sums + 12, acc3);
}
#else
void gyatso_multilayer_l1(const uint8_t *inputs, const int8_t *weights, int32_t *sums) {
    for (int output = 0; output < 16; ++output) sums[output] = 0;
    for (int group = 0; group < 256; ++group) {
        const uint8_t *x = inputs + group * 4;
        const int8_t *w = weights + group * 64;
        for (int output = 0; output < 16; ++output) {
            const int8_t *wo = w + output * 4;
            sums[output] += (int32_t) x[0] * wo[0] + (int32_t) x[1] * wo[1] +
                            (int32_t) x[2] * wo[2] + (int32_t) x[3] * wo[3];
        }
    }
}
#endif

#if defined(__AVX512F__) || defined(__AVX2__)
#include <immintrin.h>
#endif
#if defined(__AVX512F__)
static inline int32_t gyatso_clamp_l2(int64_t value, int32_t max_value) {
    if (value < 0) return 0;
    if (value > max_value) return max_value;
    return (int32_t) value;
}
void gyatso_multilayer_l2(const int32_t *inputs, const int32_t *weights,
                          const int32_t *bias, int32_t *outputs,
                          int32_t max_value) {
    for (int output_base = 0; output_base < 32; output_base += 16) {
        __m512i even = _mm512_setzero_si512();
        __m512i odd = _mm512_setzero_si512();
        for (int input = 0; input < 16; ++input) {
            const __m512i w = _mm512_loadu_si512(
                (const void *) (weights + input * 32 + output_base));
            const __m512i x = _mm512_set1_epi32(inputs[input]);
            even = _mm512_add_epi64(even, _mm512_mul_epi32(w, x));
            odd = _mm512_add_epi64(odd,
                _mm512_mul_epi32(_mm512_srli_epi64(w, 32), x));
        }
        int64_t even_lanes[8], odd_lanes[8];
        _mm512_storeu_si512((void *) even_lanes, even);
        _mm512_storeu_si512((void *) odd_lanes, odd);
        for (int lane = 0; lane < 8; ++lane) {
            outputs[output_base + lane * 2] = gyatso_clamp_l2(
                even_lanes[lane] + bias[output_base + lane * 2], max_value);
            outputs[output_base + lane * 2 + 1] = gyatso_clamp_l2(
                odd_lanes[lane] + bias[output_base + lane * 2 + 1], max_value);
        }
    }
}
#elif defined(__AVX2__)
static inline int32_t gyatso_clamp_l2(int64_t value, int32_t max_value) {
    if (value < 0) return 0;
    if (value > max_value) return max_value;
    return (int32_t) value;
}
void gyatso_multilayer_l2(const int32_t *inputs, const int32_t *weights,
                          const int32_t *bias, int32_t *outputs,
                          int32_t max_value) {
    for (int output_base = 0; output_base < 32; output_base += 8) {
        __m256i even = _mm256_setzero_si256();
        __m256i odd = _mm256_setzero_si256();
        for (int input = 0; input < 16; ++input) {
            const __m256i w = _mm256_loadu_si256(
                (const __m256i *) (weights + input * 32 + output_base));
            const __m256i x = _mm256_set1_epi32(inputs[input]);
            even = _mm256_add_epi64(even, _mm256_mul_epi32(w, x));
            odd = _mm256_add_epi64(odd,
                _mm256_mul_epi32(_mm256_srli_epi64(w, 32), x));
        }
        int64_t even_lanes[4], odd_lanes[4];
        _mm256_storeu_si256((__m256i *) even_lanes, even);
        _mm256_storeu_si256((__m256i *) odd_lanes, odd);
        for (int lane = 0; lane < 4; ++lane) {
            outputs[output_base + lane * 2] = gyatso_clamp_l2(
                even_lanes[lane] + bias[output_base + lane * 2], max_value);
            outputs[output_base + lane * 2 + 1] = gyatso_clamp_l2(
                odd_lanes[lane] + bias[output_base + lane * 2 + 1], max_value);
        }
    }
}
#else
void gyatso_multilayer_l2(const int32_t *inputs, const int32_t *weights,
                          const int32_t *bias, int32_t *outputs,
                          int32_t max_value) {
    for (int output = 0; output < 32; ++output) {
        int64_t sum = bias[output];
        for (int input = 0; input < 16; ++input)
            sum += (int64_t) inputs[input] * weights[input * 32 + output];
        if (sum < 0) sum = 0;
        if (sum > max_value) sum = max_value;
        outputs[output] = (int32_t) sum;
    }
}
#endif

#if defined(__AVX512BW__) || defined(__AVX2__)
#include <immintrin.h>
#endif
#if defined(__ARM_NEON) || defined(__ARM_NEON__)
#include <arm_neon.h>
#endif
void gyatso_pairwise(const int16_t *stm, const int16_t *nstm, uint8_t *outputs) {
#if defined(__AVX512BW__)
    const __m512i zero = _mm512_setzero_si512();
    const __m512i max = _mm512_set1_epi16(255);
    for (int perspective = 0; perspective < 2; ++perspective) {
        const int16_t *acc = perspective == 0 ? stm : nstm;
        uint8_t *out = outputs + perspective * 512;
        for (int i = 0; i < 512; i += 32) {
            __m512i a = _mm512_loadu_si512((const void *) (acc + i));
            __m512i b = _mm512_loadu_si512((const void *) (acc + 512 + i));
            a = _mm512_max_epi16(zero, _mm512_min_epi16(max, a));
            b = _mm512_max_epi16(zero, _mm512_min_epi16(max, b));
            const __m512i p = _mm512_mulhi_epi16(_mm512_slli_epi16(a, 7), b);
            const __m256i bytes = _mm512_cvtepi16_epi8(p);
            _mm256_storeu_si256((__m256i *) (out + i), bytes);
        }
    }
#elif defined(__AVX2__)
    const __m256i zero = _mm256_setzero_si256();
    const __m256i max = _mm256_set1_epi16(255);
    for (int perspective = 0; perspective < 2; ++perspective) {
        const int16_t *acc = perspective == 0 ? stm : nstm;
        uint8_t *out = outputs + perspective * 512;
        for (int i = 0; i < 512; i += 16) {
            __m256i a = _mm256_loadu_si256((const __m256i *) (acc + i));
            __m256i b = _mm256_loadu_si256((const __m256i *) (acc + 512 + i));
            a = _mm256_max_epi16(zero, _mm256_min_epi16(max, a));
            b = _mm256_max_epi16(zero, _mm256_min_epi16(max, b));
            const __m256i p = _mm256_mulhi_epi16(_mm256_slli_epi16(a, 7), b);
            __m256i bytes = _mm256_packus_epi16(p, p);
            bytes = _mm256_permute4x64_epi64(bytes, _MM_SHUFFLE(3, 1, 2, 0));
            _mm_storeu_si128((__m128i *) (out + i), _mm256_castsi256_si128(bytes));
        }
    }
#elif defined(__ARM_NEON) || defined(__ARM_NEON__)
    const int16x8_t zero = vdupq_n_s16(0);
    const int16x8_t max = vdupq_n_s16(255);
    for (int perspective = 0; perspective < 2; ++perspective) {
        const int16_t *acc = perspective == 0 ? stm : nstm;
        uint8_t *out = outputs + perspective * 512;
        for (int i = 0; i < 512; i += 8) {
            int16x8_t a = vld1q_s16(acc + i);
            int16x8_t b = vld1q_s16(acc + 512 + i);
            a = vmaxq_s16(zero, vminq_s16(max, a));
            b = vmaxq_s16(zero, vminq_s16(max, b));
            const int16x8_t p = vqdmulhq_s16(vshlq_n_s16(a, 6), b);
            vst1_u8(out + i, vqmovun_s16(p));
        }
    }
#else
    for (int perspective = 0; perspective < 2; ++perspective) {
        const int16_t *acc = perspective == 0 ? stm : nstm;
        uint8_t *out = outputs + perspective * 512;
        for (int i = 0; i < 512; ++i) {
            int32_t a = acc[i];
            int32_t b = acc[512 + i];
            if (a < 0) a = 0; else if (a > 255) a = 255;
            if (b < 0) b = 0; else if (b > 255) b = 255;
            out[i] = (uint8_t) ((a * b) >> 9);
        }
    }
#endif
}
""".}

proc gyatsoMultilayerL1*(inputs: ptr uint8, weights: ptr int8,
                         sums: ptr int32) {.importc: "gyatso_multilayer_l1", cdecl.}
proc gyatsoMultilayerL2*(inputs, weights, bias, outputs: ptr int32,
                         maxValue: int32) {.importc: "gyatso_multilayer_l2", cdecl.}
proc gyatsoPairwise*(stm, nstm: ptr int16, outputs: ptr uint8) {.importc: "gyatso_pairwise", cdecl.}

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
