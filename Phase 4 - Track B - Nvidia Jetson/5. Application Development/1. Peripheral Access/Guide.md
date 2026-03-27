# Peripheral Access

**Phase 4 — Track B — Module 5.1** · Application Development

> **Focus:** Access and control hardware peripherals on the **Jetson Orin Nano 8GB** from Linux userspace — GPIO, PWM, UART, SPI, I2C, CAN, USB, storage, and backlight. Every interface is shown with both sysfs/chardev and library approaches.

**Hub:** [5. Application Development](../Guide.md)

---

## Table of Contents

1. [GPIO (Linux)](#1-gpio-linux)
2. [GPIO Naming — Alphanumeric to Numeric Assignment](#2-gpio-naming--alphanumeric-to-numeric-assignment)
3. [PWM (Linux)](#3-pwm-linux)
4. [ADC (Linux)](#4-adc-linux)
5. [UART (Linux)](#5-uart-linux)
6. [SPI (Linux)](#6-spi-linux)
7. [I2C (Linux)](#7-i2c-linux)
8. [CAN (Linux)](#8-can-linux)
9. [USB Host Mode (Linux)](#9-usb-host-mode-linux)
10. [USB Device Mode (Linux)](#10-usb-device-mode-linux)
11. [NVMe / PCIe Storage (Linux)](#11-nvme--pcie-storage-linux)
12. [SD/MMC Card (Linux)](#12-sdmmc-card-linux)
13. [Backlight (Linux)](#13-backlight-linux)
14. [Projects](#14-projects)
15. [Resources](#15-resources)

---

## 1. GPIO (Linux)

Jetson Orin Nano exposes GPIOs through the **gpiochip** character device interface (`/dev/gpiochipN`). The legacy sysfs interface (`/sys/class/gpio/`) is deprecated — use `libgpiod` instead.

### libgpiod tools

```bash
# List all GPIO chips
gpiodetect

# Show all lines on a chip
gpioinfo gpiochip0

# Read a GPIO input
gpioget gpiochip0 <line>

# Set a GPIO output high
gpioset gpiochip0 <line>=1

# Monitor GPIO events (rising/falling edge)
gpiomon gpiochip0 <line>
```

### libgpiod in C

```c
#include <gpiod.h>

struct gpiod_chip *chip = gpiod_chip_open("/dev/gpiochip0");
struct gpiod_line *line = gpiod_chip_get_line(chip, 42);

/* Output */
gpiod_line_request_output(line, "my-app", 0);
gpiod_line_set_value(line, 1);

/* Input */
gpiod_line_request_input(line, "my-app");
int val = gpiod_line_get_value(line);

gpiod_chip_close(chip);
```

### libgpiod in Python

```python
import gpiod

chip = gpiod.Chip('gpiochip0')
line = chip.get_line(42)

# Output
line.request(consumer="my-app", type=gpiod.LINE_REQ_DIR_OUT)
line.set_value(1)

# Input
line.request(consumer="my-app", type=gpiod.LINE_REQ_DIR_IN)
val = line.get_value()
```

### Device tree GPIO configuration

GPIOs are assigned functions in the **pinmux device tree**. To use a pin as GPIO, it must be configured as GPIO (not an alternate function) in the pinmux spreadsheet. See [Module 2 — Custom Carrier Board](../../2.%20Custom%20Carrier%20Board%20Design%20and%20Bring-Up/Guide.md) for pinmux configuration.

---

## 2. GPIO naming — alphanumeric to numeric assignment

Jetson uses a **SoC-level naming** scheme (e.g., `GPIO09`, `PQ.05`, `SOC_GPIO42`) that differs from the Linux **line number** within a gpiochip.

### Finding the mapping

```bash
# Show chip + line for all GPIOs with their names
gpioinfo | grep -i "GPIO"

# Or use the Jetson-specific tool
sudo cat /sys/kernel/debug/gpio
```

### NVIDIA's mapping table

NVIDIA publishes a GPIO mapping table in the **Jetson Orin Nano Developer Kit User Guide** and the **pinmux spreadsheet**. The key columns:

| SoC pad name | GPIO port.pin | gpiochip | Line number | 40-pin header |
|-------------|--------------|----------|-------------|---------------|
| `SOC_GPIO42` | `PH.00` | gpiochip0 | 106 | Pin 7 |
| `SOC_GPIO43` | `PH.01` | gpiochip0 | 107 | Pin 11 |

Always verify with `gpioinfo` on your actual device — line numbers can shift between L4T versions.

---

## 3. PWM (Linux)

Orin Nano exposes PWM channels via the Linux PWM subsystem.

### sysfs interface

```bash
# Export PWM channel (chip 0, channel 0)
echo 0 > /sys/class/pwm/pwmchip0/export

# Configure: 1 kHz, 50% duty cycle
echo 1000000 > /sys/class/pwm/pwmchip0/pwm0/period      # ns
echo 500000  > /sys/class/pwm/pwmchip0/pwm0/duty_cycle   # ns
echo 1       > /sys/class/pwm/pwmchip0/pwm0/enable
```

### Common uses on Jetson

| Use case | PWM channel | Notes |
|----------|------------|-------|
| **Fan control** | Dedicated fan PWM | Controlled by `jetson_clocks` or device tree `pwm-fan` node |
| **LED brightness** | GPIO-capable PWM pin | Requires pinmux set to PWM function |
| **Servo motor** | GPIO-capable PWM pin | 50 Hz, 1–2 ms pulse width |
| **Backlight** | Display backlight PWM | See [Backlight](#13-backlight-linux) |

---

## 4. ADC (Linux)

The Jetson Orin Nano SoM has **limited ADC** capability — no general-purpose ADC pins are exposed on the carrier connector. For analog sensing:

### External ADC options

| ADC | Interface | Resolution | Channels | Common use |
|-----|-----------|-----------|----------|-----------|
| **ADS1115** | I2C | 16-bit | 4 | Voltage, current, temperature sensors |
| **MCP3008** | SPI | 10-bit | 8 | General-purpose analog input |
| **INA226** | I2C | 16-bit | 2 (V + I) | Power monitoring |

### Reading external ADC via IIO subsystem

If your external ADC has a Linux IIO driver:

```bash
# List IIO devices
ls /sys/bus/iio/devices/

# Read raw value
cat /sys/bus/iio/devices/iio:device0/in_voltage0_raw

# Read scale
cat /sys/bus/iio/devices/iio:device0/in_voltage0_scale
```

Voltage = raw * scale (in millivolts).

---

## 5. UART (Linux)

Orin Nano exposes multiple UART ports. The debug console uses `ttyTCU0` (Tegra Combined UART). Application UARTs appear as `/dev/ttyTHS*`.

### Available UARTs

| Device | Use | Baud rate |
|--------|-----|-----------|
| `/dev/ttyTCU0` | Debug console (bootloader + kernel) | 115200 |
| `/dev/ttyTHS0` | Application UART 0 | Configurable |
| `/dev/ttyTHS1` | Application UART 1 | Configurable |

### Using UART from userspace

```bash
# Quick test with minicom
minicom -D /dev/ttyTHS0 -b 115200

# Or with stty + cat
stty -F /dev/ttyTHS0 115200 cs8 -cstopb -parenb
echo "hello" > /dev/ttyTHS0
cat /dev/ttyTHS0
```

### Python (pyserial)

```python
import serial

ser = serial.Serial('/dev/ttyTHS0', 115200, timeout=1)
ser.write(b'hello\n')
data = ser.readline()
ser.close()
```

---

## 6. SPI (Linux)

SPI buses appear as `/dev/spidevX.Y` (bus X, chip-select Y).

### Enable SPI in device tree

SPI buses must be enabled in the pinmux and device tree. Use the pinmux spreadsheet to assign SPI function to the correct pins.

### spidev test

```bash
# Loopback test (connect MOSI to MISO)
spidev_test -D /dev/spidev0.0 -s 1000000 -v
```

### Python (spidev)

```python
import spidev

spi = spidev.SpiDev()
spi.open(0, 0)           # bus 0, CS 0
spi.max_speed_hz = 1000000
response = spi.xfer2([0x01, 0x02, 0x03])
spi.close()
```

---

## 7. I2C (Linux)

I2C buses appear as `/dev/i2c-N`.

### Scanning for devices

```bash
# Scan all addresses on bus 1
sudo i2cdetect -y -r 1
```

### Reading/writing registers

```bash
# Read register 0x00 from device 0x50 on bus 1
sudo i2cget -y 1 0x50 0x00

# Write 0xFF to register 0x01
sudo i2cset -y 1 0x50 0x01 0xFF
```

### Python (smbus2)

```python
from smbus2 import SMBus

with SMBus(1) as bus:
    data = bus.read_byte_data(0x50, 0x00)
    bus.write_byte_data(0x50, 0x01, 0xFF)
```

### Common I2C devices on Jetson carriers

| Device | Address | Purpose |
|--------|---------|---------|
| **EEPROM** (carrier ID) | 0x50–0x57 | Board identification |
| **INA3221** | 0x40–0x43 | Power monitoring (VIN, 3.3V, 5V) |
| **IMU** (BMI088, ICM-42688) | 0x68–0x69 | Inertial measurement (robotics) |
| **RTC** (DS3231) | 0x68 | Real-time clock (battery-backed) |

---

## 8. CAN (Linux)

CAN bus on Jetson requires an external CAN transceiver on the carrier board (the SoC has CAN controllers but no integrated PHY).

### Setup

```bash
# Configure CAN interface (500 kbps)
sudo ip link set can0 type can bitrate 500000
sudo ip link set can0 up

# For CAN-FD
sudo ip link set can0 type can bitrate 500000 dbitrate 2000000 fd on
sudo ip link set can0 up
```

### Send and receive

```bash
# Send a frame
cansend can0 123#DEADBEEF

# Receive (dump all frames)
candump can0

# Generate test traffic
cangen can0
```

### Python (python-can)

```python
import can

bus = can.interface.Bus(channel='can0', interface='socketcan')

# Send
msg = can.Message(arbitration_id=0x123, data=[0xDE, 0xAD, 0xBE, 0xEF])
bus.send(msg)

# Receive
msg = bus.recv(timeout=1.0)
print(f"ID: {msg.arbitration_id:#x}, Data: {msg.data.hex()}")
```

---

## 9. USB host mode (Linux)

Jetson Orin Nano supports USB 3.2 Gen 2 (10 Gbps) and USB 2.0 host ports.

### Enumeration

```bash
# List connected USB devices
lsusb

# Show USB tree with speeds
lsusb -t

# Detailed device info
lsusb -v -d <vendor>:<product>
```

### Common USB peripherals

| Device type | Driver | Notes |
|------------|--------|-------|
| **USB camera** | UVC (`uvcvideo`) | Works out of the box, see [Multimedia](../4.%20Multimedia/Guide.md) |
| **USB serial** (FTDI, CP210x) | `ftdi_sio`, `cp210x` | Appears as `/dev/ttyUSB*` |
| **USB Ethernet** | `cdc_ether`, `r8152` | Appears as `eth*` or `usb*` |
| **USB storage** | `usb-storage` | Appears as `/dev/sd*` |
| **USB audio** | `snd-usb-audio` | ALSA device |

---

## 10. USB device mode (Linux)

The Orin Nano dev kit's USB-C port supports device (gadget) mode for flashing and development.

### USB gadget framework

```bash
# Load the USB gadget configfs
modprobe libcomposite

# Common gadgets:
# - g_ether: USB Ethernet gadget (device appears as network adapter on host)
# - g_serial: USB serial gadget (device appears as ttyACM on host)
# - g_mass_storage: USB mass storage gadget
```

### Typical use cases

| Gadget | Use case |
|--------|----------|
| **Ethernet (RNDIS/ECM)** | SSH into Jetson over USB without network cable |
| **Serial (ACM)** | Debug console over USB |
| **Mass storage** | Expose a partition or file as USB drive |

---

## 11. NVMe / PCIe storage (Linux)

Most Jetson Orin Nano deployments use NVMe SSD for the root filesystem (faster and more reliable than SD card).

### NVMe operations

```bash
# List NVMe devices
nvme list

# Check health
sudo nvme smart-log /dev/nvme0

# Benchmark
sudo fio --name=test --rw=randread --bs=4k --numjobs=4 \
    --size=1G --runtime=30 --time_based --filename=/dev/nvme0n1

# Check PCIe link speed
sudo lspci -vv | grep -A 20 "Non-Volatile"
```

### PCIe link verification

```bash
# Should show Gen3 x4 or Gen4 x4 depending on module
sudo lspci -vv | grep "LnkSta:"
```

If the link trains at a lower speed than expected, check trace routing (see [Module 2 — Carrier Board](../../2.%20Custom%20Carrier%20Board%20Design%20and%20Bring-Up/Guide.md)).

---

## 12. SD/MMC card (Linux)

SD card slot (if present on carrier) appears as `/dev/mmcblk*`.

```bash
# Check SD card info
sudo fdisk -l /dev/mmcblk1

# Mount
sudo mount /dev/mmcblk1p1 /mnt

# Check speed class
cat /sys/block/mmcblk1/device/speed_class
```

**Production note:** SD cards have limited write endurance. Use NVMe for root filesystem; reserve SD for optional data logging or field updates only.

---

## 13. Backlight (Linux)

If your carrier has an LCD with PWM-controlled backlight:

```bash
# List backlight devices
ls /sys/class/backlight/

# Get current brightness
cat /sys/class/backlight/<device>/brightness

# Get max brightness
cat /sys/class/backlight/<device>/max_brightness

# Set brightness (0 = off, max = full)
echo 128 > /sys/class/backlight/<device>/brightness
```

Configure the backlight PWM channel in the device tree for your display panel.

---

## 14. Projects

- **Sensor dashboard:** Read an I2C temperature sensor (e.g., TMP102) and a SPI ADC (e.g., MCP3008 for analog input), display values on a UART terminal at 1 Hz.
- **CAN bus monitor:** Build a CAN bus sniffer that logs all frames to a file with timestamps. Add filtering by arbitration ID.
- **GPIO interrupt counter:** Use `gpiomon` or libgpiod event monitoring to count rising edges on an input pin. Measure maximum event rate.
- **USB gadget network:** Configure the Jetson as a USB Ethernet gadget so a host laptop can SSH into it over a single USB-C cable.

---

## 15. Resources

| Resource | Description |
|----------|-------------|
| **Jetson Orin Nano Developer Kit User Guide** | Pin header mapping, UART/SPI/I2C bus assignments |
| **libgpiod documentation** | Character device GPIO API (replaces sysfs) |
| **Linux kernel SPI/I2C docs** | `Documentation/spi/` and `Documentation/i2c/` in kernel source |
| **SocketCAN documentation** | Linux CAN subsystem, `ip link`, `candump`, `cansend` |
| **NVMe CLI** | `nvme-cli` package for NVMe management and diagnostics |
| [2. Custom Carrier Board](../../2.%20Custom%20Carrier%20Board%20Design%20and%20Bring-Up/Guide.md) | Pinmux, peripheral validation checklist |
