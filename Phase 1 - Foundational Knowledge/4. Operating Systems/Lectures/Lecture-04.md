# Lecture 4: System Calls, vDSO & eBPF

## The System Call Interface

System calls are the only sanctioned path for user-space code to request kernel services. User space cannot directly access hardware registers, allocate physical memory, or change scheduler policy — it asks the kernel via the syscall ABI.

### Call Path — x86-64

```
Application → glibc wrapper
  → syscall number in RAX; args in RDI, RSI, RDX, R10, R8, R9
  → SYSCALL instruction  ─── Ring 3 → Ring 0 ───
  → entry_SYSCALL_64 → sys_call_table[RAX]()
  → return value in RAX
  → SYSRET  ─── Ring 0 → Ring 3 ───
```

ARM64 uses `SVC #0` → `VBAR_EL1 + 0x400` → `el0_svc` → `sys_call_table[x8]()` → `ERET`.

```bash
strace -c ./inference_app    # count syscalls by type and cumulative time
strace -T -e mmap,ioctl ./camerad  # trace specific calls with per-call duration
```

---

## Syscall Overhead

| Cost component | Typical penalty |
|---|---|
| Mode switch (SYSCALL/SYSRET) | 50–150 ns |
| Spectre/Meltdown mitigations (IBRS, retpoline, KPTI) | 50–200 ns |
| TLB and cache effects (KPTI flushes user-space TLB entries) | 20–100 ns |
| Total round-trip (minimal kernel work) | 100–400 ns |

ARM64 mitigations (CSV2, SSBS) are lighter than x86. At 200 fps across 2 cameras, each frame requiring 4 V4L2 ioctls = 1600 syscalls/s × 300 ns = 0.5 ms/s pure mode-switch overhead. Batching and zero-copy (`mmap`, `io_uring`) reduce crossing frequency.

---

## vDSO: Kernel Calls Without Kernel Entry

The **virtual Dynamic Shared Object** is a read-only ELF page mapped by the kernel into every process address space at startup. Selected time functions read from a shared `vvar` data page that the kernel updates — no `SYSCALL` instruction, no mode transition, no TLB flush.

| Function | Full syscall | vDSO |
|---|---|---|
| `clock_gettime(CLOCK_MONOTONIC)` | ~200 ns | ~10–20 ns |
| `clock_gettime(CLOCK_REALTIME)` | ~200 ns | ~10–20 ns |
| `gettimeofday()` | ~200 ns | ~10–20 ns |
| `getcpu()` | ~150 ns | ~5 ns |

Calling through glibc automatically uses vDSO when available — no application change required. Use `CLOCK_MONOTONIC` for inter-process timing (not subject to NTP adjustments); use `CLOCK_MONOTONIC_RAW` for hardware-only monotonic counter.

```bash
# Verify vDSO is mapped
cat /proc/[pid]/maps | grep vdso
# Check which symbols are exported
nm /proc/[pid]/map_files/[vdso-range] 2>/dev/null | grep " T "
```

---

## Key Syscalls for AI and Embedded Systems

### mmap / munmap

```c
/* Zero-copy shared memory between processes */
int fd = shm_open("/sensor_ring", O_CREAT | O_RDWR, 0600);
void *buf = mmap(NULL, SIZE, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);

/* Huge page mapping for large GPU staging buffer */
void *huge = mmap(NULL, 2*1024*1024, PROT_READ | PROT_WRITE,
                  MAP_PRIVATE | MAP_ANONYMOUS | MAP_HUGETLB, -1, 0);
```

- `MAP_HUGETLB`: reduces TLB pressure for large staging buffers; requires `vm.nr_hugepages`
- `CUDA cudaMallocHost()` calls `mmap` on `/dev/nvidia*` for pinned host memory
- On Jetson unified memory, `cudaMalloc` uses `mmap` on `/dev/nvhost-as-gpu`

### ioctl

Primary device control interface; nearly all hardware-specific operations use it.

| ioctl | Device | Purpose |
|---|---|---|
| `VIDIOC_QBUF` / `VIDIOC_DQBUF` | V4L2 camera | Queue / dequeue capture buffer |
| `VIDIOC_STREAMON` / `STREAMOFF` | V4L2 | Start / stop streaming |
| `DRM_IOCTL_GEM_*` | DRM/KMS | Buffer allocation, display scanout |
| `NVGPU_IOCTL_CHANNEL_ALLOC_GPFIFO` | NVIDIA GPU (`/dev/nvhost-gpu`) | Allocate GPU command queue |
| `RPMSG_CREATE_EPT_IOCTL` | RPMsg | IPC with Cortex-M coprocessor (i.MX8) |
| Custom `_IOWR(MAGIC, N, struct)` | FPGA PCIe driver | Submit inference workload to accelerator |

### epoll

O(1) per-event multiplexing across many file descriptors. Used in openpilot's `cereal` messaging layer to multiplex CAN frames, camera V4L2 events, IMU data, and model output events.

```c
int epfd = epoll_create1(EPOLL_CLOEXEC);
struct epoll_event ev = { .events = EPOLLIN | EPOLLET, .data.fd = camera_fd };
epoll_ctl(epfd, EPOLL_CTL_ADD, camera_fd, &ev);
int n = epoll_wait(epfd, events, MAX_EVENTS, timeout_ms);
```

Edge-triggered mode (`EPOLLET`) is preferred for latency-sensitive paths — one wakeup per edge, no repeated notifications for unread data.

### prctl

```
PR_SET_NAME          Name thread; visible in ps/top/htop/perf
PR_SET_TIMERSLACK    Reduce timer coalescing (set to 1 ns for RT threads; default 50 µs)
PR_SET_SECCOMP       Apply seccomp-BPF filter to current thread
PR_SET_NO_NEW_PRIVS  Prevent privilege escalation across exec()
```

### sched_setattr — SCHED_DEADLINE

```c
struct sched_attr attr = {
    .size           = sizeof(attr),
    .sched_policy   = SCHED_DEADLINE,
    .sched_runtime  = 5000000,     /* 5ms budget per period */
    .sched_deadline = 16666666,    /* 16.7ms relative deadline (60fps) */
    .sched_period   = 16666666,    /* 16.7ms period */
};
sched_setattr(0, &attr, 0);        /* 0 = self; requires CAP_SYS_NICE */
```

### perf_event_open

Accesses hardware performance counters from userspace. Used by `perf stat`, Nsight Systems, and VTune.

```c
struct perf_event_attr pe = {
    .type   = PERF_TYPE_HARDWARE,
    .config = PERF_COUNT_HW_CACHE_MISSES,
    .disabled = 1,
};
int fd = perf_event_open(&pe, 0, -1, -1, 0);  /* measure self */
ioctl(fd, PERF_EVENT_IOC_ENABLE, 0);
/* ... inference workload ... */
read(fd, &count, sizeof(count));
```

On Jetson, ARM PMU counters measure LLC miss rate during DNN inference — guides INT8 tiling decisions.

### memfd_create

Creates an anonymous file-backed memory region — usable as shared memory without a filesystem path. Used in openpilot's `msgq` for zero-copy IPC between `modeld` and `controlsd`.

```c
int fd = memfd_create("shared_tensor", MFD_CLOEXEC);
ftruncate(fd, TENSOR_SIZE);
void *ptr = mmap(NULL, TENSOR_SIZE, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
/* pass fd over Unix socket to second process for its own mmap */
```

---

## eBPF: Kernel-Attached Verified Programs

eBPF programs run inside the kernel with verified safety: the kernel verifier checks bounds, loop termination, and pointer types before JIT-compiling to native code. No kernel module, no recompile.

### Architecture

```
C source → clang + libbpf → BPF bytecode
  → kernel verifier (bounds, termination, type checks)
  → JIT compiler → native code attached to hook
  → fires on event → writes results to BPF maps → read by user space
```

### Attachment Points

| Hook | Use |
|---|---|
| `kprobe` / `kretprobe` | Any kernel function entry/return — driver internals |
| `tracepoint` | Stable kernel tracepoints: `sched:sched_switch`, `irq:irq_handler_entry`, `block:block_rq_issue` |
| `uprobe` | User-space function: TensorRT engine execution, glibc allocations |
| `XDP` | Pre-stack packet processing in driver context — 100GbE line rate filtering |
| `TC` (traffic control) | Post-stack egress/ingress; used for latency tagging |

### BCC / bpftrace Production Tools

```bash
runqlat                                   # scheduler run-queue latency histogram
offcputime -p $(pgrep modeld) 10          # where modeld spends time blocked off-CPU

# Count context switches per process
bpftrace -e 'tracepoint:sched:sched_switch { @[comm] = count(); }'

# Trace ioctl latency from camerad
bpftrace -e '
  tracepoint:syscalls:sys_enter_ioctl /comm == "camerad"/ { @s[tid] = nsecs; }
  tracepoint:syscalls:sys_exit_ioctl  /comm == "camerad"/ {
    @us = hist((nsecs - @s[tid]) / 1000); delete(@s[tid]); }'

execsnoop        # trace new process executions
opensnoop        # trace file opens (useful to find what config camerad loads)
biolatency       # block I/O latency histogram (model loading from NVMe)
```

---

## seccomp: Syscall Filtering

A BPF program evaluated on every syscall; returns `ALLOW`, `ERRNO(N)`, `KILL`, or `TRAP`. Applied with `prctl(PR_SET_SECCOMP, SECCOMP_MODE_FILTER, &prog)`.

Docker's default seccomp profile blocks ~44 syscalls (`kexec_load`, `ptrace`, `mount`, `unshare`, etc.). A TensorRT inference container needs fewer than 50 syscalls; a tight allowlist eliminates the rest. Prevents post-exploit lateral movement in containerized AI deployments.

---

## Linux Capabilities

Root privilege is split into ~40 fine-grained grants. Drop capabilities after setup.

| Capability | Grants |
|---|---|
| `CAP_SYS_NICE` | `sched_setscheduler()`, `sched_setattr()` — set RT priority without root |
| `CAP_IPC_LOCK` | `mlockall()` — lock all memory pages; eliminates RT page-fault latency |
| `CAP_NET_ADMIN` | Network configuration, raw sockets, eBPF TC programs |
| `CAP_SYS_RAWIO` | Direct hardware I/O, PCIe MMIO access, FPGA register writes |
| `CAP_PERFMON` | `perf_event_open()` with hardware counters |

```bash
setcap cap_sys_nice+ep /opt/inference/modeld    # grant RT capability; no sudo at runtime
grep Cap /proc/$(pgrep modeld)/status           # inspect effective capability mask
```

---

## Summary

| Mechanism | Kernel entry? | Latency | Primary use |
|---|---|---|---|
| Syscall (SYSCALL / SVC) | Yes | 100–400 ns | All kernel services |
| vDSO (`clock_gettime`) | No | 10–20 ns | High-frequency timestamping |
| `mmap` (after setup) | No (page faults only) | Sub-ns when cached | Zero-copy buffers, shared memory |
| eBPF (JIT, kernel hook) | Runs in kernel | < 1 µs per probe | Production profiling, syscall filtering |
| seccomp filter | Per-syscall check | 5–20 ns overhead | Sandbox; attack surface reduction |
| vDSO `getcpu()` | No | ~5 ns | Determine current CPU for lockless rings |

---

## AI Hardware Connection

- vDSO `clock_gettime(CLOCK_MONOTONIC)` provides µs-accurate sensor timestamping at ~15 ns per call — essential for synchronizing camera frames, IMU samples, and CAN messages in openpilot's sensor fusion pipeline without kernel entry overhead.
- `ioctl(VIDIOC_DQBUF)` is the hot path in every V4L2 camera pipeline; measuring its latency distribution with `bpftrace` directly quantifies camera-to-model input delay without modifying or recompiling `camerad`.
- `bpftrace runqlat` is the first diagnostic for inference latency spikes — 5 ms scheduler run-queue latency on the model thread appears immediately in the histogram without code changes or kernel module insertion.
- `CAP_SYS_NICE` via `setcap` allows `modeld` to set its own RT scheduling policy without running as root, compatible with container security policies and Kubernetes `securityContext.capabilities`.
- seccomp allowlists on TensorRT inference containers block syscalls like `ptrace`, `kexec_load`, and `mount` that are meaningless for inference but provide significant post-exploit paths in AV deployments.
- `perf_event_open` with ARM PMU events on Jetson Orin measures LLC miss rate during DNN inference — cache miss data guides INT8 quantization and layer tiling decisions to reduce the memory working set below the L2/L3 cache size.
