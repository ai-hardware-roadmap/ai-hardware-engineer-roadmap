# Lecture 14: Memory Allocation: SLUB, kmalloc & CMA

## Physical Memory: The Buddy Allocator

The buddy allocator is the Linux kernel's primary physical page manager. Free memory is tracked in 11 free lists indexed by order (2^0 through 2^10 pages). `alloc_pages(gfp_flags, order)` returns 2^order physically contiguous pages; `__get_free_pages()` returns the kernel virtual address directly.

| Order | Size | Typical use |
|-------|------|-------------|
| 0 | 4 KB | Single page, page table |
| 1 | 8 KB | Small DMA descriptor ring |
| 4 | 64 KB | Medium DMA buffer |
| 9 | 2 MB | Huge page backing |
| 10 | 4 MB | Large contiguous allocation |

### Fragmentation

Over time, free pages become non-contiguous. High-order allocations fail even when total free memory is sufficient because no single 2^N contiguous block exists. `/proc/buddyinfo` shows the count of free blocks at each order per zone per NUMA node. `echo 3 > /proc/sys/vm/drop_caches` reclaims clean page cache and slab objects (use with care in production; does not solve fragmentation).

---

## SLUB Allocator

SLUB (default since kernel 2.6.23) manages sub-page allocations. Objects of the same type and size are grouped into slabs. Each slab is one or more contiguous pages. SLUB provides:

- **Per-CPU slabs**: each CPU maintains a local active slab; allocation and free are lock-free on the fast path
- **Partial slab list**: per-node list of partially filled slabs; shared between CPUs when the local slab is exhausted
- **Object reuse**: freed objects are returned to the cache without zeroing (unless `__GFP_ZERO`); avoids repeated initialization overhead

### kmem_cache Interface

```c
struct kmem_cache *cache = kmem_cache_create(
    "myobj", sizeof(struct myobj), __alignof__(struct myobj),
    SLAB_HWCACHE_ALIGN | SLAB_PANIC, NULL);

struct myobj *p = kmem_cache_alloc(cache, GFP_KERNEL);
kmem_cache_free(cache, p);
kmem_cache_destroy(cache);
```

### kmalloc

`kmalloc(size, gfp_flags)` is the general-purpose kernel allocator. It selects among size-based SLUB caches covering power-of-2 sizes: 8, 16, 32, 64, 128, 256, 512, 1K, 2K, 4K, 8K bytes. `kzalloc(size, gfp)` zero-fills. `kfree(ptr)` returns to the owning slab cache.

### Diagnostics

- `/proc/slabinfo`: cache name, active objects, total objects, object size, pages-per-slab
- `slabtop`: live sorted view by memory consumption; first tool to check for slab leaks in drivers
- `ksize(ptr)`: returns the actual allocated size (may exceed requested size due to cache rounding)
- KASAN/KFENCE: kernel sanitizers; detect use-after-free and out-of-bounds in slab objects

---

## vmalloc

`vmalloc(size)` allocates virtually contiguous but physically non-contiguous memory. The kernel sets up page tables in the `vmalloc` VA region, mapping individual pages. It is slower than `kmalloc` due to page table construction and TLB flushing on setup and teardown.

- `vfree(ptr)`: release; flushes vmalloc VA page tables
- `kvmalloc(size, gfp)` / `kvfree(ptr)`: preferred hybrid; attempts `kmalloc` first (contiguous, fast); falls back to `vmalloc` for large sizes
- Use cases: large kernel buffers that do not require physically contiguous DMA (module BSS, FPGA bitstream staging, large firmware images)
- Maximum size: limited by `VMALLOC_SIZE`; typically hundreds of GB on 64-bit kernels

---

## Memory Zones

Zones partition physical RAM by accessibility constraints:

| Zone | Physical range | GFP flag | Notes |
|------|---------------|----------|-------|
| ZONE_DMA | 0–16 MB | `GFP_DMA` | Legacy ISA 24-bit DMA; rarely needed today |
| ZONE_DMA32 | 0–4 GB | `GFP_DMA32` | 32-bit DMA-capable devices (PCIe default) |
| ZONE_NORMAL | 4 GB+ | `GFP_KERNEL` | Standard kernel allocations |
| ZONE_MOVABLE | Configurable | — | Pages eligible for migration/CMA |

---

## GFP Flags (Get Free Pages)

GFP flags control the allocation context and zone selection:

| Flag | Behavior |
|------|----------|
| `GFP_KERNEL` | May sleep, may reclaim; use in process context |
| `GFP_ATOMIC` | No sleep, no reclaim; use in interrupt or spinlock context; may return NULL |
| `GFP_DMA` | Must allocate from ZONE_DMA (0–16 MB) |
| `GFP_DMA32` | Must allocate from ZONE_DMA32 (0–4 GB) |
| `__GFP_ZERO` | Zero-fill the returned memory |
| `__GFP_NOFAIL` | Retry indefinitely until success; use sparingly |
| `__GFP_NOWARN` | Suppress OOM warning on allocation failure |
| `__GFP_COMP` | Return compound page (required for huge page backing) |

Key constraint: never use `GFP_KERNEL` in interrupt context or while holding a spinlock; it may sleep waiting for reclaim. Use `GFP_ATOMIC` in these paths and handle `NULL` return.

---

## CMA (Contiguous Memory Allocator)

CMA reserves physically contiguous regions at boot time within `ZONE_MOVABLE`. Normal movable pages can use this memory until a device requests it; at that point, the kernel migrates the movable pages out of the reserved region.

### Configuration

Kernel command line:
```
cma=256M
cma=128M@0x100000000   # reserve 128 MB starting at 4 GB PA
```

Device Tree (for platform-level assignment):
```dts
reserved-memory {
    linux,cma {
        compatible = "shared-dma-pool";
        reusable;
        size = <0 0x10000000>;
        linux,cma-default;
    };
};
```

### API

`dma_alloc_coherent(dev, size, &dma_handle, GFP_KERNEL)` uses CMA on platforms that support it. Returns a CPU virtual address and a device-visible `dma_handle` (physical address or IOVA). The region is non-cacheable or hardware-coherent.

CMA users on Jetson:
- NVDLA: input/output feature map DMA buffers
- VIC (Video Image Compositor): frame buffer transfers
- Camera ISP: raw frame DMA
- Display engine: framebuffer
- NVIDIA IOMMU-less DMA requires physically contiguous PA

### Monitoring

`/proc/cma`: total, used, maximum allocation. `dmesg | grep cma` at boot confirms reservation.

---

## OOM Killer

When all reclaim paths (page cache eviction, swap, slab shrinkers) fail, the OOM killer selects and terminates a process.

Selection: `badness(task)` scores each process proportional to its RSS and swap usage. Adjustable per-process:
```bash
echo -1000 > /proc/$(pidof inferenced)/oom_score_adj   # protect
echo +500  > /proc/$(pidof bloated_loader)/oom_score_adj  # prefer killing
```
Range: -1000 (never kill) to +1000 (kill first). Score -1000 disables OOM kill entirely for that process.

---

## Memory Pressure Tuning

- `vm.swappiness` (0–200): tendency to swap anonymous pages vs. reclaiming page cache; 0 avoids swap, 100 is balanced, 200 prefers swap
- `vm.min_free_kbytes`: minimum free memory before `kswapd` reclaim activates; increase on embedded systems with no swap to avoid GFP_ATOMIC failures
- `vm.overcommit_memory`: 0 = heuristic, 1 = always allow overcommit, 2 = strict (committed ≤ RAM + swap × ratio)

---

## Summary

| Allocator | Contiguous PA? | Can sleep? | Max size | Primary use |
|-----------|---------------|-----------|---------|-------------|
| kmalloc / SLUB | Yes (up to ~8KB) | Depends on GFP | 8 KB typical | Kernel objects, driver structs |
| alloc_pages | Yes | Depends on GFP | 4 MB (order 10) | Huge page backing, large contiguous |
| vmalloc | No (virtual only) | Yes | vmalloc VA range (100s GB) | Firmware images, large non-DMA buffers |
| dma_alloc_coherent / CMA | Yes | Yes | CMA reservation size | DMA-capable device buffers |

---

## AI Hardware Connection

- CMA reserves physically contiguous memory at boot for Jetson NVDLA and VIC DMA buffers, ensuring availability before any user-space process has fragmented memory
- `GFP_DMA32` is required when writing PCIe device drivers for AI accelerator cards whose DMA engines cannot address physical memory above 4 GB
- `GFP_ATOMIC` is the correct flag for camera ISR buffer allocation in V4L2 drivers, where the interrupt handler cannot sleep waiting for reclaim
- OOM score protection (`oom_score_adj = -1000`) prevents the inference daemon (modeld, controlsd) from being killed under memory pressure in openpilot's embedded environment
- `slabtop` is the first diagnostic tool for identifying memory leaks in custom sensor drivers where per-frame slab allocations accumulate without matching frees
- `kvmalloc` is the preferred pattern in FPGA driver code that loads variable-size bitstreams, transparently selecting contiguous or non-contiguous backing based on availability
