# OpenThread

*Follows [**IoT Networking and Device Connectivity**](../Guide.md) and extends the Phase 2 embedded-software path from local peripheral buses to low-power IP networking. Use this guide to understand what Thread is, how OpenThread implements it, and how the same stack can run either directly on an MCU or through a Linux host plus radio co-processor.*

---

## 1. Why OpenThread Matters

OpenThread is Google's open-source implementation of the **Thread** protocol. It is designed for low-power, IPv6-based mesh networking on top of **IEEE 802.15.4**, which makes it a good fit for battery-powered sensors, smart-home endpoints, industrial nodes, and border-router designs.  
Official sources: [OpenThread overview](https://openthread.io/), [ESP-IDF Thread guide](https://docs.espressif.com/projects/esp-idf/en/stable/esp32/api-reference/network/esp_openthread.html)

For roadmap learners, OpenThread is valuable because it sits exactly at the boundary between **MCU firmware** and **networked systems**. You cannot treat it as "just another driver" or "just another protocol" because it forces you to think about radio timing, low-power behavior, secure commissioning, IPv6 networking, and Linux-host integration at the same time.

---

## 2. What Thread Actually Is

Thread is an **IP-based mesh protocol**. At the radio layer it uses IEEE 802.15.4, but at the network layer it is still an IPv6 system, which is why a Thread node can fit into normal IP-based tooling much more naturally than many older embedded fieldbuses.

That distinction is important. BLE is excellent for short-range peripheral links, and Wi-Fi is excellent when you need bandwidth, but Thread is built for **low-power, many-node, always-available networking** where the network can repair itself as routers join or disappear.

OpenThread's official platform documentation describes the stack as implementing the full Thread networking layers, including **IPv6, 6LoWPAN, IEEE 802.15.4 with MAC security, Mesh Link Establishment, and Mesh Routing**. In practice, that means the stack handles both the radio-facing mechanics and the higher routing behavior that turns many small devices into one stable network.  
Official source: [OpenThread features](https://openthread.io/)

---

## 3. Protocol Stack: From Radio Frames to IP Packets

OpenThread is easiest to understand if you read it as a layered stack:

| Layer | What it does |
|---|---|
| IEEE 802.15.4 PHY/MAC | Defines the low-power radio link, frame format, channel use, acknowledgements, and MAC-layer security |
| 6LoWPAN | Compresses IPv6 headers so IPv6 packets fit efficiently over a tiny 802.15.4 frame budget |
| IPv6 | Gives each node a real IP identity instead of a proprietary application-only address model |
| UDP / ICMPv6 / higher services | Supports messaging, discovery, and management above the network layer |
| Thread control plane | Handles network formation, partition recovery, roles, commissioning, and mesh routing |

The important engineering idea is that Thread is not a "small custom sensor protocol." It is a constrained IP network. That is why it fits so naturally with border routers and Linux hosts, and why host tools such as `ot-ctl` and OTBR can manage it without inventing an entirely separate networking world.

6LoWPAN matters here because raw IPv6 packets are too large and verbose for a small 802.15.4 frame budget. Thread stays IP-native by compressing and fragmenting traffic where needed instead of abandoning IPv6.

### 6LoWPAN: why IPv6 can fit on tiny radios

6LoWPAN stands for **IPv6 over Low-Power Wireless Personal Area Networks**. It is an IETF-defined adaptation layer that lets constrained devices carry IPv6 traffic over small, low-power links such as IEEE 802.15.4 instead of requiring a completely separate non-IP protocol stack.

This is the core reason Thread can present itself as a real IP network even though it runs on a tiny radio. A normal IPv6 packet assumes a much larger and more capable link than 802.15.4 provides, so 6LoWPAN sits between the MAC layer and the IPv6 layer and reshapes traffic to fit the medium.

#### Header compression

A plain IPv6 header is large relative to the frame size available on 802.15.4 links. 6LoWPAN reduces this cost by compressing fields that are predictable, shared, derivable from context, or repeated across the network. In a well-formed low-power mesh, many of those fields do not need to be sent in full every time.

That means the radio spends less airtime carrying protocol overhead and more airtime carrying useful application payload. For battery-powered devices, this is not just a bandwidth optimization; it directly affects energy use, latency, and how often the radio has to stay awake.

#### Fragmentation

IPv6 requires a minimum MTU of 1280 bytes, but IEEE 802.15.4 frames are far smaller. 6LoWPAN handles this mismatch by fragmenting larger packets into smaller radio frames and reassembling them on the receiving side.

This is another reason Thread feels like a real IP network even on constrained devices. The application can still think in terms of IPv6 communication, while the adaptation layer handles the ugly details of fitting those packets onto a much smaller link.

#### Adaptation layer role

From an embedded-systems point of view, 6LoWPAN is the translation layer between "tiny radio world" and "IPv6 world." It is not a replacement for IPv6 and not a separate application protocol; it is the mechanism that makes IPv6 practical on low-power personal area networks.

In the Thread stack, this is what lets you keep standard IP ideas such as IPv6 addressing, UDP, service discovery, and border routing without pretending that the radio is as capable as Ethernet or Wi-Fi. That is why Thread can integrate cleanly with Linux hosts, OTBR, and IP-based tools instead of requiring a proprietary gateway protocol everywhere.

#### Power and mesh implications

6LoWPAN is designed for devices that may sleep often, wake briefly, and still need to participate in a routed network. It works well with low-power mesh behavior because it reduces transmission overhead and keeps the radio cost of IP communication manageable.

This is why it shows up so often in smart-home, industrial, and sensor-network deployments. The combination of IEEE 802.15.4, 6LoWPAN, IPv6, and Thread routing gives you a network that is low-power, self-healing, and still understandable through mainstream networking concepts.

### UDP and ICMPv6 in a 6LoWPAN / Thread network

Once IPv6 is made practical by 6LoWPAN, the next question is what transport and control protocols ride on top of it. In practice, **UDP** and **ICMPv6** are the two most important ones to understand first.

OpenThread's overview explicitly presents the stack as supporting **IPv6, UDP, CoAP, and ICMPv6**, which is a strong hint about how real applications are expected to use the network. UDP is the usual transport for application traffic, while ICMPv6 handles core network-control tasks such as diagnostics and parts of IPv6 control behavior.  
Official source: [OpenThread overview](https://openthread.io/)

#### Why UDP is used so often

UDP is the common transport choice in low-power Thread systems because it is lightweight and connectionless. A battery-powered sensor does not want the complexity and ongoing state cost of a heavier transport unless it truly needs it, so application protocols such as CoAP are commonly built on UDP instead of TCP.

RFC 6282 matters here because it defines **LOWPAN_NHC**, the next-header compression format used after the compressed IPv6 header. That RFC specifically defines compression for **UDP**, which is one reason UDP fits so naturally in 6LoWPAN networks.  
Official source: [RFC 6282](https://datatracker.ietf.org/doc/html/rfc6282)

UDP compression matters in two practical ways:

* the header can be compressed beyond the normal 8-byte UDP form
* a specific port range (`0xf0b0` to `0xf0bf`, decimal `61616` to `61631`) can be compressed very aggressively

That is not just a protocol curiosity. On a tiny low-power frame budget, saving a few bytes repeatedly can materially reduce airtime and power use.

One nuance is worth stating clearly: with IPv6, the UDP checksum is normally mandatory. RFC 6282 allows checksum elision only under restricted conditions, with upper-layer authorization and an additional integrity check. So the correct mental model is not "6LoWPAN removes reliability checks," but rather "6LoWPAN allows carefully controlled header-size tradeoffs when the rest of the system can still guarantee integrity."

#### Why ICMPv6 still matters

ICMPv6 is not optional background noise. It is part of how an IPv6 network remains manageable. In low-power Thread systems, it is still used for diagnostics and core control behavior, including things like echo requests (`ping`) and IPv6 control interactions.

But standard IPv6 Neighbor Discovery relies heavily on multicast, and that is a bad fit for sleepy low-power wireless networks. RFC 6775 exists exactly because unmodified IPv6 Neighbor Discovery is inefficient and sometimes impractical in a 6LoWPAN due to heavy multicast use and non-transitive wireless links.  
Official source: [RFC 6775](https://www.rfc-editor.org/info/rfc6775)

So in 6LoWPAN systems, ICMPv6 is still present, but the surrounding discovery behavior is adapted for constrained networks. This is why low-power IP networking is more than just "run IPv6 on a small radio" — the control behavior also has to be reshaped for sleepy, lossy, battery-powered nodes.

#### Why these two protocols matter together

UDP and ICMPv6 together are what make Thread devices feel like first-class IP nodes instead of proprietary endpoints behind a custom gateway. UDP carries the application traffic, while ICMPv6 and the optimized IPv6 control behavior keep the network diagnosable and operational.

That combination is one of the biggest reasons Thread integrates cleanly with Linux hosts and border routers. You are not inventing a special application protocol and then tunneling it through a gateway; you are still operating in an IPv6 world, just an adapted one.

### Thread control plane: how the mesh thinks

The data plane moves packets. The **control plane** decides how the mesh forms, which nodes trust each other, which paths are good, and how network-wide information is distributed.

In Thread, the core control-plane mechanism is **Mesh Link Establishment (MLE)**. OpenThread's Thread primer states that MLE is used to configure links and disseminate information about the network to Thread devices.  
Official source: [OpenThread Thread Primer: Network Discovery and Formation](https://openthread.io/guides/thread-primer/network-discovery)

#### MLE

MLE is the protocol that helps a device move from "I hear something on the radio" to "I am securely attached to this mesh and understand my parent, leader, and route context." The OpenThread primer lists these MLE responsibilities:

* discover neighboring devices
* determine link quality
* establish links to neighbors
* negotiate link parameters such as device type, frame counters, and timeout

The same primer also explains that MLE disseminates:

* leader data
* network data
* route propagation information

This is why MLE is best thought of as the glue of the Thread control plane. It is not only about one link coming up; it is also how the mesh shares enough state for the whole network to stay coherent.

#### Distance-vector style route propagation

OpenThread's Thread primer explicitly says that route propagation in Thread works similarly to **RIP**, a distance-vector routing protocol. That gives you a useful mental model: routers exchange route-related information and choose paths based on distributed cost knowledge rather than relying on one central controller.  
Official source: [OpenThread Thread Primer: Network Discovery and Formation](https://openthread.io/guides/thread-primer/network-discovery)

This matters because it explains why Thread can be self-healing. If one router disappears, the rest of the control plane can still converge on new parent relationships and route choices without an operator manually rebuilding the network.

#### MLE and commissioning are not the same thing

One subtle but important point from the OpenThread primer is that **MLE only proceeds once a device has obtained Thread network credentials through Thread commissioning**. In other words, secure admission to the network happens first, and only then does the device participate fully in the mesh-control machinery.

This separation is good system design. Commissioning answers "is this device allowed in?" while MLE answers "now that it is allowed in, how does it attach and learn the mesh?" Mixing those two ideas together makes Thread harder to reason about.

---

## 4. Device Roles and Why They Matter

A Thread network is not flat. Nodes take on different roles depending on whether they route traffic, sleep aggressively, or coordinate parts of the mesh.

### Leader

The Leader manages key network-wide state such as partition information and configuration data. It is not a permanent boss node; if it disappears, another eligible node can take over.

### Router

Routers forward packets for other devices and keep the mesh connected. They are the infrastructure of the Thread network, so they are normally mains-powered or at least less aggressively power-constrained than sleepy endpoints.

### Router-Eligible End Device (REED)

A REED is not routing yet, but it can become a router if the network needs more routing capacity. This makes the network adaptive instead of requiring every node to be manually assigned a role up front.

### End Device / Sleepy End Device

End devices attach through a parent router instead of forwarding mesh traffic themselves. Sleepy end devices go further and spend most of their time asleep, which is how Thread supports long battery life without giving up network reachability.

### Border Router and Commissioner

A Border Router connects the Thread mesh to other IP networks such as Ethernet, Wi-Fi, or USB-backed Linux interfaces. A Commissioner is responsible for onboarding and authorizing new devices, which is why Thread setup is a network-management problem, not just a radio problem.

---

## 5. OpenThread Software Architectures

One reason OpenThread is so widely used is that it supports multiple deployment models instead of forcing every product into the same software split. The OpenThread platform documentation explicitly calls out both **SoC** and **co-processor** designs.  
Official source: [OpenThread platforms](https://openthread.io/platforms)

### SoC Design

In a System-on-Chip design, the radio, OpenThread stack, and application all run on the same MCU or wireless SoC. This is the most common approach for end devices because it is low-cost, low-power, and direct: your firmware calls the OpenThread APIs locally and the same chip drives the radio.

This is the model you use when the device itself is the product, such as a battery sensor, light switch, or smart plug. In ESP-IDF, the `openthread/ot_cli` example is a good mental model for this path.

### NCP Design

In a Network Co-Processor design, the host application talks to a co-processor using the **Spinel** protocol. OpenThread can run partly on the host side, with the network-facing device behaving like a dedicated networking component rather than the main application processor.

This split is useful when a stronger host CPU exists already and you want the network function separated from the application logic. It also makes host-side development easier because large application changes do not require rebuilding the radio firmware every time.

### RCP Design

In a Radio Co-Processor design, the host processor runs the core OpenThread stack while the attached device handles the minimal radio-facing work. OpenThread's official co-processor documentation describes this as the host keeping the protocol logic while the device acts as the Thread radio controller, usually connected over **SPI** or **UART** using **Spinel**.  
Official sources: [Co-Processor Designs](https://openthread.io/platforms/co-processor), [OT Daemon](https://openthread.io/platforms/co-processor/ot-daemon)

This is the model that matters most for Linux gateways and Jetson-class systems. It lets a Linux host run OTBR or `ot-daemon`, while a small MCU or radio SoC provides the 802.15.4 link.

---

## 6. OpenThread Internals: Why the Stack Is Portable

OpenThread is intentionally written so the networking core is portable across many chips and operating systems. The OpenThread platform guide describes it as portable C/C++ with a **narrow Platform Abstraction Layer (PAL)**, which is why the same core can run on bare-metal systems, FreeRTOS, Zephyr, Linux, and macOS.  
Official source: [OpenThread platforms](https://openthread.io/platforms)

The PAL is the contract between the OpenThread core and the underlying hardware port. The OpenThread porting guide lists the major PAL areas as:

* alarm/timer services
* bus interfaces such as UART or SPI
* IEEE 802.15.4 radio interface
* entropy / random source
* settings storage
* logging
* system-specific initialization  
Official source: [Platform Abstraction Layer APIs](https://openthread.io/guides/porting/implement-platform-abstraction-layer-apis)

This matters because it tells you what "porting OpenThread" really means. You are not rewriting the mesh stack from scratch. You are implementing the hardware-facing interfaces correctly so the portable upper layers can trust your radio, timer, storage, and transport behavior.

---

## 7. OpenThread on ESP32-C6

ESP-IDF exposes Thread support through its `openthread` component and documents several official examples:

* `openthread/ot_cli`
* `openthread/ot_rcp`
* `openthread/ot_br`
* `openthread/ot_trel`
* sleepy-device examples  
Official source: [ESP-IDF Thread guide](https://docs.espressif.com/projects/esp-idf/en/stable/esp32/api-reference/network/esp_openthread.html)

This is the key practical point for the roadmap: **ESP32-C6 can be used either as a full Thread node or as an RCP attached to a Linux host**. That makes it unusually good for study, because the same silicon can teach you both MCU-side Thread firmware and host-plus-radio architectures.

ESP-IDF also exposes the OpenThread lifecycle through functions such as:

* `esp_openthread_init(...)`
* `esp_openthread_auto_start(...)`
* `esp_openthread_launch_mainloop(...)`

These APIs show the embedded control flow clearly. First you initialize the platform and stack, then optionally start with a dataset, then enter the main loop that services radio events, timers, and protocol work.

---

## 8. CLI, Spinel, and Host Control

The OpenThread CLI is not just a demo shell. It is one of the fastest ways to understand what state the stack is in, how a node forms a network, and what role it currently holds.

For SoC designs, the CLI usually runs directly on the device. For host-plus-RCP designs, the host talks to the radio through **Spinel**, which OpenThread describes as the standard host-controller protocol used by both RCP and NCP designs.  
Official source: [Co-Processor Designs](https://openthread.io/platforms/co-processor)

When the host side is POSIX or Linux, **OpenThread Daemon (`ot-daemon`)** is the lightweight service wrapper around this model. The OpenThread docs show that it runs as a service, exposes a UNIX socket, and can be controlled with `ot-ctl`. This is the cleanest way to understand a Linux host talking to a serial Thread radio without bringing in the full Border Router stack immediately.  
Official source: [OT Daemon](https://openthread.io/platforms/co-processor/ot-daemon)

---

## 9. Security and Reliability

Thread is designed for real deployments, not one-off lab links. OpenThread's public description emphasizes reliable, secure, low-power device-to-device communication, and the stack includes IEEE 802.15.4 MAC security, secure commissioning, and border-router support.  
Official source: [OpenThread overview](https://openthread.io/)

The important thing to understand is that OpenThread security is **layered**, not a single checkbox. Different protections apply at different points in the system:

* **Link-layer protection:** IEEE 802.15.4 frames are protected with MAC security.
* **Commissioning protection:** a new device must be authorized before it joins the mesh.
* **Application / end-to-end protection:** application traffic can use higher secure protocols such as DTLS-backed Secure CoAP.

### Link-layer security: AES-CCM

OpenThread's porting guide explicitly states that OpenThread Security uses **AES-CCM** cryptography to encrypt and decrypt IEEE 802.15.4 or MLE messages and validate their integrity. In practice, that means packets are not just hidden from casual inspection; they are also authenticated so modified packets can be detected instead of silently trusted.  
Official source: [OpenThread advanced porting features](https://openthread.io/guides/porting/implement-advanced-features)

This matters for embedded developers because the crypto is not abstract "cloud security." It depends on the local platform port doing the right thing with entropy, nonces, and key handling. If your entropy source is weak or your PAL implementation is careless, the security model weakens even if the high-level Thread code is correct.

### Secure commissioning: who is allowed onto the mesh

Thread does not let random devices join just because they are in radio range. OpenThread's Border Agent API documentation states that commissioner candidates establish **secure DTLS sessions** with the Border Agent using **PSKc**, and only then can a connected commissioner petition to become a full commissioner.  
Official source: [OpenThread Border Agent API](https://openthread.io/reference/group/api-border-agent)

On the device side, OpenThread Commissioner APIs and OTBR tools use **PSKd** or Joiner credentials to authorize specific joining devices. The practical lesson is simple: joining the network is a controlled admission process, not a broadcast "pair with anything nearby" flow. That is one of the main reasons Thread is suitable for real smart-home and industrial products instead of hobby-only mesh links.  
Official sources: [Commissioner API](https://openthread.io/reference/group/api-commissioner), [OTBR PSKc tools](https://openthread.io/guides/border-router/tools)

### End-to-end security above the mesh

Thread's built-in mesh protections do not remove the need for application-level security. OpenThread's Secure CoAP documentation shows that **Secure CoAP uses DTLS** to establish secure end-to-end connections between peers.  
Official source: [Secure CoAP CLI concepts](https://openthread.io/reference/cli/concepts/coaps)

That distinction is important. Link-layer security protects the radio hop and the mesh transport, while protocols such as Secure CoAP protect the application conversation itself. In other words, OpenThread gives you secure networking, but strong product design still requires secure application protocols on top.

### Key material, entropy, and storage

From an embedded-software perspective, the interesting part is that security is not "added later in the cloud." Device identity, network admission, credential storage, and persistent settings are part of the firmware design from the beginning. That is why the OpenThread PAL includes **entropy** and **non-volatile storage** as first-class platform requirements.  
Official source: [OpenThread PAL guide](https://openthread.io/guides/porting/implement-platform-abstraction-layer-apis)

The PAL guide explicitly calls out the entropy API as maintaining security assets for the network, including AES-CCM nonces and other random values. This is why many production platforms pair OpenThread with hardware random generators, secure storage blocks, or cryptographic accelerators: not because the stack requires vendor lock-in, but because those features improve the security quality of the port.

### Reliability and self-healing behavior

Reliability comes from the mesh behavior itself. A Thread network can survive node loss, promote eligible devices into routing roles, and keep sleepy endpoints attached through parents, which is very different from a simple point-to-point radio link.

That does not make the network invulnerable. A real deployment still has to think about denial-of-service conditions, bad radio environments, reset behavior, and credential handling during manufacturing and updates. But OpenThread starts from a much stronger foundation than ad hoc plaintext radio protocols because security, commissioning, and network repair are already part of the architecture.

---

## 10. Why OpenThread Belongs in Embedded Software

OpenThread belongs in **Embedded Software**, not only in Linux or networking sections, because the protocol is tightly coupled to firmware concerns:

* radio driver correctness
* timer precision
* ISR and task scheduling behavior
* persistent settings
* power states and sleepy-device timing
* serial buses used for CLI or Spinel

If your UART path drops bytes, your RCP host design fails. If your timer or alarm implementation is wrong, the mesh behavior becomes unstable. If your power model is wrong, your sleepy node either burns too much current or falls off the network.

This is exactly the type of protocol that turns "I can write drivers" into "I can build a networked embedded product."

---

## 11. Connection to the Rest of the Roadmap

| Roadmap area | How OpenThread connects |
|---|---|
| ARM MCU + CMSIS / HAL | You need working radio, timer, UART/SPI, entropy, and settings drivers underneath the stack |
| FreeRTOS | Thread nodes often run in RTOS-based firmware, so task structure, event loops, queues, and power-aware scheduling matter |
| UART / SPI | These buses are used not just for sensors, but also for CLI and Spinel host-controller links |
| Embedded Linux | OTBR and `ot-daemon` are Linux-host examples of the RCP architecture |
| Jetson deployment | A Jetson can act as the stronger host while an ESP32-C6 acts as the Thread radio |

OpenThread is therefore a natural bridge between pure MCU work and mixed MCU-plus-Linux systems. If you understand it well, you are better prepared for gateway design, border routers, Matter-style stacks, and multi-processor embedded products.

---

## 12. Suggested Projects

### Project 1: Single-board CLI node

Flash `ot_cli` onto an ESP32-C6 and use the CLI to form a one-node Thread network. Practice `ifconfig up`, `thread start`, `state`, and dataset commands until you are comfortable reading the network state directly.

### Project 2: Two-node mesh

Bring up two Thread-capable boards and verify that one becomes Leader while the other joins as a child or router. Watch how the routing roles and attach behavior change as you reset or power-cycle one node.

### Project 3: ESP32-C6 as RCP for a Linux host

Flash `ot_rcp` and connect it to a Linux host over UART or SPI. Use `ot-daemon` or OTBR and confirm that the host creates `wpan0`, can query `ot-ctl state`, and can start a Thread dataset.

### Project 4: Border router with external backbone

Use OTBR to bridge the Thread mesh to Ethernet, Wi-Fi, or a USB-backed Linux bridge. This is where OpenThread stops being just a radio experiment and becomes a real infrastructure component.

---

## References

### Official

* [OpenThread overview](https://openthread.io/)
* [OpenThread platforms](https://openthread.io/platforms)
* [OpenThread co-processor designs](https://openthread.io/platforms/co-processor)
* [OpenThread daemon](https://openthread.io/platforms/co-processor/ot-daemon)
* [OpenThread platform abstraction layer guide](https://openthread.io/guides/porting/implement-platform-abstraction-layer-apis)
* [ESP-IDF Thread / OpenThread guide](https://docs.espressif.com/projects/esp-idf/en/stable/esp32/api-reference/network/esp_openthread.html)

### Roadmap follow-ons

* [ARM MCU, FreeRTOS, and Communication Protocols](../../Guide.md)
* [Jetson ESP-Hosted Host Code](../../../3.%20Embedded%20Linux/Jetson%20ESP-Hosted%20Host%20Code/Guide.md)
* [ESP32-C6 OpenThread RCP on Jetson Orin Nano](../../../../Phase%204%20-%20Track%20B%20-%20Nvidia%20Jetson/5.%20Application%20Development/2.%20Network%20and%20Connectivity/ESP32-C6-OpenThread-RCP-Jetson-Orin-Nano.md)
