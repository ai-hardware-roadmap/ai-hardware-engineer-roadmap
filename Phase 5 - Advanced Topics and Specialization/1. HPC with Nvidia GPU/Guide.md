# 1. HPC with Nvidia GPU (Phase 5 Track C)

**Timeline:** 12–24 months (fundamentals and deep dives); 24–48 months for advanced phase.

---

## Basic concepts: what “HPC with Nvidia GPU” means

**HPC** = high-performance computing: solving problems that need massive compute and memory by using many machines (or many GPUs) working together. In AI, “HPC” usually means **large-scale training** and **high-throughput inference** on GPU clusters, not single workstations.

**Why Nvidia GPUs?** Nvidia GPUs are the dominant hardware for training and deploying large models. They offer the best-supported software stack: **CUDA** (programming model and runtime), **cuDNN** and **CUTLASS** (high-performance kernels — cuDNN for conv/RNN/attention; CUTLASS for customizable GEMM, matrix multiply, and epilogue fusion used by frameworks and custom kernels), **TensorRT** (inference optimization and deployment), and **NCCL** (multi-GPU collectives). Add the fastest inter-GPU links (NVLink, NVSwitch) and the architectures (Hopper, Blackwell) that ML frameworks target first, and you see why AI infrastructure and kernel-level optimization work almost always involves Nvidia GPUs in data centers.

**What this track covers:**

* **Single GPU → many GPUs** — From one GPU (e.g. Jetson, which you saw in Phase 4) to **multi-GPU nodes** and **multi-node clusters**. You need to understand how jobs are placed, how data and gradients move, and how to avoid communication becoming the bottleneck.
* **Two main workloads:**
    * **Training** — One big model, one big dataset; you split work across GPUs (data parallelism, model parallelism, pipeline parallelism). Performance is about throughput (samples/sec) and scaling to hundreds or thousands of GPUs.
    * **Inference** — Many requests, one (or many) deployed model; you care about latency and throughput under load. At scale this means batching, KV-cache, and often multi-GPU or multi-node serving (e.g. TensorRT-LLM, vLLM).
* **The stack you must understand:**
    * **Hardware:** GPUs (A100, H100/H200, L40S, etc.), NVLink/NVSwitch inside a node, InfiniBand or Ethernet across nodes.
    * **Software:** CUDA, drivers, containers (NGC), orchestrators (Slurm, Kubernetes), and collective libraries (NCCL) for multi-GPU communication.
    * **Storage and I/O:** Getting data to GPUs fast (dataloaders, GPUDirect Storage, high-throughput disks) so the GPU is not waiting.

**Why “Setup” and “DL Inference Optimization” as two parts?**

* **HPC Setup** — How to *run* and *operate* GPU clusters: provisioning, virtualization, networking, storage, job scheduling, and advanced CUDA/distributed training. You learn the environment and the performance model (where time is spent: compute vs communication vs I/O).
* **DL Inference Optimization** — How to *optimize* inference itself: graph and operator optimization, writing and tuning kernels (Triton, CUTLASS, attention), compilers, quantization, and production runtimes (TensorRT-LLM, vLLM). This is where you push single-request latency and throughput to the limit.

Together they cover both **infrastructure** (getting the cluster and the workload running correctly and at scale) and **optimization** (getting the most out of each GPU and each request). Read the [Basic concepts in DL Inference Optimization](./DL%20Inference%20Optimization/Guide.md#basic-concepts-read-this-first) for the inference-side vocabulary (batching, KV-cache, speculative decoding, etc.) before or in parallel with the inference units.

### Key terms (used in this track)

*Order: basic ops → attention → distributed.*

| Term | Meaning |
|------|--------|
| **Matrix multiply** | Compute A×B for matrices A, B (often plus bias or activation). The core operation in linear layers and most heavy compute. "GEMM" is the standard name in libraries. |
| **GEMM** | **G**eneral **E**lement-wise **M**atrix **M**ultiply: C = α·(A×B) + β·C. The BLAS/cuBLAS/CUTLASS interface for matrix multiply. GPU GEMM kernels (tiling, tensor cores) dominate training and inference time. |
| **Epilogue fusion** | In a GEMM kernel, the **epilogue** is what you do with the result (add bias, ReLU/GELU, write to memory). **Fusion** = doing that in the *same* kernel as the multiply. Saves memory bandwidth and launch overhead; CUTLASS and similar libraries support it. |
| **Attention** | In transformers: each token produces **queries (Q)**, **keys (K)**, and **values (V)** via linear layers; then *attention* = softmax(Q×Kᵀ/√d)·V. It lets the model focus on relevant tokens. The Q×Kᵀ matmul and the subsequent ×V are heavy (especially for long sequences), so **attention kernels** (e.g. FlashAttention) and **KV-cache** optimization are central to fast LLM training and inference. |
| **GEMM** | **G**eneral **E**lement-wise **M**atrix **M**ultiply: compute C = α·(A×B) + β·C for matrices A, B, C and scalars α, β. The core math behind linear layers, attention projections, and most heavy compute in deep learning. GPU kernels for GEMM are highly optimized (tiling, tensor cores) and dominate training/inference time. |
| **Matrix multiply** | Same as GEMM in practice: A×B (and often add bias or apply an activation). “Matrix multiply” is the operation; “GEMM” is the standard name in libraries (BLAS, cuBLAS, CUTLASS). |
| **Epilogue fusion** | In a GEMM kernel, the **epilogue** is what you do with the result (e.g. add bias, apply ReLU/GELU, or write to memory). **Epilogue fusion** = doing that in the same kernel as the multiply, instead of a separate kernel. Saves memory bandwidth and launch overhead (one kernel instead of two or more). CUTLASS and similar libraries let you fuse bias, activation, and sometimes normalization into the GEMM epilogue. |
| **KV-cache** | In transformer attention: keys and values for previous tokens are cached so you don’t recompute them. **KV-cache** = that cache. Long context → huge cache → memory and bandwidth become the bottleneck; paging/sharding and efficient kernels matter. |
| **Data / model / pipeline parallelism** | **Data parallelism:** same model on every GPU, different data; sync gradients (e.g. AllReduce). **Model parallelism:** split the model across GPUs (e.g. different layers). **Pipeline parallelism:** different layers on different GPUs, pass activations in a pipeline to keep all GPUs busy. |
| **NCCL** | **N**vidia **C**ollective **C**ommunications **L**ibrary. Implements multi-GPU collectives (AllReduce, AllGather, ReduceScatter, etc.) used in distributed training and sometimes inference. Often the bottleneck at scale. |
| **NVLink / NVSwitch** | **NVLink:** high-bandwidth link between GPUs (and CPU) inside a node. **NVSwitch:** switch that connects many GPUs in one node so they can all talk at full speed. Much faster than PCIe for GPU–GPU traffic. |
| **Collectives** | Operations that involve many GPUs (or processes) together: e.g. **AllReduce** (everyone has the same sum), **AllGather** (everyone gets all pieces), **ReduceScatter**. Used to sync gradients (data parallel) or to exchange activations (model/pipeline parallel). |

---

## This track has two parts

| Part | Description | Guide |
|------|--------------|-------|
| **HPC Setup** | Fundamentals, virtualization, interconnects, advanced CUDA/distributed training/performance — plus hardware-specific deep dives (8x H200, L40S, NCCL, CUDA Advanced, GPUDirect Storage) | [HPC Setup →](./HPC%20Setup/Guide.md) |
| **DL Inference Optimization** | Graph/ops, kernel engineering (Triton, CUTLASS, Flash-Attention), compiler (IR, BEAM), quantization, runtimes. *MTS Kernels–style roles.* | [DL Inference Optimization →](./DL%20Inference%20Optimization/Guide.md) |

---

## How to use this track

1. **Start with [HPC Setup](./HPC%20Setup/Guide.md)** — Covers Nvidia GPU HPC fundamentals, virtualization (vGPU, KVM), interconnects and storage (InfiniBand, GDS, Slurm, Kubernetes), and Phase 2 advanced topics (advanced CUDA, distributed training, performance modeling). Use the deep dives (8x H200, L40S, NCCL, CUDA Advanced, GDS) for your target hardware and stack.
2. **Add [DL Inference Optimization](./DL%20Inference%20Optimization/Guide.md)** — For kernel/inference optimization (e.g. MTS Kernels, DL Inference Optimization Engineer), work through the six units in order: graph/ops → kernels → compiler → quantization → runtimes → tinygrad.

**Prerequisite:** Phase 4 (Jetson, TensorRT, CUDA) is assumed for both parts.
