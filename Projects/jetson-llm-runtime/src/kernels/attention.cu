// attention.cu — Flash Attention for decode (single query) on Orin SM 8.7
//
// Decode path: Q is a single token [n_heads × head_dim]
// K/V cache: [n_kv_heads × seq_len × head_dim]
//
// Fused: Q×K^T → scale → softmax → ×V in one kernel.
// Never materializes the seq×seq attention matrix.
//
// Tile KV in chunks of TILE_KV=64 through shared memory.
// Online softmax: accumulate max and sum incrementally per tile.
//
// Supports GQA: n_heads > n_kv_heads (multiple Q heads share one KV head)
// Supports INT8 KV cache: dequantize on-the-fly

#include "jllm_kernels.h"
#include <cuda_fp16.h>
#include <cfloat>

namespace jllm {

static constexpr int ATTN_TILE_KV = 64;   // KV tokens per tile (fits 48 KB SM)
static constexpr int ATTN_BLOCK   = 128;  // threads per block

// One block per query head. Within block, threads cooperate on KV tiles.
__global__ void flash_attention_decode_kernel(
    half*        __restrict__ output,     // [n_heads × head_dim]
    const half*  __restrict__ q,          // [n_heads × head_dim]
    const void*  __restrict__ k_cache,    // [n_kv_heads × seq_len × head_dim]
    const void*  __restrict__ v_cache,    // [n_kv_heads × seq_len × head_dim]
    int n_heads, int n_kv_heads, int head_dim, int seq_len,
    float scale, bool kv_int8, const float* kv_scales)
{
    const int head = blockIdx.x;          // which query head
    const int kv_head = head / (n_heads / n_kv_heads);  // GQA mapping
    const int tid = threadIdx.x;

    // Load Q for this head into registers
    extern __shared__ float smem[];
    float* s_scores = smem;                             // [ATTN_TILE_KV]
    float* s_kv = smem + ATTN_TILE_KV;                 // [ATTN_TILE_KV × head_dim] workspace

    // Q in registers (each thread holds a portion)
    float q_reg[8];  // each thread handles head_dim/ATTN_BLOCK elements (128 dim / 128 threads ≈ 1-2)
    // For head_dim=128, each thread loads 1 element
    float my_q = (tid < head_dim) ? __half2float(q[head * head_dim + tid]) : 0.0f;

    // Online softmax accumulators
    float running_max = -FLT_MAX;
    float running_sum = 0.0f;
    float acc[4] = {0};  // partial output accumulator (thread handles head_dim/blockDim elements)

    // Tile over KV sequence
    for (int kv_start = 0; kv_start < seq_len; kv_start += ATTN_TILE_KV) {
        int tile_len = min(ATTN_TILE_KV, seq_len - kv_start);

        // Step 1: Compute Q×K^T for this tile
        // Each thread computes dot(Q, K[t]) for one or more t values
        for (int t = tid; t < tile_len; t += blockDim.x) {
            int kv_pos = kv_start + t;
            float dot = 0.0f;

            if (kv_int8) {
                const int8_t* k_int8 = (const int8_t*)k_cache;
                float ks = kv_scales ? kv_scales[kv_head] : 1.0f;
                for (int d = 0; d < head_dim; d++) {
                    float k_val = k_int8[(int64_t)kv_head * seq_len * head_dim + kv_pos * head_dim + d] * ks;
                    float q_val = __half2float(q[head * head_dim + d]);
                    dot += q_val * k_val;
                }
            } else {
                const half* k_fp16 = (const half*)k_cache;
                for (int d = 0; d < head_dim; d++) {
                    float k_val = __half2float(k_fp16[(int64_t)kv_head * seq_len * head_dim + kv_pos * head_dim + d]);
                    float q_val = __half2float(q[head * head_dim + d]);
                    dot += q_val * k_val;
                }
            }
            s_scores[t] = dot * scale;
        }
        __syncthreads();

        // Step 2: Online softmax update
        // Find tile max
        float tile_max = -FLT_MAX;
        for (int t = tid; t < tile_len; t += blockDim.x)
            tile_max = fmaxf(tile_max, s_scores[t]);

        // Warp reduce max
        #pragma unroll
        for (int off = 16; off > 0; off >>= 1)
            tile_max = fmaxf(tile_max, __shfl_xor_sync(0xFFFFFFFF, tile_max, off));

        // Broadcast max via shared memory
        __shared__ float block_max;
        if (tid == 0) block_max = -FLT_MAX;
        __syncthreads();
        if (tid % 32 == 0) atomicMax((int*)&block_max, __float_as_int(tile_max));
        __syncthreads();
        tile_max = block_max;

        // Update running softmax
        float old_max = running_max;
        running_max = fmaxf(running_max, tile_max);
        float correction = expf(old_max - running_max);

        // Correct running accumulators
        running_sum *= correction;
        for (int i = 0; i < 4; i++) acc[i] *= correction;

        // Exponentiate scores and accumulate
        float tile_sum = 0.0f;
        for (int t = tid; t < tile_len; t += blockDim.x) {
            float p = expf(s_scores[t] - running_max);
            s_scores[t] = p;
            tile_sum += p;
        }

        // Reduce tile_sum
        #pragma unroll
        for (int off = 16; off > 0; off >>= 1)
            tile_sum += __shfl_xor_sync(0xFFFFFFFF, tile_sum, off);
        __shared__ float block_sum;
        if (tid == 0) block_sum = 0.0f;
        __syncthreads();
        if (tid % 32 == 0) atomicAdd(&block_sum, tile_sum);
        __syncthreads();
        running_sum += block_sum;

        // Step 3: Accumulate P × V
        // Each thread accumulates for its portion of head_dim
        for (int d = tid; d < head_dim; d += blockDim.x) {
            float val = 0.0f;
            for (int t = 0; t < tile_len; t++) {
                int kv_pos = kv_start + t;
                float v_val;
                if (kv_int8) {
                    const int8_t* v_i8 = (const int8_t*)v_cache;
                    float vs = kv_scales ? kv_scales[n_kv_heads + kv_head] : 1.0f;
                    v_val = v_i8[(int64_t)kv_head * seq_len * head_dim + kv_pos * head_dim + d] * vs;
                } else {
                    const half* v_fp16 = (const half*)v_cache;
                    v_val = __half2float(v_fp16[(int64_t)kv_head * seq_len * head_dim + kv_pos * head_dim + d]);
                }
                val += s_scores[t] * v_val;
            }
            // Map d to acc index (simplified — full impl uses register tiling)
            acc[d % 4] += val;
        }
        __syncthreads();
    }

    // Finalize: divide by sum and write output
    float inv_sum = (running_sum > 0.0f) ? 1.0f / running_sum : 0.0f;
    for (int d = tid; d < head_dim; d += blockDim.x) {
        // Simplified: in production, use proper register-tiled accumulator
        output[head * head_dim + d] = __float2half(acc[d % 4] * inv_sum);
    }
}

void flash_attention_decode(
    half* output, const half* q, const void* k_cache, const void* v_cache,
    int n_heads, int n_kv_heads, int head_dim, int seq_len,
    float scale, bool kv_int8, const float* kv_scales, cudaStream_t stream)
{
    int smem = (ATTN_TILE_KV + ATTN_TILE_KV * 4) * sizeof(float);  // scores + workspace
    if (smem > JLLM_SHARED_MEM_SM) smem = JLLM_SHARED_MEM_SM;

    flash_attention_decode_kernel<<<n_heads, ATTN_BLOCK, smem, stream>>>(
        output, q, k_cache, v_cache,
        n_heads, n_kv_heads, head_dim, seq_len,
        scale, kv_int8, kv_scales);
}

}  // namespace jllm
