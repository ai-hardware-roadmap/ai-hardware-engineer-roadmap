# Jetson LLM Runtime — Memory-First Inference Engine

**Parent:** [ML and AI](../Guide.md)

> **Goal:** Build a Jetson-optimized LLM inference runtime that treats **memory as the primary constraint** rather than compute. Fork llama.cpp as the base, add Jetson-specific optimizations that neither llama.cpp nor TensorRT-LLM provide out of the box.

---

## Why Build This

| Runtime | Strengths | Weakness on Jetson 8 GB |
|---------|-----------|------------------------|
| **llama.cpp** | Easy, portable, GGUF native | Generic CUDA kernels, no Jetson memory awareness, no power-mode integration |
| **TensorRT-LLM** | Fastest kernels, fused ops | Heavy build pipeline, designed for datacenter (A100/H100), overkill for 8 GB |
| **Ollama** | One-command UX | Wraps llama.cpp, adds overhead, no fine-grained control |
| **This project** | Memory-first design, Jetson-native, power-aware | You build and maintain it |

The gap: **no existing runtime is designed around the 8 GB unified memory constraint**. They all assume either "plenty of VRAM" (TensorRT-LLM) or "generic GPU" (llama.cpp). Jetson's unified memory, power modes, and thermal limits create a unique optimization space.

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                    Jetson LLM Runtime                            │
│                                                                  │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────────┐  │
│  │ Model Loader │  │ Memory       │  │ Power/Thermal        │  │
│  │ (GGUF)       │  │ Manager      │  │ Manager              │  │
│  │              │  │              │  │                      │  │
│  │ • mmap       │  │ • Budget     │  │ • nvpmodel query     │  │
│  │ • lazy load  │  │ • KV pool    │  │ • thermal throttle   │  │
│  │ • layer pin  │  │ • OOM guard  │  │ • adaptive batch     │  │
│  └──────┬───────┘  └──────┬───────┘  └──────────┬───────────┘  │
│         │                 │                      │               │
│  ┌──────┴─────────────────┴──────────────────────┴───────────┐  │
│  │                    Execution Engine                        │  │
│  │                                                           │  │
│  │  ┌─────────┐  ┌──────────┐  ┌────────┐  ┌────────────┐  │  │
│  │  │Attention│  │  FFN /   │  │RMSNorm │  │  Rotary    │  │  │
│  │  │ (fused) │  │  SwiGLU  │  │ (fused)│  │  Embed     │  │  │
│  │  └────┬────┘  └────┬─────┘  └───┬────┘  └─────┬──────┘  │  │
│  │       │            │            │              │          │  │
│  │  ┌────┴────────────┴────────────┴──────────────┴──────┐   │  │
│  │  │         CUDA Kernel Library (Orin-tuned)           │   │  │
│  │  │  • Ampere SM tile sizes (64×64)                    │   │  │
│  │  │  • INT4 dequant-fused GEMM                         │   │  │
│  │  │  • FlashAttention (48 KB shared mem)               │   │  │
│  │  │  • CUDA graphs for decode loop                     │   │  │
│  │  └────────────────────────────────────────────────────┘   │  │
│  └───────────────────────────────────────────────────────────┘  │
│                                                                  │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │                    Serving Layer                           │  │
│  │  • OpenAI-compatible REST API                             │  │
│  │  • Streaming SSE token output                             │  │
│  │  • Health / metrics endpoint (memory, thermal, tok/s)     │  │
│  └───────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

---

## Phase 1 — Fork and Baseline (Week 1–2)

### 1.1 Fork llama.cpp

```bash
# Clone llama.cpp
git clone https://github.com/ggerganov/llama.cpp
cd llama.cpp

# Create your Jetson branch
git checkout -b jetson-optimized

# Build with CUDA for Jetson
cmake -B build \
    -DGGML_CUDA=ON \
    -DCMAKE_CUDA_ARCHITECTURES="87" \
    -DCMAKE_BUILD_TYPE=Release
cmake --build build --config Release -j$(nproc)
```

`CUDA_ARCHITECTURES="87"` = Ampere SM 8.7 (Orin Nano/NX). This tells the compiler to generate code specifically for your GPU — no generic fallback.

### 1.2 Baseline Measurements

Before changing anything, measure baseline performance:

```bash
# Download test model
wget https://huggingface.co/bartowski/Llama-3.2-3B-Instruct-GGUF/resolve/main/\
Llama-3.2-3B-Instruct-Q4_K_M.gguf -O model.gguf

# Set max performance
sudo nvpmodel -m 0
sudo jetson_clocks

# Baseline benchmark
./build/bin/llama-bench -m model.gguf -ngl 99 -t 6

# Record these numbers:
#   pp512  = prompt processing speed (512 tokens)
#   tg128  = token generation speed (128 tokens)
#   Memory = peak RSS during inference
```

Create a benchmark log:

```bash
#!/bin/bash
# bench.sh — run after each optimization
echo "=== Benchmark $(date) ==="
echo "Git: $(git rev-parse --short HEAD)"
echo ""

# Memory before
FREE_BEFORE=$(free -m | awk '/Mem:/ {print $7}')
echo "Free RAM before: ${FREE_BEFORE} MB"

# Run benchmark
./build/bin/llama-bench -m model.gguf -ngl 99 -t 6 2>&1 | tee -a bench.log

# Memory during (in background)
./build/bin/llama-cli -m model.gguf -ngl 99 -c 2048 -n 128 \
    -p "Explain the Jetson memory architecture" &
PID=$!
sleep 2
echo "Peak RSS: $(cat /proc/$PID/status | grep VmRSS | awk '{print $2}') KB"
wait $PID

# Thermal
echo "Thermal: $(cat /sys/devices/virtual/thermal/thermal_zone*/temp | head -1 | awk '{print $1/1000}')°C"
echo "=================================="
```

### 1.3 Profile with Nsight

```bash
# Profile the decode loop
nsys profile --trace=cuda,nvtx \
    -o baseline_profile \
    ./build/bin/llama-cli -m model.gguf -ngl 99 -c 512 -n 64 \
    -p "Hello"

# Analyze: which kernels dominate?
nsys stats baseline_profile.nsys-rep
```

You'll see something like:

```
Kernel                              Time%    Calls
────────────────────────────────────────────────────
ggml_cuda_mul_mat_q4_K             38.2%    312
ggml_cuda_flash_attn_ext           28.1%    156
ggml_cuda_rms_norm                 11.4%    312
ggml_cuda_silu_mul                  7.8%    156
ggml_cuda_rope                      4.2%    312
other                              10.3%    ...
```

**This profile tells you where to optimize.** The top 3 kernels (matmul, attention, norm) account for ~78% of execution time.

---

## Phase 2 — Memory Manager (Week 2–3)

The core differentiator. Build a memory-aware subsystem that llama.cpp doesn't have.

### 2.1 Memory Budget Tracker

```cpp
// jetson_memory.h — real-time memory budget tracking

#pragma once
#include <cstdint>
#include <cstdio>

struct JetsonMemoryBudget {
    int64_t total_mb;           // 8192 (or 7633 after carveouts)
    int64_t os_reserved_mb;     // ~500 (kernel + services)
    int64_t cma_reserved_mb;    // ~768 (camera, can reduce for LLM-only)
    int64_t cuda_overhead_mb;   // ~300 (CUDA runtime + context)
    int64_t model_mb;           // model weight size
    int64_t kv_cache_mb;        // current KV cache usage
    int64_t activation_mb;      // scratch / intermediate tensors

    int64_t available() const {
        return total_mb - os_reserved_mb - cma_reserved_mb
               - cuda_overhead_mb - model_mb - kv_cache_mb - activation_mb;
    }

    int64_t max_kv_cache_mb() const {
        // Leave 256 MB headroom to prevent OOM
        return total_mb - os_reserved_mb - cma_reserved_mb
               - cuda_overhead_mb - model_mb - activation_mb - 256;
    }

    int max_context_tokens(int num_layers, int num_kv_heads,
                           int head_dim, int bytes_per_element) const {
        int64_t kv_per_token = 2LL * num_layers * num_kv_heads
                               * head_dim * bytes_per_element;
        return (max_kv_cache_mb() * 1024 * 1024) / kv_per_token;
    }

    void print() const {
        printf("Memory Budget:\n");
        printf("  Total:      %4lld MB\n", total_mb);
        printf("  OS:        -%4lld MB\n", os_reserved_mb);
        printf("  CMA:       -%4lld MB\n", cma_reserved_mb);
        printf("  CUDA:      -%4lld MB\n", cuda_overhead_mb);
        printf("  Model:     -%4lld MB\n", model_mb);
        printf("  KV cache:  -%4lld MB (current)\n", kv_cache_mb);
        printf("  Activations:-%4lld MB\n", activation_mb);
        printf("  ─────────────────────\n");
        printf("  Available:  %4lld MB\n", available());
        printf("  Max KV:     %4lld MB → %d tokens\n",
               max_kv_cache_mb(),
               max_context_tokens(26, 8, 128, 1)); // Llama 3.2 3B INT8 KV
    }
};

// Read actual free memory from /proc/meminfo
int64_t jetson_get_free_mb() {
    FILE* f = fopen("/proc/meminfo", "r");
    char line[256];
    while (fgets(line, sizeof(line), f)) {
        long val;
        if (sscanf(line, "MemAvailable: %ld kB", &val) == 1) {
            fclose(f);
            return val / 1024;
        }
    }
    fclose(f);
    return -1;
}
```

### 2.2 OOM Prevention Guard

```cpp
// Before every KV cache expansion, check if we can afford it
bool can_extend_context(const JetsonMemoryBudget& budget, int new_tokens) {
    int64_t kv_per_token_bytes = 2LL * 26 * 8 * 128 * 1;  // Llama 3.2 3B INT8
    int64_t needed_mb = (new_tokens * kv_per_token_bytes) / (1024 * 1024);

    int64_t actual_free = jetson_get_free_mb();

    if (actual_free < needed_mb + 256) {  // 256 MB safety margin
        fprintf(stderr, "WARNING: only %lld MB free, need %lld MB for %d more tokens\n",
                actual_free, needed_mb + 256, new_tokens);
        return false;
    }
    return true;
}

// In the decode loop:
for (int i = 0; i < max_tokens; i++) {
    if (!can_extend_context(budget, 1)) {
        printf("[memory guard] Stopping at token %d — OOM risk\n", i);
        break;  // graceful stop instead of crash
    }
    // ... generate next token ...
}
```

### 2.3 Dynamic KV Cache with CPU Offload

When GPU memory runs low, offload oldest KV entries to CPU (still fast on unified memory):

```cpp
struct HybridKVCache {
    float* gpu_cache;      // recent tokens (hot) — cudaMalloc
    float* cpu_cache;      // old tokens (cold) — cudaMallocHost (zero-copy)
    int gpu_capacity;      // max tokens in GPU cache
    int cpu_capacity;      // max tokens in CPU cache
    int gpu_used;
    int cpu_used;

    void evict_to_cpu(int n_tokens) {
        // Move oldest n_tokens from GPU cache to CPU cache
        // On Jetson unified memory, this is a memcpy within same DRAM
        // — much faster than PCIe offload on discrete GPU
        size_t bytes = n_tokens * kv_entry_size;
        memcpy(cpu_cache + cpu_used * kv_entry_size,
               gpu_cache,  // oldest entries at front
               bytes);

        // Shift GPU cache (move remaining entries to front)
        memmove(gpu_cache,
                gpu_cache + n_tokens * kv_entry_size,
                (gpu_used - n_tokens) * kv_entry_size);

        gpu_used -= n_tokens;
        cpu_used += n_tokens;
    }

    // On Jetson, CPU cache is still accessible by GPU (unified memory!)
    // Attention kernel reads from both gpu_cache and cpu_cache
    // Older context = slightly slower (cache hierarchy) but doesn't OOM
};
```

**Why this works well on Jetson but not on discrete GPUs:** On discrete GPU, CPU offload means PCIe transfer (~64 GB/s, high latency). On Jetson, "CPU memory" and "GPU memory" are the same physical DRAM — offloading just changes the CUDA allocation type, not the physical location. The GPU can still read "CPU" memory at DRAM bandwidth.

---

## Phase 3 — Orin-Tuned CUDA Kernels (Week 3–5)

### 3.1 Kernel Optimization Targets

From the Phase 1 profile, the top targets:

| Kernel | % of time | Optimization |
|--------|-----------|-------------|
| `mul_mat_q4_K` | ~38% | Orin-tuned tile size (64×64), Tensor Core INT4 dequant-fused |
| `flash_attn_ext` | ~28% | 48 KB shared mem tile, INT8 KV, Orin block size |
| `rms_norm` | ~11% | Fuse with residual add and SwiGLU activation |
| `silu_mul` | ~8% | Fuse into FFN kernel |
| `rope` | ~4% | Fuse into attention kernel |

### 3.2 Orin-Specific Tile Sizes

```cpp
// llama.cpp default (tuned for desktop GPUs):
#define GGML_CUDA_MMQ_Y       64    // too large for Orin SM
#define GGML_CUDA_MMQ_X      128

// Orin Nano optimized (SM 8.7, 48 KB shared mem, 1024 CUDA cores):
#define GGML_CUDA_MMQ_Y       32    // smaller tiles fit shared memory
#define GGML_CUDA_MMQ_X       64

// Why: Orin SM has less shared memory (48 KB vs 164 KB on H100)
// Smaller tiles = less shared mem per block = more blocks = better occupancy
```

### 3.3 Fused RMSNorm + Residual + SwiGLU

Three separate kernels → one kernel, 3× less DRAM traffic:

```cpp
__global__ void fused_rmsnorm_residual_swiglu(
    float* __restrict__ output,
    const float* __restrict__ input,
    const float* __restrict__ residual,
    const float* __restrict__ weight,
    const float* __restrict__ gate_weight,
    const float* __restrict__ up_weight,
    int hidden_dim, float eps)
{
    int row = blockIdx.x;
    int tid = threadIdx.x;

    extern __shared__ float sdata[];

    // Step 1: Load input + residual, compute variance (RMSNorm)
    float val = 0.0f;
    float sum_sq = 0.0f;
    for (int i = tid; i < hidden_dim; i += blockDim.x) {
        float h = input[row * hidden_dim + i] + residual[row * hidden_dim + i];
        sdata[i] = h;
        sum_sq += h * h;
    }
    // Warp reduction for sum_sq
    sum_sq = warp_reduce_sum(sum_sq);
    // Block reduction
    __shared__ float block_sum;
    if (tid == 0) block_sum = 0;
    __syncthreads();
    if (tid % 32 == 0) atomicAdd(&block_sum, sum_sq);
    __syncthreads();

    float rrms = rsqrtf(block_sum / hidden_dim + eps);

    // Step 2: Normalize + SwiGLU
    for (int i = tid; i < hidden_dim; i += blockDim.x) {
        float normed = sdata[i] * rrms * weight[i];
        // SwiGLU: silu(gate) * up
        float gate = normed * gate_weight[i];    // simplified
        float up   = normed * up_weight[i];
        output[row * hidden_dim + i] = (gate / (1.0f + expf(-gate))) * up;
    }
}
```

### 3.4 CUDA Graphs for Decode Loop

Capture the entire decode step as a graph:

```cpp
// Capture graph (once, at first decode step)
cudaGraph_t graph;
cudaGraphExec_t graph_exec;

cudaStreamBeginCapture(stream, cudaStreamCaptureModeGlobal);

// All kernels for one decode step:
for (int layer = 0; layer < n_layers; layer++) {
    launch_attention(layer, stream);
    launch_ffn(layer, stream);
}
launch_logits(stream);

cudaStreamEndCapture(stream, &graph);
cudaGraphInstantiate(&graph_exec, graph, NULL, NULL, 0);

// Replay for every subsequent token (near-zero launch overhead)
for (int token = 0; token < max_tokens; token++) {
    update_kv_pointers(token);
    cudaGraphLaunch(graph_exec, stream);
    cudaStreamSynchronize(stream);
    sample_token();
}
```

---

## Phase 4 — Power-Aware Inference (Week 5–6)

### 4.1 Power Mode Integration

```cpp
// jetson_power.h — query and adapt to Jetson power state

#include <cstdio>
#include <cstring>

enum JetsonPowerMode {
    MAXN = 0,    // 25W — maximum performance
    MODE_15W = 1,
    MODE_10W = 2,
    MODE_7W = 3  // minimum power
};

struct JetsonPowerConfig {
    int power_mode;
    int watts;
    int max_gpu_freq_mhz;
    int recommended_batch_size;
    int recommended_context;
};

JetsonPowerConfig get_power_config() {
    JetsonPowerConfig config = {};

    FILE* f = popen("nvpmodel -q 2>/dev/null | grep 'NV Power Mode'", "r");
    char buf[256];
    if (f && fgets(buf, sizeof(buf), f)) {
        if (strstr(buf, "MAXN"))   { config = {0, 25, 1300, 4, 4096}; }
        else if (strstr(buf, "15W")) { config = {1, 15, 900, 2, 2048}; }
        else if (strstr(buf, "10W")) { config = {2, 10, 600, 1, 1024}; }
        else if (strstr(buf, "7W"))  { config = {3, 7, 400, 1, 512}; }
    }
    if (f) pclose(f);
    return config;
}

float get_thermal_celsius() {
    FILE* f = fopen("/sys/devices/virtual/thermal/thermal_zone0/temp", "r");
    int temp = 0;
    if (f) { fscanf(f, "%d", &temp); fclose(f); }
    return temp / 1000.0f;
}

// Adaptive inference: slow down if overheating
int adaptive_batch_size(const JetsonPowerConfig& config) {
    float temp = get_thermal_celsius();
    if (temp > 85.0f) return 1;                           // thermal throttle
    if (temp > 75.0f) return config.recommended_batch_size / 2;
    return config.recommended_batch_size;
}
```

### 4.2 Thermal-Aware Token Generation

```cpp
void generate_tokens(LLMContext& ctx, int max_tokens) {
    auto power = get_power_config();
    printf("Power mode: %dW, max GPU: %d MHz\n", power.watts, power.max_gpu_freq_mhz);

    for (int i = 0; i < max_tokens; i++) {
        // Check memory
        if (!can_extend_context(ctx.budget, 1)) {
            printf("[memory] Stopping at token %d\n", i);
            break;
        }

        // Check thermal
        float temp = get_thermal_celsius();
        if (temp > 90.0f) {
            printf("[thermal] %.1f°C — pausing 100ms to cool\n", temp);
            usleep(100000);  // 100ms cooldown
        }

        // Generate
        int token = decode_one_token(ctx);
        output_token(token);

        // Metrics (every 10 tokens)
        if (i % 10 == 0) {
            printf("[%d] %.1f tok/s | %.0f MB free | %.1f°C\n",
                   i, ctx.tokens_per_sec(), jetson_get_free_mb(), temp);
        }
    }
}
```

---

## Phase 5 — Serving API (Week 6–7)

### 5.1 OpenAI-Compatible REST API

```cpp
// Minimal HTTP server using cpp-httplib (header-only)
#include "httplib.h"
#include <nlohmann/json.hpp>

using json = nlohmann::json;

void start_server(LLMContext& ctx, int port = 8080) {
    httplib::Server svr;

    // Health endpoint with Jetson-specific metrics
    svr.Get("/health", [&](const auto& req, auto& res) {
        json health = {
            {"status", "ok"},
            {"model", ctx.model_name},
            {"memory_free_mb", jetson_get_free_mb()},
            {"thermal_celsius", get_thermal_celsius()},
            {"power_mode_watts", get_power_config().watts},
            {"tokens_generated", ctx.total_tokens},
            {"uptime_seconds", ctx.uptime()}
        };
        res.set_content(health.dump(), "application/json");
    });

    // OpenAI-compatible chat completion
    svr.Post("/v1/chat/completions", [&](const auto& req, auto& res) {
        auto body = json::parse(req.body);
        std::string prompt = format_chat(body["messages"]);
        int max_tokens = body.value("max_tokens", 256);

        std::string response = generate(ctx, prompt, max_tokens);

        json result = {
            {"id", "jetson-" + std::to_string(time(nullptr))},
            {"object", "chat.completion"},
            {"model", ctx.model_name},
            {"choices", {{
                {"index", 0},
                {"message", {{"role", "assistant"}, {"content", response}}},
                {"finish_reason", "stop"}
            }}},
            {"usage", {
                {"prompt_tokens", ctx.last_prompt_tokens},
                {"completion_tokens", ctx.last_completion_tokens},
                {"total_tokens", ctx.last_prompt_tokens + ctx.last_completion_tokens}
            }}
        };
        res.set_content(result.dump(), "application/json");
    });

    printf("Jetson LLM Runtime serving on http://0.0.0.0:%d\n", port);
    svr.listen("0.0.0.0", port);
}
```

### 5.2 Streaming SSE (Server-Sent Events)

```cpp
// Streaming endpoint — tokens sent as they're generated
svr.Post("/v1/chat/completions", [&](const auto& req, auto& res) {
    auto body = json::parse(req.body);
    bool stream = body.value("stream", false);

    if (stream) {
        res.set_header("Content-Type", "text/event-stream");
        res.set_header("Cache-Control", "no-cache");

        res.set_content_provider("text/event-stream",
            [&](size_t offset, httplib::DataSink& sink) {
                generate_streaming(ctx, prompt, max_tokens,
                    [&](const std::string& token_text, bool is_done) {
                        json chunk = {
                            {"object", "chat.completion.chunk"},
                            {"choices", {{
                                {"delta", {{"content", token_text}}},
                                {"finish_reason", is_done ? "stop" : nullptr}
                            }}}
                        };
                        sink.write("data: " + chunk.dump() + "\n\n");
                    });
                sink.write("data: [DONE]\n\n");
                sink.done();
                return true;
            });
    }
});
```

---

## Project Structure

```
jetson-llm-runtime/
├── CMakeLists.txt
├── README.md
├── src/
│   ├── main.cpp                 # CLI entry point
│   ├── server.cpp               # REST API server
│   ├── engine/
│   │   ├── model_loader.cpp     # GGUF loading (from llama.cpp)
│   │   ├── decode.cpp           # Token generation loop
│   │   └── sample.cpp           # Token sampling (top-k, top-p, temp)
│   ├── memory/
│   │   ├── budget.cpp           # JetsonMemoryBudget
│   │   ├── kv_cache.cpp         # HybridKVCache (GPU + CPU offload)
│   │   └── oom_guard.cpp        # Pre-allocation checks
│   ├── kernels/
│   │   ├── matmul_q4.cu         # Orin-tuned INT4 GEMM
│   │   ├── attention.cu         # FlashAttention for 48 KB SM
│   │   ├── fused_norm.cu        # RMSNorm + residual + SwiGLU
│   │   └── rope.cu              # Rotary position embedding
│   ├── jetson/
│   │   ├── power.cpp            # nvpmodel query, thermal monitor
│   │   ├── memory_info.cpp      # /proc/meminfo, CMA, buddyinfo
│   │   └── clocks.cpp           # GPU/EMC frequency control
│   └── utils/
│       ├── tokenizer.cpp        # Tokenizer (from llama.cpp)
│       └── metrics.cpp          # tok/s, latency, memory tracking
├── include/
│   ├── jetson_memory.h
│   ├── jetson_power.h
│   └── ...
├── models/                      # Downloaded GGUF files
├── scripts/
│   ├── bench.sh                 # Benchmark script
│   ├── profile.sh               # nsys profiling
│   └── setup_jetson.sh          # Initial Jetson configuration
└── tests/
    ├── test_memory_budget.cpp
    ├── test_kv_cache.cpp
    └── test_power.cpp
```

---

## Build and Run

```bash
# Build
cmake -B build \
    -DGGML_CUDA=ON \
    -DCMAKE_CUDA_ARCHITECTURES="87" \
    -DCMAKE_BUILD_TYPE=Release
cmake --build build -j$(nproc)

# Run CLI
./build/jetson-llm -m models/Llama-3.2-3B-Q4_K_M.gguf -c 2048

# Run as API server
./build/jetson-llm-server -m models/Llama-3.2-3B-Q4_K_M.gguf -p 8080

# Test from another machine
curl http://jetson-ip:8080/v1/chat/completions \
    -H "Content-Type: application/json" \
    -d '{"model":"llama-3.2-3b","messages":[{"role":"user","content":"Hello"}]}'

# Health check (Jetson-specific metrics)
curl http://jetson-ip:8080/health | jq .
```

---

## Milestone Targets

| Phase | Milestone | Success metric |
|-------|-----------|---------------|
| 1 | Fork + baseline | Benchmark numbers recorded, nsys profile analyzed |
| 2 | Memory manager | OOM guard prevents crash, memory budget prints correctly |
| 3 | Orin-tuned kernels | **>20% faster** than stock llama.cpp on Llama 3.2 3B Q4_K_M |
| 4 | Power-aware | Adapts generation to power mode, no thermal throttle crashes |
| 5 | API server | OpenAI-compatible endpoint, streaming works, health metrics |
| **Final** | **Production-ready** | **Stable 24/7 operation**, auto-restart on OOM, 25+ tok/s on 3B model |

---

## Resources

| Resource | What for |
|----------|----------|
| [llama.cpp source](https://github.com/ggerganov/llama.cpp) | Base to fork from |
| [GGML CUDA kernels](https://github.com/ggerganov/llama.cpp/tree/master/ggml/src/ggml-cuda) | Existing CUDA kernels to optimize |
| [cpp-httplib](https://github.com/yhirose/cpp-httplib) | Header-only HTTP server |
| [nlohmann/json](https://github.com/nlohmann/json) | Header-only JSON library |
| [Nsight Systems](https://docs.nvidia.com/nsight-systems/) | Profiling |
| [CUDA Graphs Guide](https://docs.nvidia.com/cuda/cuda-c-programming-guide/#cuda-graphs) | Graph capture for decode loop |
| [Orin Nano Memory Architecture](../../1.%20Nvidia%20Jetson%20Platform/Orin-Nano-Memory-Architecture/Guide.md) | Memory system reference (this roadmap) |
| [LLM Optimization on Jetson](../llm-optimization-jetson/Guide.md) | Optimization techniques reference (this roadmap) |
