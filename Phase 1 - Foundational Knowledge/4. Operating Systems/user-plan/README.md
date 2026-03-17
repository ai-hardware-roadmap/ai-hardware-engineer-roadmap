# User Plan: Example Code for Lectures 1–9

This folder contains a **single runnable example** that uses concepts from **Lectures 1 through 9** (OS Architecture, Processes, Interrupts, System Calls, Boot/Modules, Scheduling, Real-Time Linux, CPU Affinity & Isolation, Synchronization).

## What the Example Does

A small **real-time–style worker** that:

- Runs as a normal process (L1, L2) and uses **system calls** (L4) for scheduling, affinity, and memory locking.
- Sets **scheduler policy and priority** (L6: SCHED_FIFO, nice) and **real-time–friendly** setup (L7: mlockall, pre-fault, no malloc in loop).
- Pins itself to specific **CPUs** (L8: CPU affinity).
- Uses **synchronization** (L9): mutex, read-write lock, and a completion-style event (condition variable).

Concepts from **L3 (interrupts)** and **L5 (boot/modules)** are referenced in comments and in the README; full kernel-side examples would require a kernel module.

## Lecture → Code Mapping

| Lecture | Topic | Where in the code |
|--------|--------|-------------------|
| **L1** | OS as resource manager, user vs kernel (Ring 3 / EL0) | Process runs in user space; syscalls cross into kernel (see L4). |
| **L2** | Process, threads, `task_struct` (PID, tgid, affinity) | `main()` + worker thread; `getpid()`, `gettid()`; `sched_setaffinity()` writes to task’s CPU mask. |
| **L3** | Interrupts, top/bottom half | Commented: RT loop simulates “wake on event”; real IRQs would be in kernel/driver. |
| **L4** | System calls, vDSO | `sched_setscheduler`, `sched_setaffinity`, `mlockall`, `gettid`, `clock_gettime` (often vDSO). Use `strace ./rt_demo` to see syscalls. |
| **L5** | Boot, modules, device tree | Not in userspace code; see “L5” section in README. |
| **L6** | Scheduling (CFS, SCHED_FIFO, nice) | `sched_setscheduler(SCHED_FIFO)`, optional `setpriority()` for non-RT; comment on EEVDF/CFS. |
| **L7** | Real-Time Linux (PREEMPT_RT, latency) | `mlockall()`, pre-fault of stack/buffers, SCHED_FIFO, no malloc in RT loop; comments on cyclictest/ftrace. |
| **L8** | CPU affinity & isolation | `sched_setaffinity()`; comments on `isolcpus` + nohz_full for full isolation. |
| **L9** | Synchronization (mutex, rwlock, completion-like) | `pthread_mutex_t`, `pthread_rwlock_t`, `pthread_cond_t` + `pthread_cond_signal` (completion-style). |

## Build and Run

**Requires:** Linux (or WSL on Windows) with pthreads and `sched.h`.

```bash
cd "Phase 1 - Foundational Knowledge/4. Operating Systems/user-plan"
make
./rt_demo [options]
```

If `make` is not available, build manually:

```bash
gcc -Wall -O2 -pthread -o rt_demo rt_demo.c
```

**Options (see `./rt_demo --help`):**

- `--cpu 2,3` — Pin process to CPUs 2 and 3 (affinity).
- `--rt` — Use SCHED_FIFO priority 80 (requires root/cap_sys_nice).
- `--lock-memory` — Call mlockall (requires root/cap_ipc_lock).
- `--no-rt` — Run without RT scheduling (default for non-root).

**Running with real-time and locking (needs root):**

```bash
sudo ./rt_demo --rt --lock-memory --cpu 1
```

**Observing syscalls (L4):**

```bash
strace -e sched_setscheduler,sched_setaffinity,mlockall,gettid,clock_gettime ./rt_demo --rt --cpu 1 2>&1 | head -50
```

## L5 (Boot / Modules / Device Tree)

There is no kernel module in this repo. To see L5 in action:

- **Boot:** Watch `dmesg` during boot; use `systemd-analyze` for boot time.
- **Modules:** `lsmod`, `modinfo`, load/unload a module (e.g. `sudo modprobe loop` then `sudo modprobe -r loop`).
- **Device Tree:** On ARM, inspect `/sys/firmware/devicetree/base/` or boot logs for “Machine model”.

## Requirements

- Linux with pthreads and `sched.h` (POSIX real-time optional).
- For `--rt` and `--lock-memory`: run as root or have `cap_sys_nice` and `cap_ipc_lock`.
- For affinity: `sched_setaffinity` is supported on multi-core systems.

## Files

- `README.md` — This file (lecture mapping and usage).
- `rt_demo.c` — Main example (process, threads, syscalls, scheduling, affinity, sync).
- `Makefile` — Builds `rt_demo`.
