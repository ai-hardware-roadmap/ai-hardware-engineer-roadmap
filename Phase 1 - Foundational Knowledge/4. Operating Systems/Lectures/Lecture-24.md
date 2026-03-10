# Lecture 24: OS for AI Systems: L4T, openpilot OS & RT Tuning

This lecture synthesizes the OS curriculum into a practical reference for building AI hardware systems. Four platforms are covered: Jetson L4T, openpilot Agnos, Zephyr RTOS, and embedded Linux (custom Yocto).

## Jetson L4T (Linux for Tegra)

L4T is NVIDIA's downstream Linux distribution for Jetson SoCs. It tracks mainline LTS kernels with Tegra-specific patches.

- **L4T 36.x = Linux 6.1 LTS**: shipped with JetPack 6.x for Jetson Orin
- **L4T 35.x = Linux 5.10 LTS**: shipped with JetPack 5.x for Jetson AGX Orin and Xavier

### Key Downstream Drivers

| Driver module | Function | Interface |
|---|---|---|
| `nvdla.ko` | NVDLA AI accelerator | `/dev/nvhost-ctrl`; `dma_alloc_coherent` for inference buffers |
| `nvgpu` (gpu.ko) | Jetson GPU (replaces nouveau) | Custom `nvmap` allocator; CUDA via NVGPU API |
| `nvcsi.ko` / `tegra-vi.ko` | Camera CSI2 + Video Input | V4L2 driver; DMA-BUF buffer sharing |
| `tegra-vde.ko` | Video Decode Engine | V4L2 M2M; accelerated H.264/H.265 decode |
| `vic.ko` (VIC) | Video Image Compositor | 2D pre-processing before inference (resize, color convert) |

### Camera Pipeline (Argus API)

```
Sensor → NVCSI (CSI2 lane) → VI (Video Input) → ISP → nvmap/DMA-BUF buffer
                                                        ↓
                                                 CUDA inference (zero-copy)
```

`Argus::CaptureSession` → `Argus::Request` → `IEGLImageSource` → `EGLImage` → `cudaGraphicsEGLRegisterImage()` → CUDA device pointer. This is the zero-copy pipeline covered in Lecture 19.

### JetPack SDK Components

JetPack bundles: L4T kernel + BSP + CUDA + cuDNN + TensorRT + VPI (Vision Programming Interface) + Multimedia API + DeepStream SDK.

### Jetson Inference Tuning

```bash
sudo nvpmodel -m 0          # maximum power mode (all cores, max TDP)
sudo jetson_clocks           # lock CPU/GPU/memory clocks to maximum frequency
# CPU governor
echo performance | sudo tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor
```

Kernel config options for inference latency: `CONFIG_PREEMPT` (low-latency desktop) or `CONFIG_PREEMPT_RT` (full RT patch). RT patch reduces worst-case scheduling latency from ~1 ms to ~100 µs.

### Jetson OTA

- **A/B boot via UEFI capsule**: `UpdateCapsule()` UEFI runtime service writes new BSP to inactive slot
- **Extlinux.conf**: bootloader config selects active slot (`LABEL primary` vs `LABEL secondary`)
- **RPMB**: TrustZone secure world increments anti-rollback counter after successful capsule verification

## openpilot / Agnos OS

Agnos is openpilot's purpose-built OS based on Ubuntu 20.04 LTS with a custom kernel targeting the comma 3/3X hardware.

- **Kernel**: 5.10 LTS with Qualcomm Snapdragon 845 (SDM845) downstream patches
- **Hardware**: Snapdragon 845 CPU + Adreno 630 GPU + DSP; UFS storage; 4 cameras (3× road, 1× driver)

### Process Architecture

openpilot is structured as a collection of independent Linux processes communicating via cereal IPC. Each process runs at a defined scheduling priority:

| Process | Function | Scheduler | IPC role |
|---|---|---|---|
| `camerad` | V4L2 camera capture from 3 cameras | SCHED_FIFO 50 | VisionIPC producer |
| `modeld` | Supercombo neural net inference on GPU | SCHED_FIFO 55 | VisionIPC consumer; cereal publisher |
| `plannerd` | Trajectory planning from model outputs | SCHED_OTHER | cereal subscriber/publisher |
| `controlsd` | Lateral/longitudinal control; CAN output | SCHED_FIFO 50, 10 ms loop | cereal subscriber; SocketCAN writer |
| `sensord` | IMU + GPS data collection | SCHED_FIFO | cereal publisher |
| `pandad` | panda MCU USB communication; CAN relay | SCHED_FIFO | cereal publisher/subscriber |

### cereal IPC Framework

- **Schema**: capnproto `.capnp` definitions for all message types (carState, modelV2, lateralPlan, etc.)
- **Transport**: `msgq` — POSIX shared memory message queue; zero-copy for fixed-size messages
- **VisionIPC**: separate high-throughput path for video frames; `vipc_server` / `vipc_client`; buffer pool in shared memory; no video data copy between camerad → modeld

### VisionIPC Detail

```
camerad fills buffer[N]
  → semaphore post to modeld
modeld reads buffer[N] directly (mmap'd shared memory)
  → passes buffer pointer to GPU inference (DMA-BUF or nvmap import)
  → semaphore post to encoderd
encoderd reads same buffer[N] for H.265 encode
  → buffer returned to pool
```

No copies of the video frame occur between these three processes. The frame travels from V4L2 DMA → shared memory buffer → GPU, all without CPU-side memcpy.

## Zephyr RTOS (Microcontroller)

Zephyr is used for safety-critical MCU firmware in the openpilot ecosystem.

### Kernel Architecture

- **Scheduler**: preemptive, priority-based (0 = highest); cooperative threads; `k_yield()` for voluntary preemption
- **Thread API**: `K_THREAD_DEFINE(name, stack_sz, entry, prio, options, delay)`
- **Synchronization**: `k_mutex`, `k_sem`, `k_condvar`, `k_msgq` (fixed-size message queue), `k_pipe` (byte stream)
- **Interrupts**: `IRQ_CONNECT(irq, prio, isr, param, flags)`; ISRs must not block; use `k_work` for deferred processing

### Device Model and DTS

Zephyr uses the same DTS (Device Tree Source) concept as Linux. Hardware is described in `.dts` files; drivers use the `compatible` string to match. The same mental model transfers from Linux kernel driver development.

### Relevant Subsystems

- **CAN**: `can_send()` / `can_add_rx_filter()`; socketcan-compatible API; used for vehicle CAN bus communication
- **USB**: USB device stack; CDC ACM for serial-over-USB to host (pandad communication)
- **Power management**: device runtime PM; system sleep states
- **BLE**: Bluetooth LE stack (NimBLE or Zephyr BLE); used in comma body robot

### panda MCU Role

panda is an open-source CAN gateway (STM32-based) running Zephyr. It:

- Receives CAN frames from 3 vehicle CAN buses via hardware CAN transceivers
- Filters and relays frames to openpilot host via USB (pandad)
- Receives control commands from openpilot; injects them onto the vehicle CAN bus
- Implements a safety layer: validates command ranges; blocks unsafe commands regardless of host request

## RT Tuning Checklist (Production)

| Item | Setting | Purpose |
|---|---|---|
| Kernel | `CONFIG_PREEMPT_RT` or `CONFIG_PREEMPT` | Bounded scheduling latency |
| Boot parameters | `isolcpus=N nohz_full=N rcu_nocbs=N` | Dedicate cores; no timer ticks; no RCU callbacks |
| CPU frequency | `scaling_governor=performance` | No frequency transition jitter |
| IRQ affinity | Move IRQs to non-RT cores via `/proc/irq/*/smp_affinity` | Reduce RT core interference |
| NUMA balancing | `echo 0 > /proc/sys/kernel/numa_balancing` | No page migration jitter |
| RT process setup | `mlockall(MCL_CURRENT|MCL_FUTURE)` + `SCHED_FIFO` or `SCHED_DEADLINE` | No page faults; deterministic scheduling |
| Huge pages | `madvise(MADV_HUGEPAGE)` on inference buffers | Reduce TLB misses; fewer page walks |
| OOM protection | `echo -1000 > /proc/<PID>/oom_score_adj` | Critical process survives OOM kill |
| Validation | `cyclictest -m -p99 -t8 -i200 -D24h` | Worst-case latency must be < 100 µs |

### SCHED_DEADLINE for Periodic Tasks

`SCHED_DEADLINE` is preferable to `SCHED_FIFO` for periodic tasks with known timing requirements:

```c
struct sched_attr attr = {
    .size        = sizeof(attr),
    .sched_policy = SCHED_DEADLINE,
    .sched_runtime  = 2000000,   // 2 ms worst-case runtime
    .sched_deadline = 10000000,  // 10 ms deadline
    .sched_period   = 10000000,  // 10 ms period
};
sched_setattr(0, &attr, 0);
```

`controlsd` in openpilot runs a 10 ms control loop. `SCHED_DEADLINE` with 10 ms period and 2 ms runtime guarantee prevents CPU starvation even under high system load.

## Summary

| Platform | Kernel | Key drivers | IPC | Use case |
|---|---|---|---|---|
| Jetson Orin | L4T 6.1 (LTS) | `nvdla`, `nvgpu`, `nvcsi` | VisionIPC, DMA-BUF | Edge AI inference |
| openpilot (Agnos) | L4T / Agnos 5.10 | V4L2, SocketCAN | cereal msgq, VisionIPC | Autonomous driving |
| Zephyr (panda) | RTOS 3.x | CAN, USB CDC, BLE | `k_msgq`, `k_pipe` | MCU safety firmware |
| Yocto custom | Custom LTS | Platform-specific BSP | mmap, POSIX | Custom embedded AI |

## AI Hardware Connection

- Jetson L4T NVDLA driver combined with DMA-BUF zero-copy delivers the complete camera-to-inference pipeline with minimal latency; every component from ISP output to CUDA inference operates without CPU-side data copies
- openpilot VisionIPC and cereal demonstrate production-grade OS-level IPC design: zero-copy video via shared memory pools and capnproto-serialized control messages over msgq, achieving multi-process AV software with no video data copies
- `SCHED_DEADLINE` on controlsd with a 10 ms period and 2 ms runtime budget ensures CAN output meets the actuator deadline even under transient CPU load spikes
- Zephyr on the panda MCU implements the safety-critical CAN gateway between openpilot's Linux process and the vehicle; hardware-enforced command range validation runs at the RTOS level, independent of host OS state
- The RT tuning checklist (isolcpus + nohz_full + mlockall + SCHED_FIFO/DEADLINE + hugepages) is directly applicable to any edge AI system requiring deterministic inference timing, from autonomous vehicles to industrial robotics
- Container runtime (NVIDIA Container Toolkit) + cgroups v2 cpuset isolation + Triton dynamic batching forms the production deployment stack for TensorRT inference in Kubernetes, combining GPU access with CPU core dedication
