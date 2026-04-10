// jllm.h — Jetson LLM Runtime: master header
// Target: Orin Nano Super 8GB (SM 8.7, 102 GB/s LPDDR5, 67 TOPS GPU + 10 TOPS DLA)
// Design: memory-first — every decision optimizes for the 8 GB unified memory budget.

#pragma once

#include "jllm_memory.h"
#include "jllm_jetson.h"
#include "jllm_engine.h"
#include "jllm_kernels.h"

#define JLLM_VERSION_MAJOR 0
#define JLLM_VERSION_MINOR 1
#define JLLM_VERSION_PATCH 0

// SM 8.7 constants (Orin Nano/NX/AGX)
constexpr int JLLM_SM_COUNT         = 16;    // Orin Nano Super: 16 SMs
constexpr int JLLM_CUDA_CORES       = 1024;  // 16 SMs × 64 cores
constexpr int JLLM_TENSOR_CORES     = 32;    // 16 SMs × 2 TC per SM
constexpr int JLLM_WARP_SIZE        = 32;
constexpr int JLLM_MAX_THREADS_SM   = 1536;
constexpr int JLLM_MAX_WARPS_SM     = 48;
constexpr int JLLM_SHARED_MEM_SM    = 48 * 1024;  // 48 KB per SM
constexpr int JLLM_REG_FILE_SM      = 256 * 1024;  // 256 KB per SM
constexpr int JLLM_L2_CACHE         = 512 * 1024;  // 512 KB L2

// Memory bandwidth (Orin Nano Super)
constexpr float JLLM_DRAM_BW_GBS    = 102.0f;  // GB/s (128-bit LPDDR5)
constexpr float JLLM_GPU_TOPS_INT8  = 67.0f;
constexpr float JLLM_DLA_TOPS_INT8  = 10.0f;

// Derived: ridge point
constexpr float JLLM_RIDGE_POINT    = JLLM_GPU_TOPS_INT8 / JLLM_DRAM_BW_GBS;  // ~0.66 OP/byte
