// gemv_q4.cu — INT4 dequant-fused GEMV for Orin SM 8.7
//
// THE hot path: ~38% of decode time.
//
// y[M] = W[M×K](Q4) × x[K](FP16)
//
// Dequant happens inside the kernel — never writes FP16 weights to DRAM.
// Memory traffic: K/2 bytes (INT4) + K/32×2 bytes (scales) + K×2 bytes (x)
// vs K×2 bytes if FP16 weights → ~3.5× bandwidth reduction.

#include "jllm_kernels.h"
#include <cuda_fp16.h>

namespace jllm {

// Dequantize 8 INT4 values from packed uint32
__device__ __forceinline__ void dequant_8(uint32_t packed, float scale, float* out) {
    #pragma unroll
    for (int i = 0; i < 8; i++) {
        int q = (packed >> (i * 4)) & 0xF;
        out[i] = (q - 8) * scale;    // unsigned [0,15] → signed [-8,7] × scale
    }
}

// Grid:  (ceil(M / 4), 1)
// Block: (128) = 4 warps, one output row per warp
__global__ void gemv_q4_kernel(
    half*           __restrict__ y,
    const uint32_t* __restrict__ W,       // [M × K/8]
    const half*     __restrict__ scales,  // [M × num_groups]
    const half*     __restrict__ x,
    int M, int K, int group_size)
{
    const int row  = blockIdx.x * 4 + threadIdx.x / 32;
    const int lane = threadIdx.x & 31;
    if (row >= M) return;

    const int K8 = K / 8;
    const int ngroups = K / group_size;
    const uint32_t* Wr = W      + (int64_t)row * K8;
    const half*     Sr = scales  + (int64_t)row * ngroups;

    float acc = 0.0f;

    // Each lane strides across K, coalesced uint32 loads within warp
    for (int p = lane; p < K8; p += 32) {
        uint32_t packed = Wr[p];
        int k0 = p * 8;
        float s = __half2float(Sr[k0 / group_size]);

        float dq[8];
        dequant_8(packed, s, dq);

        // Dot with x — x stays in L2/L1 after first read
        #pragma unroll
        for (int i = 0; i < 8; i++) {
            acc += dq[i] * __half2float(x[k0 + i]);
        }
    }

    // Warp reduce (shuffle, no shared memory)
    #pragma unroll
    for (int off = 16; off > 0; off >>= 1)
        acc += __shfl_xor_sync(0xFFFFFFFF, acc, off);

    if (lane == 0)
        y[row] = __float2half(acc);
}

void gemv_q4(half* y, const void* W_q4, const half* scales, const half* x,
             int M, int K, int group_size, cudaStream_t stream) {
    dim3 grid((M + 3) / 4);
    dim3 block(128);
    gemv_q4_kernel<<<grid, block, 0, stream>>>(
        y, (const uint32_t*)W_q4, scales, x, M, K, group_size);
}

}  // namespace jllm
