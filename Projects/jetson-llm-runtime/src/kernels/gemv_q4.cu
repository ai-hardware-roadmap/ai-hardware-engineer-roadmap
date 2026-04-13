// gemv_q4.cu — Q4_K_M dequant-fused GEMV for Orin SM 8.7
//
// THE hot path: ~38% of decode time.
//
// GGUF Q4_K_M block layout (256 elements per block, 144 bytes):
//   bytes  0– 1: d     (FP16) — super-block scale
//   bytes  2– 3: dmin  (FP16) — super-block minimum
//   bytes  4–15: scales[12]   — packed 6-bit sub-block scales + mins
//   bytes 16–143: qs[128]     — 256 × 4-bit quantized values (2 per byte)
//
// Dequant formula for element i in block:
//   sub = i / 32                          (which of 8 sub-blocks)
//   sc  = 6-bit scale for sub-block
//   m   = 6-bit min for sub-block
//   q   = 4-bit quant value
//   val = d * sc * q  -  dmin * m
//
// Reference: ggml-cuda/dequantize.cuh in llama.cpp

#include "jllm_kernels.h"
#include <cuda_fp16.h>

namespace jllm {

// Q4_K block: 256 elements, 144 bytes
static constexpr int QK_K = 256;
static constexpr int Q4K_BLOCK_BYTES = 144;

struct block_q4_K {
    half    d;           // super-block scale
    half    dmin;        // super-block min
    uint8_t scales[12];  // packed 6-bit sub-block scales + mins
    uint8_t qs[128];     // 256 × 4-bit values (low nibble first)
};

// Extract 6-bit sub-block scale and min from packed scales[12]
// Layout: scales[0..3] = low 4 bits of scales for sub 0..3 and 4..7
//         scales[4..5] = high 2 bits of scales for sub 0..7
// This matches ggml's pack_q4_K format.
__device__ __forceinline__ void get_scale_min_k4(
    const uint8_t* scales, int sub, float* out_scale, float* out_min)
{
    if (sub < 4) {
        *out_scale = (scales[sub] & 0x3F);
        *out_min   = (scales[sub + 4] & 0x3F);
    } else {
        *out_scale = ((scales[sub + 4] & 0x0F) | ((scales[sub - 4] >> 6) << 4));
        *out_min   = ((scales[sub + 4] >> 4)    | ((scales[sub]     >> 6) << 4));
    }
}

// GEMV: y[M] = W[M × K] (Q4_K_M) × x[K] (FP16)
// Each warp handles one output row, lanes stride across K.
__global__ void gemv_q4k_kernel(
    half*              __restrict__ y,
    const block_q4_K*  __restrict__ W,     // [M × K/256] blocks
    const half*        __restrict__ x,
    int M, int K)
{
    const int row  = blockIdx.x * 4 + threadIdx.x / 32;
    const int lane = threadIdx.x & 31;
    if (row >= M) return;

    const int n_blocks = K / QK_K;  // blocks per row
    const block_q4_K* row_blocks = W + (int64_t)row * n_blocks;

    float acc = 0.0f;

    // Each lane handles some blocks (lane strides across blocks)
    for (int b = lane; b < n_blocks; b += 32) {
        const block_q4_K& blk = row_blocks[b];

        float d    = __half2float(blk.d);
        float dmin = __half2float(blk.dmin);

        int k_base = b * QK_K;  // first element index for this block

        // Process 8 sub-blocks of 32 elements each
        for (int sub = 0; sub < 8; sub++) {
            float sc, m;
            get_scale_min_k4(blk.scales, sub, &sc, &m);

            float d_sc  = d * sc;
            float dm    = dmin * m;

            int sub_offset = sub * 32;
            // 32 elements: stored as 16 bytes (2 elements per byte)
            // Lower nibble = element 0,2,4,...; upper nibble = element 1,3,5,...
            // Actually in Q4_K: first 128 bytes store all 256 values sequentially
            // qs[i] low nibble = element 2*i, qs[i] high nibble = element 2*i+1

            for (int j = 0; j < 32; j += 2) {
                int qi = (sub_offset + j) / 2;  // byte index in qs[128]
                uint8_t byte = blk.qs[qi];

                int q0 = byte & 0xF;         // low nibble
                int q1 = (byte >> 4) & 0xF;  // high nibble

                float w0 = d_sc * q0 - dm;
                float w1 = d_sc * q1 - dm;

                int k0 = k_base + sub_offset + j;
                acc += w0 * __half2float(x[k0]);
                acc += w1 * __half2float(x[k0 + 1]);
            }
        }
    }

    // Warp reduce (shuffle)
    #pragma unroll
    for (int off = 16; off > 0; off >>= 1)
        acc += __shfl_xor_sync(0xFFFFFFFF, acc, off);

    if (lane == 0)
        y[row] = __float2half(acc);
}

// ── Public API ──────────────────────────────────────────────────────────
// Note: 'scales' parameter is ignored for Q4_K — scales are inside the block.
// 'group_size' is ignored too — block size is always 256.

void gemv_q4(half* y, const void* W_q4, const half* scales, const half* x,
             int M, int K, int group_size, cudaStream_t stream) {
    dim3 grid((M + 3) / 4);
    dim3 block(128);
    gemv_q4k_kernel<<<grid, block, 0, stream>>>(
        y, (const block_q4_K*)W_q4, x, M, K);
}

}  // namespace jllm
