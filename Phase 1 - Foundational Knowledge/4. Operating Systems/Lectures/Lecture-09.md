# Lecture 9: Synchronization: Spinlocks, Mutexes, RW Locks & Seqlocks

## Mutual Exclusion Problem

A **race condition** occurs when multiple CPUs or threads access shared state concurrently without coordination, and the outcome depends on scheduling order.

Three requirements for correct mutual exclusion:

1. **Mutual exclusion**: at most one thread in the critical section at a time
2. **Progress**: if no thread is in the critical section, a waiting thread must eventually enter
3. **Bounded waiting**: no thread waits indefinitely (no starvation)

## Spinlock (`spinlock_t`)

Busy-waits (spins) on an atomic test-and-set instruction until the lock is available. Disables preemption on the local CPU while held.

```c
spin_lock(&lock);                        // acquire; disables preemption
/* critical section */
spin_unlock(&lock);                      // release; re-enables preemption

// When data is shared with an interrupt service routine:
spin_lock_irqsave(&lock, flags);         // disables preemption + local IRQs; saves IRQ state
/* critical section (safe against ISR) */
spin_unlock_irqrestore(&lock, flags);    // restores IRQ state + re-enables preemption
```

Key constraints:
- Only for very short critical sections (<1µs); holding while sleeping is a kernel bug
- On NUMA systems, contended spinlocks cause cache-line bouncing across sockets
- Under `PREEMPT_RT`: `spinlock_t` becomes a sleeping `rtmutex`; `raw_spinlock_t` retains true spin behavior

## Mutex (`struct mutex`)

Task blocks (`TASK_UNINTERRUPTIBLE`) if lock is unavailable; scheduler runs other tasks. No CPU wasted spinning.

```c
mutex_lock(&mutex);                    // blocks until acquired; process context only
/* critical section */
mutex_unlock(&mutex);

mutex_trylock(&mutex);                 // non-blocking; returns 1 if acquired, 0 if not
mutex_lock_interruptible(&mutex);      // returns -EINTR if signal received while waiting
```

- Cannot use in interrupt context — interrupts cannot sleep
- Userspace equivalent: `pthread_mutex_t` backed by `futex` (fast path avoids syscall when uncontended)
- Kernel `mutex` is not the same as `pthread_mutex_t`; different implementation and rules

### rtmutex — Priority Inheritance Mutex

`rtmutex` is a mutex with **priority inheritance (PI)**:
- When high-priority task `H` blocks on an `rtmutex` held by low-priority task `L`, the kernel temporarily boosts `L`'s priority to `H`'s level
- `L` runs sooner, releases the lock sooner, `H` unblocks; `L` returns to original priority on release
- Under `PREEMPT_RT`, most kernel `spinlock_t` instances are replaced with `rtmutex`
- Prevents the Mars Pathfinder scenario (see Lecture 11) in kernel code

## Read/Write Semaphore (`struct rw_semaphore`)

Allows multiple concurrent readers **or** one exclusive writer; not both simultaneously.

```c
down_read(&rw_semaphore);          // shared read lock; multiple readers concurrent
/* read shared data */
up_read(&rw_semaphore);

down_write(&rw_semaphore);         // exclusive write lock; blocks all readers + writers
/* modify shared data */
up_write(&rw_semaphore);

// Downgrades write lock to read lock without releasing (atomic)
downgrade_write(&rw_semaphore);
```

- Sleeping lock; process context only; cannot use in interrupt context
- Writer-bias: once a writer is waiting, new readers are blocked to prevent writer starvation
- Used for: `mmap_lock` (in `mm_struct`), filesystem inode locks, device driver config tables
- Spinlock variant `rwlock_t` exists for interrupt context (busy-waits; not sleeping)

## Seqlock (`seqlock_t`)

Writers never block. Readers detect concurrent writes via a sequence counter and retry if needed.

```c
// Writer — always proceeds immediately, never blocks
write_seqlock(&seqlock);
/* increment sequence counter (now odd = write in progress) */
/* modify shared data */
write_sequnlock(&seqlock);
/* increment sequence counter again (now even = write complete) */

// Reader — retries if a concurrent write was detected
unsigned seq;
do {
    seq = read_seqbegin(&seqlock);   // returns counter; odd means write in progress (retry)
    /* read shared data */
} while (read_seqretry(&seqlock, seq));  // retries if counter changed during read
```

Properties:
- Writer overhead: two atomic counter increments; no blocking
- Reader overhead on write-free path: two reads of the counter (extremely cheap)
- Reader overhead on write path: retry loop (rare if writes are infrequent)
- Not suitable for pointer-containing data (reader may dereference freed pointer before retry detects the change)

Linux kernel uses seqlocks for: `jiffies_64`, `timespec64` for clock reads, kernel `xtime` timekeeping, `vDSO` time variables.

## Completion (`struct completion`)

One-shot synchronization: thread A waits for an event signaled by thread B. Cleaner than a semaphore for one-time events.

```c
DECLARE_COMPLETION(dma_done);         // static declaration

// Waiter thread
wait_for_completion(&dma_done);               // blocks in TASK_UNINTERRUPTIBLE
wait_for_completion_timeout(&dma_done, HZ);   // with timeout; returns 0 on timeout
wait_for_completion_interruptible(&dma_done); // can be interrupted by signal

// Signaler (e.g., DMA completion ISR)
complete(&dma_done);      // wake one waiter
complete_all(&dma_done);  // wake all waiters

reinit_completion(&dma_done);  // reset for reuse
```

Use cases: DMA transfer complete notification, kthread startup synchronization, driver probe sequencing, FPGA firmware load completion.

## lockdep — Lock Dependency Validator

`CONFIG_PROVE_LOCKING` enables lockdep, the kernel's runtime lock dependency validator:

- Assigns each lock a **lock class** based on its static address in the binary
- Records lock acquisition chains: "lock A held when lock B was acquired"
- Reports **AB-BA cycles** (potential deadlocks) at first occurrence — before they manifest as actual hangs
- Reports **lock-from-interrupt violations**: sleeping lock acquired in interrupt context
- Output: `WARNING: possible circular locking dependency` with full stack traces in `dmesg`

```bash
# Enable in kernel config
CONFIG_PROVE_LOCKING=y
CONFIG_LOCK_STAT=y    # adds lock contention statistics

# View lock stats
cat /proc/lock_stat | head -40
```

Always enable during driver development and regression testing. `lockdep` adds ~10% overhead; disable in production.

## Summary

| Primitive | Context Usable | Blocks? | PI Support | Best For |
|---|---|---|---|---|
| `spinlock_t` | Process + IRQ | No (busy-wait) | No | Short CS (<1µs), ISR-shared data |
| `raw_spinlock_t` | Process + IRQ | No (busy-wait) | No | Hardware-critical, cannot be sleeping lock |
| `mutex` | Process only | Yes | No | Longer CS in process context |
| `rtmutex` | Process only | Yes | Yes | RT tasks, PREEMPT_RT kernel |
| `rwlock_t` | Process + IRQ | No (spin) | No | Read-heavy, short CS, IRQ context |
| `rw_semaphore` | Process only | Yes | No | Read-heavy, longer CS |
| `seqlock_t` | Process + IRQ (writer); retry (reader) | Writer: No; Reader: retry | No | Rarely-written, frequently-read data |
| `struct completion` | Process only | Yes | No | One-shot event signaling |

## AI Hardware Connection

- `spin_lock_irqsave` in a camera DMA completion ISR protects the current frame buffer index shared with the inference thread; must not sleep in interrupt context; critical section is a single index write
- `rw_semaphore` for model weight hot-reload: many concurrent inference threads hold the read lock during forward passes; the weight updater holds the write lock only during the pointer swap, so inference is never stalled longer than the swap itself
- Seqlock passes hardware timestamps from the sensor acquisition thread to the fusion pipeline without blocking the sensor thread on slow readers; reader retries are negligible since sensor writes occur at 100Hz against reads at 1kHz
- `completion` for "DMA transfer done" synchronization in FPGA accelerator drivers: the host CPU submits a command buffer, blocks on `wait_for_completion`, and the FPGA interrupt handler calls `complete()` when processing finishes
- `rtmutex` with priority inheritance is essential on PREEMPT_RT AV compute platforms; all `spinlock_t` locks become `rtmutex` instances system-wide, providing PI in every kernel subsystem without modifying driver code
- `lockdep` during Jetson embedded driver development catches AB-BA lock ordering violations in camera, ISP, and DMA subsystems before the hardware is deployed in a vehicle or robot
