# jetson-llm

Memory-first LLM inference runtime for NVIDIA Jetson Orin.

**Target hardware:** Orin Nano Super 8 GB (SM 8.7, 102 GB/s, 77 TOPS)
**Not supported:** x86, discrete GPUs, Windows, macOS — Jetson only.

## Why

Existing runtimes are not designed for 8 GB unified memory:

- **llama.cpp** — portable but generic CUDA kernels, no Jetson memory awareness
- **TensorRT-LLM** — fast but heavy, designed for datacenter A100/H100
- **jetson-llm** — memory-first, power-aware, Orin-tuned kernels, zero-allocation inference

## Features

- **Memory budget tracking** — knows where every MB goes (OS, CMA, CUDA, model, KV, scratch)
- **OOM guard** — checks real free memory before every KV extension, stops gracefully
- **KV cache tiering** — fast pinned pool + overflow to unpinned (still zero-copy on unified mem)
- **Scratch pool** — pre-allocated, bump allocator, no malloc during inference
- **Orin-tuned kernels** — SM 8.7 tile sizes (32x64), fused ops, INT4 dequant-fused GEMV
- **Power-aware** — reads nvpmodel, adapts to 7W/10W/15W/25W modes
- **Thermal throttling** — backs off before hardware throttles
- **CUDA graphs** — near-zero kernel launch overhead for decode loop
- **OpenAI-compatible API** — REST + streaming SSE

## Build

```bash
cmake -B build \
    -DGGML_CUDA=ON \
    -DCMAKE_CUDA_ARCHITECTURES="87" \
    -DCMAKE_BUILD_TYPE=Release
cmake --build build -j$(nproc)
```

## Run

```bash
# Single prompt
./build/jetson-llm -m models/Llama-3.2-3B-Q4_K_M.gguf -p "Hello, Jetson"

# Interactive chat
./build/jetson-llm -m models/Llama-3.2-3B-Q4_K_M.gguf -i

# API server
./build/jetson-llm-server -m models/Llama-3.2-3B-Q4_K_M.gguf -p 8080
```

## Architecture

```
Memory Manager (budget, OOM guard, KV pool, scratch pool)
       │
Engine (GGUF loader, prefill, decode, sampling)
       │
CUDA Kernels (gemv_q4, fused_rmsnorm, flash_attention, rope, swiglu)
       │
Jetson HAL (power mode, thermal, sysfs, live stats)
```

## License

MIT
