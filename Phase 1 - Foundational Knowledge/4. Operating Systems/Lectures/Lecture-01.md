# Lecture 1: Modern OS Architecture & the Linux Kernel

## OS Definition: Three Roles

| Role | Meaning |
|---|---|
| Resource manager | Arbitrates CPU time, memory pages, I/O bandwidth, and network across competing processes |
| Abstraction layer | Presents uniform interfaces (files, sockets, virtual memory) over heterogeneous hardware |
| Protection boundary | Isolates processes from each other and from kernel data structures; enforced in hardware |

Without protection, a buggy camera driver corrupts kernel memory. Without abstraction, each application must know specific hardware register layouts.

---

## Privilege Levels

### x86 Rings

| Ring | Mode | Access | Example occupants |
|---|---|---|---|
| Ring 0 | Kernel | All instructions, I/O ports, MSRs, CR0/CR3 | Linux kernel, device drivers |
| Ring 1–2 | Unused | — | Historical OS/2; unused by Linux |
| Ring 3 | User | Restricted; privileged instruction → GP Fault | Applications, runtimes, Python |

Mode switch: `SYSCALL` instruction → Ring 0; `SYSRET` → Ring 3.

### ARM Exception Levels (AArch64)

| EL | Name | Purpose |
|---|---|---|
| EL0 | User | Applications, TensorRT, ONNX Runtime, ROS2 nodes |
| EL1 | Kernel | Linux kernel, exception handlers, MMU configuration |
| EL2 | Hypervisor | KVM, Xen; controls VM-to-VM memory partitioning |
| EL3 | Secure Monitor | ARM TrustZone, PSCI power management, BCT/BL31 signing |

The two-level EL0/EL1 split is sufficient for most deployments. EL2 adds virtualization overhead; EL3 handles secure world and is always present on Cortex-A platforms. On Jetson Orin (Cortex-A78AE), the Linux kernel runs at EL1 and NVIDIA MB1/SC7 firmware occupies EL3.

---

## Linux Kernel Architecture

Linux is a **monolithic kernel with loadable modules**: all core subsystems share a single address space at Ring 0 / EL1 with no IPC overhead between them. Drivers and filesystems compile as `.ko` modules inserted at runtime without rebuilding the kernel.

The monolithic design delivers fast in-kernel calls at the cost of shared fate — a crashing driver can panic the whole system. Contrast with microkernels (QNX, seL4) where drivers are separate processes; slower IPC, but crash isolation.

### Major Subsystems

| Directory | Subsystem | Responsibility |
|---|---|---|
| `kernel/` | Scheduler, signals, timers | CFS/EEVDF, workqueues, kthreads |
| `mm/` | Memory manager | Page allocator, slab/slub, OOM killer, mmap |
| `drivers/gpu/drm/` | DRM / GPU | Display, render, GEM/PRIME buffer management |
| `drivers/media/` | V4L2 / Media | Camera ISP, video capture pipeline |
| `drivers/char/`, `drivers/block/` | Char / Block | TTY, GPIO, NVMe, MMC |
| `fs/` | VFS | ext4, tmpfs, overlayfs, procfs, sysfs |
| `net/` | Networking | TCP/IP, netfilter, XDP, RDMA |
| `arch/` | CPU-specific | x86, arm64 — exception tables, syscall entry, MMU |
| `include/` | Headers | Shared kernel-wide type definitions |
| `Documentation/` | Docs | ABI contracts, Device Tree bindings, admin guides |

---

## Kernel Versioning

Format: `major.minor.patch` — e.g., `6.1.57`

| Track | Lifespan | Purpose | Example |
|---|---|---|---|
| Mainline | ~9 weeks per release | New features merge here | 6.13, 6.14 |
| Stable | ~3 months | Fixes only after release | 6.13.y |
| LTS | 2–6 years | Security and critical fixes only | 5.10, 5.15, 6.1, 6.6 |

### Why AI Platforms Pin to LTS

Board Support Packages couple tightly to a specific kernel ABI. Upgrading to mainline breaks downstream out-of-tree modules and vendor driver patches.

| Platform | Kernel base | Notable additions |
|---|---|---|
| Jetson L4T 35.x (JetPack 5) | 5.10 LTS | NVDLA, Argus ISP/VI/CSI, NvMedia, Tegra PCIe |
| Jetson L4T 36.x (JetPack 6) | 6.1 LTS | Orin NvDLA v2, Tegra ISP v5, PCIe Gen4 |
| openpilot Agnos (comma 3X) | Ubuntu LTS-based | Snapdragon camera ISPs, CAN-over-SPI, openpilot services |
| Yocto Kirkstone embedded AI | 5.15 LTS | Stripped BSP; FPGA/NPU out-of-tree modules |
| Yocto Scarthgap embedded AI | 6.6 LTS | EEVDF scheduler; latest nftables, XDP |

---

## /proc Virtual Filesystem

`/proc` is a kernel interface that looks like a filesystem. Files have no disk representation; reads invoke kernel functions that format data on demand.

| Path | Content |
|---|---|
| `/proc/cpuinfo` | Per-CPU: model, frequency, flags (avx512, neon, crypto) |
| `/proc/meminfo` | MemTotal, MemFree, Buffers, Cached, HugePages |
| `/proc/interrupts` | Per-CPU interrupt counts per IRQ line and name |
| `/proc/cmdline` | Kernel boot parameters passed by bootloader |
| `/proc/[pid]/maps` | VMA layout: address range, permissions, backing file |
| `/proc/[pid]/status` | State, VmRSS, threads, capability sets |
| `/proc/[pid]/fd/` | Symlinks to all open file descriptors |
| `/proc/[pid]/wchan` | Kernel function where process is currently sleeping |

---

## /sys (sysfs)

sysfs exports kernel objects — devices, drivers, buses — as a directory tree. Structure mirrors the kernel object model rather than process hierarchy.

| Path | Purpose |
|---|---|
| `/sys/class/net/eth0/` | Interface attributes: speed, mtu, carrier state |
| `/sys/bus/pci/devices/` | PCI devices; vendor/device IDs, resource (BAR) files |
| `/sys/class/thermal/thermal_zone*/temp` | Zone temperature in millidegrees Celsius |
| `/sys/class/gpio/` | GPIO pin export, direction, and value control |
| `/sys/fs/cgroup/` | cgroup v2 hierarchy; resource controllers |
| `/sys/kernel/debug/` | Debugfs: DVFS state, tracing, GPU activity monitors |
| `/sys/firmware/devicetree/base/` | Live Device Tree from running kernel |

On Jetson, `/sys/class/thermal/` exposes CPU, GPU, and SoC thermal zones. Polling during inference detects throttling before it causes latency spikes.

---

## Kernel Modules

Modules run at Ring 0 and have full kernel access. They provide the standard integration path for device drivers without rebuilding the kernel.

```bash
insmod my_driver.ko          # load from file; no dependency resolution
rmmod my_driver              # unload by name
modprobe nvidia              # load with dependency resolution (reads modules.dep)
lsmod                        # list loaded modules and usage count
modinfo nvme                 # show parameters, license, firmware requirements
```

### Module Lifecycle in C

```c
static int __init my_init(void) {
    pr_info("my_driver: loaded\n");
    return 0;  /* non-zero = load failure */
}
static void __exit my_exit(void) {
    pr_info("my_driver: unloaded\n");
}
module_init(my_init);
module_exit(my_exit);
MODULE_LICENSE("GPL");
MODULE_DEVICE_TABLE(of, my_of_match);  /* enables udev auto-load on DT match */
```

`__init` lets the kernel discard initialization code after boot, reclaiming memory. `MODULE_DEVICE_TABLE` generates a `modules.alias` entry so `modprobe` can auto-load when the Device Tree node appears.

DKMS (Dynamic Kernel Module Support) rebuilds out-of-tree modules when the kernel is updated — used by the NVIDIA GPU driver on development hosts and custom FPGA PCIe drivers.

---

## Kernel Source Layout

| Directory | Contents |
|---|---|
| `kernel/` | Core scheduler, signals, timers, printk, kprobes |
| `mm/` | Buddy allocator, slab/slub, vmalloc, OOM killer |
| `drivers/` | All device drivers — approximately 60% of kernel source lines |
| `arch/arm64/`, `arch/x86/` | Platform entry (head.S, entry.S), IRQ setup, NUMA |
| `fs/` | Filesystems: ext4, xfs, tmpfs, procfs, overlayfs |
| `include/` | Kernel headers; `include/linux/` for cross-arch types |
| `net/` | TCP, UDP, netfilter, socket layer, XDP |
| `Documentation/` | `Documentation/ABI/` defines stable sysfs interfaces |

---

## Linux on AI Platforms

### Jetson L4T
NVIDIA's Linux for Tegra is a downstream LTS fork with patches for NVDLA, VIC (Video Image Compositor), ISP (Image Signal Processor), NvMedia, and Tegra PCIe IOMMU. L4T 35.x is based on 5.10; L4T 36.x rebased to 6.1. These patches are absent from mainline; they live in `drivers/gpu/`, `drivers/media/`, and `arch/arm64/` of the L4T tree.

### openpilot Agnos
Comma's Agnos OS runs on comma 3X (Snapdragon-based). Kernel patches cover road-facing and driver-monitoring camera ISPs, CAN-over-SPI, and power management for always-on vehicle operation. `modeld`, `camerad`, and `controlsd` depend on stable V4L2 and SocketCAN ABIs.

### Yocto for Custom Boards
Production inference nodes use Yocto to build minimal, reproducible kernel + rootfs images. Only required drivers are compiled; attack surface and boot time are minimized for safety-critical deployment.

---

## Summary

| Component | Location in kernel tree | Purpose |
|---|---|---|
| Process scheduler | `kernel/sched/` | CPU time allocation across tasks |
| Memory manager | `mm/` | Virtual memory, page and slab allocators |
| VFS | `fs/` | Uniform file API over all filesystem types |
| Device drivers | `drivers/` | Hardware abstraction and resource management |
| Architecture code | `arch/arm64/`, `arch/x86/` | Platform entry, MMU, exception tables |
| Network stack | `net/` | Protocols, socket layer, XDP |
| IPC | `kernel/` (futex, signal), `ipc/` | Inter-process communication primitives |

---

## AI Hardware Connection

- L4T downstream patches add NVDLA, VIC, and ISP drivers absent from mainline; production Jetson deployments rely on these for hardware-accelerated inference and camera pipelines — understanding the kernel source layout locates them immediately when debugging initialization failures.
- `/sys/class/thermal/thermal_zoneN/temp` is the primary interface for detecting GPU and CPU throttling on Jetson; inference benchmarks should poll this to correlate latency spikes with temperature events.
- Custom FPGA PCIe accelerators require out-of-tree `.ko` modules compiled against the target LTS kernel; DKMS manages rebuilds across point releases automatically.
- openpilot Agnos pins its kernel to maintain camera ISP register map compatibility with comma 3X hardware; upstream kernel changes would break the V4L2 subdevice interface.
- `/proc/interrupts` is the first diagnostic for interrupt storm conditions in high-framerate camera pipelines — per-CPU counts per IRQ line reveal unbalanced distribution before it becomes a throughput problem.
- The monolithic architecture means an FPGA DMA driver crash kernel-panics the entire system; production AI hardware deployments invest in IOMMU protection and driver fault injection testing to contain faults before deployment.
