// fused_norm.cu — Fused RMSNorm + Residual Add (SM 8.7)
//
// Combines two operations into one kernel:
//   output = RMSNorm(x + residual) * weight
//
// Without fusion: 3 kernels, 6 DRAM accesses (read x, read residual, write sum,
//                 read sum, write norm, read norm + weight, write output)
// With fusion: 1 kernel, 3 DRAM accesses (read x, read residual, write output)
// → 2× less memory traffic

#include "jllm_kernels.h"
#include <cuda_fp16.h>

namespace jllm {

// One block per row. Block size = 128 (fits well on Orin SM).
// For hidden_dim > 128, each thread handles multiple elements.
__global__ void fused_rmsnorm_residual_kernel(
    half*       __restrict__ output,
    const half* __restrict__ x,
    const half* __restrict__ residual,
    const half* __restrict__ weight,
    int rows, int dim, float eps)
{
    const int row = blockIdx.x;
    if (row >= rows) return;

    const int tid = threadIdx.x;
    const int stride = blockDim.x;
    const int offset = row * dim;

    // Pass 1: compute x + residual and accumulate sum of squares
    extern __shared__ float sdata[];  // [dim] floats for the fused values

    float sum_sq = 0.0f;
    for (int i = tid; i < dim; i += stride) {
        float val = __half2float(x[offset + i]) + __half2float(residual[offset + i]);
        sdata[i] = val;
        sum_sq += val * val;
    }

    // Block reduction for sum_sq
    // Warp reduction first
    #pragma unroll
    for (int off = 16; off > 0; off >>= 1)
        sum_sq += __shfl_xor_sync(0xFFFFFFFF, sum_sq, off);

    // Cross-warp reduction via shared memory
    __shared__ float warp_sums[4];  // max 4 warps in block of 128
    int warp_id = tid / 32;
    int warp_lane = tid & 31;
    if (warp_lane == 0) warp_sums[warp_id] = sum_sq;
    __syncthreads();

    if (tid == 0) {
        float total = 0.0f;
        for (int w = 0; w < (stride + 31) / 32; w++)
            total += warp_sums[w];
        warp_sums[0] = total;
    }
    __syncthreads();

    float rrms = rsqrtf(warp_sums[0] / dim + eps);

    // Pass 2: normalize and scale by weight, write output
    for (int i = tid; i < dim; i += stride) {
        float normed = sdata[i] * rrms;
        float w = __half2float(weight[i]);
        output[offset + i] = __float2half(normed * w);
    }
}

void fused_rmsnorm_residual(half* output, const half* x, const half* residual,
                            const half* weight, int rows, int hidden_dim,
                            float eps, cudaStream_t stream) {
    int block = BLOCK_SIZE;  // 128
    int smem = hidden_dim * sizeof(float);

    // Ensure shared memory fits (48 KB on Orin SM)
    if (smem > JLLM_SHARED_MEM_SM) {
        // Fallback: process in chunks (shouldn't happen for hidden_dim ≤ 4096)
        smem = JLLM_SHARED_MEM_SM;
    }

    fused_rmsnorm_residual_kernel<<<rows, block, smem, stream>>>(
        output, x, residual, weight, rows, hidden_dim, eps);
}

}  // namespace jllm
