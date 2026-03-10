# Lecture 12: Virtual Memory & the Linux Memory Model

## Virtual Address Space

Each process has a private **virtual address space** isolated from all other processes. The MMU translates virtual addresses to physical addresses per-page using the page table tree. No process can directly access another's physical memory without explicit kernel-mediated sharing.

Key properties:
- **Isolation**: a bad pointer in one process cannot corrupt another's memory
- **Overcommit**: total virtual memory across all processes can exceed physical RAM; pages allocated on demand
- **Abstraction**: uniform flat address space regardless of physical DRAM layout or fragmentation

## x86-64 Virtual Address Layout

```
0x0000000000000000 – 0x00007FFFFFFFFFFF   User space (~128 TB)
  [ text | data/BSS | heap → | ← mmap region | ← stack ]

0xFFFF800000000000 – 0xFFFFFFFFFFFFFFFF   Kernel space (~128 TB)
  [ direct physical mapping | vmalloc | kernel text | modules | vDSO ]
```

- **ASLR**: randomizes stack, heap, and mmap base addresses at process start; controlled via `/proc/sys/kernel/randomize_va_space`; disable on latency-sensitive deterministic systems
- **Canonical addresses**: bits 48–63 must sign-extend bit 47; non-canonical address triggers #GP fault; 57-bit VA (5-level paging) extends this to bit 56

## ARM64 Virtual Address Layout

| Register | Maps | Notes |
|---|---|---|
| `TTBR0_EL1` | User space (VA starting at 0x0) | Per-process; reloaded on every context switch |
| `TTBR1_EL1` | Kernel space (VA with high bits set) | Constant; always present for all processes |

- 4KB pages × 4 levels of page tables = 48-bit VA by default
- 64KB pages = 3 levels of page tables
- ARMv8.2 LPA extension: 52-bit VA; used on Cortex-A78, A710, Jetson Orin (Cortex-A78AE)

## mm_struct — Process Memory Descriptor

`struct mm_struct` describes a process's complete virtual address space. One instance per process; all threads of a process share the same `mm_struct`.

| Field | Meaning |
|---|---|
| `pgd` | Physical address of Page Global Directory (top-level page table) |
| `mmap` | Linked list of all `vm_area_struct` entries |
| `mm_rb` | Red-black tree of VMAs for O(log n) address lookup |
| `start_code`, `end_code` | Text segment bounds |
| `start_data`, `end_data` | Initialized data segment bounds |
| `start_brk`, `brk` | Heap bounds (`brk` grows upward via `sbrk()`/`brk()` syscall) |
| `start_stack` | Initial stack pointer value |
| `total_vm` | Total virtual pages mapped |
| `locked_vm` | Pages pinned by `mlock`/`mlockall` |

## vm_area_struct (VMA)

A VMA represents one contiguous, uniformly-mapped region of virtual address space.

| Field | Meaning |
|---|---|
| `vm_start`, `vm_end` | Address range (page-aligned; exclusive end) |
| `vm_flags` | `VM_READ`, `VM_WRITE`, `VM_EXEC`, `VM_SHARED`, `VM_LOCKED`, `VM_GROWSDOWN` |
| `vm_file` | Pointer to backing `struct file` (NULL for anonymous mappings) |
| `vm_pgoff` | Offset within the backing file (in pages) |
| `vm_ops` | VMA operations: `fault()`, `open()`, `close()`, `mmap()` |

## VMA Types

| VMA Type | `vm_flags` | Backed By | Fault Action | Example |
|---|---|---|---|---|
| Text (code) | `VM_READ\|VM_EXEC` | Executable / `.so` file | Read from file | `main()` code |
| Data/BSS | `VM_READ\|VM_WRITE` | Executable file / zero-fill | Read from file or zero | Global variables |
| Heap | `VM_READ\|VM_WRITE` | Anonymous | Zero-fill on demand | `malloc()` regions |
| Stack | `VM_READ\|VM_WRITE\|VM_GROWSDOWN` | Anonymous | Zero-fill; expand on fault | Thread stack |
| File mmap (shared) | `VM_READ\|VM_WRITE\|VM_SHARED` | File pages | Read from file | Model weights mmap |
| Anonymous shared | `VM_READ\|VM_WRITE\|VM_SHARED` | `tmpfs` / swap | Zero-fill | POSIX shm, VisionIPC |
| vDSO | `VM_READ\|VM_EXEC` | Kernel-provided | Pre-mapped | `gettimeofday()` |

## mmap() — Creating Mappings

```c
// File-backed, shared — changes visible to all processes mapping same file
void *p = mmap(NULL, length, PROT_READ|PROT_WRITE, MAP_SHARED, fd, offset);

// Anonymous, private — zero-filled; not backed by file; used for heap/stack extensions
void *p = mmap(NULL, length, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0);

// Anonymous, shared — IPC between related processes; backed by tmpfs
void *p = mmap(NULL, length, PROT_READ|PROT_WRITE, MAP_SHARED|MAP_ANONYMOUS, -1, 0);

// HUGE pages — 2MB pages; reduce TLB pressure for large model buffers
void *p = mmap(NULL, length, PROT_READ|PROT_WRITE,
               MAP_PRIVATE|MAP_ANONYMOUS|MAP_HUGETLB, -1, 0);
```

`mmap()` creates the VMA descriptor but does **not** allocate physical pages. Pages are allocated on first access via demand paging.

## Demand Paging

Page table entry (PTE) is initially absent. On first access, the CPU raises a **page fault**. The kernel's `do_page_fault()` handler:

1. Finds the VMA covering the faulting virtual address
2. Validates permissions (`vm_flags` vs. fault type)
3. Allocates a physical page frame
4. Fills the frame: zero-fill (anonymous), read from file (file-backed), swap-in (previously evicted)
5. Installs the PTE and flushes the local TLB entry
6. Returns; the faulting instruction retries transparently

| Fault Type | Cause | Typical Cost |
|---|---|---|
| Minor (soft) | Page in memory but PTE absent (COW, demand-zero) | ~1µs |
| Major (hard) | Page must be read from disk (file-backed or swap) | 1–10ms |

Major faults are fatal to real-time latency guarantees. `mlockall()` prevents them entirely.

## Copy-on-Write (COW)

After `fork()`, parent and child share all pages mapped read-only. On first write to a shared page:
1. Hardware page fault triggered (write to read-only PTE)
2. Kernel allocates a new page frame
3. Copies original page content to new frame
4. Installs a writable PTE in the writing process's page table
5. Original page remains shared and unchanged

COW makes `fork()` O(1) — the address space size does not matter; only written pages are physically duplicated. Model weights shared read-only via COW after `fork()` consume only one physical copy.

## mlock() / mlockall() — Pinning Pages in RAM

```c
mlockall(MCL_CURRENT | MCL_FUTURE);   // pin all current + future mappings
mlock(addr, length);                   // pin specific address range only
munlockall();                          // release all locks
```

- `MCL_CURRENT`: locks all pages currently mapped in the address space
- `MCL_FUTURE`: any future `mmap()` or heap growth is automatically locked
- Requires `CAP_IPC_LOCK` or `RLIMIT_MEMLOCK` raised sufficiently

After `mlockall()`, pre-touch all pages to eliminate minor faults as well:

```c
// Force demand-zero pages to be physically allocated immediately
memset(buffer, 0, buffer_size);
```

## Inspecting Virtual Memory

```bash
cat /proc/<pid>/maps           # all VMAs: address range, permissions, backing file
cat /proc/<pid>/smaps          # per-VMA detail: RSS, PSS, dirty, swap, AnonHugePages
cat /proc/<pid>/smaps_rollup   # per-process totals from smaps
pmap -x <pid>                  # formatted smaps output
```

| Metric | Definition |
|---|---|
| RSS | Resident Set Size: total physical pages mapped (double-counts shared pages) |
| PSS | Proportional Set Size: RSS but shared pages divided proportionally; correct per-process metric |
| Swap | Pages evicted to swap currently |
| AnonHugePages | Anonymous pages backed by 2MB transparent huge pages |

PSS is the correct metric for per-process memory accounting in multi-process systems where shared libraries would otherwise be double-counted by RSS.

## Summary

| VMA Type | Flags | Backed By | Fault Action | Example |
|---|---|---|---|---|
| Text segment | `R-X` | ELF / `.so` file | Read from file | Code pages |
| Data/BSS | `RW-` | ELF file / zero | File read or zero-fill | Global vars |
| Heap | `RW-` | Anonymous | Zero-fill on demand | `malloc` |
| Stack | `RW-` (growsdown) | Anonymous | Zero-fill, auto-extend | Thread stack |
| File mmap (shared) | `RWS` | File | Read from file | Model weight file |
| Anonymous shared | `RWS` | `tmpfs` | Zero-fill | VisionIPC ring buffer |
| vDSO | `R-X` | Kernel-provided | Pre-mapped at boot | `clock_gettime` |

## AI Hardware Connection

- `mmap(MAP_SHARED)` on a DMA-BUF file descriptor maps GPU-allocated DRAM into a CPU process's virtual address space for zero-copy buffer sharing between V4L2 camera capture and CUDA inference; no data copy crosses the PCIe bus
- `mlockall(MCL_CURRENT|MCL_FUTURE)` is called at startup in real-time inference daemons on Jetson Orin to eliminate major page faults from the inference loop; a single fault to swap during a forward pass can add 10ms of latency
- COW `fork()` allows openpilot to spawn child processes sharing the parent's model weight pages in physical memory without doubling RAM; on a 512MB weight tensor, this avoids a 512MB physical copy on every process restart
- Shared anonymous `mmap` (`MAP_SHARED|MAP_ANONYMOUS`) backed by `memfd_create` provides the inter-process camera frame ring buffer in VisionIPC; `camerad` writes frames directly into the shared region and `modeld` reads without any copy
- `/proc/<pid>/smaps` PSS is the correct memory metric for per-process accounting in multi-process edge AI systems; RSS would count each shared library (libcuda, libtorch) multiple times across `camerad`, `modeld`, and `controlsd`
- CUDA Unified Virtual Memory (UVM) uses the same demand-paging mechanism as Linux VM: GPU page faults trigger CPU→GPU or GPU→CPU page migrations via the CUDA driver's fault handler, transparently mapping GPU and CPU virtual address spaces to the same physical memory
