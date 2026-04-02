# AI Hardware Engineering — Roles and Market Analysis

> *Job titles, salary ranges, work arrangement data, and hiring priorities mapped to the 8-layer AI chip stack.*

**Purpose:** This document helps you (1) understand which roles exist at each layer, (2) benchmark compensation, (3) plan hiring for a chip startup, and (4) decide which layer to specialize in based on your career goals.

**Data basis:** US market, 2025–2026. Ranges reflect base salary + equity/bonus for FAANG-adjacent and well-funded startups. Adjust -20% to -30% for non-coastal or smaller companies. Remote percentages reflect current postings on LinkedIn, levels.fyi, and Greenhouse.

---

## L1 — Application Layer (Edge / HPC / Inference)

**Focus:** ML inference deployment, model optimization, on-device AI pipelines

**Curriculum path:** Phase 3 → Phase 4B + 4C Part 2 → Phase 5B/5C

### Job Titles

| Title | Specialization |
|-------|---------------|
| ML Inference Optimization Engineer | Model graph optimization, TensorRT, quantization, latency tuning |
| Edge AI Deployment Engineer | On-device inference (Jetson, Snapdragon, custom NPU), power/latency targets |
| Edge AI Engineer | End-to-end edge pipeline: sensor → preprocess → inference → actuation |
| AI Application Engineer (Edge) | Customer-facing deployment, SDK integration, demo systems |
| Computer Vision Engineer (Edge AI) | Detection, segmentation, tracking on resource-constrained devices |
| Robotics AI Engineer | Perception + planning on robot hardware (ROS 2, Jetson, FPGA) |
| AI Performance Engineer | Profiling (Nsight, perf), bottleneck analysis, throughput optimization |
| Applied ML Engineer (Inference) | Take research models to production inference with measurable SLAs |
| Embedded AI Engineer | ML on MCU/MPU (TFLite Micro, TinyML), ultra-low-power inference |
| AI Solutions Engineer (Edge/HPC) | Pre-sales/post-sales technical, benchmark customer workloads |

### Market Data (US, 2025–2026)

| Level | Base + Equity | Total Comp (Top Tier) | Remote | Hybrid | Onsite |
|-------|--------------|----------------------|--------|--------|--------|
| Junior (0–2 yr) | $105K–$135K | $120K–$160K | 15% | 20% | 65% |
| Mid (3–5 yr) | $135K–$180K | $170K–$230K | 10% | 25% | 65% |
| Senior (6+ yr) | $180K–$240K | $250K–$350K+ | 10% | 20% | 70% |

**Market notes:**
- Edge AI testing requires physical hardware access (cameras, sensors, dev kits), limiting remote work
- Highest demand: TensorRT optimization, Jetson deployment, real-time vision pipelines
- Growing: LLM inference optimization (TensorRT-LLM, vLLM) — these roles are trending toward L2 salary levels
- Companies hiring: NVIDIA, Qualcomm, comma.ai, Tesla, Amazon (Alexa/Ring), Apple (Neural Engine), startups (Hailo, Syntiant, Perceive)

---

## L2 — Compiler Layer (AI / HPC / Chip Design)

**Focus:** Graph optimization, IR lowering, kernel scheduling, code generation for accelerators

**Curriculum path:** Phase 4C → Phase 5B → Phase 5F

### Job Titles

| Title | Specialization |
|-------|---------------|
| AI Compiler Engineer | End-to-end ML compiler: graph IR → optimized kernels for GPU/NPU/TPU |
| ML Compiler Backend Engineer | Target-specific code generation (NVPTX, AMDGPU, custom accelerator) |
| Deep Learning Graph Optimization Engineer | Operator fusion, memory planning, layout optimization, quantization passes |
| Compiler Engineer (LLVM / MLIR / TVM) | Compiler infrastructure: passes, dialects, lowering, codegen |
| GPU Compiler Engineer | GPU-specific compilation: register allocation, instruction scheduling, occupancy |
| HPC Compiler Engineer | Scientific computing compilers: vectorization, parallelization, Fortran/C++ |
| Kernel Optimization Engineer | Triton, CUTLASS, Flash-Attention — hand-tuning kernels for peak hardware utilization |
| AI Systems Compiler Engineer | Distributed compilation, multi-device scheduling, pipeline parallelism |
| Code Generation Engineer (AI Accelerators) | Custom backend for startup NPU/TPU: ISA design, instruction selection |
| Performance Compiler Engineer | Auto-tuning, BEAM search, roofline-guided optimization |

### Market Data (US, 2025–2026)

| Level | Base + Equity | Total Comp (Top Tier) | Remote | Hybrid | Onsite |
|-------|--------------|----------------------|--------|--------|--------|
| Junior (0–2 yr) | $120K–$160K | $150K–$200K | 5% | 10% | 85% |
| Mid (3–5 yr) | $160K–$220K | $220K–$320K | 2% | 10% | 88% |
| Senior (6+ yr) | $220K–$300K | $350K–$500K+ | 1% | 10% | 89% |

**Market notes:**
- **Highest-paid layer** in the AI hardware stack — extreme scarcity of engineers who understand both compilers and hardware
- Almost entirely onsite: compiler engineers must collaborate daily with silicon architects (L5) and RTL teams (L6)
- Fastest-growing demand: MLIR dialect development for custom accelerators, torch.compile/Inductor, TVM BYOC
- Senior compiler engineers at NVIDIA, Google (XLA/TPU), Meta (Glow), AMD, and AI chip startups command $400K–$600K+ total comp
- Companies hiring: NVIDIA, Google, AMD, Intel, Meta, Apple, Cerebras, Groq, SambaNova, Tenstorrent, d-Matrix, every well-funded AI chip startup

---

## L3 — Runtime & Driver Layer (HPC / Systems)

**Focus:** Execution runtime, GPU/accelerator drivers, memory management, scheduling, DMA

**Curriculum path:** Phase 1 §3 → Phase 2 → Phase 4A §5 / Phase 4B §8 → Phase 5A

### Job Titles

| Title | Specialization |
|-------|---------------|
| GPU/Accelerator Runtime Engineer | CUDA runtime internals, stream scheduling, memory pools, context management |
| Inference Platform Engineer | TensorRT engine execution, Triton Inference Server, dynamic batching, model serving |
| Linux Kernel Engineer (GPU/Drivers) | nvgpu, amdgpu, DRM subsystem, IOMMU/SMMU, interrupt handling |
| Device Driver Engineer (GPU/AI) | PCIe/CXL drivers, DMA engines, memory-mapped I/O, device tree |
| Embedded Linux BSP Engineer | Yocto, PetaLinux, L4T, kernel customization, rootfs, OTA |
| CUDA Runtime Engineer | CUDA driver API, context management, module loading, JIT compilation |
| Distributed Runtime Engineer (HPC) | NCCL, NVSHMEM, MPI+CUDA, GPUDirect RDMA, multi-node scheduling |
| Parallel Computing Engineer | OpenMP, oneTBB, task scheduling, CPU-GPU coordination |
| Resource Scheduler Engineer (AI/HPC) | Slurm, Kubernetes + GPU, multi-tenant GPU sharing, MIG/MPS |
| Systems Software Engineer (AI Runtime) | Full-stack systems: profiling, debugging, performance analysis |

### Market Data (US, 2025–2026)

| Level | Base + Equity | Total Comp (Top Tier) | Remote | Hybrid | Onsite |
|-------|--------------|----------------------|--------|--------|--------|
| Junior (0–2 yr) | $130K–$160K | $150K–$190K | 5% | 15% | 80% |
| Mid (3–5 yr) | $160K–$210K | $210K–$280K | 5% | 15% | 80% |
| Senior (6+ yr) | $210K–$270K | $280K–$400K+ | 5% | 10% | 85% |

**Market notes:**
- Linux kernel engineers with GPU driver experience are extremely rare — they command premiums comparable to L2
- Strong demand for NCCL/distributed systems engineers as training clusters scale to 100K+ GPUs
- BSP engineers are foundational for every edge product (Jetson, custom SoC) — steady, reliable demand
- Moderate remote flexibility for infrastructure/scheduler roles; kernel/driver work is mostly onsite
- Companies hiring: NVIDIA, AMD, Intel, Meta (infra), Google (TPU runtime), Microsoft (Azure GPU), Qualcomm, every Jetson product company

---

## L4 — Firmware & OS Layer (Embedded / Edge / Automotive)

**Focus:** Bare-metal firmware, RTOS, bootloaders, hardware bring-up, on-chip control

**Curriculum path:** Phase 2 → Phase 4B §3/§4 → Phase 5E (Autonomous Vehicles)

### Job Titles

| Title | Specialization |
|-------|---------------|
| Firmware Engineer (AI/Edge SoC) | Command processor firmware, DMA scheduling, power management on AI chips |
| Embedded Software Engineer | ARM Cortex-M/R, FreeRTOS, bare-metal drivers, SPI/I2C/UART/CAN |
| Embedded Linux Engineer | Yocto/Buildroot, kernel modules, device tree, systemd, rootfs optimization |
| BSP Engineer (Board Support Package) | Board bring-up, driver development, hardware abstraction layer |
| IoT Firmware Engineer | Low-power wireless (BLE, LoRa, Wi-Fi), OTA updates, cloud connectivity |
| Automotive Embedded Engineer (ADAS) | ISO 26262, AUTOSAR, ECU firmware, CAN/CAN-FD, functional safety |
| Jetson / Edge AI Platform Engineer | L4T customization, JetPack, SPE firmware, carrier board bring-up |
| Bootloader / UEFI Engineer | U-Boot, UEFI, secure boot chain, A/B slot management |
| Device Firmware Engineer | Storage controllers, NIC firmware, PCIe endpoint firmware |
| Real-Time Systems Engineer (RTOS) | FreeRTOS, Zephyr, RT-Linux, deterministic scheduling, deadline guarantees |

### Market Data (US, 2025–2026)

| Level | Base + Equity | Total Comp (Top Tier) | Remote | Hybrid | Onsite |
|-------|--------------|----------------------|--------|--------|--------|
| Junior (0–2 yr) | $95K–$120K | $110K–$140K | 10% | 15% | 75% |
| Mid (3–5 yr) | $120K–$155K | $145K–$195K | 10% | 20% | 70% |
| Senior (6+ yr) | $155K–$195K | $200K–$260K+ | 10% | 20% | 70% |

**Market notes:**
- Lowest salary band in the AI hardware stack, but **highest job count** — embedded engineers are needed everywhere
- Hardware interaction (dev boards, oscilloscopes, JTAG) limits remote work
- Automotive ADAS roles pay 15–25% premium over general embedded due to safety certification requirements
- IoT roles have the most remote flexibility in this layer
- Growing: RISC-V firmware, Rust-based embedded (Embassy, RTIC), Zephyr RTOS
- Companies hiring: Tesla, comma.ai, Rivian, Cruise, NXP, STMicroelectronics, Texas Instruments, every hardware product company, defense contractors

---

## L5 — Hardware Architecture Layer (Chip / System Design)

**Focus:** Microarchitecture, accelerator design, memory hierarchy, NoC, system-level specification

**Curriculum path:** Phase 1 §2 → Phase 4A §2 → Phase 5F (AI Chip Design)

### Job Titles

| Title | Specialization |
|-------|---------------|
| AI Accelerator Architect | Systolic array design, dataflow architecture, tensor core specification |
| SoC Platform Engineer | Zynq/Versal PS-PL co-design, AXI interconnect, IP integration |
| Hardware Systems Architect (AI/HPC) | Full-chip architecture: compute, memory, I/O, power budget |
| GPU Architect | SM/CU microarchitecture, warp scheduler, tensor core, memory hierarchy |
| ML Systems Architect | Hardware-software co-design: workload analysis → architecture decisions |
| Silicon Architect (AI Chips) | Die floorplan, chiplet partitioning, power/thermal budgets |
| Performance Architect (AI Workloads) | Roofline modeling, bottleneck analysis, workload characterization |
| Heterogeneous Computing Architect | CPU + GPU + NPU + DSP integration, coherency, shared memory |
| Memory Systems Architect | HBM controller, cache hierarchy, scratchpad design, bandwidth optimization |
| Edge AI Systems Architect | Power-constrained accelerator architecture (< 5W TDP) |

### Market Data (US, 2025–2026)

| Level | Base + Equity | Total Comp (Top Tier) | Remote | Hybrid | Onsite |
|-------|--------------|----------------------|--------|--------|--------|
| Mid (5–8 yr) | $180K–$250K | $280K–$380K | 5% | 10% | 85% |
| Senior (8+ yr) | $250K–$350K | $400K–$550K+ | 2% | 10% | 88% |
| Principal/Fellow | $350K–$500K+ | $600K–$1M+ | 1% | 5% | 94% |

**Market notes:**
- **No junior roles** — architecture requires years of RTL + systems experience first
- Most strategic hires in a chip startup: the architect defines what gets built
- Principal/Fellow architects at NVIDIA, Google, Apple, and Intel are among the highest-paid individual contributors in tech
- Almost exclusively onsite — daily whiteboard sessions with RTL, verification, and physical design teams
- Companies hiring: NVIDIA, AMD, Intel, Apple, Google (TPU), Qualcomm, Cerebras, Groq, Tenstorrent, SambaNova, d-Matrix, Esperanto, every AI chip startup

---

## L6 — RTL & Logic Design Layer (Hardware Implementation)

**Focus:** Digital design, verification, synthesis, FPGA prototyping

**Curriculum path:** Phase 1 §1 → Phase 4A → Phase 5F

### Job Titles

| Title | Specialization |
|-------|---------------|
| RTL Design Engineer | SystemVerilog/Verilog microarchitecture implementation, datapaths, FSMs |
| FPGA Design Engineer | Vivado, Quartus, timing closure, IP integration, FPGA-based prototyping |
| ASIC Design Engineer | Tape-out-quality RTL, synthesis constraints, clock domain crossing |
| Design Verification Engineer | UVM testbenches, constrained random, coverage-driven verification, formal |
| Hardware Design Engineer (Digital) | General digital design: interfaces, controllers, data paths |
| SystemVerilog Engineer | Specialized in SystemVerilog design and verification |
| Logic Design Engineer | Combinational/sequential logic, area/power optimization |
| SoC Integration Engineer | IP block integration, bus interconnect, address maps, subsystem verification |
| HLS Engineer | C/C++ to RTL (Vitis HLS), dataflow optimization, pragma tuning |
| Emulation Engineer | Palladium, Zebu — run firmware on RTL at MHz speeds for pre-silicon validation |

### Market Data (US, 2025–2026)

| Level | Base + Equity | Total Comp (Top Tier) | Remote | Hybrid | Onsite |
|-------|--------------|----------------------|--------|--------|--------|
| Junior (0–2 yr) | $120K–$155K | $140K–$180K | 2% | 10% | 88% |
| Mid (3–5 yr) | $155K–$200K | $200K–$280K | 2% | 10% | 88% |
| Senior (6+ yr) | $200K–$260K | $280K–$380K+ | 1% | 10% | 89% |

**Market notes:**
- **Largest headcount** for any chip design team — RTL and verification are ~60% of engineering staff
- Verification engineers are in chronic shortage — demand consistently exceeds supply
- FPGA roles pay 10–15% less than ASIC roles at the same level
- Almost zero remote: lab access (emulation, FPGA boards), EDA tool licenses, and security requirements
- Growing: Chisel/SpinalHDL in startups, formal verification, AI-assisted RTL generation
- Companies hiring: NVIDIA, AMD, Intel, Apple, Qualcomm, Broadcom, Marvell, MediaTek, every semiconductor company and AI chip startup

---

## L7 — Physical Implementation (Back-End Design)

**Focus:** Synthesis, place & route, timing closure, power integrity, DRC/LVS

**Curriculum path:** Phase 5F (AI Chip Design — theory and OpenROAD labs)

### Job Titles

| Title | Specialization |
|-------|---------------|
| Physical Design Engineer | Place & route, floorplanning, clock tree synthesis, timing closure |
| STA Engineer (Static Timing Analysis) | PrimeTime, setup/hold analysis, MCMM, OCV, timing signoff |
| Power Integrity Engineer | IR drop analysis, EM analysis, power grid design, DVFS |
| DFT Engineer (Design for Test) | Scan insertion, ATPG, BIST, fault coverage |
| Layout Engineer | Standard cell placement, routing, DRC/LVS clean |
| CAD/EDA Engineer | Tool flow automation, methodology, custom EDA scripting |

### Market Data (US, 2025–2026)

| Level | Base + Equity | Total Comp (Top Tier) | Remote | Hybrid | Onsite |
|-------|--------------|----------------------|--------|--------|--------|
| Junior (0–2 yr) | $110K–$140K | $130K–$165K | 1% | 5% | 94% |
| Mid (3–5 yr) | $140K–$185K | $180K–$250K | 1% | 5% | 94% |
| Senior (6+ yr) | $185K–$240K | $250K–$350K+ | 1% | 5% | 94% |

**Market notes:**
- Requires access to expensive EDA tools (Synopsys, Cadence, Siemens) and foundry PDKs — security-sensitive
- Almost entirely onsite due to tool licensing, data security, and foundry NDA requirements
- Smaller team than RTL/DV but absolutely critical — one timing violation = broken chip
- Companies hiring: all semiconductor companies, ASIC design houses, foundry design centers

---

## L8 — Fabrication & Packaging

**Focus:** Foundry interface, advanced packaging, post-silicon validation, manufacturing

**Curriculum path:** Phase 5F (AI Chip Design — theory lectures on packaging and fabrication)

### Job Titles

| Title | Specialization |
|-------|---------------|
| Packaging Engineer | CoWoS, EMIB, Foveros, chiplet integration, substrate design |
| Process Integration Engineer | Foundry interface, process node selection, yield optimization |
| Post-Silicon Validation Engineer | First silicon bring-up, debug, characterization, speed binning |
| Test Engineer | ATE programming, production test, yield analysis |
| Reliability Engineer | Burn-in, electromigration, thermal cycling, qualification |
| Supply Chain Engineer (Semiconductor) | Foundry relationships, wafer allocation, lead time management |

### Market Data (US, 2025–2026)

| Level | Base + Equity | Total Comp (Top Tier) | Remote | Hybrid | Onsite |
|-------|--------------|----------------------|--------|--------|--------|
| Junior (0–2 yr) | $100K–$130K | $120K–$155K | 1% | 5% | 94% |
| Mid (3–5 yr) | $130K–$175K | $170K–$230K | 1% | 5% | 94% |
| Senior (6+ yr) | $175K–$230K | $230K–$320K+ | 1% | 5% | 94% |

**Market notes:**
- Smallest engineering team but highest financial risk — a packaging defect or yield problem can cost millions
- Post-silicon validation engineers are the first to touch real hardware — extremely hands-on
- Advanced packaging (CoWoS, chiplets) is the hottest growth area as Moore's Law slows
- Almost exclusively onsite: cleanroom access, lab equipment, foundry visits
- Companies hiring: TSMC, Samsung, Intel Foundry, ASE, Amkor, plus every company doing tape-outs

---

## Cross-Layer Summary

### Compensation by Layer (Senior, Total Comp, Top Tier)

| Layer | Senior Total Comp | Scarcity | Demand Trend |
|:-----:|------------------|----------|-------------|
| **L1** Application | $250K–$350K+ | Medium | Growing (LLM inference) |
| **L2** Compiler | $350K–$500K+ | **Very High** | **Surging** (every chip needs a compiler) |
| **L3** Runtime | $280K–$400K+ | High | Growing (multi-GPU, distributed) |
| **L4** Firmware | $200K–$260K+ | Medium | Stable (huge job count) |
| **L5** Architecture | $400K–$550K+ | **Extreme** | **Surging** (new chip startups) |
| **L6** RTL | $280K–$380K+ | High | Growing (AI chip wave) |
| **L7** Physical | $250K–$350K+ | High | Growing (advanced nodes) |
| **L8** Fab/Package | $230K–$320K+ | Medium-High | Growing (chiplets, CoWoS) |

### Work Arrangement Summary

| Work Mode | Range Across All Layers | Notes |
|-----------|------------------------|-------|
| **Onsite** | 65–94% | Hardware, EDA tools, and lab access drive onsite requirements |
| **Hybrid** | 5–25% | More common for software-heavy roles (L1, L3) |
| **Remote** | 1–15% | Mostly L1 (inference optimization) and L4 (IoT firmware) |

### Hiring Priority for an AI Chip Startup

If you're building a team from scratch, hire in this order:

| Hire # | Role | Layer | Why first |
|:------:|------|:-----:|-----------|
| 1 | AI Accelerator Architect | L5 | Defines the chip — everything else follows |
| 2 | AI Compiler Engineer | L2 | Software must co-design with hardware from day 1 |
| 3 | RTL Design Engineer (2–3) | L6 | Implement the architect's design |
| 4 | Design Verification Engineer (2–3) | L6 | Verify correctness before tape-out |
| 5 | Firmware Engineer | L4 | Build the command processor, bring-up software |
| 6 | Runtime Engineer | L3 | Build the host-side API and driver |
| 7 | Physical Design Engineer | L7 | Synthesis, P&R, timing closure |
| 8 | ML Inference Engineer | L1 | Benchmark against competition, optimize workloads |
| 9 | Packaging Engineer | L8 | Engage with foundry, plan packaging |

**Estimated first-year engineering cost (9 hires, mid/senior):** $2.5M–$4M salary + equity

---

## Where This Roadmap Takes You

| Roadmap Completion | Layer You Can Target | Expected Entry Level |
|-------------------|---------------------|---------------------|
| Phase 1–3 | L1 (Application) | Junior |
| Phase 1–3 + Phase 4B | L4 (Firmware), L1 (Edge AI) | Junior–Mid |
| Phase 1–3 + Phase 4C | L2 (Compiler) | Junior |
| Phase 1–3 + Phase 4A | L6 (FPGA/RTL) | Junior |
| Phase 1–4 (all tracks) | L1–L4 (any) | Mid |
| Phase 1–4 + Phase 5F | L5 (Architecture), L6 (ASIC RTL) | Mid |
| Phase 1–5 (full roadmap) | **Any layer L1–L6** | Mid–Senior |
