// jllm_engine.h — LLM inference engine (Jetson-native)
//
// Design:
//   - Zero allocation during inference (everything pre-allocated)
//   - Memory budget checked before model load, before KV extension
//   - Power/thermal aware — adapts generation speed
//   - CUDA graphs for decode loop (near-zero launch overhead)

#pragma once

#include "jllm_memory.h"
#include "jllm_jetson.h"
#include "jllm_kernels.h"
#include <cuda_runtime.h>
#include <string>
#include <vector>
#include <functional>

namespace jllm {

// ── Model config (read from GGUF header) ─────────────────────────────────

struct ModelConfig {
    std::string name;
    int         n_layers;
    int         n_heads;
    int         n_kv_heads;      // GQA: may be < n_heads
    int         head_dim;
    int         hidden_dim;
    int         intermediate_dim;
    int         vocab_size;
    int         max_seq_len;
    float       rope_theta;
    int         quant_type;      // GGUF quant type (Q4_K_M, Q8_0, etc.)

    // Derived
    int gqa_group_size() const { return n_heads / n_kv_heads; }
    int64_t weight_bytes() const;   // total model weight size
    int64_t kv_per_token_bytes(int kv_type_bytes) const {
        return 2LL * n_layers * n_kv_heads * head_dim * kv_type_bytes;
    }
};

// ── Generation parameters ────────────────────────────────────────────────

struct GenParams {
    int   max_tokens   = 256;
    float temperature  = 0.7f;
    int   top_k        = 40;
    float top_p        = 0.9f;
    float repeat_penalty = 1.1f;
    int   context_limit = 0;       // 0 = auto (calculated from memory budget)
    bool  use_cuda_graph = true;
    bool  kv_int8      = true;     // INT8 KV cache (halves KV memory)
};

// ── Token callback (for streaming output) ────────────────────────────────

using TokenCallback = std::function<void(const char* text, bool is_eos)>;

// ── Generation stats ─────────────────────────────────────────────────────

struct GenStats {
    int     prompt_tokens;
    int     completion_tokens;
    float   prompt_ms;          // time for prefill
    float   decode_ms;          // time for all decode steps
    float   prompt_tok_per_sec;
    float   decode_tok_per_sec;
    int64_t peak_memory_mb;
    float   peak_thermal_c;
    int     oom_stops;          // times OOM guard triggered
    int     thermal_pauses;     // times thermal backoff triggered
};

// ── The engine ───────────────────────────────────────────────────────────

class Engine {
public:
    Engine();
    ~Engine();

    // Load model and pre-allocate all memory.
    // Returns false if model doesn't fit in memory budget.
    bool load(const std::string& gguf_path, const GenParams& params);
    void unload();

    // Run generation. Calls token_cb for each generated token.
    GenStats generate(const std::string& prompt, const GenParams& params,
                      TokenCallback token_cb = nullptr);

    // Stop generation (from another thread, e.g., timeout or HTTP cancel)
    void stop();

    // State queries
    bool          is_loaded() const { return loaded_; }
    ModelConfig   config() const { return config_; }
    MemoryBudget  memory() const { return budget_; }
    LiveStats     stats() const;

private:
    bool loaded_ = false;
    bool stop_flag_ = false;

    ModelConfig   config_;
    GenParams     gen_params_;
    MemoryBudget  budget_;

    // Memory pools (pre-allocated, never freed during inference)
    KVCachePool   kv_cache_;
    ScratchPool   scratch_;

    // Model weights (mapped from GGUF, pinned)
    void*         weights_ = nullptr;
    int64_t       weights_size_ = 0;

    // CUDA
    cudaStream_t  stream_ = nullptr;
    cudaGraph_t   decode_graph_ = nullptr;
    cudaGraphExec_t decode_graph_exec_ = nullptr;
    bool          graph_captured_ = false;

    // Internal
    bool prefill(const std::vector<int>& tokens);
    int  decode_step(int pos);        // returns token id
    void build_cuda_graph(int pos);   // capture decode step as graph
    bool check_memory_and_thermal(int pos);
};

// ── GGUF loader (minimal — only what we need) ────────────────────────────
// We don't use llama.cpp's full GGUF parser. We read:
//   - model config (n_layers, n_heads, etc.)
//   - weight tensors (mapped read-only)
//   - tokenizer vocab

ModelConfig load_gguf_config(const std::string& path);
bool        load_gguf_weights(const std::string& path, void** weights, int64_t* size);

}  // namespace jllm
