# Phase 3: Artificial Intelligence — The Workloads Your Hardware Must Run

> *Before you design hardware, you must deeply understand the software it accelerates.*

**Layer mapping:** **L1** (Application & Framework) — this entire phase teaches you what AI chips compute.

**Prerequisites:** Phase 1 (Digital Foundations — architecture, OS, C++/CUDA), Phase 2 (Embedded Systems — MCU, RTOS, Linux).

**What comes after:** Phase 4 Track A (deploy on FPGA), Track B (deploy on Jetson), Track C (compile for any hardware).

---

## Why This Phase Exists

Every decision in the 8-layer stack is driven by workload requirements:

- **L5 (Architecture):** Systolic array dimensions are chosen to match matrix sizes from real models
- **L2 (Compiler):** Fusion passes exist because Conv+BN+ReLU is the most common pattern in CNNs
- **L6 (RTL):** INT8 datapaths exist because quantized inference is 4x faster than FP32
- **L3 (Runtime):** TensorRT's engine builder exists because models need graph-level optimization

If you skip this phase, you'll design hardware without knowing what it needs to run. Phase 3 gives you the workload intuition that informs every hardware decision downstream.

---

## Module Map

| # | Module | What you learn | Why it matters for hardware |
|---|--------|---------------|---------------------------|
| **1** | [Neural Networks](1.%20Neural%20Networks/Guide.md) | MLPs, CNNs, training, backpropagation, loss functions, regularization | What accelerators compute — tensors, matrix multiply, activation functions |
| **2** | [Deep Learning Frameworks](2.%20Deep%20Learning%20Frameworks/Guide.md) | micrograd → PyTorch → tinygrad: autograd, ops, compiler pipeline | How software generates the workloads — the interface between models and hardware |
| **3** | [Computer Vision](3.%20Computer%20Vision/Guide.md) | Image processing, detection, segmentation, 3D vision, OpenCV | The perception workloads that drive edge AI and autonomous systems |
| **4** | [Sensor Fusion](4.%20Sensor%20Fusion/Guide.md) | Camera/LiDAR/IMU, Kalman filtering, BEVFusion, multi-object tracking | Multi-sensor pipelines — the real-world input to inference |
| **5** | [Edge AI and Model Optimization](5.%20Edge%20AI%20and%20Model%20Optimization/Guide.md) | Quantization, pruning, knowledge distillation, deployment pipeline | Making models hardware-friendly — the bridge to Phase 4 |

---

## Recommended Order

```
Module 1 (Neural Networks)
    ↓
Module 2 (Frameworks: micrograd → PyTorch → tinygrad)
    ↓
Module 3 (Computer Vision) ←→ Module 4 (Sensor Fusion)   [parallel or interleaved]
    ↓
Module 5 (Edge AI & Model Optimization)
    ↓
Phase 4 (deploy on real hardware)
```

Module 5 (Edge AI) is the bridge to Phase 4 — it teaches you how to compress and optimize models before deploying them on FPGA (Track A), Jetson (Track B), or through a compiler (Track C).

---

## How This Phase Connects to the 8-Layer Stack

| What you learn here | How it informs hardware design |
|--------------------|-----------------------------|
| Matrix multiply in neural networks | L5: systolic array dimensions, dataflow strategy |
| Conv2D, attention, pooling ops | L2: what the compiler must fuse and tile |
| Backpropagation and gradients | L1: training workloads for GPU clusters (Phase 5A/B) |
| Quantization (INT8, FP8) | L6: precision support in PE design, L2: quantization passes |
| Model computational graphs | L2: graph IR representation, fusion opportunities |
| Inference latency requirements | L3: runtime scheduling, L4: firmware command processor |
| Multi-sensor perception | L1: real workload complexity, L3: DMA/streaming pipelines |

---

## Reference Projects

| Project | Used in |
|---------|---------|
| **[micrograd](https://github.com/karpathy/micrograd)** | Module 2 — build autograd from scratch, understand backprop |
| **[tinygrad](https://github.com/tinygrad/tinygrad)** | Module 2 — trace from tensor ops to GPU kernels, study compiler pipeline |
| **[PyTorch](https://pytorch.org/)** | Module 1–5 — industry-standard framework for model development |
| **[OpenCV](https://opencv.org/)** | Module 3 — image processing, camera calibration, detection |

---

## Additional Resources

- [CMU AI Courses Reference](CMU-AI-Courses.md) — Carnegie Mellon AI, ML, and vision courses mapped to this roadmap

---

## Next

→ [**Phase 4 Track A — Xilinx FPGA**](../Phase%204%20-%20Track%20A%20-%20Xilinx%20FPGA/1.%20Xilinx%20FPGA%20Development/Guide.md) · [**Phase 4 Track B — Jetson**](../Phase%204%20-%20Track%20B%20-%20Nvidia%20Jetson/1.%20Nvidia%20Jetson%20Platform/Guide.md) · [**Phase 4 Track C — ML Compiler**](../Phase%204%20-%20Track%20C%20-%20ML%20Compiler%20and%20Graph%20Optimization/Guide.md)
