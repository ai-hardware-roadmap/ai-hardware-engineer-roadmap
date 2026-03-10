# Lecture 10: Lock-Free Programming: RCU, Atomics & Memory Ordering

## Motivation for Lock-Free

Locks introduce unavoidable costs even when not contended:

- **Cache-line bouncing**: the lock variable ping-pongs between CPU L1 caches during contention; each acquire costs ~100–300 cycles on NUMA
- **Context switches**: blocked threads incur scheduler overhead (~1–10µs per switch)
- **Priority inversion**: low-priority lock holder delays high-priority waiter (see Lecture 11)
- **Convoying**: multiple threads queue behind one slow holder, serializing a hot path

Lock-free algorithms use atomic hardware primitives to achieve safe concurrent access without mutual exclusion. They provide better scalability and eliminate priority inversion on performance-critical paths.

## C++11/C11 Memory Model

CPUs and compilers reorder instructions for performance. The C11/C++11 memory model defines ordering guarantees via `std::atomic<T>` / `_Atomic T`:

| Memory Order | Guarantee |
|---|---|
| `memory_order_relaxed` | Atomicity only; no ordering relative to other operations; use for counters |
| `memory_order_acquire` | No load/store after this point may be reordered before it; pairs with release |
| `memory_order_release` | No load/store before this point may be reordered after it; pairs with acquire |
| `memory_order_acq_rel` | Both acquire + release; for atomic read-modify-write operations |
| `memory_order_seq_cst` | Total global order across all threads; full fence; default for `std::atomic<>` |

**Acquire-release pairing**: a `release` store to variable X "happens-before" a subsequent `acquire` load from X in another thread. All writes before the release are visible after the acquire.

## Hardware Memory Models

| Architecture | Memory Model | Barrier Requirement |
|---|---|---|
| x86-64 | TSO (Total Store Order) — relatively strong | Few explicit barriers needed; LOCK prefix for atomics |
| ARM64 | Weakly ordered | Explicit `DMB`/`DSB` barriers required; `LDADD`/`CAS` for atomics |
| RISC-V | Weakly ordered (RVWMO) | `FENCE` instruction; `LR`/`SC` for LL/SC atomics |

Linux kernel barrier macros:
- `smp_mb()`: full memory barrier (load + store in both directions)
- `smp_rmb()`: read (load) barrier only
- `smp_wmb()`: write (store) barrier only

## Atomic Operations

Map to single indivisible hardware instructions: `LOCK ADD`/`XADD`/`CMPXCHG` on x86, `LDADD`/`CAS` on ARMv8.1 LSE.

```c
atomic_t counter = ATOMIC_INIT(0);
atomic_inc(&counter);                        // LOCK XADD on x86
atomic_dec_and_test(&counter);               // returns true if result is zero
int old = atomic_cmpxchg(&counter, 5, 10);  // CAS: if counter==5, set to 10; return old value
atomic_add_return(n, &counter);              // add n, return new value
```

- `atomic_t` is 32-bit; `atomic64_t` for 64-bit values
- `ATOMIC_INIT(n)` for static initialization
- Use for: reference counts, flags, per-CPU statistics accumulators

## Compare-and-Swap (CAS)

Foundation of most lock-free data structures.

```cpp
std::atomic<int> val{0};
int expected = 0;
// Atomically: if val == expected, set val = 1; return true
// If val != expected: expected = val (actual value); return false
bool ok = val.compare_exchange_strong(expected, 1,
              std::memory_order_acq_rel,
              std::memory_order_acquire);
// On failure, retry loop uses updated 'expected'
```

`compare_exchange_weak`: may spuriously fail on LL/SC architectures (ARM, RISC-V); preferred inside retry loops because it avoids a separate load instruction.

### ABA Problem

CAS sees the same value but the object was replaced: pointer A → B → A between load and CAS; CAS succeeds incorrectly.

Solutions:
- **Version tag**: pack a monotonically increasing counter alongside the pointer in a 128-bit CAS (`CMPXCHG16B` on x86-64); pointer change is always detectable
- **Hazard pointers**: reader publishes pointer before dereferencing; reclaimer scans all hazard pointer slots before freeing
- **RCU**: grace period mechanism ensures old objects are not freed until all readers are done

## SPSC Ring Buffer (Lock-Free)

Single-producer / single-consumer ring buffer requires only `acquire`/`release` atomics on head and tail indices. No locks, no cache-line bouncing on payload data.

```c
#define N 256  // must be power of 2
T buf[N];
atomic_size_t head = 0, tail = 0;  // head: consumer index, tail: producer index

// Producer (single thread only)
buf[tail % N] = item;
atomic_store_explicit(&tail, tail + 1, memory_order_release);

// Consumer (single thread only)
size_t t = atomic_load_explicit(&tail, memory_order_acquire);
if (head != t) {
    item = buf[head % N];
    atomic_store_explicit(&head, head + 1, memory_order_release);
}
```

Throughput: limited only by memory bandwidth; no lock overhead. Used in openpilot VisionIPC for zero-copy camera frame passing from capture process to inference process at 30Hz.

## RCU (Read-Copy-Update)

Linux kernel's primary mechanism for read-mostly shared data structures. Achieves O(1) read-side overhead: no locks, no atomics, no cache-line writes.

### Reader Side

```c
rcu_read_lock();                    // disable preemption; O(1); no memory barrier emitted
ptr = rcu_dereference(gp);          // loads pointer with READ_ONCE + compiler barrier
/* safely use *ptr — guaranteed to remain valid until rcu_read_unlock */
rcu_read_unlock();                  // re-enable preemption
```

Only cost: disable/enable preemption — a single per-CPU flag write.

### Writer Side

```c
new_obj = kmalloc(sizeof(*new_obj), GFP_KERNEL);
*new_obj = *old_obj;               // copy the object
new_obj->field = updated_value;    // modify the copy
rcu_assign_pointer(gp, new_obj);   // atomic publish: smp_wmb() + pointer store
synchronize_rcu();                 // block until all CPUs complete in-progress read sections
kfree(old_obj);                    // safe: no reader can still hold old_obj
```

`call_rcu(&old->rcu_head, free_fn)`: asynchronous callback form; avoids blocking `synchronize_rcu()`; used in interrupt context or when writer must not block.

### Grace Period

A **grace period** is the interval after `rcu_assign_pointer()` until every CPU has passed through a **quiescent state**: a context switch, entry to idle, or return to user space. After the grace period, no pre-existing reader can hold a reference to the old pointer.

### RCU Variants

| Variant | Read Section Can Sleep? | Use Case |
|---|---|---|
| Classic RCU | No | Routing tables, `task_struct` lookup, module parameters |
| SRCU (Sleepable RCU) | Yes | Notifier chains, subsystem registrations |
| PREEMPT_RCU | No (but preemptible) | `CONFIG_PREEMPT` kernels |

### rcu_nocbs= Kernel Parameter

`rcu_nocbs=<cpulist>` offloads `call_rcu` callbacks to `rcuoc` kthreads running on non-isolated CPUs. Eliminates RCU callback invocations from isolated RT or inference cores, removing a source of unpredictable latency jitter.

## kfifo — Kernel Lock-Free SPSC FIFO

```c
DECLARE_KFIFO(my_fifo, int, 64);   // static SPSC FIFO of 64 ints
INIT_KFIFO(my_fifo);

kfifo_put(&my_fifo, value);        // producer; no lock needed for SPSC
kfifo_get(&my_fifo, &value);       // consumer; no lock needed for SPSC
kfifo_len(&my_fifo);               // number of elements available
```

Used in kernel drivers for RX data buffers between ISR (producer) and process context (consumer).

## Hazard Pointers

Userspace alternative to RCU for lock-free memory reclamation:
- Reader **publishes** the pointer it is about to dereference into a per-thread hazard pointer slot
- Before freeing, the reclaimer scans all hazard pointer slots for the pointer
- If found, deferral is required; if not found, free is safe

Used in: Folly (Meta), Java `java.util.concurrent`. `std::hazard_pointer` standardized in C++26.

## Summary

| Technique | Reader Overhead | Writer Overhead | Safe for ISR? | Main Limitation |
|---|---|---|---|---|
| Spinlock | Cache-line write + spin | Cache-line write | Yes | Wasted CPU; no sleep |
| CAS loop | Atomic RMW + retry | Atomic RMW + retry | Yes | ABA problem; retry cost |
| SPSC ring buffer | Acquire load | Release store | Yes (producer or consumer) | Single producer AND single consumer only |
| RCU | Preempt disable/enable | Copy + grace period | No (synchronize_rcu blocks) | Writer pays grace period; read-mostly |
| Hazard pointers | Publish + load | Scan all HP slots | No | Higher reclamation overhead than RCU |
| `kfifo` | Acquire load | Release store | Yes | Kernel-only; SPSC only |

## AI Hardware Connection

- RCU enables live model configuration updates (LoRA adapter swaps, quantization config changes) without pausing inference threads; the writer publishes the new config atomically and the old config is freed only after all in-progress forward passes exit their read sections
- SPSC ring buffer with `acquire`/`release` atomics provides the zero-copy camera frame pipeline in openpilot VisionIPC, eliminating mutex overhead on the 30Hz video path between `camerad` and `modeld`
- `rcu_nocbs=` on Jetson inference-dedicated cores removes RCU callback execution jitter, enabling sub-millisecond worst-case latency bounds on isolated real-time inference cores
- CAS-based lock-free queue is used in openpilot VisionIPC for multi-producer sensor data aggregation: each sensor driver enqueues readings without a mutex; the inference thread drains the queue once per inference cycle
- Atomic reference counts (`kref`, `std::atomic<int>`) manage DMA-BUF buffer lifetimes across multiple GPU consumers in the V4L2 + CUDA pipeline; the buffer is freed only when the last consumer decrements the count to zero
- SPSC ring buffer is the correct data structure for ISR-to-inference-thread pipelines; using a mutex in an ISR would require `spin_lock_irqsave`, adding latency; the atomic ring buffer avoids this entirely
