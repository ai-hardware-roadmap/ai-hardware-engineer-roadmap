# OrinClaw — introduction & vision dialogue

Study and speaking notes aligned with **[Guide.md](Guide.md)**. Framed for **product vision**, **architecture story**, and **differentiation**—not for debug or bring-up minutiae.

---

## Introduction (you can deliver in ~45–60 seconds)

I lead firmware and platform work on **OrinClaw**, our capstone product: an **always-on, local-first AI assistant appliance** built around **Jetson Orin Nano 8GB**, orchestrated by **OpenClaw**. The name **OrinClaw** is the product identity—hostname, OTA channels, and docs use it; the folder name “OpenClaw Assistant Box” is just repository structure.

What we are building is deliberately **not** another cloud-tethered speaker. **OrinClaw** optimizes end-to-end across **hardware**—power, thermals, NVMe storage, I2S audio, Ethernet, and an **ESP32-C6** coprocessor for WiFi, Bluetooth, and a **Matter-forward** smart-home path—**system** behavior—reliable OTA with rollback, encryption at rest, and a clear **offline-first** default—and **inference**—streaming STT, local LLM, and TTS sized for **unified memory** on Orin, not a desktop GPU recipe. On top of that we care about **UX**: fast wake, immediate feedback, hardware mute, and a **headless** cylinder so privacy and calm design stay central; optional display or wall **satellite** controllers are product choices, not the default story.

The promise in one line: **better usability than typical premium cloud assistants** by being **offline-first**, **faster in perception** through streaming and local compute, **more reliable** without mandatory cloud, and **more capable** for power users through skills, LAN automation, and optional BYOK cloud only when the user opts in.

Longer term, I see this Jetson and OpenClaw stack as the **foundation** for a broader practice: **NVIDIA edge platforms**, disciplined **OTA and security**, and—down the road—**automotive-adjacent** and **open ecosystem** work in the same engineering culture—not the same product box, but the same rigor.

---

## Vision dialogue (two voices)

Use this as a **rehearsal script** for investors, partners, or cross-functional interviews. Adjust names and tempo to the room.

---

**A:** Everyone says “local AI box” now. What is **OrinClaw** in one sentence?

**B:** A **home-scope voice assistant and automation hub** that runs **OpenClaw** on **Jetson**, keeps **mic and inference local by default**, and is **designed as a product**—custom carrier, appliance UX, and OTA—not a dev kit in a case.

---

**A:** Why **Jetson** instead of a Mac Mini or a big x86 mini PC?

**B:** For **24/7 always-on** duty we care about **wall power**, **thermals**, and **a unified software line** with **CUDA and TensorRT** on the same SoC. A Mac or a dGPU box can win raw speed for huge models; **OrinClaw** bets on **watts-per-wake-word**, **LAN-first home automation**, and an architecture that includes **ESP32-C6** for wireless and **Matter/Thread** style radios—not a general desktop.

---

**A:** What does **OpenClaw** actually do for you?

**B:** It is the **orchestrator**: gateway, channels, skills, browser automation, onboarding patterns. It does **not** replace the **STT, LLM, and TTS** engines—we wire those as **local services** the gateway calls. **OrinClaw** adds **DeviceService**—LED, mute, power and thermal signals—and ties the stack to **our** hardware and **§8-class** security and OTA story from the guide.

---

**A:** “Offline-first” sounds like a slogan. What does the user actually get?

**B:** With **no WAN**, they still get **wake → listen → local reply** for core assistant turns, **LAN web UI**, **MQTT / Home Assistant**, and skills that hit **on-device** data and **LAN** targets. If updates are unreachable, we **say so**—LED and UI—instead of failing silently. **Audio and transcripts do not leave the device** unless the user **explicitly** enables a cloud connector.

---

**A:** How do you compare to **Alexa Pro–class** products without trashing competitors?

**B:** We are not claiming a bigger music catalog. We compete on **privacy by default**, **predictable latency** under load, **no subscription lock-in for the core brain**, and **ownership**: you can extend **skills**, point automation at **Home Assistant**, and keep **keys** on the box. The guide states it plainly: we want **better usability** for people who want **control** and **reliability**, not only convenience.

---

**A:** Why a **custom PCB** if ClawBox-style turnkey already exists?

**B:** **ClawBox** is the **closest cousin**—same broad Jetson class and OpenClaw-friendly story. **OrinClaw** is the path where we **own the BOM**: only the **USB, Ethernet, NVMe, I2S audio, PD, LED ring, ESP-Hosted SPI, and certification-oriented** blocks we need—no dev-kit baggage. That is how we get **cost, thermals, RF, and mechanical** aligned with a **single hero SKU** first, then optional display or battery variants.

---

**A:** Where does **ESP32-C6** fit? Why not M.2 WiFi on the Jetson?

**B:** **ESP-Hosted on SPI** gives Linux a **real `wlan0`** stack—NetworkManager, wpa_supplicant—not a brittle serial bridge. The **same** C6 can participate in **Thread, Zigbee, Matter** with a planned **coexistence** story. If we ever need **laptop-grade WiFi only**, the guide already sketches an **upgrade path**—separate WiFi on Jetson, C6 for IoT—but the default integrated story is **one** well-placed radio module and antenna design.

---

**A:** You said **no screen** on the main device. Won’t people want touch?

**B:** **V1** is **voice + LED + LAN UI**—calm, glanceable, no second phone on the cylinder. A **small top display** or a **wall satellite** with touch tiles is a **later SKU** so we do not boil the ocean. Smart-home **control UI** can live on a **separate ESP32 controller** on the wall, talking **MQTT or Matter** to the box—clear **UX split**: speaker stays **ambient**, controls live where hands expect them.

---

**A:** Security and theft—people will steal the SSD.

**B:** **512GB NVMe** is default for models, logs, and OTA staging—and **removable storage** means **encryption at rest** and **key custody off the naked drive** are **production requirements**, not nice-to-haves, plus mechanical deterrence. That is part of the **trust story**, not an afterthought.

---

**A:** What are you **not** building in V1?

**B:** From the guide: **no** tablet-style on-device UI as the main product, **no** whole-home synchronized audio by default, **no** cloud-only assistant as primary mode, **no** enterprise fleet SOC2 console. We ship **one room**, **one strong appliance**, **private admin over Tailscale** if we want remote access without port forwarding.

---

**A:** Where is this headed for **you** personally?

**B:** **OrinClaw** is the **concrete product** that forces mastery of **Jetson, L4T, inference budgeting, and shipped UX**. The vision extends to **full NVIDIA Jetson–based services**—repeatable images, OTA, security—and toward **automotive-grade discipline** in a different vertical later: **open stacks**, **openpilot-class** curiosity, and **platform** work, with the same **systems** mindset—just not the same box or safety claims until the program matches.

---

## Ultra-short elevator (15 seconds)

**OrinClaw** is a **Jetson Orin Nano**–based, **OpenClaw**-orchestrated **local-first voice assistant and smart-home hub**: **privacy default**, **streaming latency**, **reliable OTA**, **custom hardware** for real product fit—not a cloud speaker clone.

---

## Phrases to reuse (from the guide’s vocabulary)

| Idea | Words you can lift |
|------|-------------------|
| Scope | Hardware → inference → UX |
| Pillars | Privacy + security, smart-home hub, Siri-like flow with **skills** |
| Stack | Wake → STT → Gateway → local LLM + tools → TTS |
| Radio | ESP32-C6, ESP-Hosted-NG, Matter-prefer |
| Storage | 512GB NVMe, models + logs + OTA staging |
| SKU discipline | Single **Core OrinClaw** first; display / battery / satellite later |
| Crowd Supply pitch | **Original / useful / respectful** hardware; **[Proclamation of User Rights](https://www.crowdsupply.com/about#user-rights)** ↔ offline-first, no forced cloud, hackable scope—details in [Guide.md](Guide.md) **§2.5** |

---

*Keep [Guide.md](Guide.md) as the source of truth for checklists, §8 security, benchmarks, and **§2.5 Crowd Supply**; this file is for **how you talk about the work**.*
