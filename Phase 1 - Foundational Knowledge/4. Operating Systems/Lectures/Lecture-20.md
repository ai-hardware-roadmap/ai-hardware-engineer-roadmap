# Lecture 20: PCIe, NVMe & GPU Driver Architecture

## PCIe Topology

PCIe (Peripheral Component Interconnect Express) is the standard high-speed interconnect for GPUs, NVMe SSDs, FPGAs, and NICs in AI hardware systems.

**Hierarchy**: Root Complex (CPU/SoC) → Root Ports → PCIe Switches → Endpoints (GPU, NVMe, NIC, FPGA)

**Lane bandwidth** by generation (per lane, each direction):

| Generation | Transfer rate | x16 bandwidth (bidirectional) |
|---|---|---|
| Gen3 | 8 GT/s (~1 GB/s/lane) | ~32 GB/s |
| Gen4 | 16 GT/s (~2 GB/s/lane) | ~64 GB/s |
| Gen5 | 32 GT/s (~4 GB/s/lane) | ~128 GB/s |

### PCIe Device Discovery

During boot, BIOS/firmware walks the bus hierarchy via configuration cycles. Each device exposes a **config space**:

- Standard (256 B): Vendor ID, Device ID, Command, Status, Revision, Class Code
- Extended (4 KB): PCIe capabilities linked list (MSI-X, AER, SR-IOV, etc.)
- Kernel reads config space via `/sys/bus/pci/devices/0000:01:00.0/config`

### Base Address Registers (BARs)

BARs declare what memory and I/O regions a device needs. The kernel allocates physical addresses and programs them during PCI enumeration.

- Kernel maps BAR into virtual address space via `ioremap()`; accessed with `readl()`/`writel()`
- **GPU BAR0**: device registers and control (16 MB–256 MB)
- **GPU BAR1**: VRAM aperture (CPU-accessible window into GPU framebuffer; up to full VRAM on recent GPUs with Resizable BAR / SAM)

### PCIe DMA

Devices perform DMA to system RAM as bus masters. The kernel provides `dma_map_sg()` for scatter-gather mappings. The IOMMU translates bus addresses to physical addresses, providing isolation and protection.

### PCIe Peer-to-Peer (P2P)

Devices on the same PCIe switch can DMA directly to each other without data transiting system RAM:

- Requires `pci_p2pmem_alloc_sgl()` and IOMMU bypass or ACS (Access Control Services) disabled
- GPUDirect Storage uses P2P: NVMe SSD → GPU memory without CPU involvement
- FPGA → GPU inference pipeline: FPGA posts results directly to GPU buffers

## NVMe

NVMe (Non-Volatile Memory Express) is the PCIe-native storage protocol designed for flash SSDs.

- **Latency**: ~100 µs (vs ~5 ms for SATA SSD, ~5–10 ms for HDD)
- **Queue depth**: up to 64K queues × 64K commands per queue
- **MSI-X**: one interrupt vector per queue; queues mapped to CPU cores for NUMA efficiency
- **Namespace**: logical drive abstraction; supports multiple namespaces per controller
- **ZNS (Zoned Namespaces)**: divide SSD into sequential-write zones; reduces write amplification for log workloads

### NVMe Linux Driver Stack

- `nvme_core.ko` + transport module (`nvme.ko` for PCIe, `nvme-rdma.ko` for NVMe-oF)
- `blk-mq`: multi-queue block layer; per-CPU software queues map to NVMe hardware queues
- `io_uring` or `libaio` submit directly to blk-mq; bypass page cache with `O_DIRECT`

## GPU Driver Architecture (NVIDIA)

### Kernel-Mode Driver (KMD)

`nvidia.ko` is the kernel-mode driver responsible for:

- PCIe device initialization, BAR mapping, firmware load
- GPU memory management (VRAM allocation, page table setup)
- UVM (Unified Virtual Memory): migrate pages between CPU and GPU on demand
- Context scheduling: time-share GPU across multiple processes
- MSI-X interrupt handling for completion events
- GSP-RM (GPU System Processor Resource Manager): since Ampere/Ada, firmware runs on the GPU's internal ARM core; `nvidia.ko` communicates with GSP via RPC

### User-Mode Driver (UMD)

`libcuda.so` is the CUDA user-mode driver:

- Communicates with `nvidia.ko` via `ioctl()` on `/dev/nvidia0`, `/dev/nvidiactl`, `/dev/nvidia-uvm`
- Manages CUDA contexts, streams, and events in userspace
- NVCC compiles CUDA C++ → PTX (portable assembly) → SASS (GPU ISA) via `ptxas`

### Device Nodes

| Node | Purpose |
|---|---|
| `/dev/nvidia0` | Per-GPU: context creation, memory allocation |
| `/dev/nvidiactl` | Global: device enumeration, capability query |
| `/dev/nvidia-uvm` | Unified Virtual Memory: managed memory, prefetch |
| `/dev/nvidia-modeset` | Display output (DRM/KMS via `nvidia-drm.ko`) |

### CUDA Execution Model

- **Context**: per-process GPU state; one context per device per process by default
- **Stream**: in-order command queue within a context; multiple streams enable overlap of compute and memory transfer
- **Event**: synchronization primitive; `cudaEventRecord()` / `cudaStreamWaitEvent()`

## Open-Source GPU Drivers

| Driver | GPU | Status | Userspace |
|---|---|---|---|
| `amdgpu` | AMD RDNA/CDNA | Fully open (driver + firmware) | `mesa` (ROCm, OpenGL, Vulkan) |
| `i915` | Intel | Fully open | `mesa` |
| `nouveau` | NVIDIA | Reverse-engineered; limited perf | `mesa` (no CUDA) |
| `nvidia-open` | NVIDIA (Turing+) | Open KMD; proprietary firmware | CUDA (same as proprietary) |

All open drivers use the Linux **DRM (Direct Rendering Manager)** subsystem. DRM provides the kernel framework for GPU command submission, GEM buffer objects, and KMS (Kernel Mode Setting) for display.

## FPGA as PCIe Endpoint

Xilinx/AMD XDMA IP core exposes FPGA as a PCIe DMA device:

- H2C (Host-to-Card) and C2H (Card-to-Host) DMA channels
- Device nodes: `/dev/xdma0_h2c_0`, `/dev/xdma0_c2h_0`
- Write bitstream via PCIe during runtime reconfiguration (partial reconfiguration)
- PCIe P2P: FPGA can DMA directly to GPU buffer for post-processing pipelines

## Summary

| Component | Interface | Latency | Bandwidth | Kernel driver |
|---|---|---|---|---|
| GPU (A100) | PCIe Gen4 x16 | ~1 µs (DMA) | ~64 GB/s | `nvidia.ko` |
| NVMe SSD | PCIe Gen4 x4 | ~100 µs | ~7 GB/s | `nvme.ko` |
| FPGA (XDMA) | PCIe Gen3/4 x8 | ~5 µs (DMA) | ~16–32 GB/s | `xdma.ko` |
| NIC (100 GbE) | PCIe Gen4 x16 | ~1 µs | ~12 GB/s | `mlx5_core.ko` |
| GPU (P2P to NVMe) | PCIe switch | ~100 µs | PCIe switch BW | GPUDirect Storage |

## AI Hardware Connection

- GPU BAR0 register mapping via `ioremap()` is the foundation of every CUDA context; `nvidia.ko` programs GPU page tables through this interface
- GPUDirect Storage uses PCIe P2P to stream dataset batches from NVMe directly into GPU HBM without CPU involvement, eliminating a critical bottleneck in training pipelines
- PCIe P2P between FPGA and GPU enables real-time pre-processing (e.g., radar signal processing on FPGA → feature tensors in GPU memory) with no CPU in the data path
- The XDMA driver exposes FPGA H2C/C2H channels as character devices; inference accelerator prototypes commonly use this interface for tensor transfer
- `nvidia.ko` ioctl paths are how every CUDA API call ultimately reaches the GPU; understanding them is necessary for profiling and debugging anomalous CUDA launch latency
- MSI-X per-queue interrupts on NVMe (and per-stream on GPU) allow pinning completion interrupts to specific CPU cores, eliminating cross-NUMA interrupt overhead in multi-GPU servers
