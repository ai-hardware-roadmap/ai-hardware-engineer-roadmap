# Lecture 19: Modern I/O: io_uring, DMA-BUF & Zero-Copy Pipelines

## Traditional I/O Limitations

The legacy POSIX I/O model imposes overhead that becomes a bottleneck in high-throughput AI data pipelines.

- `read()`/`write()`: each operation requires at least 2 syscalls (initiate + complete) plus a kernel-to-userspace data copy
- `select()`/`poll()`: O(n) scanning of file descriptor sets; degrades linearly with fd count
- `epoll`: eliminates O(n) scan but still requires one syscall per event notification; context switch cost accumulates at high IOPS

At 1M IOPS (NVMe throughput), syscall overhead alone can consume 30–50% of CPU cycles.

## io_uring (Linux 5.1+)

io_uring replaces per-operation syscalls with shared memory ring buffers visible to both kernel and userspace simultaneously.

### Ring Buffer Architecture

Two rings reside in memory mapped into both kernel and userspace:

- **SQE ring (Submission Queue Entry)**: application writes operation descriptors here; kernel reads them
- **CQE ring (Completion Queue Entry)**: kernel writes completion status here; application polls without a syscall

### Submission and Completion Flow

1. Application calls `io_uring_prep_read()` / `io_uring_prep_write()` etc. to fill an SQE
2. Application calls `io_uring_submit()` which may call `io_uring_enter()` — or kernel sqpoll thread handles it automatically (`IORING_SETUP_SQPOLL`)
3. Kernel processes the operation asynchronously
4. Kernel writes CQE to the CQ ring
5. Application polls CQ ring — **no syscall required** for completion

With `IORING_SETUP_SQPOLL`, a dedicated kernel thread continuously drains the SQ ring. The submit path becomes zero-syscall. The application only polls the CQ ring.

### Key Flags and Features

| Flag / Feature | Meaning |
|---|---|
| `IORING_SETUP_SQPOLL` | Kernel thread auto-submits; zero syscall submit path |
| `IORING_SETUP_IOPOLL` | Kernel polls for completions (no IRQ); lowest latency |
| `IORING_FEAT_NODROP` | CQEs never dropped; backpressure instead of loss |
| Fixed buffers | Pre-registered buffers skip `get_user_pages()` per op |
| Multishot | Single SQE generates multiple CQEs (e.g., accept loop) |

### Supported Operations

`read`, `write`, `send`, `recv`, `accept`, `connect`, `fsync`, `splice`, `openat`, `statx`, `timeout`, `link`, `hardlink`, `renameat`, `unlinkat`

### liburing Helper Library

```c
struct io_uring ring;
io_uring_queue_init(256, &ring, 0);          // init with depth 256

struct io_uring_sqe *sqe = io_uring_get_sqe(&ring);
io_uring_prep_read(sqe, fd, buf, len, 0);
io_uring_sqe_set_data(sqe, user_data_ptr);

io_uring_submit(&ring);                      // single syscall for batch

struct io_uring_cqe *cqe;
io_uring_wait_cqe(&ring, &cqe);             // blocks until one CQE ready
io_uring_cqe_seen(&ring, cqe);              // advance CQ head
```

### Performance Comparison

| Method | IOPS (NVMe 4K rand read) | CPU utilization | Syscalls per op |
|---|---|---|---|
| `pread()` | ~200K | high | 1 |
| `epoll` + `aio` | ~600K | moderate | 2 |
| `io_uring` (default) | ~800K | low | ~0.1 (batched) |
| `io_uring` + SQPOLL | 1M+ | near-zero | 0 |

## DMA-BUF: Cross-Subsystem Buffer Sharing

DMA-BUF provides a file descriptor abstraction for memory buffers that multiple kernel subsystems and userspace can share without copying.

- One subsystem allocates a buffer and exports it as an fd via `dma_buf_export()` → `dma_buf_fd()`
- Another subsystem imports the fd via `dma_buf_get()` and maps it into its own DMA address space
- Userspace passes fds between processes via `sendmsg()` or direct API calls

### V4L2 + DMA-BUF Integration

- `V4L2_MEMORY_DMABUF`: V4L2 buffer type that accepts external DMA-BUF fds
- Application exports a DMA-BUF fd from GPU allocator (nvmap, ION, or DRM allocator)
- Passes fd to camera driver via `VIDIOC_QBUF` with `m.fd` set
- Camera DMA engine writes captured frame directly to GPU-accessible memory
- `VIDIOC_EXPBUF`: export a V4L2 `MMAP` buffer as a DMA-BUF fd for import by another device

## Zero-Copy Camera to Inference Pipeline (Jetson)

Traditional pipeline: Camera → DMA → kernel buffer → copy to userspace → copy to GPU (2 extra copies).

Zero-copy pipeline via DMA-BUF:

1. GPU allocates buffer: `cudaMalloc()` → nvmap handle → `dma_buf_fd()`
2. Camera (V4L2): `VIDIOC_QBUF` with `V4L2_MEMORY_DMABUF`; fd passed to camera driver
3. Camera ISP DMA engine writes directly into that GPU-mapped buffer
4. CUDA inference: buffer already in GPU memory; no `cudaMemcpy()` needed
5. Access via `cudaGraphicsMapResources()` or direct device pointer

Latency reduction: eliminates 1–2 CPU-GPU memcpy operations. At PCIe Gen3 bandwidth (~12 GB/s), copying a 1080p RGBA frame (~8 MB) costs ~0.7 ms. At 30 fps with 3 cameras, eliminated copies save significant memory bandwidth.

## splice and sendfile: Kernel-to-Kernel Zero-Copy

Both calls move data between file descriptors without copying to userspace:

- `sendfile(out_fd, in_fd, &offset, count)`: copy from file or socket to socket inside kernel; used for HTTP video streaming and static file serving
- `splice(fd_in, off_in, fd_out, off_out, len, flags)`: more general; works with pipes; can chain across calls
- `tee(fd_in, fd_out, len, flags)`: duplicate pipe data without consuming it

Use case: camera recording server sending H.264 frames over HTTP without a userspace buffer copy.

## DPDK: User-Space Network Driver

DPDK (Data Plane Development Kit) bypasses the kernel network stack entirely:

- User-space PMD (Poll Mode Driver) owns the NIC; no kernel driver, no interrupts
- Huge pages (2 MB/1 GB) for packet buffers: eliminates TLB misses at line rate
- CPU core polling at 100% — achieves 100 Gbps with a single core
- No context switches, no syscalls, no socket buffer copies
- Used in inference-serving front-ends where network I/O must match GPU throughput

Tools: `dpdk-testpmd` for benchmarking; `rte_mbuf` for zero-copy packet buffers; `rte_ring` for inter-core packet passing.

## VisionIPC: openpilot Zero-Copy Video IPC

openpilot replaces socket-based video transfer with shared memory:

- `vipc_server` allocates a pool of shared memory buffers at startup via `mmap(MAP_SHARED)`
- `camerad` (producer): fills a buffer, posts the buffer index to consumers via semaphore
- `modeld` and `encoderd` (consumers): receive the index, map the same memory region, read directly
- No video data copy between processes; only a small integer (buffer index) is communicated
- `cereal` handles all other IPC (non-video) via capnproto over `msgq` (also shared memory)

## Summary

| I/O Method | Syscall per op | Data copy | Max throughput | Use case |
|---|---|---|---|---|
| `read()`/`write()` | 1 | kernel to user | ~200K IOPS | Simple file I/O |
| `epoll` + callbacks | 1 per event | kernel to user | ~600K IOPS | Network servers |
| `io_uring` batched | ~0.1 (batched) | kernel to user | ~800K IOPS | NVMe logging |
| `io_uring` SQPOLL | 0 | kernel to user | 1M+ IOPS | Ultra-low latency |
| `sendfile` | 1 | none (kernel) | line rate | Video streaming |
| DMA-BUF + V4L2 | 0 (DMA) | none | hardware DMA rate | Camera to GPU |
| DPDK | 0 | none | 100 Gbps | Inference serving |
| VisionIPC | 0 (shared mem) | none | memory bandwidth | openpilot camera IPC |

## AI Hardware Connection

- DMA-BUF with `V4L2_MEMORY_DMABUF` enables true zero-copy camera-to-GPU pipelines on Jetson; frames arrive in GPU memory directly from the ISP with no CPU involvement in the data path
- io_uring with `IORING_SETUP_SQPOLL` is applicable to high-throughput CAN bus and sensor logging in openpilot, achieving 1M+ IOPS with near-zero CPU cost
- VisionIPC demonstrates the OS-level shared memory design that eliminates inter-process video copies in production autonomous driving software
- DPDK is used in cloud inference front-ends where network I/O at 100 Gbps must be matched to GPU throughput without kernel overhead
- `sendfile` enables camera stream relay servers to forward encoded video to clients with zero userspace buffer involvement
- Understanding the full copy chain (camera ISP → kernel buffer → userspace → GPU) is prerequisite for diagnosing latency in any AI perception pipeline
