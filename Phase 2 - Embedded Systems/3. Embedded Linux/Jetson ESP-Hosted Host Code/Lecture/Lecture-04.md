# Lecture 4 — How Wi-Fi becomes `wlan0`

**Course:** [Jetson ESP-Hosted Host Code guide](../Guide.md) · **Phase 2 — Embedded Linux**

**Previous:** [Lecture 03](Lecture-03.md) · **Next:** [Lecture 05 — How BLE becomes `hci0`](Lecture-05.md)

---

## 1. Linux does not want “an SPI Wi-Fi gadget”

Linux userspace tools do not know or care that your radio sits behind a custom SPI transport.

They want:

- a registered wireless device
- a `wiphy`
- a `wireless_dev`
- a net device that userspace can manage

That mapping happens in:

- `esp_hosted_ng/host/esp_cfg80211.c`
- plus the orchestration in `esp_hosted_ng/host/main.c`

---

## 2. The main control flow

In `main.c`, study:

- `process_esp_bootup_event(...)`
- `process_internal_event(...)`
- `process_rx_packet(...)`
- `esp_add_network_ifaces(...)`

The logic is:

1. transport receives ESP boot-up event
2. host validates the chipset
3. host learns capabilities
4. host initializes the Linux-facing interface layer
5. the Wi-Fi side gets registered

This is what turns “working protocol” into “working Linux network interface.”

---

## 3. The exact place where `wlan0` is created

In `main.c`, `esp_add_network_ifaces(...)` calls:

- `esp_cfg80211_add_iface(adapter->wiphy, "wlan%d", 1, NL80211_IFTYPE_STATION, NULL)`

That is the moment where the code requests a normal Linux wireless interface.

That one call is a great Embedded Linux lesson:

- the transport does not expose raw packets to userspace directly
- the driver translates the remote radio into a standard Linux interface model

That is why `nmcli`, `iw`, and other tools can work.

---

## 4. What `esp_cfg80211.c` contributes

Read these areas in `esp_cfg80211.c`:

- `esp_add_wiphy(...)`
- `esp_cfg80211_add_iface(...)`
- `esp_cfg80211_scan(...)`
- `esp_cfg80211_disconnect(...)`
- `esp_cfg80211_connect(...)`
- the `esp_cfg80211_ops` table

This file is your map from:

- Linux wireless subsystem expectations

to:

- command messages sent to the ESP

The major ideas are:

- create and register a `wiphy`
- declare supported bands, rates, and capabilities
- provide operation handlers for scan/connect/disconnect/etc.
- allocate and register the interface objects Linux expects

That is standard subsystem integration work. The ESP is remote, but Linux still wants the usual `cfg80211` contract.

---

## 5. Why `wlan0` is such a strong signal

`wlan0` appearing means much more than “the SPI bus works.”

It implies:

- the host transport is alive
- boot-up event handling completed far enough to initialize upper layers
- `cfg80211` registration succeeded
- interface allocation and registration succeeded

That is why the validated Jetson bring-up used `wlan0` as a major milestone.

It is the difference between:

- low-level electrical or protocol success

and:

- actual Linux subsystem success

---

## 6. What userspace is really exercising

When you run:

- `nmcli dev wifi list`
- `nmcli dev wifi connect ...`

you are indirectly testing:

- `cfg80211` hooks
- command message flow to the ESP
- event and response handling back into Linux

So a Wi-Fi scan is not “just a user command.” It is a full end-to-end test of:

- Linux subsystem registration
- transport reliability
- ESP firmware command handling

That is what makes this repo valuable as an Embedded Linux teaching example.

---

## Lab

Answer these:

1. Where is the `wiphy` created?
2. Where is the station interface requested?
3. Why is `wlan0` stronger proof than a successful `insmod`?
4. Which user-space command best tests the full Wi-Fi path after bring-up?

Optional:

- map `nmcli dev wifi list` to the likely `cfg80211` call path at a high level

---

**Previous:** [Lecture 03](Lecture-03.md) · **Next:** [Lecture 05 — How BLE becomes `hci0`](Lecture-05.md)
