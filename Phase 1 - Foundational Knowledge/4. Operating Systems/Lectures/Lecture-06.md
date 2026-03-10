# Lecture 6: CPU Scheduling: CFS, EEVDF & Real-Time Classes

## Scheduler Class Hierarchy

Linux scheduler classes are checked in strict priority order — a higher class always preempts a lower one:

```
stop_sched_class       highest — CPU migration, stop-machine operations
dl_sched_class         SCHED_DEADLINE — CBS/EDF; periodic real-time tasks
rt_sched_class         SCHED_FIFO, SCHED_RR — static priority 1–99
fair_sched_class       SCHED_NORMAL / SCHED_BATCH — CFS (< 6.6) or EEVDF (>= 6.6)
idle_sched_class       SCHED_IDLE — below nice +19; background maintenance
```

A single `SCHED_FIFO` task at priority 1 preempts every CFS/EEVDF task on the system. There is no cooperative override — the kernel enforces it unconditionally.

---

## CFS: Completely Fair Scheduler (Linux 2.6.23 – 6.5)

CFS models an "ideal CPU" running all runnable tasks simultaneously at 1/N speed. Replaced by EEVDF in Linux 6.6.

### vruntime and the Red-Black Tree

Each task accumulates virtual runtime weighted by its scheduling weight:

```
vruntime += actual_runtime x (NICE_0_WEIGHT / task_weight)
```

Tasks are stored in a red-black tree keyed by `vruntime`. The scheduler always picks the leftmost node (minimum vruntime): O(log n) insert/delete, O(1) pick-next.

### Nice Values and Weights

| Nice | Weight | CPU share vs nice-0 |
|---|---|---|
| -20 | 88761 | ~88x baseline |
| -5 | 3121 | ~3x baseline |
| 0 | 1024 | Baseline |
| +10 | 110 | ~1/9 baseline |
| +19 | 15 | ~1/68 baseline |

`weight = 1024 / (1.25 ^ nice)` — each step is a 25% change in CPU allocation.

### CFS Tuning Parameters

```bash
/proc/sys/kernel/sched_latency_ns          # scheduling period (default 6 ms)
/proc/sys/kernel/sched_min_granularity_ns  # minimum slice (default 0.75 ms)
```

With 8 tasks at nice 0: each gets 6 ms / 8 = 0.75 ms. CFS weakness: a newly woken latency-sensitive task may wait up to `sched_latency_ns` if many tasks have lower vruntime.

---

## EEVDF: Earliest Eligible Virtual Deadline First (Linux 6.6+)

EEVDF replaces CFS entirely in Linux 6.6. CFS code is removed from the kernel tree.

### Key Concepts

- **lag**: how much CPU time a task is owed relative to the ideal fair scheduler; positive lag means the task is behind schedule
- **eligible**: task whose virtual start time is at or before the current virtual time (lag >= 0)
- **virtual deadline**: assigned per task from `sched_slice` and current vruntime
- **Selection rule**: among all eligible tasks, pick the one with the **earliest virtual deadline**

### Why EEVDF Improves Tail Latency

CFS delays a freshly woken task if other tasks have lower vruntime. EEVDF's deadline-based selection ensures tight-deadline tasks run as soon as they become eligible, regardless of other tasks' vruntime history.

```bash
cat /proc/[pid]/sched | grep slice    # per-task sched_slice; smaller = more responsive
```

Jetson JetPack 6.x (5.15 kernel) still uses CFS. EEVDF is the default on Linux 6.6+ hosts and in Yocto Scarthgap.

---

## SCHED_FIFO

`rt_sched_class`; static priority 1–99 (99 = highest).

- Runs until it voluntarily blocks, calls `sched_yield()`, or is preempted by a higher-priority RT task
- No time slice within a priority level — a misbehaving task at prio 99 starves everything below it
- Suitable for tasks with well-understood, bounded CPU usage: CAN bus writes, IMU read loops

```bash
chrt -f 50 ./controlsd                   # launch with SCHED_FIFO priority 50
chrt -f -p 70 $(pgrep modeld)            # change priority of running process
chrt -p $(pgrep camerad)                 # query scheduler class and priority
```

### RT Throttling

```bash
cat /proc/sys/kernel/sched_rt_runtime_us   # default 950000 (950 ms)
cat /proc/sys/kernel/sched_rt_period_us    # default 1000000 (1 s) — 95% CPU cap for all RT tasks
```

RT tasks are collectively throttled to 95% of CPU by default — non-RT tasks retain at least 5%. Setting `sched_rt_runtime_us = -1` disables throttling entirely; used in AV/robotics setups where all RT tasks have known bounded runtime and starvation of non-RT is acceptable.

---

## SCHED_RR

Same as SCHED_FIFO plus a time slice.

- Within the same priority level, tasks round-robin after their slice expires
- Slice length: `/proc/sys/kernel/sched_rr_timeslice_ms` (default 100 ms)
- Useful when multiple equal-priority RT tasks must share time without cooperative yielding

---

## SCHED_DEADLINE

`dl_sched_class`; uses Constant Bandwidth Server (CBS) with Earliest Deadline First (EDF).

### Parameters

```c
struct sched_attr attr = {
    .size           = sizeof(attr),
    .sched_policy   = SCHED_DEADLINE,
    .sched_runtime  = 5000000,    /* 5 ms: CPU budget per period */
    .sched_deadline = 16666666,   /* 16.7 ms: relative deadline from period start */
    .sched_period   = 16666666,   /* 16.7 ms: period — 60 fps */
};
sched_setattr(0, &attr, 0);       /* requires CAP_SYS_NICE */
```

### Properties

- **Admission control**: kernel rejects `sched_setattr()` with `EBUSY` if adding this task makes sum(runtime/period) > 1.0 on the CPU set — a hard schedulability guarantee
- **Budget enforcement**: task is descheduled after consuming its `runtime` budget; replenished at the next period — misbehaving tasks cannot starve others
- **No static priority**: the kernel's EDF logic dynamically orders tasks by absolute deadline

```bash
# 30fps inference: 10ms budget, 33ms deadline, 33ms period
chrt -d --sched-runtime 10000000 --sched-deadline 33333333 --sched-period 33333333 0 ./modeld
```

---

## Scheduler Inspection

```bash
cat /proc/[pid]/sched                    # vruntime, nr_voluntary_switches, nr_involuntary_switches
schedtool [pid]                          # scheduler class, priority, affinity (human-readable)

# Trace scheduler decisions
trace-cmd record -e sched_switch -e sched_wakeup ./workload
trace-cmd report | head -100

# Per-task scheduling latency report
perf sched record -- sleep 5
perf sched latency                       # avg/max wakeup-to-run latency per task

# Run queue latency histogram (eBPF; no recompile needed)
runqlat -m 10                            # histogram in milliseconds, 10 second window
```

### /proc/[pid]/sched Key Fields

| Field | Meaning |
|---|---|
| `nr_voluntary_switches` | Times task gave up CPU willingly (blocking I/O, sleep) |
| `nr_involuntary_switches` | Times task was preempted (slice expired, higher-priority task woke) |
| `se.load.weight` | CFS scheduling weight (derived from nice value) |
| `se.vruntime` | Accumulated virtual runtime |
| `policy` | Scheduler policy integer: 0=NORMAL, 1=FIFO, 2=RR, 6=DEADLINE |
| `prio` | Effective priority: 100=RT prio 99; 120=nice 0; 139=nice 19 |

High `nr_involuntary_switches` on `modeld` indicates CFS preemption — first signal to elevate to `SCHED_FIFO` or `SCHED_DEADLINE`.

---

## Summary

| Policy | Class | Priority range | Time slice | Preemptible by | Use case |
|---|---|---|---|---|---|
| `SCHED_DEADLINE` | `dl_sched_class` | EDF/CBS dynamic | Per runtime budget | Higher-deadline DL task | Periodic RT: modeld, sensor pipeline |
| `SCHED_FIFO` | `rt_sched_class` | 1–99 (99 highest) | None | Higher RT priority | Hard RT: CAN writes, actuation thread |
| `SCHED_RR` | `rt_sched_class` | 1–99 | `sched_rr_timeslice_ms` | Higher RT priority | Equal-priority RT sharing |
| `SCHED_NORMAL` | `fair_sched_class` | nice -20 to +19 | `sched_latency_ns / n` | Any RT or DL task | General processes, background work |
| `SCHED_IDLE` | `idle_sched_class` | Below nice +19 | CFS/EEVDF slice | Everything else | Telemetry, log compression |

---

## AI Hardware Connection

- `SCHED_DEADLINE` maps directly to periodic inference tasks: `modeld` at 30fps declares `runtime=10ms, deadline=33ms, period=33ms`; the kernel's admission control proves schedulability and enforces the budget — no user-space watchdog required.
- `SCHED_FIFO` at priority 50–70 is standard for openpilot `controlsd`: CAN bus writes at 100Hz must not be delayed by CFS jitter, which can exceed 5 ms on an untuned multi-process system.
- EEVDF (Linux 6.6) reduces tail latency for mixed workloads — relevant when TensorRT inference, sensor reading, and logging share the same Jetson without full CPU isolation; newly woken inference threads are scheduled sooner than under CFS's vruntime ordering.
- `chrt -f 50 $(pgrep modeld)` is a standard production tuning step on openpilot and Autoware-based AV stacks; for persistent configuration use systemd unit options `CPUSchedulingPolicy=fifo` and `CPUSchedulingPriority=50`.
- `rt_throttling` disabled (`sched_rt_runtime_us = -1`) is used in safety-certified AV ECU deployments where all RT tasks have formally verified bounded CPU usage and non-RT starvation is mitigated by running telemetry at `SCHED_IDLE`.
- `perf sched latency` after a field test surfaces scheduler-induced delays invisible in application-level timing — the primary diagnostic when inference latency increases in deployment vs. bench testing on the same hardware.
