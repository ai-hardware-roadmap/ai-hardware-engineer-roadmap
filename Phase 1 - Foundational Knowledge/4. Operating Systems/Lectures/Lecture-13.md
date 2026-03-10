# Lecture 13: Page Tables, TLBs & Huge Pages

## x86-64 Four-Level Page Table Walk

### Virtual Address Decomposition

A 48-bit canonical virtual address is split into five fields:

```
Bits [47:39] → PGD index   (9 bits, 512 entries)
Bits [38:30] → PUD index   (9 bits, 512 entries)
Bits [29:21] → PMD index   (9 bits, 512 entries)
Bits [20:12] → PTE index   (9 bits, 512 entries)
Bits [11:0]  → page offset (12 bits, 4KB page)
```

Walk: `CR3` holds the physical address of the PGD. Each table is exactly one 4KB page containing 512 × 8-byte entries. The hardware MMU performs the walk automatically on a TLB miss, issuing up to four sequential memory reads before the final data access.

### Page Table Entry (PTE) Fields

| Bit | Name | Function |
|-----|------|----------|
| 0 | Present (P) | Entry valid; page fault if clear |
| 1 | R/W | 0 = read-only, 1 = read/write |
| 2 | U/S | 0 = supervisor only, 1 = user accessible |
| 3 | PWT | Page Write-Through cache policy |
| 4 | PCD | Page Cache Disable (uncached MMIO) |
| 5 | Accessed (A) | Set by hardware on any read; used by page reclaim |
| 6 | Dirty (D) | Set by hardware on write; used by swapper |
| 7 | PAT | Page Attribute Table index extension |
| 8 | Global (G) | Skip TLB flush on CR3 reload (kernel pages) |
| 63 | NX/XD | No-Execute; prevents instruction fetch |
| 51:12 | PFN | Physical Frame Number |

---

## ARM64 Page Table Walk

ARM64 uses two separate base registers: `TTBR0_EL1` for user-space (low VA, `0x0000...`) and `TTBR1_EL1` for kernel-space (high VA, `0xFFFF...`). This avoids the need to swap a single CR3 on kernel entry.

| Configuration | Walk depth | Notes |
|---------------|-----------|-------|
| 4KB pages, 48-bit VA | 4 levels (PGD→PUD→PMD→PTE) | Standard Linux ARM64 |
| 4KB pages, 52-bit VA | 5 levels (ARMv8.2-LPA) | Large Physical Address extension |
| 16KB pages, 48-bit VA | 3 levels | Reduced depth, coarser granularity |
| 64KB pages, 48-bit VA | 2–3 levels | Low TLB entry count per GB |

---

## Translation Lookaside Buffer

The TLB is a hardware cache of recent virtual→physical translations. On a hit, the CPU obtains the physical address in one cycle. On a miss, the hardware page table walker executes the full multi-level walk.

### Typical TLB Hierarchy (Intel Skylake / AMD Zen)

| Level | Type | Entries | Latency |
|-------|------|---------|---------|
| L1 iTLB | Instruction | 128 (4KB), 8 (2MB) | 1 cycle |
| L1 dTLB | Data | 64 (4KB), 32 (2MB) | 1 cycle |
| L2 TLB | Unified | 1024–1536 (4KB) | 6–8 cycles |
| Hardware walker on DRAM miss | — | — | 100–200 cycles |

A cold walk touching all four page table levels in uncached DRAM costs four sequential DRAM round-trips (~300–400 ns on DDR5 at 80 ns latency), dominating memory access time for sparse access patterns.

### TLB Shootdown on SMP

When a CPU modifies a PTE that other CPUs may have cached in their TLBs, all stale copies must be invalidated:

1. Modify PTE in page table memory
2. Issue `INVLPG vaddr` locally
3. Send IPI to all CPUs that may hold the mapping
4. Target CPUs execute `INVLPG` or `TLBI` (ARM64)
5. Originating CPU waits for all acknowledgements before proceeding

`flush_tlb_range()` implements this. Shootdown is expensive at high CPU counts (N×IPI round-trip latency) and is a hot path in `mmap()`/`munmap()`-heavy workloads such as Python memory allocators and JVM garbage collectors.

---

## PCID and ASID: Context-Switch Optimization

### PCID (x86, Process Context Identifier)

PCID is a 12-bit tag stored in `CR3[11:0]`. TLB entries carry the PCID of the process that installed them. On a context switch, the new CR3 value carries the new process PCID. With the `NOFLUSH` bit set in CR3, TLB entries from other PCIDs are retained but invisible to the new process. Linux enables PCID on kernel ≥ 4.14, reducing context-switch overhead by 10–20% in syscall-heavy workloads.

### ASID (ARM64, Address Space Identifier)

ASID is an 8-bit or 16-bit tag (configurable at kernel build time) written into `TTBR0`. Each `mm_struct` is assigned a unique ASID. When the ASID space is exhausted, a rollover event triggers a global TLB flush and ASID reassignment across all cores.

---

## Standard vs. Huge Pages

### 4KB Standard Pages

- Fine-grained physical memory protection and allocation
- 1 GB allocation → 262,144 PTEs → 512 page tables → 2 MB of page table memory
- 262,144 TLB entries required to cover 1 GB with zero misses; far exceeds L2 TLB capacity
- A 7B parameter model at fp16 (14 GB) requires ~3.6 million active PTEs

### 2MB Huge Pages (PMD-level, x86)

A single PMD entry marked as a huge page covers 2MB directly; the PMD[21] `PS` bit indicates a leaf entry. TLB entry count reduced 512× for the same address range.

**HugeTLBFS** (explicit pre-allocation):
```bash
echo 512 > /sys/kernel/mm/hugepages/hugepages-2048kB/nr_hugepages
mmap(NULL, size, PROT_READ|PROT_WRITE,
     MAP_HUGETLB|MAP_ANONYMOUS|MAP_PRIVATE, -1, 0)
```
Pages are pinned; cannot be swapped or migrated. Used by databases (PostgreSQL shared_buffers), DPDK packet pools, and GPU driver host-pinned buffers.

**Transparent Huge Pages (THP)** (automatic kernel promotion):
```bash
echo always  > /sys/kernel/mm/transparent_hugepage/enabled
echo madvise > /sys/kernel/mm/transparent_hugepage/enabled
echo never   > /sys/kernel/mm/transparent_hugepage/enabled

# Per-VMA opt-in (effective under madvise mode)
madvise(addr, len, MADV_HUGEPAGE);
```
The `khugepaged` kernel thread scans anonymous VMAs and collapses 512 contiguous 4KB pages into one PMD entry when alignment and availability allow. `/proc/vmstat` fields `thp_collapse_alloc` and `thp_split_page` track promotion and demotion events.

### 1GB Huge Pages (PUD-level, x86)

Single PUD leaf entry covers 1GB. Static-only allocation via kernel boot parameter:
```
hugepagesz=1G hugepages=4
```
Cannot be freed at runtime. Maximally reduces TLB footprint for full-model weight buffers.

---

## madvise() Hints

`madvise(addr, len, advice)` communicates access pattern hints to the kernel VM:

| Hint | Effect |
|------|--------|
| `MADV_HUGEPAGE` | Enable THP for this VMA |
| `MADV_NOHUGEPAGE` | Disable THP; force 4KB pages |
| `MADV_WILLNEED` | Prefetch pages into RAM (synchronous readahead) |
| `MADV_DONTNEED` | Release physical pages; VMA mapping retained |
| `MADV_SEQUENTIAL` | Increase readahead window for linear scan |
| `MADV_RANDOM` | Disable readahead; random access pattern |
| `MADV_FREE` | Pages may be reclaimed lazily; data lost on reclaim |

---

## Monitoring TLB and Huge Page Behavior

`/proc/[pid]/smaps` per-VMA fields:
- `AnonHugePages`: bytes in this VMA backed by 2MB THP
- `THPeligible: 1`: VMA meets size and alignment criteria for promotion

`/proc/vmstat` system-wide counters:
- `thp_fault_alloc`: THP allocated directly on page fault
- `thp_collapse_alloc`: THP created by khugepaged background scan
- `thp_split_page`: THP split back to 4KB (alignment failure, copy-on-write, etc.)

`perf stat -e dTLB-load-misses,iTLB-load-misses`: hardware PMU TLB miss rate per run.

---

## Summary

| Page size | Arch level | TLB entries for 1GB | Allocation method | Use case |
|-----------|-----------|---------------------|-------------------|----------|
| 4KB | PTE | 262,144 | Default `mmap` / page fault | General purpose, fine protection granularity |
| 2MB | PMD | 512 | THP (auto) or HugeTLBFS (explicit) | Model weights, DPDK buffers, GPU pinned memory |
| 1GB | PUD | 1 | HugeTLBFS static boot parameter | Full-model single-mapping, NUMA servers |
| 64KB (ARM64) | PTE | 16,384 | Kernel build config (`PAGE_SIZE=64K`) | ARM SoC with 64KB granule, fewer walk levels |

---

## AI Hardware Connection

- THP with `MADV_HUGEPAGE` reduces TLB miss rate for PyTorch and TensorRT model weight tensors; a 7B parameter fp16 model needs 27 PMD entries at 2MB granularity versus 3.6 million PTEs at 4KB
- HugeTLBFS pre-allocates 2MB pages for DPDK packet buffer pools on network-attached AI inference servers, guaranteeing zero TLB pressure during line-rate packet processing
- PCID (x86) and ASID (ARM64) eliminate full TLB flushes on context switches between the inference daemon and kernel I/O threads, critical when GPU completion interrupts and inference share the same CPU cores
- `madvise(MADV_WILLNEED)` on model weight files pre-faults pages into RAM before the first inference call, removing page-fault latency from the critical path of cold-start inference
- NVIDIA GPU drivers map large VRAM BAR apertures using 2MB PMD entries on the host side, reducing host TLB pressure when CPU accesses GPU memory through the PCIe BAR window
- On Jetson with the ARM64 kernel built for 64KB page granule, NVDLA DMA allocations require fewer page table levels and fewer TLB entries to cover large contiguous input feature map buffers
