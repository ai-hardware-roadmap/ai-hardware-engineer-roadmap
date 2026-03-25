# L4T customization

**Phase 4 — Track B — Nvidia Jetson** · Module 2 of 5

> **Focus:** Change the **stock Linux for Tegra (L4T)** stack in controlled ways—root filesystem composition, kernel and device tree, OTA and A/B patterns, and when to leave JetPack images alone versus moving to **Yocto** (see [Orin-Nano-Yocto-BSP-Production](../1.%20Nvidia%20Jetson%20Platform/Orin-Nano-Yocto-BSP-Production/Guide.md)).

**Previous:** [1. Nvidia Jetson Platform](../1.%20Nvidia%20Jetson%20Platform/Guide.md) · **Next:** [3. Edge AI Optimization](../3.%20Edge%20AI%20Optimization/Guide.md)

---

## What this module covers

| Topic | Why it matters |
|-------|----------------|
| **Root filesystem** | Preinstalled packages, read-only root, overlays, and custom images for fleet consistency |
| **Kernel / DTB** | Drivers, camera pipeline, `isolcpus`, PREEMPT — ties to [Kernel internals](../1.%20Nvidia%20Jetson%20Platform/Orin-Nano-Kernel-Internals/Guide.md) and [RT Linux](../1.%20Nvidia%20Jetson%20Platform/Orin-Nano-RT-Linux-Deep-Dive/Guide.md) |
| **Boot & redundancy** | A/B slots, recovery, and OTA expectations — see [Rootfs and A/B](../1.%20Nvidia%20Jetson%20Platform/Orin-Nano-Rootfs-and-AB-Redundancy/Guide.md) and [OTA deep dive](../1.%20Nvidia%20Jetson%20Platform/Orin-Nano-OTA-Deep-Dive/Guide.md) |
| **BSP vs Yocto** | When L4T + Debian/Ubuntu workflows win vs when you need **meta-tegra** / custom distros |

---

## Practical workflow (high level)

1. **Freeze a JetPack / L4T baseline** (version, board SKU, carrier). Document `apt` sources and NVIDIA repositories you rely on.
2. **List deltas** your product needs (packages, kernel configs, DT overlays, systemd units, disabled services).
3. **Prefer supported knobs:** NVIDIA sample rootfs scripts, `flash.sh` options, `extlinux.conf`, `nvpmodel`, `jetson-io` for DT overlays where applicable—before maintaining a forked kernel tree.
4. **Reproduce builds:** script `debootstrap`/rootfs steps or move to Yocto when apt drift blocks releases.
5. **Validate OTA:** if you use image-based updates, align partition layout and bootloader env with your update agent (vendor docs first).

---

## Deep dives (in §1 Platform)

Use these Platform guides as the **implementation** detail for L4T-facing work:

- [Yocto BSP & production](../1.%20Nvidia%20Jetson%20Platform/Orin-Nano-Yocto-BSP-Production/Guide.md)
- [Rootfs and A/B redundancy](../1.%20Nvidia%20Jetson%20Platform/Orin-Nano-Rootfs-and-AB-Redundancy/Guide.md)
- [Kernel internals](../1.%20Nvidia%20Jetson%20Platform/Orin-Nano-Kernel-Internals/Guide.md)
- [Security hardening](../1.%20Nvidia%20Jetson%20Platform/Orin-Nano-Security/Guide.md) (services, disk encryption, secure boot direction)

---

## Relationship to Edge AI (module 3)

**L4T customization** shapes *what runs on the OS* (kernel, drivers, rootfs, CUDA stack install path). **Edge AI Optimization** assumes that foundation and focuses on **models** (TensorRT, quantization, DeepStream). Do module 2 (or parallel Platform deep dives) before treating inference as the bottleneck.
