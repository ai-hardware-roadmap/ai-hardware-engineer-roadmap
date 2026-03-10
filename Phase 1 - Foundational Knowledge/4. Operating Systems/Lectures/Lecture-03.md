# Lecture 3: Interrupts, Exceptions & Bottom Halves

## Interrupts vs Exceptions

| Type | Origin | Synchronous? | Example |
|---|---|---|---|
| Hardware interrupt | External device asserts IRQ line | No (async) | NIC packet arrives, GPU job done, camera frame end |
| Software interrupt | CPU executes INT/SVC instruction | Yes (sync trap) | System call, debug breakpoint |
| Exception (fault) | CPU detects error during instruction | Yes (sync) | Page fault, divide-by-zero, GP fault |
| Exception (abort) | Unrecoverable hardware error | Yes (sync) | Machine check, double fault |

Faults re-execute the faulting instruction after the handler resolves the error (e.g., page fault installs a PTE). Traps advance to the next instruction after the handler returns (e.g., syscall). Aborts do not return.

---

## Interrupt Controllers

### ARM GIC (Generic Interrupt Controller v3)

Used on Jetson Orin, Qualcomm SoCs, NXP i.MX.

| Interrupt type | ID range | Description |
|---|---|---|
| SGI (Software Generated) | 0–15 | IPI — one CPU signals another; used by scheduler migration and TLB shootdowns |
| PPI (Per-CPU Private) | 16–31 | Per-core timers, PMU (performance monitoring) |
| SPI (Shared Peripheral) | 32–1019 | All external device interrupts: cameras, GPUs, NVMe, CAN |

Priority levels: 0 (highest) to 255 (lowest). CPU interface register `PMR` (Priority Mask Register) masks interrupts below a threshold — used during spinlock-held sections.

```c
gic_send_sgi(target_cpu, sgi_id);  /* trigger IPI from kernel/smp.c */
```

### x86 APIC

- Local APIC per CPU: receives IPIs and local timer interrupts
- I/O APIC: routes external device IRQs to specific CPUs
- IDT (Interrupt Descriptor Table): 256 entries; 0–31 reserved for CPU exceptions; 32–255 for external IRQs and software traps
- TPR (Task Priority Register): masks interrupts at or below a priority level

---

## MSI and MSI-X (PCIe)

Legacy wire-based IRQs share physical lines, limiting parallelism. PCIe MSI replaces line assertion with a **memory write to a special MMIO address** — the CPU's APIC/GIC interprets the write as an interrupt.

| Feature | MSI | MSI-X |
|---|---|---|
| Max vectors per device | 32 | 2048 |
| Per-vector CPU affinity | No | Yes (each vector independently affinable) |
| Vector table location | Capability register | Separate BAR region |

### Why MSI-X Matters for AI Hardware

- **NVMe**: 32+ queues each get a dedicated MSI-X vector, pinned to the core running that queue's I/O — eliminates contention during large model weight loading via GPUDirect Storage.
- **NVIDIA GPU**: separate MSI-X vectors for CUDA compute engine completion, copy engine completion, and fault notification — CUDA's event system is built on per-engine MSI-X delivery.
- **NICs (100GbE)**: per-TX/RX-queue MSI-X enables multi-queue RSS without lock contention.

```bash
cat /proc/interrupts | grep nvidia   # per-CPU counts for each GPU MSI-X vector
cat /proc/interrupts | grep nvme     # per-queue NVMe completion counts
```

---

## Interrupt Handling Flow

```
Peripheral asserts interrupt line
  → Interrupt controller assigns IRQ number, selects target CPU
  → CPU completes current instruction; saves minimal state to kernel stack
  → IDT lookup (x86) or VBAR_EL1 vector table (ARM64)
  → ISR (top half): acknowledge hardware, store data, schedule bottom half
  → EOI written to interrupt controller
  → Pending softirqs checked and run (or deferred to ksoftirqd)
  → Return to preempted context (user space or a lower-priority kernel path)
```

---

## Top Half vs Bottom Half

| Half | Context | Can sleep? | Goal |
|---|---|---|---|
| Top half (hardirq / ISR) | IRQs disabled on local CPU | No | Acknowledge hardware; schedule deferred work; must complete in < 1 µs ideal |
| Bottom half | IRQs re-enabled | Depends on mechanism | Process data; wake waiters; do actual work |

The ISR must be minimal: acknowledge the interrupt controller, save a pointer to received data, and schedule a bottom half. All I/O processing happens in bottom halves.

---

## Bottom-Half Mechanisms

### Softirqs

- 10 statically defined types: `NET_TX`, `NET_RX`, `BLOCK`, `TASKLET`, `SCHED`, `HRTIMER`, `RCU`, and others
- Run in interrupt context immediately after hardirq completion; can run concurrently on multiple CPUs simultaneously (no per-softirq lock)
- Cannot sleep; cannot be dynamically added without patching the kernel
- When backlog grows too large, `ksoftirqd/N` kernel threads drain the queue to bound latency

```c
raise_softirq(NET_RX_SOFTIRQ);   /* schedule NET_RX softirq from ISR */
```

### Tasklets

- Dynamically allocated; built on `TASKLET_SOFTIRQ`
- Serialized per instance — same tasklet cannot run on two CPUs simultaneously
- **Deprecated** in new driver code since Linux 5.x; migrate to workqueues or threaded IRQs

### Workqueues

Deferred work executed in kernel threads (`kworker/N:M`). Process context — can sleep, allocate memory, take mutexes.

```c
INIT_WORK(&work, handler_fn);         /* initialize work item */
schedule_work(&work);                  /* queue onto system_wq */
schedule_work_on(cpu, &work);         /* queue to specific CPU's kworker */

/* Dedicated high-priority workqueue for camera ISP completion */
wq = alloc_workqueue("isp_done", WQ_HIGHPRI | WQ_UNBOUND, 1);
queue_work(wq, &work);
```

| Workqueue | Threads | Use |
|---|---|---|
| `system_wq` | Shared `kworker` pool | General deferred work |
| `system_highpri_wq` | High-priority kworkers | Latency-sensitive paths (camera, CAN) |
| `system_unbound_wq` | CPU-unbound | Work that should migrate freely |
| Custom via `alloc_workqueue()` | Dedicated | Exclusive queue for one driver |

### Threaded IRQs

```c
request_threaded_irq(irq, hard_handler, thread_fn,
                     IRQF_SHARED, "cam-frame-done", dev);
```

- `hard_handler`: minimal hardirq context — acknowledges hardware, returns `IRQ_WAKE_THREAD`
- `thread_fn`: runs in dedicated kernel thread (`irq/N-cam-frame-done`) — can sleep, take locks, call `v4l2_buffer_done()`
- **Preferred for all new drivers**; required under `PREEMPT_RT` (mainlined in Linux 6.12)
- Thread priority is settable via `chrt`, enabling bounded latency via the RT scheduler
- `IRQF_NO_THREAD`: forces true hardirq context even under PREEMPT_RT — use only for interrupt controllers and `hrtimer`

---

## Interrupt Affinity

```bash
cat /proc/irq/42/smp_affinity         # hex bitmask (e.g., 0x8 = CPU 3)
cat /proc/irq/42/smp_affinity_list    # human-readable (e.g., "3")
echo 8 > /proc/irq/42/smp_affinity   # pin IRQ 42 to CPU 3
systemctl stop irqbalance             # prevent irqbalance from overriding manual settings
```

Pinning a GPU MSI-X completion vector to the same core as the CUDA stream management thread eliminates cross-core wakeup latency of 10–50 µs. Camera frame-done IRQs should be pinned away from RT inference cores to prevent ISR execution interfering with deadline tasks.

---

## Interrupt Coalescing: NAPI

For network and high-bandwidth devices, firing one interrupt per packet is unsustainable at high rates. NAPI (New API) uses interrupt coalescing:

1. First packet arrives → one interrupt fires
2. ISR disables further interrupts for this queue, schedules `poll()` callback
3. `poll()` runs in softirq context, drains the queue in a loop (up to budget packets)
4. Queue drained → re-enable interrupts

Tradeoff: coalescing adds latency (up to `ethtool -C eth0 rx-usecs`) but dramatically reduces interrupt overhead at high packet rates. Relevant for multi-camera Ethernet (GigE Vision) and RDMA NIC configurations in AI server racks.

---

## Exception Handling: Page Faults

Page fault is the most frequent exception in normal operation. Handler: `do_page_fault()` → `handle_mm_fault()`.

Fault reasons (ARM64 `ESR_EL1` or x86 CR2 + error code):
- Anonymous mapping not yet allocated: allocate physical page, update PTE, return
- File-backed mapping not in page cache: read from storage into cache, map PTE
- CoW write fault: allocate private copy, update PTE, return
- Permission fault on unmapped address: send SIGSEGV to process

Under `PREEMPT_RT`, page faults in RT threads introduce unbounded latency spikes. `mlockall(MCL_CURRENT | MCL_FUTURE)` prevents this by locking all pages in RAM before the RT phase begins.

---

## Summary

| Mechanism | Context | Can sleep? | Latency target | Example use |
|---|---|---|---|---|
| Top half (ISR/hardirq) | Interrupts disabled | No | < 1 µs | Acknowledge HW, start DMA |
| Softirq | Post-hardirq interrupt context | No | < 10 µs | Network RX/TX, block completion |
| Tasklet | Via softirq (serialized) | No | < 10 µs | Legacy; deprecated |
| Workqueue | Process context (kworker) | Yes | 10s–100s µs | General deferred work, memory allocation |
| Threaded IRQ | Process context (irq/N thread) | Yes | Bounded by RT scheduler | Modern drivers, PREEMPT_RT compatible |

---

## AI Hardware Connection

- GPU MSI-X per-engine completion vectors enable async CUDA stream operation; pinning each vector to the CUDA stream management core eliminates 10–50 µs cross-core wakeup overhead in inference pipelines.
- Camera frame-done ISR → threaded IRQ path (or workqueue) sets the end-to-end latency floor for `camerad`; measuring it with `bpftrace tracepoint:irq:irq_handler_entry` directly quantifies camera-to-model input delay in openpilot.
- NVMe per-queue MSI-X is prerequisite for GPUDirect Storage: each NVMe completion must wake the DMA engine on the correct NUMA node without cross-node memory traffic — requires both MSI-X and CPU affinity to be configured.
- Threaded IRQs are mandatory under PREEMPT_RT (Linux 6.12 mainline): camera and GPU completion handlers become schedulable threads, bounding their latency via the RT scheduler rather than interrupt-disable windows.
- `/proc/irq/N/smp_affinity` is the primary control point for IRQ isolation on AV platforms — GPU, NVMe, and camera IRQs are moved off RT cores to prevent top-half execution interfering with `modeld` and `controlsd` deadlines.
- FPGA AXI-stream DMA completion interrupts on Zynq/MPSoC follow the same top-half/workqueue pattern: the ISR acknowledges the CDMA, queues a work item that processes the result buffer and signals the inference thread via a wait queue.
