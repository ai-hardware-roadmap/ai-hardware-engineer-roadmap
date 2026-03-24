# Operating Systems — Final Practice (5 problems)

Short-answer practice aligned with [Operating Systems — Guide](Guide.md) and the Phase 1 lecture notes below. Difficulty: **moderate**. **Each numbered problem is a single question** (write a short paragraph unless noted).

**Suggested time:** ~45–60 minutes total.

---

## Problem 1 — Building a custom kernel

**Outline how you build a custom Linux kernel** for a target (embedded AI board or generic tree), and **name typical tools or workflows** used along the way — e.g. where **configuration** happens, how **cross-compilation** fits in, and at least one **distribution-style** approach (not only “run `make` on your laptop for x86”).

*Maps to: [Lecture 25 — Capstone: custom Linux images with Yocto](Lectures/Lecture-25.md) (factory workflow); [Lecture 5](Lectures/Lecture-05.md) / vendor BSP context for **defconfig**, **DTB**, and flashing.*

---

## Problem 2 — PREEMPT_RT (real-time Linux)

**What is `PREEMPT_RT`, what problem on “normal” Linux does it address, and what does it change in the kernel at a high level** (enough to show you understand *predictability* vs raw speed)?

*Maps to: [Lecture 7 — Real-Time Linux: PREEMPT_RT & Determinism](Lectures/Lecture-07.md).*

---

## Problem 3 — ext4

**What is the ext4 filesystem, and what are its main strengths** for typical Linux roots / embedded boards (name several concrete pros from the lecture — allocation, directories, journaling/crash behavior, maturity, etc.)?

*Maps to: [Lecture 21 — Filesystems: ext4, btrfs, F2FS & overlayfs](Lectures/Lecture-21.md).*

---

## Problem 4 — Boot order

**For an ARM SoC–style embedded boot flow (as in the lecture), list the boot chain in order from power-on to PID 1**, naming **at least six** clear stages (order must be correct).

*Maps to: [Lecture 5 — Kernel Modules, Boot Process & Device Tree](Lectures/Lecture-05.md).*

---

## Problem 5 — Kernel modules and device drivers

**What is a loadable kernel module, and how does driver bring-up typically work** for a **Device Tree–matched** driver — including **`compatible` matching**, **`probe()`**, and why **`modprobe`** is usually used instead of **`insmod`**?

*Maps to: [Lecture 5 — Kernel Modules, Boot Process & Device Tree](Lectures/Lecture-05.md).*

---

## Answer key (for self-check)

<details>
<summary>Click to expand</summary>

**1.** **Typical flow:** obtain **kernel source** (mainline, vendor/L4T BSP, or via a build system recipe) → choose **config** (**`defconfig`**, **`make menuconfig` / nconfig**, or **fragments** / `CONFIG_*` in Yocto **`bbappend`**) → build with a **cross-toolchain** matching the target (**`aarch64-linux-gnu-*`** etc.) or let **Yocto/BitBake** invoke **`make`** inside the recipe → produce **`Image`/`zImage`**, **modules**, and match **DTB** / boot artifacts → deploy (flash, OTA, or replace `/boot`). **Tools / stacks (credit any coherent set):** **Yocto** (**Poky**, **BitBake**, **meta-tegra** / machine layers), **`make` + `LLVM=` optional**, **Buildroot** as an alternative embedded integrator, **DKMS** for **out-of-tree** modules on an existing kernel, **`installkernel` / `modules_install`** for packaging.

**2.** **`PREEMPT_RT`** targets **bounded worst-case latency** (hard/soft RT **predictability**), not higher average throughput. It makes almost the whole kernel **preemptible** by turning many **spinlocks into sleeping rtmutexes**, moving **IRQ handling** into **schedulable threads**, and making **softirq** work **preemptible** — shrinking long non-preemptible sections that delay high-priority tasks.

**3.** **ext4** is the default **ext family** (ext2/3/4) **journaled** Linux disk FS under **VFS**, above the **block layer**. **Pros** (examples): **extent-based** allocation and **64-bit** volumes; **delayed allocation** for better locality; **dir_index** (htree) for large directories; **journaling** and modes like **`data=ordered`** for sensible crash recovery; mature and widely used on **rootfs** (e.g. Jetson).

**4.** Example order: **BootROM** → **SPL / primary bootloader** (DRAM bring-up) → **TF-A BL31 / PSCI** (secure monitor) → **U-Boot or UEFI** (loads kernel + **DTB** + initramfs) → **Linux entry** (decompression / early boot) → **`start_kernel()`** and driver probing → **PID 1** (`systemd` / `init`).

**5.** A **module** is a **`.ko`** linked into the **running** kernel (extra drivers/code) **without** reboot. For **DT** devices, **`MODULE_DEVICE_TABLE` / `compatible`** matches a node; **`modprobe`** loads the module (and **dependencies**); the kernel calls **`probe()`** when the device is **bound** (boot or hotplug). **`modprobe`** is preferred over **`insmod`** because it **resolves dependency order** from **`modules.dep`**.

</details>
