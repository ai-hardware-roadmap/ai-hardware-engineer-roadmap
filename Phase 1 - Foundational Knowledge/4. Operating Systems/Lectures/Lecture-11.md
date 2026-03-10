# Lecture 11: Deadlock, Priority Inversion & PI Mutexes

## Deadlock: Definition

A **deadlock** is a state where a set of processes are each waiting for a resource held by another process in the set, and no process can ever make progress.

## Coffman Conditions

All four conditions must hold simultaneously for a deadlock to be possible. Breaking any single one prevents deadlock.

| Condition | Definition |
|---|---|
| Mutual exclusion | At least one resource is non-sharable — only one process may hold it at a time |
| Hold-and-wait | A process holds at least one resource while waiting to acquire additional resources |
| No preemption of resources | Resources cannot be forcibly taken from a holder; only voluntary release |
| Circular wait | A cycle exists in the resource-allocation graph: P1 → R1 → P2 → R2 → P1 |

## Deadlock Prevention

Attack one of the four conditions at design time:

| Condition to Break | Technique | Trade-off |
|---|---|---|
| Hold-and-wait | Acquire all locks simultaneously before starting; release all if any acquisition fails | Reduces concurrency; may require retry |
| Circular wait | Global lock ordering: always acquire locks in a fixed, documented order | Requires discipline across all call sites; lockdep enforces this |
| No preemption | `mutex_trylock()` with randomized exponential backoff | Retry overhead; potential livelock |
| Mutual exclusion | Use lock-free data structures | Higher implementation complexity |

**Global lock ordering** is the most practical approach in kernel and embedded code. Linux documents lock ordering in code comments and enforces it at runtime with lockdep annotations (`lockdep_assert_held`, `lockdep_set_class`).

## Deadlock Detection

When prevention is too costly, the OS can detect deadlocks at runtime:

- **Resource allocation graph**: nodes for processes (P) and resources (R); edge P→R means P waits for R; edge R→P means R is held by P; a cycle indicates deadlock
- **Wait-for graph**: simplified form; edge P→Q means P waits for something held by Q; cycle = deadlock

Recovery options after detection:
1. Abort one process; free its resources; select victim by cost (priority, runtime, resources held)
2. Preempt a resource from one process and give to another (requires rollback support)
3. Roll back a process to a safe checkpoint (requires checkpointing infrastructure)

`lockdep` in Linux performs static-analysis-style deadlock detection at runtime without waiting for the deadlock to actually occur.

## Priority Inversion

Priority inversion occurs when a high-priority task `H` is effectively blocked by a medium-priority task `M` through an indirect chain involving a shared resource.

### Mechanism

1. `L` (low priority) acquires mutex `M`
2. `H` (high priority) wakes and tries to acquire mutex `M` — blocks waiting for `L`
3. `M` (medium priority) wakes and preempts `L` (`M` > `L` in priority)
4. `L` cannot run to release mutex `M`; `H` waits indefinitely despite being highest priority

Effective priority of `H` is inverted to below `M`'s level for the entire duration of `M`'s execution. Duration of inversion is **unbounded** without PI.

## Mars Pathfinder Case Study (1997)

The Mars Pathfinder rover experienced periodic system resets approximately 18 hours after landing on the Martian surface.

**Root cause: unbounded priority inversion**

| Task | Priority | Role |
|---|---|---|
| `bc_dist` | High | Data distribution bus — held the critical mutex |
| `bc_sched` | Low | Bus scheduler — also needed the mutex to release it |
| `ASI_MET` | Medium | Meteorological data acquisition — CPU-intensive |

Sequence: `bc_sched` (low) held the mutex → `bc_dist` (high) blocked waiting → `ASI_MET` (medium) preempted `bc_sched` and ran continuously → `bc_sched` never ran → `bc_dist` missed its watchdog deadline → VxWorks watchdog timer fired → full system reset.

**Fix**: enable the `PTHREAD_PRIO_INHERIT` flag on the shared VxWorks mutex. The PI feature existed in VxWorks but was disabled by default. The fix was uploaded to the already-landed rover via uplink command.

**Lesson for AV/robotics**: priority inversion can cause safety-critical resets in deployed, inaccessible hardware. PI mutexes must be the default for any resource shared between tasks of different priorities in safety-critical systems.

## Priority Inheritance (PI)

When high-priority task `H` blocks on a mutex held by low-priority task `L`, the kernel **temporarily boosts** `L`'s scheduling priority to `H`'s level. The boost is removed when `L` releases the mutex.

- **Transitive PI**: if `L` is also blocked on another mutex held by `X`, the boost propagates to `X` along the entire blocking chain
- Linux `rtmutex` implements PI for kernel code and userspace (via `FUTEX_LOCK_PI`)
- PREEMPT_RT converts most kernel `spinlock_t` to `rtmutex` → system-wide PI without changing driver code

```c
// POSIX userspace PI mutex
pthread_mutexattr_t attr;
pthread_mutexattr_init(&attr);
pthread_mutexattr_setprotocol(&attr, PTHREAD_PRIO_INHERIT);
pthread_mutex_init(&mutex, &attr);
// Requires SCHED_FIFO/SCHED_RR threads for PI to have meaningful effect
```

## Priority Ceiling Protocol

Each mutex is assigned a **ceiling priority** = highest priority of any task that will ever acquire it. Any task acquiring the mutex immediately runs at the ceiling priority for the duration of ownership.

- Prevents priority inversion entirely without needing runtime priority discovery
- Requires static analysis: all potential lock acquirers and their priorities must be known at design time
- POSIX: `PTHREAD_PRIO_PROTECT` protocol (`pthread_mutexattr_setprotocol`)
- Mandated by: ARINC 653 (avionics partitioned RTOS), AUTOSAR OS (automotive ECUs)
- Stronger formal guarantees than PI for safety-certified systems where the task model is fixed at configuration time

## lockdep — Live Deadlock Detector

`CONFIG_PROVE_LOCKING` enables lockdep, the kernel's runtime lock dependency graph validator:

```bash
CONFIG_PROVE_LOCKING=y
CONFIG_LOCK_STAT=y      # adds per-lock contention statistics
```

- Assigns each lock a **lock class** based on its static address in the kernel binary
- Records every lock acquisition chain: "lock A was held when lock B was acquired"
- Reports AB-BA cycles at first detection — before they manifest as actual hangs
- Reports invalid lock-from-interrupt context: e.g., `mutex_lock()` called from hardirq context

```
WARNING: possible circular locking dependency detected
task/1234 is trying to acquire lock:
  (&lockB){...}, at: function_b+0x30
but task holds lock:
  (&lockA){...}, taken at: function_a+0x20
which lock already depends on the new lock.
```

Enable during all development, CI, and regression testing. `lockdep` adds ~10% runtime overhead; disable in production or performance-sensitive contexts.

`lockdep_assert_held(&lock)`: assertion that documents and verifies that a lock is held at a given point; useful for complex drivers with multi-step lock protocols.

## Watchdog Timers as Last Resort

Hardware or software watchdog: if a process does not kick the watchdog within the timeout period, the system resets or enters a safe state. Provides defense-in-depth against deadlocks that escape lockdep in deployed hardware.

The Mars Pathfinder watchdog worked correctly; it correctly detected `bc_dist` missing its deadline. The root problem was the missing PI configuration that caused `bc_dist` to miss the deadline in the first place.

## Summary

| Problem | Symptom | Detection Tool | Solution |
|---|---|---|---|
| Deadlock | System hangs; tasks blocked forever | Resource allocation graph; lockdep | Lock ordering; acquire-all-at-once; `trylock` + backoff |
| Priority inversion | High-priority task stalls unexpectedly | Latency monitoring; watchdog timeout | PI mutex (`rtmutex`, `PTHREAD_PRIO_INHERIT`); priority ceiling |
| Livelock | Tasks run but make no progress | CPU profiling (100% util, no throughput) | Randomized backoff; central arbitration |
| Starvation | Low-priority task never runs | Long wait monitoring; `perf sched` | Aging; FIFO wait queues; priority boosting |

## AI Hardware Connection

- PI mutex (`rtmutex` / `PTHREAD_PRIO_INHERIT`) is required for openpilot `controlsd` (highest priority) sharing cereal shared-memory state with `plannerd` (medium) and log-writing processes (low); without PI, the Mars Pathfinder scenario can recur in a production AV system
- The Mars Pathfinder root cause analysis is a mandatory reference document in ASIL-B safety reviews; it demonstrates that priority inversion can cause safety-critical resets in deployed, inaccessible hardware with zero possibility of manual intervention
- `PTHREAD_PRIO_INHERIT` is used in ROS2 real-time executor configurations to prevent control callbacks from being starved by data-logging threads; the rclcpp real-time executor documentation explicitly references this requirement
- `lockdep` is standard practice during embedded Linux driver development on Jetson and i.MX platforms; AB-BA cycles in camera, ISP, and DMA subsystem locks must be eliminated before hardware deployment
- Priority ceiling protocol is used in AUTOSAR-compliant ECU software where all task priorities and shared resource sets are fixed at configuration time; this is stronger than PI for ASIL-D certified safety functions
- PREEMPT_RT's system-wide conversion of `spinlock_t` to `rtmutex` means that PI is automatically applied to all kernel synchronization on the CAN bus driver, V4L2 camera driver, and GPU driver without any driver code changes
