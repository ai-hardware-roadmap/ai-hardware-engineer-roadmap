# Lecture 17: Linux Device Driver Model & Device Tree

## Linux Driver Model: Core Abstractions

The Linux device model provides a unified framework across all buses. Three primary structures, defined in `include/linux/device.h`, represent the hardware and software entities:

| Object | Structure | Role |
|--------|-----------|------|
| Bus | `struct bus_type` | Enumeration and matching logic (PCIe, USB, I2C, SPI, platform) |
| Device | `struct device` | One instance of physical or virtual hardware |
| Driver | `struct device_driver` | Code that manages a specific device type |

The bus core compares each driver's `id_table` (PCI/USB) or `of_match_table` (Device Tree `compatible`) against each registered device. On a match, the bus calls `driver->probe(device)`. On removal or driver unbind, it calls `driver->remove(device)`.

---

## Platform Devices

SoC peripherals (UART, I2C controller, camera CSI, AI accelerator, FPGA AXI slave) are not self-describing; the bus cannot enumerate them. They are registered as **platform devices** using descriptions from Device Tree or ACPI.

```c
static const struct of_device_id mydev_of_match[] = {
    { .compatible = "vendor,mydevice-v2" },
    { .compatible = "vendor,mydevice-v1" },   /* older silicon */
    { }   /* sentinel */
};
MODULE_DEVICE_TABLE(of, mydev_of_match);

static struct platform_driver mydev_driver = {
    .probe  = mydev_probe,
    .remove = mydev_remove,
    .driver = {
        .name           = "mydevice",
        .of_match_table = mydev_of_match,
    },
};
module_platform_driver(mydev_driver);
```

`module_platform_driver()` expands to `module_init` / `module_exit` wrappers that call `platform_driver_register()` and `platform_driver_unregister()`.

---

## Device Tree (DTS)

Device Tree is a hardware description language for embedded SoCs. The source format (`.dts`) is compiled by `dtc` into a binary blob (`.dtb`). The bootloader (U-Boot, EDK II) passes the DTB physical address to the kernel at boot (in a CPU register: `x0` on ARM64, `r2` on ARM32). The kernel parses it to discover all platform devices.

### Node Structure

```dts
soc {
    camera_isp@fe100000 {
        compatible = "vendor,cam-isp-v3", "vendor,cam-isp";
        reg = <0 0xfe100000 0 0x10000>;      /* 64KB MMIO at PA 0xfe100000 */
        interrupts = <GIC_SPI 25 IRQ_TYPE_LEVEL_HIGH>;
        clocks = <&cru SCLK_ISP_CLK>, <&cru ACLK_ISP_CLK>;
        clock-names = "isp", "aclk";
        resets = <&cru SRST_ISP>;
        reset-names = "isp";
        dmas = <&dmac1 5>;
        dma-names = "dma";
        power-domains = <&power RK3588_PD_ISP>;
        status = "okay";
    };
};
```

### Key DTS Properties

| Property | Parsed by | Kernel API |
|----------|-----------|-----------|
| `compatible` | Bus match logic | `of_match_table` lookup |
| `reg` | Resource subsystem | `platform_get_resource()`, `devm_ioremap_resource()` |
| `interrupts` | IRQ subsystem | `platform_get_irq()`, `devm_request_irq()` |
| `clocks` / `clock-names` | Clock framework | `devm_clk_get(dev, "isp")`, `clk_prepare_enable()` |
| `resets` / `reset-names` | Reset controller | `devm_reset_control_get(dev, "isp")` |
| `dmas` / `dma-names` | DMA engine | `dma_request_chan(dev, "dma")` |
| `power-domains` | genpd | Automatic on `pm_runtime_get()` |
| `status` | Boot scan | `"okay"` enables; `"disabled"` skips probe |

---

## Device Tree Overlays (DTBO)

Overlays are incremental additions to the base DTB, applied at runtime (via `/sys/kernel/config/device-tree/overlays/`) or by the bootloader. They add, modify, or delete nodes without recompiling the full DTB.

```bash
# Compile overlay source to binary
dtc -I dts -O dtb -o camera_imx477.dtbo camera_imx477.dts

# Jetson: reference in extlinux.conf
FDT_OVERLAYS /boot/camera_imx477.dtbo

# Runtime apply (if ConfigFS enabled)
mkdir /sys/kernel/config/device-tree/overlays/camera
cp camera_imx477.dtbo /sys/kernel/config/device-tree/overlays/camera/dtbo
echo 1 > /sys/kernel/config/device-tree/overlays/camera/status
```

Used in Jetson Xavier/Orin for camera carrier board (sensor module) configuration and in Raspberry Pi for HAT descriptor overlays.

---

## probe() Function: Resource Setup Pattern

```c
static int mydev_probe(struct platform_device *pdev)
{
    struct device *dev = &pdev->dev;
    struct mydev_priv *priv;
    struct resource *res;
    int irq, ret;

    priv = devm_kzalloc(dev, sizeof(*priv), GFP_KERNEL);
    if (!priv)
        return -ENOMEM;

    /* Map MMIO registers */
    res = platform_get_resource(pdev, IORESOURCE_MEM, 0);
    priv->base = devm_ioremap_resource(dev, res);
    if (IS_ERR(priv->base))
        return PTR_ERR(priv->base);

    /* Register interrupt handler */
    irq = platform_get_irq(pdev, 0);
    ret = devm_request_irq(dev, irq, mydev_isr,
                           IRQF_SHARED, "mydevice", priv);
    if (ret)
        return ret;

    /* Acquire clock and reset */
    priv->clk = devm_clk_get(dev, "core");
    priv->rst = devm_reset_control_get(dev, "rst");

    platform_set_drvdata(pdev, priv);
    return 0;
}
```

If any `devm_*` call fails and the function returns a negative error code, all previously acquired managed resources are automatically released in reverse order. No `goto err_cleanup` labels needed.

---

## devm_* Managed Resources

`devres` framework automatically releases resources when the device is unbound from its driver or when `probe()` returns an error:

| Function | Resource released on detach |
|----------|-----------------------------|
| `devm_kzalloc()` | `kfree()` |
| `devm_ioremap_resource()` | `iounmap()` + `release_mem_region()` |
| `devm_request_irq()` | `free_irq()` |
| `devm_clk_get()` | `clk_put()` |
| `devm_reset_control_get()` | `reset_control_put()` |
| `devm_regulator_get()` | `regulator_put()` |
| `devm_gpiod_get()` | `gpiod_put()` |

Custom managed resources: `devm_add_action(dev, fn, data)` registers an arbitrary cleanup function.

---

## sysfs Attributes

```c
static ssize_t utilization_show(struct device *dev,
                                struct device_attribute *attr, char *buf)
{
    struct mydev_priv *priv = dev_get_drvdata(dev);
    return sysfs_emit(buf, "%u\n", readl(priv->base + REG_UTIL));
}
static DEVICE_ATTR_RO(utilization);

static struct attribute *mydev_attrs[] = {
    &dev_attr_utilization.attr,
    NULL,
};
ATTRIBUTE_GROUPS(mydev);
```

sysfs attributes appear at `/sys/bus/platform/devices/mydevice.0/utilization`. Userspace reads with `cat`; write with `echo`. Must be re-entrant; protect shared state with a mutex or spinlock.

---

## udev: Userspace Device Management

The kernel emits uevent netlink messages on device add/remove. `udevd` receives them, matches `/etc/udev/rules.d/` rules, and acts:

- Creates `/dev/` device nodes with correct owner and permissions
- Loads firmware via `request_firmware()` mechanism
- Runs `modprobe` for modules with matching `MODULE_DEVICE_TABLE` entries
- Executes custom scripts for device initialization

```
SUBSYSTEM=="video4linux", ATTRS{name}=="IMX477*", SYMLINK+="camera0", MODE="0666"
```

---

## debugfs

Drivers expose internal state for development diagnostics via debugfs:

```c
debugfs_create_u32("frame_count", 0444, priv->dbgfs_dir, &priv->frame_count);
debugfs_create_file("regs", 0444, priv->dbgfs_dir, priv, &mydev_regs_fops);
```

Accessible at `/sys/kernel/debug/mydevice/`. Not ABI-stable; may change between kernel versions. `media-ctl` and `v4l2-ctl` use the media controller and V4L2 ioctl interfaces (which do have stable ABI) for pipeline topology configuration.

---

## Summary

| Bus type | Self-describing? | DT needed? | Match mechanism | Example |
|----------|-----------------|-----------|----------------|---------|
| PCIe | Yes (config space) | No | `pci_device_id` vendor:device | NVIDIA GPU, Intel E810 NIC |
| USB | Yes (descriptor) | No | `usb_device_id` vid:pid | UVC camera, USB GNSS |
| Platform | No | Yes (DTS/ACPI) | `of_match_table` compatible | UART, FPGA AXI peripheral |
| I2C | Partial (address) | Yes | `of_match_table` + I2C address | IMX477, ICM-42688 IMU |
| SPI | Partial (CS) | Yes | `of_match_table` + SPI chip select | ADC, display controller |

---

## AI Hardware Connection

- DTS nodes with correct `compatible` strings link Jetson IMX477 and AR0234 camera sensors to NVIDIA's V4L2 sensor drivers; `reg` specifies the I2C address and `clocks` provisions the NVCSI clock tree
- NVDLA on Jetson is a platform device with DTS entries for MMIO base, IRQ lines, clock domains, and DMA channels; the kernel driver maps all resources via `devm_ioremap_resource` and `dma_request_chan`
- Custom Xilinx Zynq AXI peripherals for sensor fusion or pre-processing are described as platform devices in the DTS; `reg` specifies AXI slave base address and size; the driver accesses registers with `ioread32` / `iowrite32`
- DTBO overlays enable hot-swappable camera module configuration on Jetson development kits without reflashing the base system image, accelerating sensor bring-up iteration
- sysfs `DEVICE_ATTR_RO` attributes expose AI accelerator utilization counters and error registers to Prometheus node exporters and health monitoring daemons without requiring privileged ioctls
- `devm_*` managed resources prevent resource leaks in FPGA driver `probe()` error paths, which are exercised at every module reload during iterative hardware bring-up cycles
