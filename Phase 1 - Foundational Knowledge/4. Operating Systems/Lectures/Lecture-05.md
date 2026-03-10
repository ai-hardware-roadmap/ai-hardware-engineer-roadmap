# Lecture 5: Kernel Modules, Boot Process & Device Tree

## Linux Boot Sequence on ARM SoC

Modern embedded AI boards (Jetson Orin, Zynq UltraScale+, i.MX8) follow this sequence:

| Stage | Responsible | Artifact loaded | Notes |
|---|---|---|---|
| 1. Power-on | SoC ROM (BootROM) | BootROM code from mask ROM | Checks fuses, loads signed next stage from flash |
| 2. Primary bootloader | U-Boot SPL or UEFI stub | SPL / TF-A BL2 | Initializes DRAM, minimal clocks |
| 3. Firmware | TF-A BL31 / PSCI | Secure monitor (EL3) | Sets up ATF, optionally loads OP-TEE |
| 4. Second bootloader | U-Boot proper or UEFI | Kernel + DTB + initramfs | Reads storage, sets boot args |
| 5. Kernel decompression | Kernel `head.S` | Decompresses `Image.gz` | Verifies DTB, sets up early paging |
| 6. Kernel init | `start_kernel()` | Initializes all subsystems | Memory, scheduler, drivers, VFS |
| 7. PID 1 | systemd (or `init`) | Mounts rootfs, starts services | udev creates `/dev` nodes |

On x86: UEFI (or legacy BIOS) replaces U-Boot. On Jetson: NVIDIA's MB1 (Miniboot) and MB2 correspond to SPL and U-Boot; CBoot is NVIDIA's U-Boot replacement in JetPack 5.

---

## Secure Boot

Trust chain from ROM to running kernel: each stage verifies the signature of the next before executing it.

- BootROM verifies SPL/BL2 signature with a key burned into fuses
- BL2 verifies BL31 and U-Boot/UEFI
- U-Boot verifies kernel image signature
- Kernel verifies rootfs (dm-verity) or module signatures

**Jetson Secure Boot**: BCT (Boot Configuration Table) and BL31 are signed with NVIDIA's key by default; production deployment uses a customer RSA-2048/4096 or ECDSA key pair fused into OTP. `tegraflash` handles signing and flashing.

Secure boot is mandatory for production AV platforms — prevents substitution of a malicious kernel image or modified inference binary at the bootloader stage.

---

## UEFI vs U-Boot

| | UEFI | U-Boot |
|---|---|---|
| Primary domain | x86 servers, workstations, modern ARM servers | Embedded: Zynq, Jetson, Raspberry Pi, i.MX |
| Standard | UEFI specification (Tianocore/EDK2) | Open-source; board-specific configuration |
| Boot protocol | EFI stub in kernel; DTB from EFI config | Passes kernel + DTB address in registers |
| Script / config | EFI variables, NVRAM | U-Boot environment variables, `boot.cmd` |
| Network boot | PXE via UEFI network stack | TFTP + NFS; common for embedded development |

Both load the kernel image, a DTB, and optionally an initramfs into memory, then jump to the kernel entry point.

---

## initramfs

- Compressed cpio archive (gzip, lz4, zstd) embedded in the kernel or loaded separately
- Contains early userspace: busybox, udev, cryptsetup, `fsck`, custom `init` script
- Kernel mounts it as the initial rootfs in a tmpfs; runs `/init`; mounts the real rootfs; `switch_root` to the permanent root
- On Jetson, NVIDIA uses initramfs for early TNSPEC (board identification) and extlinux-based boot selection

```bash
mkdir /tmp/initrd && cd /tmp/initrd
zcat /boot/initrd.img | cpio -idm    # inspect initramfs contents
ls -la                               # busybox, lib, udev, etc.
```

---

## Device Tree

### Purpose

Hardware description for SoCs without self-describing buses. PCIe is self-describing (devices report vendor/device IDs); I2C, SPI, UART, AXI, and MMIO peripherals are not — the kernel must be told they exist.

The Device Tree replaces per-board `#ifdef` hacks in kernel source with a data file the bootloader passes to the kernel at runtime. U-Boot places the DTB address in a register before jumping to the kernel entry point.

### Node Structure

```dts
/* Example: IMX477 camera sensor on I2C bus */
&i2c0 {
    camera0: imx477@1a {
        compatible = "sony,imx477";
        reg = <0x1a>;                          /* I2C address */
        clocks = <&clk IMX477_CLK>;
        clock-names = "xclk";
        reset-gpios = <&gpio 42 GPIO_ACTIVE_LOW>;
        port {
            cam0_ep: endpoint {
                remote-endpoint = <&csi0_ep>;
                data-lanes = <1 2>;
            };
        };
    };
};
```

| Property | Meaning |
|---|---|
| `compatible` | String list; kernel matches against `of_match_table` in driver |
| `reg` | MMIO base address and size, or bus address (I2C, SPI) |
| `interrupts` | IRQ specifier: GIC SPI number, trigger type |
| `clocks` | Clock provider handle and clock ID |
| `dma-names` | Named DMA channels assigned to the device |
| `status` | `"okay"` to enable; `"disabled"` to suppress driver probe |

### Compilation and Inspection

```bash
dtc -I dts -O dtb -o my_board.dtb my_board.dts    # compile DTS → DTB
dtc -I dtb -O dts -o decoded.dts my_board.dtb      # decompile for inspection
ls /sys/firmware/devicetree/base/                   # live DT from running kernel
cat /sys/firmware/devicetree/base/model             # board model string
```

### Device Tree Overlays (DTBO)

Overlays patch the base DT at runtime without rebuilding the kernel or base DTB.

- **Jetson pin mux overlays**: select UART vs SPI vs I2C function for carrier board expansion pins
- **Raspberry Pi HAT overlays**: enable I2S audio, SPI ADC, camera sensor nodes
- **Zynq PL overlays**: load partial bitstream and add DT nodes for FPGA-connected AXI peripherals

```bash
dtoverlay imx477                        # apply overlay (Raspberry Pi)
cat /boot/extlinux/extlinux.conf        # FDT_OVERLAYS= line on Jetson
ls /sys/firmware/devicetree/base/       # verify overlay nodes appeared
```

---

## Kernel Modules

### Module Entry, Exit, and Device Matching

```c
static const struct of_device_id my_of_match[] = {
    { .compatible = "vendor,my-accel" },
    { }
};
MODULE_DEVICE_TABLE(of, my_of_match);    /* writes alias → modules.alias → udev auto-load */

static struct platform_driver my_driver = {
    .probe  = my_probe,
    .remove = my_remove,
    .driver = {
        .name           = "my-accel",
        .of_match_table = my_of_match,
    },
};
module_platform_driver(my_driver);       /* wraps module_init / module_exit */
MODULE_LICENSE("GPL");
```

When a DT node with `compatible = "vendor,my-accel"` appears (at boot or via overlay), udev reads `modules.alias`, calls `modprobe`, and the driver's `probe()` function runs.

### modprobe vs insmod

| Command | Behavior |
|---|---|
| `insmod my.ko` | Load from file path; no dependency resolution |
| `modprobe mymodule` | Resolve and load dependencies from `/lib/modules/$(uname -r)/modules.dep` |
| `modprobe -r mymodule` | Unload module and any unused dependencies |
| `depmod -a` | Rebuild `modules.dep` after installing new modules |
| `lsmod` | List loaded modules, usage count, dependents |
| `modinfo nvme` | Show parameters, license, firmware version fields |

### Module Signing

- `CONFIG_MODULE_SIG_FORCE` rejects unsigned modules; production Jetson and automotive ECU kernels enforce this
- Sign during build: `scripts/sign-file sha256 signing_key.pem signing_cert.pem my_driver.ko`
- Custom FPGA PCIe driver must be signed before deployment on a secure-boot platform

### DKMS

Dynamic Kernel Module Support rebuilds out-of-tree modules automatically when the kernel is updated.

```bash
dkms add -m my-fpga-driver -v 1.0
dkms build -m my-fpga-driver -v 1.0
dkms install -m my-fpga-driver -v 1.0
```

DKMS is standard for the NVIDIA proprietary GPU driver on development hosts and for custom FPGA PCIe drivers that must survive kernel point-release updates without manual rebuilds.

---

## Kernel Command Line

Passed by U-Boot (`bootargs` env variable) or UEFI. Readable at `/proc/cmdline`.

| Parameter | Effect |
|---|---|
| `console=ttyS0,115200n8` | Kernel log to serial at boot |
| `root=/dev/mmcblk0p1` | Root filesystem device |
| `rdinit=/sbin/init` | First userspace process in initramfs |
| `isolcpus=4-7` | Exclude cores 4–7 from the general scheduler |
| `nohz_full=4-7` | Eliminate scheduler tick interrupts on isolated cores |
| `rcu_nocbs=4-7` | Move RCU callbacks off isolated cores |
| `systemd.unit=inference.target` | Boot to custom systemd target |
| `nvidia-l4t-bootloader.secure-boot=1` | Jetson: enable verified boot chain |

```bash
cat /proc/cmdline                         # inspect active boot parameters
cat /sys/devices/system/cpu/isolated      # verify isolcpus took effect
```

---

## Summary

| Boot stage | Responsible | Artifact loaded | Jetson equivalent |
|---|---|---|---|
| BootROM | SoC mask ROM | Signed first-stage loader | Jetson BootROM → MB1 |
| SPL / BL2 | U-Boot SPL / TF-A | DRAM init; TF-A BL31 | MB1 → MB2 |
| Bootloader | U-Boot / CBoot | Kernel + DTB + initramfs | CBoot (JetPack 5), UEFI (JetPack 6) |
| Kernel entry | `head.S` → `start_kernel()` | Subsystem init | L4T kernel image |
| Early userspace | initramfs `/init` | Mount real rootfs | NVIDIA TNSPEC + `switch_root` |
| PID 1 | systemd | All services, udev | Jetson systemd inference target |

---

## AI Hardware Connection

- U-Boot for Zynq/MPSoC loads the FPGA bitstream (BOOT.BIN) before the kernel starts — the PL (Programmable Logic) is configured and ready when the kernel's Device Tree describes the AXI inference accelerator nodes, eliminating a firmware-load delay from the boot path.
- Device Tree `compatible` strings are the binding contract between Jetson camera sensor drivers and hardware; changing `sony,imx477` to `sony,imx219` in the DTBO selects a different V4L2 subdevice configuration, affecting every frame captured by `camerad`.
- DTBO overlays for IMX477 on Jetson AGX Orin allow runtime CSI lane and pin mux configuration without reflashing the base DTB — essential for carrier board bring-up and multi-sensor robot arm payloads.
- Secure boot chain verification (BootROM → MB1 → CBoot → kernel) is mandatory for production AV deployment; an unverified kernel image breaks the safety argument for ISO 26262 ASIL compliance and opens the platform to persistent rootkit attacks.
- DKMS manages the NVIDIA proprietary GPU driver on development hosts across kernel point-release updates — without it, every kernel update would break CUDA initialization and TensorRT engine builds.
- `isolcpus=4-7 nohz_full=4-7 rcu_nocbs=4-7` in the Jetson kernel command line reserves the big-cluster Cortex-A78AE cores exclusively for `modeld`, `camerad`, and `controlsd` before any userspace process starts, forming the foundation of real-time inference CPU isolation.
