# Lecture 5 — How BLE becomes `hci0` and how to validate the full path

**Course:** [Jetson ESP-Hosted Host Code guide](../Guide.md) · **Phase 2 — Embedded Linux**

**Previous:** [Lecture 04](Lecture-04.md)

---

## 1. The Bluetooth side is a separate Linux subsystem

Wi-Fi and Bluetooth ride over the same host transport, but Linux does not treat them as the same thing.

For BLE, the important file is:

- `esp_hosted_ng/host/esp_bt.c`

This file integrates with the Linux HCI subsystem instead of `cfg80211`.

That is the key Embedded Linux lesson:

- one transport
- multiple Linux subsystem personalities

---

## 2. The exact code path for `hci0`

Read these functions:

- `esp_init_bt(...)`
- `esp_deinit_bt(...)`
- `esp_bt_send_frame(...)`

In `esp_init_bt(...)`, the driver:

- allocates an HCI device
- associates it with the adapter
- sets the HCI bus type
- registers the HCI device

On the SPI path, the bus becomes:

- `HCI_SPI`

That is why the validated Jetson logs and tools showed:

- `hci0`
- `Bus: SPI`

This is not cosmetic. It means Linux Bluetooth tooling now sees a standard controller interface.

---

## 3. How incoming BLE data reaches Linux

Now return to `main.c` and re-read part of `process_rx_packet(...)`.

That function checks the incoming payload type.

When the packet is for Bluetooth:

- `payload_header->if_type == ESP_HCI_IF`

the code forwards the data to the HCI stack using:

- `hci_recv_frame(...)`

This is the crucial handoff:

- transport packet from ESP
- becomes HCI traffic in Linux

That is exactly how a custom hardware path gets translated into a standard subsystem view.

---

## 4. What the capability logs are telling you

In `main.c`, the capability printout tells you what the ESP claims to support.

On the validated Jetson path, the logs showed:

- `BT/BLE`
- `HCI over SPI`
- `BLE only`

That last point matters for **ESP32-C6**:

- this path is **BLE-only**
- do not expect classic Bluetooth audio profiles from this configuration

That is a practical product constraint, not just a code detail.

---

## 5. The validated Linux-side BLE proof

On real hardware, the validation path was:

- `hciconfig -a`
- `bluetoothctl list`
- `bluetoothctl`
- `scan on`

And the proof points were:

- `hci0` existed
- BlueZ recognized the controller
- the controller bus reported `SPI`
- BLE scan discovered nearby devices

That means the BLE path was not just registered. It was functional.

This is important:

- `hci0` appearing is good
- `scan on` finding devices is much better

That is the same lesson you saw with Wi-Fi:

- appearance is not the same as validated behavior

---

## 6. End-to-end success criteria for this codebase

For this Jetson case study, full success means:

- transport up
- boot-up event received
- chipset validated
- `wlan0` created
- Wi-Fi scan works
- `hci0` created
- BLE scan works

That is the right Embedded Linux mindset:

- validate at the subsystem level the operating system actually cares about
- not just at the signal or module-insert level

---

## Final lab

Answer these:

1. Where is the HCI device allocated?
2. Where is the HCI bus type set to SPI?
3. Where do incoming Bluetooth packets get handed to Linux?
4. Why is `scan on` stronger evidence than `bluetoothctl list` alone?
5. Why does this repo make a good Embedded Linux case study for subsystem integration?

Optional extension:

- write a short comparison of:
  - `cfg80211` integration for Wi-Fi
  - HCI integration for BLE
- identify what is shared between them and what is subsystem-specific

---

**Previous:** [Lecture 04](Lecture-04.md) · **Back to:** [Course hub](../Guide.md)
