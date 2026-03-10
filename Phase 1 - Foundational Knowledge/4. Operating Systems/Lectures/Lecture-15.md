# Lecture 15: DMA, IOMMU & GPU Memory Management

## DMA: Direct Memory Access

DMA allows a device (NIC, NVMe controller, GPU PCIe DMA engine, camera ISP) to transfer data directly to or from system RAM without CPU participation in the data path. The CPU programs a descriptor specifying source address, destination address, transfer length, and flags; the device executes the transfer autonomously; completion is signaled via an interrupt or a status flag the driver polls.

Benefits: CPU is freed during bulk transfers; transfer latency overlaps with CPU computation; system throughput increases.

---

## Cache Coherency Problem

Modern CPUs cache data in L1/L2/L3. When a device writes to RAM (DMA write), the CPU may hold a stale cached copy. When a device reads from RAM (DMA read), the device may read stale data that the CPU has modified in cache but not yet written back. Two programming models address this:

### Coherent (Consistent) DMA

`dma_alloc_coherent(dev, size, &dma_handle, GFP_KERNEL)`

- Returns a physically contiguous CPU virtual address and a device-visible `dma_handle`
- Memory is marked non-cacheable (or managed by hardware coherency fabric on some SoCs)
- CPU and device always see the same data; no explicit synchronization required
- CPU accesses are slower (uncached); use for control rings, descriptor tables, small status registers

### Streaming (Non-Coherent) DMA

CPU uses cached memory; driver explicitly synchronizes:

```c
/* CPU writes data, then hands to device */
dma_addr_t dma = dma_map_single(dev, cpu_ptr, size, DMA_TO_DEVICE);
/* submit descriptor to device hardware */
/* ... device performs DMA transfer ... */
dma_unmap_single(dev, dma, size, DMA_TO_DEVICE);
/* now safe to reuse cpu_ptr */
```

`dma_map_single()` flushes CPU cache lines covering the buffer (DMA_TO_DEVICE) or invalidates them (DMA_FROM_DEVICE). `dma_unmap_single()` ensures CPU sees the device-written data.

For fragmented memory, `dma_map_sg()` / `dma_unmap_sg()` operate on scatter-gather lists.

DMA directions:
- `DMA_TO_DEVICE`: CPU→device; flush cache before map
- `DMA_FROM_DEVICE`: device→CPU; invalidate cache before device write, invalidate again after
- `DMA_BIDIRECTIONAL`: both; most conservative (flush + invalidate)

---

## IOMMU (Input-Output Memory Management Unit)

The IOMMU sits between PCIe (or AXI) devices and the system memory bus. It translates device-issued IOVAs (I/O Virtual Addresses) to physical addresses using device-specific page tables.

| IOMMU implementation | Platform |
|----------------------|----------|
| Intel VT-d | x86 Intel SoCs and Xeon |
| AMD-Vi (IOMMU) | x86 AMD Ryzen / EPYC |
| ARM SMMU v2/v3 | ARM SoCs, Jetson Orin, server ARM |

### Security and Isolation

Without IOMMU: a device (or compromised driver) can issue DMA to any physical address, reading or corrupting arbitrary memory. With IOMMU: device can only DMA to explicitly mapped IOVAs; any access outside mapped windows causes an IOMMU fault (logged, device stalled or reset).

### IOMMU Groups

PCIe devices behind the same IOMMU translation unit form a group. For VFIO GPU passthrough, all devices in the group must be assigned together to a VM; a device cannot be isolated within a group.

### Kernel API

```c
iommu_map(domain, iova, paddr, size, IOMMU_READ | IOMMU_WRITE);
iommu_unmap(domain, iova, size);
```

### VFIO

VFIO (Virtual Function I/O) exposes IOMMU-backed device access to userspace without a kernel driver. Used by: DPDK (user-space NIC drivers), SPDK (user-space NVMe), FPGA userspace drivers, KVM GPU passthrough. The VFIO container maps groups to IOMMU domains and allows userspace DMA via `/dev/vfio/N`.

---

## DMA-BUF Framework

DMA-BUF is a kernel abstraction for sharing DMA buffers between independent subsystems (CPU, GPU, camera ISP, video encoder, display engine) without copying.

### Roles

- **Exporter**: owns the buffer; allocates backing pages or device memory; implements `struct dma_buf_ops` (`attach`, `map_attachment`, `unmap_attachment`, `mmap`, `release`, `vmap`)
- **Importer**: attaches to an exported buffer; maps it for its device's DMA engine

### Lifecycle

```c
/* Exporter */
struct dma_buf *buf = dma_buf_export(&exp_info);
int fd = dma_buf_fd(buf, O_CLOEXEC);
/* pass fd to importer process via Unix socket */

/* Importer */
struct dma_buf *buf = dma_buf_get(fd);
struct dma_buf_attachment *att = dma_buf_attach(buf, importer_dev);
struct sg_table *sgt = dma_buf_map_attachment(att, DMA_FROM_DEVICE);
/* sgt contains scatter-gather list with IOVAs for importer device */
dma_buf_unmap_attachment(att, sgt, DMA_FROM_DEVICE);
dma_buf_detach(buf, att);
dma_buf_put(buf);
```

### Zero-Copy Pipeline

```
V4L2 camera driver → DMABUF fd → CUDA importer → inference kernel → display
```

No CPU copy at any stage. The fd is passable between processes via `SCM_RIGHTS` on a Unix socket, enabling cross-process zero-copy. Synchronization between producers and consumers uses the DMA fence framework (`dma_fence_wait()`).

### V4L2 Integration

V4L2 supports DMA-BUF as a memory type (`V4L2_MEMORY_DMABUF`). Userspace passes the DMA-BUF fd in `struct v4l2_buffer.m.fd`. The ISP driver maps the buffer for its DMA engine automatically on `VIDIOC_QBUF`.

---

## GPU Memory Architecture

### VRAM and PCIe BAR

GPU VRAM (GDDR6X on GeForce, HBM2e/HBM3 on datacenter GPUs) is accessed by the CPU through PCIe Base Address Registers (BAR). The GPU exposes a BAR aperture; the CPU maps it as uncached MMIO.

- PCIe 5.0 x16 peak bandwidth: ~128 GB/s bidirectional
- Discrete GPU typically exposes 1/8 of VRAM via the 256 MB or 16 GB BAR (resizable BAR / Above-4G Decoding)
- NVIDIA NVLink bypasses PCIe for GPU-GPU transfers (600 GB/s on H100 NVLink 4.0)

### CUDA Memory Types

| Type | API | Coherent CPU↔GPU? | Notes |
|------|-----|-------------------|-------|
| Device memory | `cudaMalloc()` | No | VRAM; fastest for GPU kernels |
| Pinned host memory | `cudaMallocHost()` | No | DMA-able; faster H2D/D2H transfers |
| Unified Memory | `cudaMallocManaged()` | Yes (demand migration) | Single pointer, both CPU and GPU |
| Mapped host memory | `cudaHostGetDevicePointer()` | No | Zero-copy over PCIe; low bandwidth |

### CUDA Unified Memory

A single pointer is valid on both CPU and GPU. The CUDA driver and OS collaborate to migrate 64KB-granule pages on fault:
- GPU page fault → migrate from CPU to VRAM
- CPU page fault → migrate from VRAM to CPU DRAM

`cudaMemPrefetchAsync(ptr, size, device, stream)`: explicit prefetch before access; hides migration latency.
`cudaMemAdvise()` hints: `cudaMemAdviseSetReadMostly` (replicate across devices), `cudaMemAdviseSetPreferredLocation` (preferred residency).

Production inference code typically uses explicit `cudaMemcpy()` with pinned buffers for deterministic latency. Unified Memory is most useful for rapid prototyping and memory-constrained models that exceed VRAM.

### nvmap on Jetson

Jetson uses a unified memory architecture (CPU and GPU share DRAM). `nvmap` manages carveout (physically contiguous) and IOMMU-mapped allocations for IOMMU-less peripherals:
- NVDLA, VIC, camera ISP, display engine use nvmap buffers
- `/dev/nvmap` userspace interface; `NVMAP_IOC_ALLOC`, `NVMAP_IOC_SHARE` ioctls
- CPU and GPU access the same physical pages; no PCIe transfer needed

---

## Summary

| DMA type | Cache sync? | IOMMU needed? | API | Use case |
|----------|------------|--------------|-----|---------|
| Coherent | No (hardware) | No | `dma_alloc_coherent()` | Descriptor rings, control registers |
| Streaming single | Yes (explicit) | Optional | `dma_map_single()` | Single-buffer bulk transfers |
| Streaming SG | Yes (explicit) | Optional | `dma_map_sg()` | NVMe, network scatter-gather |
| DMA-BUF | Fence-based | Optional | `dma_buf_*` | Cross-device zero-copy pipelines |
| CUDA Unified | Automatic (driver) | N/A | `cudaMallocManaged()` | Prototype multi-stage inference |

---

## AI Hardware Connection

- DMA-BUF with `V4L2_MEMORY_DMABUF` enables camera frame→CUDA zero-copy on Jetson; eliminates a full 1080p60 frame copy (~12 MB/frame × 60 = 720 MB/s CPU copy avoided)
- `dma_alloc_coherent` is the correct API for Zynq PL↔PS AXI DMA command rings and status descriptors where correctness and simplicity outweigh throughput
- IOMMU (ARM SMMU on Jetson Orin) partitions DRAM access per hardware engine; a malfunctioning NVDLA kernel cannot corrupt VIC or camera ISP buffers outside its mapped IOVA window
- CUDA Unified Memory with `cudaMemPrefetchAsync` allows prototype inference code to exceed VRAM size by streaming weights through CPU DRAM, at the cost of migration latency
- Streaming DMA with `DMA_FROM_DEVICE` is the access pattern for NVMe-to-GPU GPUDirect Storage, where NVMe data bypasses CPU cache and lands directly in GPU-accessible pinned memory
- VFIO enables userspace FPGA DMA drivers that bypass the kernel driver model entirely, useful for low-latency AI accelerator cards requiring sub-microsecond command submission
