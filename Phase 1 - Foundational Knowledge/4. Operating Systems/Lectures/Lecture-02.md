# Lecture 2: Processes, task_struct & the Linux Process Model

## The Process Abstraction

A process is a program in execution. It combines three orthogonal components:

- **Virtual CPU**: register state (PC, SP, general-purpose registers) saved in `task_struct` during preemption
- **Virtual memory**: address space — text, data, heap, stack, and memory-mapped regions, described by `mm_struct`
- **Resources**: file descriptor table, signal handlers, sockets, cgroup membership — all reachable from `task_struct`

Threads are processes that share `mm_struct` and `files_struct` but have independent stacks and register state. Linux makes no kernel distinction between "process" and "thread" — both are represented by `task_struct`.

---

## task_struct Key Fields

`task_struct` is defined in `include/linux/sched.h`. It is large (~5 KB); only the fields relevant to AI/embedded work are listed here.

| Field | Type | Purpose |
|---|---|---|
| `pid` | `pid_t` | Process ID — unique per thread in the system |
| `tgid` | `pid_t` | Thread group ID — shared across all threads; returned by `getpid()` |
| `state` | `unsigned int` | Current run state (TASK_RUNNING, TASK_INTERRUPTIBLE, etc.) |
| `mm` | `struct mm_struct *` | Virtual memory descriptor; NULL for kernel threads |
| `fs` | `struct fs_struct *` | Filesystem root and working directory |
| `files` | `struct files_struct *` | Open file descriptor table |
| `signal` | `struct signal_struct *` | Signal handlers, pending signals, process group |
| `sched_class` | pointer | Which scheduler class handles this task |
| `se` | `struct sched_entity` | CFS/EEVDF entity: vruntime, load weight, slice |
| `rt` | `struct sched_rt_entity` | RT entity: static priority, time slice |
| `dl` | `struct sched_dl_entity` | DEADLINE entity: runtime, deadline, period budgets |
| `cgroups` | `struct css_set *` | cgroup v2 membership; pointer to CSS set |
| `cpus_mask` | `cpumask_t` | Allowed CPU affinity; set via `sched_setaffinity()` |

---

## Process States

| State | Macro | Wakeable by signal? | `ps` letter | Example cause |
|---|---|---|---|---|
| Running or runnable | `TASK_RUNNING` | — | R | On CPU or on a run queue |
| Interruptible sleep | `TASK_INTERRUPTIBLE` | Yes | S | Waiting for I/O, event, or timer |
| Uninterruptible sleep | `TASK_UNINTERRUPTIBLE` | No | D | DMA wait, kernel I/O path (V4L2, NVMe) |
| Killable | `TASK_KILLABLE` | SIGKILL only | D | Uninterruptible but yields to kill |
| Stopped | `__TASK_STOPPED` | SIGCONT | T | SIGSTOP or debugger attach |
| Zombie | `EXIT_ZOMBIE` | — | Z | Exited; awaiting parent `wait()` call |
| Dead | `TASK_DEAD` | — | — | Fully reclaimed after parent reaps |

`D` state in `ps` indicates a process blocked inside a kernel I/O path. Persistent `D` state is a driver hang indicator — common during V4L2 buffer dequeue failures or NVMe timeout.

---

## fork / exec / wait

### fork() and Copy-on-Write

`fork()` creates a child as a structural copy of the parent. Physical memory is **not** copied immediately — Copy-on-Write defers allocation:

1. Child's page table entries point to parent's physical pages, all marked read-only.
2. On the first write to a shared page, a page fault allocates a private copy.
3. Read-only text (code) and read-only data are never copied — genuinely shared.

CoW makes `fork()` fast even for large processes. openpilot's multi-process architecture relies on this: `camerad`, `modeld`, `plannerd`, and `controlsd` each fork from a common base without duplicating megabytes of shared library code.

### exec() and wait()

`execve()` replaces the current address space with a new ELF binary. File descriptors without `O_CLOEXEC` survive across exec. `waitpid()` reaps a zombie child, reclaiming its `task_struct`. Without `wait()`, zombies accumulate and eventually exhaust PID space.

If a parent exits before reaping, orphan children are reparented to PID 1 (systemd), which calls `wait()` internally.

---

## clone() and Threads

`clone()` is the underlying syscall behind both `fork()` and `pthread_create()`. The flags argument determines what the new task shares with its parent.

| Flag | Effect |
|---|---|
| `CLONE_VM` | Share `mm_struct` — both tasks use the same address space (thread) |
| `CLONE_FILES` | Share open file descriptor table |
| `CLONE_SIGHAND` | Share signal handlers |
| `CLONE_NEWPID` | New PID namespace — child is PID 1 inside it |
| `CLONE_NEWNET` | New network namespace — isolated interface/routing table |
| `CLONE_NEWNS` | New mount namespace — isolated filesystem view |

A thread is simply a task created with `CLONE_VM | CLONE_FILES | CLONE_SIGHAND`. `getpid()` returns `tgid` (same for all threads in a process); `gettid()` returns the unique per-thread `pid`.

---

## Linux Namespaces

Namespaces partition kernel resources so a set of processes sees an isolated view. They are the foundation of containers.

| Namespace | Isolates | Container use |
|---|---|---|
| `pid` | Process ID numbering | Container init appears as PID 1 |
| `mnt` | Filesystem mount tree | Container-private root filesystem |
| `net` | Network interfaces, routes, iptables | Per-container networking |
| `uts` | Hostname and domain name | Container-specific hostname |
| `ipc` | System V IPC, POSIX message queues | IPC isolation between containers |
| `user` | UID/GID mappings | Rootless containers |
| `cgroup` | cgroup root view | Nested cgroup hierarchies |
| `time` | Clock offsets | Time namespace per container |

```bash
ls -la /proc/[pid]/ns/          # inspect namespace membership of a running process
unshare --pid --fork bash       # launch shell in new PID namespace
```

GPU device files (`/dev/nvidia0`, `/dev/nvhost-ctrl`) must be bind-mounted into the container's mount namespace for CUDA to initialize inside containers.

---

## cgroups v2: Resource Control

Unified hierarchy at `/sys/fs/cgroup/`. All controllers (cpu, memory, io, cpuset) attach to the same hierarchy tree.

| Controller | Key file | Example value | Effect |
|---|---|---|---|
| cpu | `cpu.max` | `50000 100000` | 50% of one CPU (quota µs / period µs) |
| cpuset | `cpuset.cpus` | `0-3` | Restrict to cores 0–3 |
| cpuset | `cpuset.mems` | `0` | Restrict to NUMA node 0 |
| memory | `memory.max` | `4G` | OOM-kill if exceeded |
| memory | `memory.swap.max` | `0` | Disable swap for this group |
| io | `io.max` | `8:0 rbps=104857600` | 100 MB/s read on device 8:0 |
| pids | `pids.max` | `512` | Limit fork bombs in untrusted containers |

```bash
cat /proc/[pid]/cgroup              # cgroup membership path for a process
cat /sys/fs/cgroup/[path]/cpu.stat  # throttled_usec, nr_throttled — detect throttling
```

Kubernetes uses cgroup v2 to enforce CPU and memory limits on inference pods. A pod with `cpu.max = 200000 1000000` (20% of one core) will have `modeld` throttled if it exceeds that budget.

---

## Context Switch Mechanics

`context_switch()` is in `kernel/sched/core.c`:

1. `switch_mm_irqs_off()` — install the new page table: write CR3 (x86) or TTBR0_EL1 (ARM64)
2. `switch_to()` — save callee-saved registers and stack pointer; restore the next task's
3. Return into the next task's execution context at the point it was last preempted

**TLB cost**: ARM64 uses ASID-tagged TLBs — switching between tasks with valid ASIDs avoids a full TLB flush. x86 uses PCID for the same purpose. Context switch overhead: 1–10 µs depending on cache state and whether the TLB must be flushed. For a 1 kHz control loop (`controlsd` at 100 Hz CAN output), scheduler jitter must stay well below 1 ms.

---

## /proc/[pid]/ Runtime Inspection

| Path | Contents |
|---|---|
| `/proc/[pid]/maps` | Virtual memory regions: address, permissions, backing file |
| `/proc/[pid]/smaps` | Per-region RSS and PSS; identifies memory waste and sharing |
| `/proc/[pid]/status` | State, VmRSS, threads, capability sets |
| `/proc/[pid]/fd/` | Symlinks to open files, sockets, V4L2 device nodes |
| `/proc/[pid]/sched` | CFS/EEVDF: vruntime, nr_voluntary_switches, se.load.weight |
| `/proc/[pid]/wchan` | Kernel function where task is currently sleeping |
| `/proc/[pid]/cgroup` | cgroup v2 membership path |
| `/proc/[pid]/oom_score` | OOM killer score; higher value killed first under memory pressure |
| `/proc/[pid]/oom_score_adj` | Writable: tune OOM priority (-1000 = never kill, +1000 = kill first) |

---

## Summary

| State | Macro | Wakeable? | Example cause |
|---|---|---|---|
| Running / runnable | `TASK_RUNNING` | — | On CPU or waiting on run queue |
| Interruptible sleep | `TASK_INTERRUPTIBLE` | Yes (signal) | Blocked on `read()`, `epoll_wait()` |
| Uninterruptible sleep | `TASK_UNINTERRUPTIBLE` | No | DMA wait, `VIDIOC_DQBUF` in driver |
| Killable | `TASK_KILLABLE` | SIGKILL only | NFS soft mount wait |
| Stopped | `__TASK_STOPPED` | SIGCONT | Debugger, SIGSTOP |
| Zombie | `EXIT_ZOMBIE` | — | Awaiting parent `waitpid()` |

---

## AI Hardware Connection

- `task_struct.sched_class` determines the scheduler for each task; assigning `modeld` to `SCHED_FIFO` switches it to `rt_sched_class`, preventing CFS/EEVDF jitter from delaying frame processing by up to 5 ms on an untuned system.
- `cpuset.cpus` in cgroup v2 pins inference processes to isolated cores, preventing migration to cores shared with interrupt handlers; on Jetson Orin, the big-cluster Cortex-A78AE cores are typically reserved for `modeld` and `camerad`.
- `cpu.max` throttles background processes (telemetry, logging) to a fixed quota so inference threads retain burst CPU headroom — directly writable at `/sys/fs/cgroup/[pod]/cpu.max` in Kubernetes.
- openpilot's `camerad`, `modeld`, `sensord`, `plannerd`, and `controlsd` run as separate processes; CoW fork semantics give each an independent `mm_struct`, enabling crash isolation without corrupting sibling address spaces.
- `TASK_UNINTERRUPTIBLE` appears in camera and DMA driver code paths — a persistent `D`-state process in `/proc/[pid]/wchan` pointing to `v4l2_dqbuf` or `nvdla_submit` immediately identifies the stalled hardware interface.
- PID namespaces in Kubernetes inference pods isolate service process trees; `/proc/[pid]/cgroup` on the host maps any guest PID to its pod's resource accounting group for OOM investigation.
