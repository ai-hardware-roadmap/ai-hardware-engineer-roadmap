// decode.cpp — Token generation loop (memory-first design)
//
// Key design: check memory and thermal BEFORE every token.
// Zero allocation during decode — everything uses pre-allocated pools.

#include "jllm_engine.h"
#include <chrono>
#include <unistd.h>

namespace jllm {

using Clock = std::chrono::high_resolution_clock;

Engine::Engine() {}

Engine::~Engine() {
    unload();
}

void Engine::unload() {
    if (decode_graph_exec_) { cudaGraphExecDestroy(decode_graph_exec_); decode_graph_exec_ = nullptr; }
    if (decode_graph_)      { cudaGraphDestroy(decode_graph_); decode_graph_ = nullptr; }
    if (stream_)            { cudaStreamDestroy(stream_); stream_ = nullptr; }
    kv_cache_.destroy();
    scratch_.destroy();
    if (weights_) { cudaFreeHost(weights_); weights_ = nullptr; }
    loaded_ = false;
    graph_captured_ = false;
}

bool Engine::load(const std::string& gguf_path, const GenParams& params) {
    gen_params_ = params;

    // Probe system memory
    budget_ = probe_system_memory();
    budget_.print();

    // Load model config from GGUF
    config_ = load_gguf_config(gguf_path);
    fprintf(stderr, "[engine] Model: %s, %d layers, %d heads, %d KV heads\n",
            config_.name.c_str(), config_.n_layers, config_.n_heads, config_.n_kv_heads);

    // Load weights into pinned memory
    if (!load_gguf_weights(gguf_path, &weights_, &weights_size_)) {
        fprintf(stderr, "[engine] Failed to load weights\n");
        return false;
    }
    budget_.model_mb = weights_size_ / (1024 * 1024);

    // Calculate max context from memory budget
    int kv_bytes = params.kv_int8 ? 1 : 2;
    int auto_context = budget_.max_context(
        config_.n_layers, config_.n_kv_heads, config_.head_dim, kv_bytes);

    int context = params.context_limit > 0 ? params.context_limit : auto_context;
    context = std::min(context, config_.max_seq_len);
    context = std::min(context, auto_context);  // never exceed what fits

    fprintf(stderr, "[engine] Context: %d tokens (auto-calculated from memory budget)\n", context);

    // Initialize KV cache
    KVCachePool::Config kv_cfg = {};
    kv_cfg.n_layers = config_.n_layers;
    kv_cfg.n_kv_heads = config_.n_kv_heads;
    kv_cfg.head_dim = config_.head_dim;
    kv_cfg.max_context = context;
    kv_cfg.overflow_context = context / 4;  // 25% overflow buffer
    kv_cfg.kv_type_bytes = kv_bytes;

    if (!kv_cache_.init(kv_cfg)) {
        fprintf(stderr, "[engine] Failed to allocate KV cache\n");
        return false;
    }
    budget_.kv_cache_mb = kv_cache_.capacity_bytes() / (1024 * 1024);

    // Initialize scratch pool
    int64_t scratch_size = (int64_t)config_.hidden_dim * 4 * sizeof(float);  // ~4× hidden_dim
    scratch_size = std::max(scratch_size, (int64_t)64 * 1024 * 1024);  // min 64 MB
    if (!scratch_.init(scratch_size)) {
        fprintf(stderr, "[engine] Failed to allocate scratch pool\n");
        return false;
    }
    budget_.scratch_mb = scratch_size / (1024 * 1024);

    // Create CUDA stream
    cudaStreamCreate(&stream_);

    budget_.print();
    loaded_ = true;
    return true;
}

bool Engine::check_memory_and_thermal(int pos) {
    // Memory check
    OOMGuard guard(256);
    if (!guard.can_extend(config_.kv_per_token_bytes(gen_params_.kv_int8 ? 1 : 2))) {
        fprintf(stderr, "\n[oom_guard] Stopping at token %d — %lld MB free\n",
                pos, guard.real_free_mb());
        return false;
    }

    // Thermal check
    auto ts = read_thermal();
    int backoff = thermal_backoff_us(ts);
    if (backoff > 0) {
        fprintf(stderr, "\n[thermal] %.1f°C — backing off %d ms\n",
                ts.gpu_temp_c, backoff / 1000);
        usleep(backoff);
    }

    return true;
}

GenStats Engine::generate(const std::string& prompt, const GenParams& params,
                          TokenCallback token_cb) {
    GenStats stats = {};
    stop_flag_ = false;

    // TODO: tokenize prompt (requires tokenizer implementation)
    // For now, placeholder
    std::vector<int> prompt_tokens;  // = tokenize(prompt);
    stats.prompt_tokens = prompt_tokens.size();

    // Prefill
    auto t0 = Clock::now();
    // TODO: prefill(prompt_tokens);
    auto t1 = Clock::now();
    stats.prompt_ms = std::chrono::duration<float, std::milli>(t1 - t0).count();
    if (stats.prompt_tokens > 0)
        stats.prompt_tok_per_sec = stats.prompt_tokens / (stats.prompt_ms / 1000.0f);

    // Decode loop
    auto t2 = Clock::now();
    int64_t peak_mem = 0;
    float peak_temp = 0;

    for (int i = 0; i < params.max_tokens && !stop_flag_; i++) {
        // Memory + thermal guard
        if (!check_memory_and_thermal(i)) {
            stats.oom_stops++;
            break;
        }

        scratch_.reset();  // reuse scratch for each step

        // TODO: decode one token
        // int token = decode_step(kv_cache_.used_tokens());

        // Track peaks
        int64_t free = OOMGuard(0).real_free_mb();
        int64_t used = budget_.total_mb - free;
        peak_mem = std::max(peak_mem, used);
        peak_temp = std::max(peak_temp, read_thermal().gpu_temp_c);

        stats.completion_tokens++;

        // Callback for streaming
        if (token_cb) {
            // TODO: detokenize and call
            // token_cb(detokenize(token), is_eos);
        }
    }

    auto t3 = Clock::now();
    stats.decode_ms = std::chrono::duration<float, std::milli>(t3 - t2).count();
    if (stats.completion_tokens > 0)
        stats.decode_tok_per_sec = stats.completion_tokens / (stats.decode_ms / 1000.0f);

    stats.peak_memory_mb = peak_mem;
    stats.peak_thermal_c = peak_temp;

    return stats;
}

void Engine::stop() {
    stop_flag_ = true;
}

LiveStats Engine::stats() const {
    auto s = read_live_stats();
    // Engine can overlay its own metrics
    return s;
}

}  // namespace jllm
