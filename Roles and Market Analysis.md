# AI Hardware Engineering — Roles and Market Analysis

> *Job titles, salary ranges, work arrangement data, and hiring priorities — organized by sub-layer so you can target a specific niche, not just a broad layer.*

**Data basis:** US market, 2025–2026. Ranges reflect base salary + equity/bonus for FAANG-adjacent and well-funded startups. Adjust -20% to -30% for non-coastal or smaller companies.

---

## Layer Map — 8 Layers, 21 Sub-Layers

| Layer | Sub-Layer | Focus | Typical Roles |
|:-----:|:---------:|-------|---------------|
| **L1** | **L1a** Inference Optimization | Model optimization, profiling, quantization | ML Inference Engineer, AI Performance Engineer |
| | **L1b** Edge AI Deployment | On-device pipelines, Jetson/MCU, power-constrained | Edge AI Engineer, Embedded AI Engineer |
| | **L1c** AI Application | Vision, robotics, solutions engineering | CV Engineer, Robotics AI Engineer |
| **L2** | **L2a** Graph & IR Optimization | Fusion, memory planning, graph passes | DL Graph Optimization Engineer |
| | **L2b** Compiler Backend | LLVM, MLIR, code generation, custom targets | AI Compiler Engineer, GPU Compiler Engineer |
| | **L2c** Kernel Engineering | Triton, CUTLASS, Flash-Attention, hand-tuned kernels | Kernel Optimization Engineer, MTS Kernels |
| **L3** | **L3a** GPU/Accelerator Runtime | CUDA runtime, TensorRT execution, DLA scheduling | GPU Runtime Engineer, Inference Platform Engineer |
| | **L3b** Linux Kernel & Drivers | nvgpu, amdgpu, PCIe, DMA, IOMMU, device tree | Linux Kernel Engineer, Device Driver Engineer |
| | **L3c** HPC Infrastructure | NCCL, Slurm, K8s+GPU, GPUDirect, multi-node | Distributed Runtime Engineer, Resource Scheduler |
| **L4** | **L4a** Embedded Software | MCU, FreeRTOS, bare-metal, SPI/I2C/CAN | Embedded Software Engineer, RTOS Engineer |
| | **L4b** Embedded Linux & BSP | Yocto, L4T, kernel modules, OTA, rootfs | Embedded Linux Engineer, BSP Engineer |
| | **L4c** Automotive & IoT | ADAS firmware, ISO 26262, BLE/LoRa, cloud IoT | Automotive Embedded Engineer, IoT Engineer |
| **L5** | **L5a** Accelerator Architecture | Systolic arrays, dataflow, tensor core design | AI Accelerator Architect, GPU Architect |
| | **L5b** System & SoC Architecture | NoC, memory hierarchy, power domains, chiplet partitioning | SoC Architect, Memory Systems Architect |
| **L6** | **L6a** RTL Design | SystemVerilog datapaths, FSMs, IP implementation | RTL Design Engineer, ASIC Design Engineer |
| | **L6b** Design Verification | UVM, formal, constrained random, emulation | DV Engineer, Emulation Engineer |
| | **L6c** FPGA & HLS | Vivado, HLS, FPGA prototyping, timing closure | FPGA Engineer, HLS Engineer |
| **L7** | **L7a** Physical Design | P&R, floorplan, CTS, timing closure, signoff | Physical Design Engineer, STA Engineer |
| | **L7b** DFT & CAD | Scan insertion, ATPG, tool flow automation | DFT Engineer, CAD Engineer |
| **L8** | **L8a** Packaging & Process | CoWoS, chiplets, foundry interface, yield | Packaging Engineer, Process Engineer |
| | **L8b** Silicon Validation | Post-silicon bring-up, characterization, ATE | Validation Engineer, Test Engineer |

---

## L1a — Inference Optimization

**Focus:** Make ML models run faster — graph optimization, quantization, profiling, TensorRT/vLLM tuning.

| Title | What they do |
|-------|-------------|
| ML Inference Optimization Engineer | Graph-level optimization, TensorRT engine builds, INT8/FP8 quantization |
| AI Performance Engineer | Nsight profiling, roofline analysis, bottleneck identification |
| Applied ML Engineer (Inference) | Take research models to production with latency/throughput SLAs |

| Level | Total Comp (Top Tier) | Remote | Hybrid | Onsite |
|-------|----------------------|--------|--------|--------|
| Junior | $120K–$160K | 15% | 25% | 60% |
| Mid | $170K–$230K | 10% | 25% | 65% |
| Senior | $250K–$350K+ | 10% | 20% | 70% |

**Trending:** LLM inference optimization (TensorRT-LLM, vLLM) is pushing these roles toward L2 salary levels.

---

## L1b — Edge AI Deployment

**Focus:** Deploy inference on resource-constrained hardware — Jetson, Snapdragon, MCU, TinyML.

| Title | What they do |
|-------|-------------|
| Edge AI Deployment Engineer | Jetson/Snapdragon on-device inference, power/latency targets |
| Edge AI Engineer | Full pipeline: sensor → preprocess → inference → actuation |
| Embedded AI Engineer | TFLite Micro, TinyML on Cortex-M, ultra-low-power inference |

| Level | Total Comp (Top Tier) | Remote | Hybrid | Onsite |
|-------|----------------------|--------|--------|--------|
| Junior | $110K–$140K | 10% | 20% | 70% |
| Mid | $150K–$200K | 10% | 20% | 70% |
| Senior | $220K–$300K+ | 10% | 15% | 75% |

**Note:** Hardware access (cameras, sensors, dev kits) limits remote work.

---

## L1c — AI Application (CV / Robotics / Solutions)

**Focus:** Domain-specific AI deployment — vision, robotics, customer-facing solutions.

| Title | What they do |
|-------|-------------|
| Computer Vision Engineer (Edge AI) | Detection, segmentation, tracking on constrained devices |
| Robotics AI Engineer | Perception + planning on robot hardware (ROS 2, Jetson) |
| AI Application Engineer | SDK integration, demo systems, customer deployment |
| AI Solutions Engineer | Pre/post-sales technical, benchmark customer workloads |

| Level | Total Comp (Top Tier) | Remote | Hybrid | Onsite |
|-------|----------------------|--------|--------|--------|
| Junior | $110K–$145K | 15% | 25% | 60% |
| Mid | $160K–$220K | 10% | 25% | 65% |
| Senior | $240K–$320K+ | 10% | 20% | 70% |

---

## L2a — Graph & IR Optimization

**Focus:** Compiler front-end — graph passes, operator fusion, memory planning, layout transforms.

| Title | What they do |
|-------|-------------|
| DL Graph Optimization Engineer | Fusion passes, constant folding, memory planning, quantization insertion |
| AI Systems Compiler Engineer | Distributed graph partitioning, multi-device scheduling |
| Performance Compiler Engineer | Auto-tuning (BEAM search), roofline-guided pass selection |

| Level | Total Comp (Top Tier) | Remote | Hybrid | Onsite |
|-------|----------------------|--------|--------|--------|
| Junior | $150K–$200K | 5% | 10% | 85% |
| Mid | $230K–$320K | 2% | 10% | 88% |
| Senior | $350K–$480K+ | 1% | 10% | 89% |

---

## L2b — Compiler Backend (LLVM / MLIR / TVM)

**Focus:** Compiler infrastructure — IR design, lowering passes, instruction selection, code generation for GPU/NPU/TPU.

| Title | What they do |
|-------|-------------|
| AI Compiler Engineer | Full ML compiler: ONNX → IR → optimized target code |
| ML Compiler Backend Engineer | Target-specific codegen: NVPTX, AMDGPU, custom accelerator ISA |
| Compiler Engineer (LLVM/MLIR/TVM) | Framework-level: write passes, define dialects, implement lowering |
| GPU Compiler Engineer | GPU-specific: register allocation, occupancy, instruction scheduling |
| Code Generation Engineer | Custom NPU/TPU backend: ISA design, instruction selection, scheduling |

| Level | Total Comp (Top Tier) | Remote | Hybrid | Onsite |
|-------|----------------------|--------|--------|--------|
| Junior | $160K–$210K | 5% | 10% | 85% |
| Mid | $250K–$350K | 2% | 10% | 88% |
| Senior | $400K–$550K+ | 1% | 10% | 89% |

**Note:** Highest-paid sub-layer in the stack. Extreme scarcity — every AI chip startup needs one, few exist.

---

## L2c — Kernel Engineering

**Focus:** Hand-write or tune the actual GPU/accelerator kernels — Triton, CUTLASS, Flash-Attention, NCCL kernels.

| Title | What they do |
|-------|-------------|
| Kernel Optimization Engineer | Triton/CUTLASS kernel authoring, tiling, memory optimization |
| MTS Kernels (Member of Technical Staff) | Production attention/GEMM kernels for LLM training and inference |
| HPC Compiler Engineer | Vectorization, parallelization for scientific computing |

| Level | Total Comp (Top Tier) | Remote | Hybrid | Onsite |
|-------|----------------------|--------|--------|--------|
| Junior | $150K–$200K | 5% | 15% | 80% |
| Mid | $220K–$320K | 5% | 10% | 85% |
| Senior | $350K–$500K+ | 2% | 10% | 88% |

**Trending:** Flash-Attention, long-context kernels, FP8/FP4 — hottest kernel engineering area.

---

## L3a — GPU/Accelerator Runtime

**Focus:** Execution layer — CUDA runtime, TensorRT engine execution, DLA scheduling, memory management.

| Title | What they do |
|-------|-------------|
| GPU Runtime Engineer | CUDA runtime internals: streams, events, memory pools, context |
| Accelerator Runtime Engineer | Custom NPU/TPU runtime: command queue, buffer management |
| Inference Platform Engineer | TensorRT engine execution, Triton server, dynamic batching |
| CUDA Runtime Engineer | Driver API, module loading, JIT compilation, multi-context |

| Level | Total Comp (Top Tier) | Remote | Hybrid | Onsite |
|-------|----------------------|--------|--------|--------|
| Junior | $140K–$180K | 5% | 15% | 80% |
| Mid | $200K–$270K | 5% | 15% | 80% |
| Senior | $280K–$380K+ | 5% | 10% | 85% |

---

## L3b — Linux Kernel & Drivers

**Focus:** Kernel-space GPU/accelerator drivers, DMA, PCIe, IOMMU, interrupt handling.

| Title | What they do |
|-------|-------------|
| Linux Kernel Engineer (GPU/Drivers) | nvgpu, amdgpu, DRM, IOMMU/SMMU, memory-mapped I/O |
| Device Driver Engineer | PCIe/CXL endpoint driver, DMA engine, scatter-gather |
| Embedded Linux BSP Engineer | Yocto kernel customization, device tree, L4T, rootfs |

| Level | Total Comp (Top Tier) | Remote | Hybrid | Onsite |
|-------|----------------------|--------|--------|--------|
| Junior | $140K–$175K | 5% | 10% | 85% |
| Mid | $200K–$260K | 5% | 10% | 85% |
| Senior | $280K–$380K+ | 5% | 10% | 85% |

**Note:** GPU kernel driver engineers are extremely rare — compensation approaches L2 levels.

---

## L3c — HPC Infrastructure

**Focus:** Multi-GPU/multi-node systems — NCCL, Slurm, Kubernetes+GPU, GPUDirect, InfiniBand.

| Title | What they do |
|-------|-------------|
| Distributed Runtime Engineer | NCCL tuning, AllReduce overlap, multi-node communication |
| Resource Scheduler Engineer | Slurm, K8s GPU scheduling, MIG/MPS, multi-tenant GPU sharing |
| Parallel Computing Engineer | MPI+CUDA, GPUDirect RDMA, storage I/O optimization |
| Systems Software Engineer (AI) | Full-stack performance: CPU-GPU coordination, profiling, debugging |

| Level | Total Comp (Top Tier) | Remote | Hybrid | Onsite |
|-------|----------------------|--------|--------|--------|
| Junior | $145K–$185K | 10% | 20% | 70% |
| Mid | $210K–$280K | 10% | 20% | 70% |
| Senior | $300K–$400K+ | 10% | 15% | 75% |

**Note:** Most remote-friendly sub-layer in L3 — infrastructure work is often SSH-based.

---

## L4a — Embedded Software (MCU / RTOS)

**Focus:** Bare-metal and RTOS firmware on microcontrollers — the hardware-closest software layer.

| Title | What they do |
|-------|-------------|
| Embedded Software Engineer | ARM Cortex-M/R, FreeRTOS/Zephyr, SPI/I2C/UART/CAN drivers |
| Firmware Engineer (AI/Edge SoC) | Command processor firmware, DMA scheduling, power management |
| Real-Time Systems Engineer | Deterministic scheduling, deadline guarantees, PREEMPT_RT |
| Bootloader / UEFI Engineer | U-Boot, UEFI, secure boot chain, A/B partition management |

| Level | Total Comp (Top Tier) | Remote | Hybrid | Onsite |
|-------|----------------------|--------|--------|--------|
| Junior | $100K–$130K | 10% | 15% | 75% |
| Mid | $140K–$185K | 10% | 20% | 70% |
| Senior | $195K–$250K+ | 10% | 20% | 70% |

---

## L4b — Embedded Linux & BSP

**Focus:** Linux kernel customization, board support packages, Yocto, OTA, production images.

| Title | What they do |
|-------|-------------|
| Embedded Linux Engineer | Yocto/Buildroot, kernel config, systemd, rootfs optimization |
| BSP Engineer | Board bring-up, device tree, driver integration, HAL |
| Jetson Platform Engineer | L4T customization, JetPack, carrier board bring-up, SPE firmware |

| Level | Total Comp (Top Tier) | Remote | Hybrid | Onsite |
|-------|----------------------|--------|--------|--------|
| Junior | $105K–$135K | 10% | 20% | 70% |
| Mid | $150K–$200K | 10% | 20% | 70% |
| Senior | $210K–$270K+ | 10% | 20% | 70% |

---

## L4c — Automotive & IoT

**Focus:** Domain-specific firmware — ADAS safety standards, connected IoT, fleet management.

| Title | What they do |
|-------|-------------|
| Automotive Embedded Engineer (ADAS) | ISO 26262, AUTOSAR, ECU firmware, CAN/CAN-FD, functional safety |
| IoT Firmware Engineer | Low-power wireless (BLE, LoRa, Wi-Fi), OTA, cloud connectivity |
| Device Firmware Engineer | Storage controllers, NIC firmware, PCIe endpoint firmware |

| Level | Total Comp (Top Tier) | Remote | Hybrid | Onsite |
|-------|----------------------|--------|--------|--------|
| Junior | $105K–$140K | 15% | 20% | 65% |
| Mid | $150K–$200K | 15% | 20% | 65% |
| Senior | $210K–$275K+ | 10% | 20% | 70% |

**Note:** Automotive ADAS pays 15–25% premium due to ISO 26262 certification. IoT has most remote flexibility in L4.

---

## L5a — Accelerator Architecture

**Focus:** Define the compute engine — systolic arrays, dataflow, tensor core specs, PE design.

| Title | What they do |
|-------|-------------|
| AI Accelerator Architect | Systolic array dimensions, dataflow strategy, precision support |
| GPU Architect | SM/CU microarchitecture, warp scheduler, tensor core design |
| ML Systems Architect | Workload analysis → architecture decisions, hardware-software co-design |
| Performance Architect | Roofline modeling, bottleneck analysis, workload characterization |

| Level | Total Comp (Top Tier) | Remote | Hybrid | Onsite |
|-------|----------------------|--------|--------|--------|
| Mid (5+ yr) | $280K–$380K | 5% | 10% | 85% |
| Senior (8+ yr) | $400K–$550K+ | 2% | 10% | 88% |
| Principal/Fellow | $600K–$1M+ | 1% | 5% | 94% |

**Note:** No junior roles. Requires years of RTL + systems experience. Defines what gets built.

---

## L5b — System & SoC Architecture

**Focus:** Full-chip system design — NoC, memory hierarchy, I/O, power domains, chiplet partitioning.

| Title | What they do |
|-------|-------------|
| SoC Platform Engineer | Zynq/Versal PS-PL co-design, AXI interconnect, IP integration |
| Silicon Architect | Die floorplan, chiplet partitioning, power/thermal budgets |
| Memory Systems Architect | HBM controller, cache hierarchy, scratchpad design |
| Heterogeneous Computing Architect | CPU+GPU+NPU+DSP integration, coherency, shared memory |
| Edge AI Systems Architect | Power-constrained accelerator design (< 5W TDP) |

| Level | Total Comp (Top Tier) | Remote | Hybrid | Onsite |
|-------|----------------------|--------|--------|--------|
| Mid (5+ yr) | $260K–$360K | 5% | 10% | 85% |
| Senior (8+ yr) | $380K–$500K+ | 2% | 10% | 88% |

---

## L6a — RTL Design

**Focus:** Implement the architecture in synthesizable HDL — datapaths, controllers, interfaces.

| Title | What they do |
|-------|-------------|
| RTL Design Engineer | SystemVerilog implementation: PE arrays, FSMs, AXI interfaces |
| ASIC Design Engineer | Tape-out quality RTL, CDC handling, synthesis constraints |
| Logic Design Engineer | Combinational/sequential optimization, area/power trade-offs |
| SoC Integration Engineer | IP block integration, address maps, subsystem-level wiring |

| Level | Total Comp (Top Tier) | Remote | Hybrid | Onsite |
|-------|----------------------|--------|--------|--------|
| Junior | $140K–$180K | 2% | 10% | 88% |
| Mid | $200K–$280K | 2% | 10% | 88% |
| Senior | $300K–$400K+ | 1% | 10% | 89% |

---

## L6b — Design Verification

**Focus:** Prove the RTL is correct — UVM testbenches, formal, coverage, emulation.

| Title | What they do |
|-------|-------------|
| Design Verification Engineer | UVM constrained random, coverage-driven verification, assertions |
| Formal Verification Engineer | Property checking, equivalence checking for critical blocks |
| Emulation Engineer | Palladium/Zebu, run firmware on RTL at MHz for pre-silicon validation |

| Level | Total Comp (Top Tier) | Remote | Hybrid | Onsite |
|-------|----------------------|--------|--------|--------|
| Junior | $135K–$175K | 2% | 10% | 88% |
| Mid | $195K–$270K | 2% | 10% | 88% |
| Senior | $290K–$380K+ | 1% | 10% | 89% |

**Note:** Chronic shortage. DV engineers are ~40% of chip design staff. Always in demand.

---

## L6c — FPGA & HLS

**Focus:** FPGA prototyping, HLS-based accelerator design, Vivado/Quartus.

| Title | What they do |
|-------|-------------|
| FPGA Design Engineer | Vivado/Quartus, timing closure, IP integration, ILA debug |
| HLS Engineer | C/C++ to RTL (Vitis HLS), pragma optimization, dataflow |
| Hardware Design Engineer | General digital design on FPGA: interfaces, controllers |

| Level | Total Comp (Top Tier) | Remote | Hybrid | Onsite |
|-------|----------------------|--------|--------|--------|
| Junior | $125K–$160K | 5% | 15% | 80% |
| Mid | $175K–$240K | 5% | 10% | 85% |
| Senior | $250K–$340K+ | 2% | 10% | 88% |

**Note:** 10–15% lower than ASIC roles at the same level. More entry points for new grads.

---

## L7a — Physical Design

**Focus:** Synthesis, place & route, timing closure, power integrity, signoff.

| Title | What they do |
|-------|-------------|
| Physical Design Engineer | Floorplan, placement, CTS, routing, congestion management |
| STA Engineer | PrimeTime, setup/hold analysis, MCMM, OCV, timing ECOs |
| Power Integrity Engineer | IR drop, EM analysis, power grid design, DVFS planning |

| Level | Total Comp (Top Tier) | Remote | Hybrid | Onsite |
|-------|----------------------|--------|--------|--------|
| Junior | $130K–$165K | 1% | 5% | 94% |
| Mid | $180K–$250K | 1% | 5% | 94% |
| Senior | $260K–$360K+ | 1% | 5% | 94% |

---

## L7b — DFT & CAD

**Focus:** Test insertion, ATPG, tool flow automation, methodology.

| Title | What they do |
|-------|-------------|
| DFT Engineer | Scan insertion, ATPG, BIST, fault coverage optimization |
| CAD/EDA Engineer | Tool flow scripts, methodology, custom EDA automation |
| Layout Engineer | Standard cell placement, DRC/LVS clean, metal optimization |

| Level | Total Comp (Top Tier) | Remote | Hybrid | Onsite |
|-------|----------------------|--------|--------|--------|
| Junior | $120K–$150K | 1% | 5% | 94% |
| Mid | $165K–$230K | 1% | 5% | 94% |
| Senior | $240K–$330K+ | 1% | 5% | 94% |

---

## L8a — Packaging & Process

**Focus:** Advanced packaging, foundry interface, yield, process selection.

| Title | What they do |
|-------|-------------|
| Packaging Engineer | CoWoS, EMIB, Foveros, chiplet integration, substrate design |
| Process Integration Engineer | Foundry relationship, process node selection, yield optimization |
| Reliability Engineer | Burn-in, electromigration, thermal cycling, qualification |
| Supply Chain Engineer | Wafer allocation, lead time, foundry contracts |

| Level | Total Comp (Top Tier) | Remote | Hybrid | Onsite |
|-------|----------------------|--------|--------|--------|
| Junior | $120K–$155K | 1% | 5% | 94% |
| Mid | $170K–$235K | 1% | 5% | 94% |
| Senior | $240K–$330K+ | 1% | 5% | 94% |

---

## L8b — Silicon Validation

**Focus:** Post-silicon bring-up, characterization, ATE programming, production test.

| Title | What they do |
|-------|-------------|
| Post-Silicon Validation Engineer | First silicon bring-up, debug, speed/power characterization |
| Test Engineer | ATE programming, production test development, yield analysis |

| Level | Total Comp (Top Tier) | Remote | Hybrid | Onsite |
|-------|----------------------|--------|--------|--------|
| Junior | $115K–$150K | 1% | 5% | 94% |
| Mid | $165K–$225K | 1% | 5% | 94% |
| Senior | $235K–$310K+ | 1% | 5% | 94% |

---

## Cross-Layer Summary

### Compensation by Sub-Layer (Senior, Top-Tier Total Comp)

| Sub-Layer | Senior Total Comp | Scarcity | Demand Trend |
|:---------:|------------------|:--------:|:------------:|
| L1a Inference Optimization | $250K–$350K+ | Medium | Growing (LLM) |
| L1b Edge AI | $220K–$300K+ | Medium | Stable |
| L1c AI Application | $240K–$320K+ | Low-Medium | Stable |
| **L2a Graph/IR** | **$350K–$480K+** | **High** | **Surging** |
| **L2b Compiler Backend** | **$400K–$550K+** | **Very High** | **Surging** |
| **L2c Kernel Engineering** | **$350K–$500K+** | **Very High** | **Surging** |
| L3a GPU Runtime | $280K–$380K+ | High | Growing |
| L3b Kernel/Drivers | $280K–$380K+ | High | Growing |
| L3c HPC Infrastructure | $300K–$400K+ | Medium-High | Growing |
| L4a Embedded Software | $195K–$250K+ | Medium | Stable (huge volume) |
| L4b Embedded Linux/BSP | $210K–$270K+ | Medium | Stable |
| L4c Automotive/IoT | $210K–$275K+ | Medium | Growing (ADAS) |
| **L5a Accelerator Arch** | **$400K–$550K+** | **Extreme** | **Surging** |
| L5b System/SoC Arch | $380K–$500K+ | Extreme | Surging |
| L6a RTL Design | $300K–$400K+ | High | Growing |
| L6b Verification | $290K–$380K+ | High (chronic) | Growing |
| L6c FPGA/HLS | $250K–$340K+ | Medium | Stable |
| L7a Physical Design | $260K–$360K+ | High | Growing (advanced nodes) |
| L7b DFT/CAD | $240K–$330K+ | Medium | Stable |
| L8a Packaging/Process | $240K–$330K+ | Medium-High | Growing (chiplets) |
| L8b Silicon Validation | $235K–$310K+ | Medium | Stable |

### Work Arrangement Summary

| Work Mode | Software-Heavy (L1–L3) | Hardware-Heavy (L4–L8) |
|-----------|----------------------|----------------------|
| **Remote** | 5–15% | 1–10% |
| **Hybrid** | 10–25% | 5–20% |
| **Onsite** | 60–85% | 70–94% |

---

## Hiring Priority for an AI Chip Startup

| Hire # | Sub-Layer | Role | Why this order |
|:------:|:---------:|------|---------------|
| 1 | L5a | AI Accelerator Architect | Defines the chip — everything else follows |
| 2 | L2b | AI Compiler Engineer | Software must co-design with hardware from day 1 |
| 3 | L6a | RTL Design Engineer (2–3x) | Implement the architect's design |
| 4 | L6b | DV Engineer (2–3x) | Verify correctness before tape-out |
| 5 | L2c | Kernel Optimization Engineer | Write reference kernels that prove the architecture works |
| 6 | L4a | Firmware Engineer | Command processor, bring-up software |
| 7 | L3a | Runtime Engineer | Host-side API and driver |
| 8 | L7a | Physical Design Engineer | Synthesis, P&R, timing closure |
| 9 | L1a | ML Inference Engineer | Benchmark against competition |
| 10 | L8a | Packaging Engineer | Engage foundry, plan packaging |

**Estimated first-year cost (10 hires, mid/senior): $3M–$5M** salary + equity

---

## Where This Roadmap Takes You

| Roadmap Completion | Sub-Layers You Can Target | Expected Level |
|-------------------|--------------------------|:--------------:|
| Phase 1–3 | L1a, L1b, L1c | Junior |
| Phase 1–3 + Phase 4B | L4a, L4b, L1b | Junior–Mid |
| Phase 1–3 + Phase 4C | L2a, L2c | Junior |
| Phase 1–3 + Phase 4A | L6c (FPGA) | Junior |
| Phase 1–4 (all tracks) | L1a–L4c (any software sub-layer) | Mid |
| Phase 1–4 + Phase 5F | L5a, L5b, L6a, L6b | Mid |
| Phase 1–5 (full roadmap) | **Any sub-layer L1a–L6c** | Mid–Senior |
