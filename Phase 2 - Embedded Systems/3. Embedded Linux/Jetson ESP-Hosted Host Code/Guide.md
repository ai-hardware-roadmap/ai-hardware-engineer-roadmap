# Jetson ESP-Hosted Host Code — Embedded Linux Driver Reading Course

A structured mini-course for engineers who want to read a **real Embedded Linux host stack** instead of only consuming board bring-up tutorials.

The code studied here is the Jetson-oriented fork:

- [ai-hpc/jetson-esp-hosted](https://github.com/ai-hpc/jetson-esp-hosted)

The center of gravity is the `esp_hosted_ng/host/` tree, especially the SPI path validated on **Jetson Orin Nano** with **ESP32-C6**.

---

## Why this course exists

Most Embedded Linux learning material splits the world into separate boxes:

- SPI and GPIO tutorials
- kernel module tutorials
- Wi-Fi tutorials
- Bluetooth tutorials

Real systems are not split that way.

This codebase is useful because one host stack crosses all of those at once:

- an out-of-tree kernel module
- a board-specific bring-up script
- SPI transport and GPIO IRQs
- `cfg80211` Wi-Fi integration
- HCI / BlueZ integration for BLE
- Linux userspace tools such as `nmcli`, `bluetoothctl`, `hciconfig`, and `rfkill`

That makes it a strong Embedded Linux case study.

---

## What you will learn

- How a Linux host driver maps a remote ESP chip into normal Linux interfaces.
- How board-specific shell tooling and generic kernel module code fit together.
- How to read transport code in `esp_spi.c` without getting lost in implementation detail.
- How Wi-Fi becomes `wlan0` through `cfg80211`.
- How BLE becomes `hci0` through the HCI subsystem.
- How to separate:
  - **board policy**
  - **transport policy**
  - **Linux subsystem integration**

---

## What you should already know

Before this mini-course, you should be comfortable with:

- Linux command-line basics
- the boot chain at a high level: bootloader -> kernel -> root filesystem
- device tree and kernel modules at a beginner level
- basic SPI/GPIO concepts

If not, do the main Embedded Linux guide and Yocto course first.

---

## Step-by-step lectures

Each lecture is under **[Lecture/](Lecture/README.md)**. Work in order.

| # | Topic | Lecture |
|---|-------|---------|
| 1 | Linux mental model for this host stack | [Lecture-01.md](Lecture/Lecture-01.md) |
| 2 | Build, load, and board policy on Jetson | [Lecture-02.md](Lecture/Lecture-02.md) |
| 3 | SPI transport, GPIOs, and IRQ-driven bring-up | [Lecture-03.md](Lecture/Lecture-03.md) |
| 4 | How Wi-Fi becomes `wlan0` | [Lecture-04.md](Lecture/Lecture-04.md) |
| 5 | How BLE becomes `hci0` and how to validate the full path | [Lecture-05.md](Lecture/Lecture-05.md) |

---

## Recommended study pattern

For each lecture:

1. read the Linux-side explanation first
2. open the exact file in the repo
3. trace the named functions yourself
4. compare the explanation against the real code
5. answer the lab questions before moving on

Do not try to memorize the whole repo. Learn to recognize the architecture and the subsystem boundaries.

---

## Validated real-hardware context

This course reflects the validated Jetson flow already documented elsewhere in the roadmap:

- Jetson Orin Nano over SPI
- `spi0.0`
- `resetpin=-1`
- `spi_handshake_gpio=471`
- `spi_dataready_gpio=433`
- runtime SPI clock capped at `10 MHz`
- `wlan0` appears after manual ESP reset
- `hci0` appears and BLE scan works

That matters because this is not a hypothetical driver-reading exercise. It is grounded in a path that was actually brought up on hardware.
