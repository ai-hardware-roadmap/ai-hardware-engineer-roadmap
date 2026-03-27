# Orin Nano 8GB — custom carrier L4T engineering flow

**Phase 4 — Track B — Nvidia Jetson** · L4T customization module

This page is a **concrete step-by-step flowchart** for bringing **Jetson Linux (L4T)** up on a **custom board** around **Jetson Orin Nano 8GB**: inputs, process, and outputs per stage. Pin **exact** JetPack / L4T builds and tarball names from [NVIDIA Jetson documentation](https://docs.nvidia.com/jetson/) for your ship baseline—the example release tags below are illustrative.

**See also:** [Jetson-Module-Adaptation-Bring-Up-Orin-NX-Nano.md](Jetson-Module-Adaptation-Bring-Up-Orin-NX-Nano.md) (official-style adaptation), [T23x-Deployment.md](T23x-Deployment.md) (BCT / MB1), [ODMDATA-and-GPIO-Jetson-Linux.md](ODMDATA-and-GPIO-Jetson-Linux.md) (UPHY / GPIO layers).

---

## Before you start (scope check)

| Topic | Note |
|--------|------|
| **Reference design** | Start from the **NVIDIA Orin Nano devkit** or **module + carrier** documentation that matches your **SoC + module SKU**; copy the **closest** DT / flash config, then delta for your schematic. |
| **Flash target** | **`mmcblk0p1`** applies to many **eMMC/SD** flows; **external NVMe/USB** on a custom carrier often uses **`l4t_initrd_flash.sh`** and a **different** board/storage argument—match the **Module Adaptation** guide for your storage topology. |
| **`flash.sh` board name** | The second argument is a **configured board name** (see `Linux_for_Tegra/*.conf`), not a free-form string. After adaptation you may use a **custom** name defined by your `BOARD` / `.conf` pair. |
| **Device tree workflow** | Decompiling a **`.dtb` → `.dts`** is valid for **learning and quick diffs**; **production** usually edits **kernel DTS sources** under the BSP’s kernel tree, rebuilds **`Image` + DTBs**, and installs artifacts into **`Linux_for_Tegra/`** per NVIDIA’s kernel customization guide. |

---

## Step 1: Prepare host environment

| Step | Input | Process | Output / result |
|------|--------|---------|------------------|
| Install Ubuntu & tools | Clean **Ubuntu 22.04** host (typical for JetPack 6.x host flashing) | Install `build-essential`, `device-tree-compiler` (`dtc`), `git`, `python3`, `libncurses-dev`, and any packages NVIDIA lists for your L4T release | Host can compile kernel, DTB, and run flash scripts |
| Create workspace | Directory path | `mkdir -p ~/jetson-l4t-custom` (or your standard) | Workspace folder for BSP, sources, and build trees |

---

## Step 2: Download L4T BSP and sources

| Step | Input | Process | Output / result |
|------|--------|---------|------------------|
| Download L4T | Target **JetPack / L4T** (example: **JetPack 6.2.1 / L4T 36.4.4**) | Download from the **NVIDIA Jetson** developer / embedded pages for that release | Archives such as `Jetson_Linux_R36.4.4_aarch64.tbz2`, `Tegra_Linux_Sample-Root-Filesystem_R36.4.4_aarch64.tbz2`, and **public_sources** / kernel source tarballs (names vary slightly by release—use the page for your version) |
| Extract BSP | L4T driver package archive | `tar -xf Jetson_Linux_R*_aarch64.tbz2` | **`Linux_for_Tegra/`** with flash scripts, prebuilt kernel artifacts, sample rootfs staging paths |
| Extract kernel sources | Kernel / sources tarball from the same release line | Extract per **NVIDIA kernel customization** instructions for that JetPack | Kernel tree ready to patch, configure, and build (`ARCH=arm64`) |

---

## Step 3: Prepare device tree (DTB)

| Step | Input | Process | Output / result |
|------|--------|---------|------------------|
| Select reference DTB | **Baseline** DTB for Orin Nano + your starting carrier (from unpacked BSP / prebuilts, or from a first kernel build) | Copy the **closest** `.dtb` into a working folder | Known-good binary to diff against |
| Convert DTB → DTS | `.dtb` file | `dtc -I dtb -O dts -o custom_board.dts <reference>.dtb` | Editable `.dts` for review (optional; prefer source DTS in tree for shipping) |
| Edit DTS | Board schematic, net names, regulators, I2C/SPI/UART, GPIO, PCIe/USB/CSI | Align with **pinmux / porting** sections of the module adaptation guide; keep **ODMDATA / UPHY** consistent with physical wiring | `custom_board.dts` (or kernel `*.dts` patches) describing your hardware |
| Compile DTS → DTB | Edited `.dts` | `dtc -I dts -O dtb -o custom_board.dtb custom_board.dts` (and/or kernel `make dtbs`) | `.dtb` ready to install under **`Linux_for_Tegra/kernel/dtb/`** (or the path your flash config expects) |

---

## Step 4: Kernel configuration and build

| Step | Input | Process | Output / result |
|------|--------|---------|------------------|
| Configure kernel | Kernel sources, SoC family `defconfig` from NVIDIA | `make ARCH=arm64 CROSS_COMPILE=... O=build tegra_defconfig` (exact `defconfig` name is release-specific) | Base config aligned with Jetson |
| Enable drivers | Required peripherals | `make ARCH=arm64 O=build menuconfig` (or `nconfig`) | Config with drivers for storage, networking, sensors, cameras, etc. |
| Compile kernel | Configured tree | `make ARCH=arm64 O=build -j"$(nproc)"` (plus `modules` / `modules_install` if you use out-of-tree modules) | `Image`, `modules`, and built **DTBs** per tree layout |
| Install into `Linux_for_Tegra` | Built `Image`, DTBs, modules | Copy or `install` per NVIDIA guide into **`Linux_for_Tegra/kernel/`** (and rootfs if modules go on target) | Flash step picks up your kernel + DTB |

---

## Step 5: Customize root filesystem

| Step | Input | Process | Output / result |
|------|--------|---------|------------------|
| Extract rootfs | Sample rootfs archive | `sudo tar -xpf Tegra_Linux_Sample-Root-Filesystem_R*_aarch64.tbz2 -C rootfs` | Editable Ubuntu-based rootfs |
| Install packages | Product dependencies | `chroot` + `qemu-aarch64-static` (cross) or native build host workflow per guide; `apt install` | Rootfs with libraries and apps |
| Optional repack | Modified tree | `sudo tar -cJpf rootfs_custom.tbz2 -C rootfs .` | Custom archive you point **`Linux_for_Tegra/rootfs`** at before flash |

---

## Step 6: Flash / boot

| Step | Input | Process | Output / result |
|------|--------|---------|------------------|
| Flash to SD / eMMC | BSP, kernel, DTB, rootfs | `sudo ./flash.sh <board_name> <storage>` — example pattern: **internal** eMMC/SD boot targets often look like `mmcblk0p1`; **verify** against your board’s `flash.xml` / conf | Bootable media with Linux + your DTB/kernel |
| Initrd / external storage | NVMe / USB boot on custom carrier | Often **`./tools/kernel_flash/l4t_initrd_flash.sh`** with board-specific env (see adaptation guide) | Image written to the correct device |
| Serial console | USB–UART to debug header | Monitor at the baud rate in your carrier docs | Boot logs, UEFI / CBoot / kernel messages for bring-up |

---

## Step 7: Test and debug peripherals

| Step | Input | Process | Output / result |
|------|--------|---------|------------------|
| Minimal boot | Kernel + DTB + rootfs | Power on | Shell or login over serial / SSH |
| Bus / GPIO smoke tests | Connected hardware | `i2cdetect`, `spidev` tests, UART loopback, **libgpiod** / line names on JetPack 6 (avoid relying on deprecated sysfs GPIO for new work) | Confirmed electrical + driver path |
| Camera / USB / PCIe | Modules and cables | `dmesg`, `v4l2`, application tests | Integration verified |
| Debug | Logs, device tree, regulator errors | Adjust DTS, kernel config, or BCT / pinmux; iterate Steps 4–6 | Stable board support |

---

## Step 8: Iteration and versioning

| Step | Input | Process | Output / result |
|------|--------|---------|------------------|
| Version control | DTS, kernel `defconfig` fragments, patches, flash config | `git` commits with **L4T version** in tag or README | Reproducible baselines and rollback |
| Incremental testing | Small deltas | Repeat kernel/DTB/flash cycle | Production-ready image for your Orin Nano 8GB custom board |

---

## One-line dependency graph

```text
Host + BSP ──► kernel/DTS work ──► install to Linux_for_Tegra ──► rootfs deltas ──► flash.sh / initrd flash ──► UART + tests ──► git tag
```

---

## Related in-repo material

- **[Guide.md](Guide.md)** — L4T module overview and EchoPilot / NVMe reference.
- **[Jetson-Module-Adaptation-Bring-Up-Orin-NX-Nano.md](Jetson-Module-Adaptation-Bring-Up-Orin-NX-Nano.md)** — board naming, `l4t_initrd_flash.sh`, pinmux, DT porting.
- **[T23x-Deployment.md](T23x-Deployment.md)** — MB1/MB2 BCT tables when flash or boot firmware behavior must change.
