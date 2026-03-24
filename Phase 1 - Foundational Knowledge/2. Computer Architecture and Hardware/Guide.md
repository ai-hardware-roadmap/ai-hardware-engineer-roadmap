# Computer Architecture and Hardware

Phase 1, section 2 — how processors and memory systems work **in principle**, and what ships **in real machines** (client, workstation, and server). Use this as the single entry point; deeper material lives in the linked guides.

---

## 1. Architecture: ISA → microarchitecture → practice

**Theory and principles**

* **[Architecture_Guide.md](Architecture_Guide.md)** — Instruction sets, CPU design from single-cycle to pipelined execution, hazards, superscalar and out-of-order cores, caches and coherence, branch prediction, multi-core, and ISA case studies (ARM64, x86-64, RISC-V).

**Labs and projects**

* **[Labs_and_ProjectsGuide.md](Labs_and_ProjectsGuide.md)** — Verilog CPUs, pipeline forwarding, branch-predictor and cache simulators, coherence exercises, and capstone-style work.

**Depth, products, and security**

* **[Advanced_Topics_and_CaseStudies.md](Advanced_Topics_and_CaseStudies.md)** — Register-level ISA detail, Apple/AMD/Qualcomm-style case studies, speculative-execution security, TLBs, bandwidth, and profiling (roofline, Amdahl).

**Structured course path**

* **[README.md](README.md)** — Full overview, recommended week-by-week paths, and bibliography (Hennessy & Patterson, etc.).

---

## 2. Hardware platforms: what you buy and deploy

**Systems-level survey**

* **[Hardware_Platforms_Guide.md](Hardware_Platforms_Guide.md)** — Modern CPUs (Intel, AMD, Apple, Qualcomm, RISC-V momentum), memory (DDR5, ECC, unified memory), GPUs and NPUs, storage (NVMe, form factors), I/O and networking, power and thermals — oriented to laptops through data-center gear (including recent product generations through CES 2026 where noted).

---

## 3. How the two parts fit together

Read **Architecture_Guide** (and labs) when you need to explain *why* a cache miss, branch mispredict, or memory bottleneck hurts inference or training. Read **Hardware_Platforms_Guide** when you need to reason about *which* silicon, memory width, or interconnect you are actually targeting for edge AI, workstations, or servers.

**AI connection:** Accelerators and SoCs are still CPUs, memory hierarchies, and I/O; TinyML through data-center GPUs all inherit the same architectural limits — bandwidth, latency, and power — that these two tracks make explicit.
