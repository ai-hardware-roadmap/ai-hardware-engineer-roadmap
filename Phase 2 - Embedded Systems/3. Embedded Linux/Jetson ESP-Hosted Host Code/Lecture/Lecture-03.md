# Lecture 3 — SPI transport, GPIOs, and IRQ-driven bring-up

**Course:** [Jetson ESP-Hosted Host Code guide](../Guide.md) · **Phase 2 — Embedded Linux**

**Previous:** [Lecture 02](Lecture-02.md) · **Next:** [Lecture 04 — How Wi-Fi becomes `wlan0`](Lecture-04.md)

---

## 1. The transport file to study

Read:

- `esp_hosted_ng/host/spi/esp_spi.c`

This file is where the host turns:

- SPI bus selection
- chip select
- handshake GPIO
- data-ready GPIO

into a working transport endpoint for the ESP.

That makes it the best file for learning how transport glue looks in a real Embedded Linux driver.

---

## 2. Start at the module parameters

Near the top of `esp_spi.c`, look for these:

- `spi_bus_num`
- `spi_chip_select`
- `spi_handshake_gpio`
- `spi_dataready_gpio`
- `spi_mode`

These are exposed as `module_param(...)`.

That tells you:

- transport wiring is now configurable at load time
- the driver can be reused across boards without recompilation

This is a direct improvement over hardcoded board assumptions.

---

## 3. Find `spi_dev_init(...)`

`spi_dev_init(...)` is the heart of transport bring-up.

Conceptually, it is responsible for:

- selecting the Linux SPI device
- configuring SPI mode and clock
- setting up the transport context
- requesting and configuring the handshake/data-ready GPIOs
- mapping those GPIOs into IRQs

This is the point where a “Linux board description” becomes an “active transport endpoint.”

That is an important Embedded Linux mental shift:

- device tree and sysfs prove presence
- transport init proves usability

---

## 4. Why the IRQs matter more than the GPIO names

The validated Jetson path used:

- `spi_handshake_gpio=471`
- `spi_dataready_gpio=433`

But those numbers alone are not success.

The stronger success signal is:

- the host driver requested them
- they became IRQ sources
- interrupt counters moved when the ESP booted

That is how you should debug GPIO-based bring-up:

- name -> request -> IRQ mapping -> actual edge activity

If you stop at “the number looks right,” you have not really debugged anything.

---

## 5. Reusing `spi0.0` is a Linux device-model decision

The Jetson fork reuses an existing SPI device such as:

- `spi0.0`

when possible.

That matters because Linux may already have:

- a device tree node
- a bus number
- a chip-select mapping

This is better than always forcing the driver to invent a new SPI device object.

Embedded Linux lesson:

- respect the kernel’s device model when it already describes the hardware correctly

The shell script unbinds `spidev`, but the transport code is written to cooperate with the existing SPI device path.

---

## 6. Runtime clock clamping is a real bring-up policy

The validated Jetson work changed the runtime clock behavior.

The host can receive a request from the ESP boot-up path to move to:

- `26 MHz`

But the validated Jetson flow intentionally keeps the host capped at:

- `10 MHz`

Why this is important:

- transport stability beat nominal peak speed during bring-up
- the driver now uses `clockspeed=` as both:
  - initial speed
  - runtime ceiling

That is a very real Embedded Linux engineering pattern:

- make the code reflect the validated board limit
- then widen later only with measurement

---

## 7. What success looked like on hardware

The key transport-level log lines were:

- `Received ESP boot-up event`
- `Chipset=ESP32-C6 ID=0d detected over SPI`
- `ESP requested SPI CLK 26 MHz, clamping to host limit 10 MHz`

That proves:

- SPI data transfer is alive
- the protocol exchange is alive
- the transport policy is being enforced

This is a much stronger success criterion than:

- module inserted
- no kernel oops
- `/dev/spidev0.0` exists

---

## Lab

Do these:

1. Find where `spi_context.spi_bus_num` and `spi_context.spi_chip_select` get filled.
2. Find where the handshake and data-ready GPIO values enter the transport context.
3. Find the function that handles runtime SPI clock changes.
4. Write down the three strongest transport-level log lines you would want during bring-up.

---

**Previous:** [Lecture 02](Lecture-02.md) · **Next:** [Lecture 04 — How Wi-Fi becomes `wlan0`](Lecture-04.md)
