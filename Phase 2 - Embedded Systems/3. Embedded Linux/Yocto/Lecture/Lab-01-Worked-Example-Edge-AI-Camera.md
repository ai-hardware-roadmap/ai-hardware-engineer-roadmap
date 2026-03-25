# Lab 1 — Worked example: product requirements in Yocto terms

**Companion:** [Lecture 3 — Module 1](Lecture-03.md) · **Course:** [Yocto guide](../Guide.md)

This is a **complete reference answer** for Lab 1: one plausible embedded product described in **Yocto vocabulary** (MACHINE, layers, image contents, OTA, partitions). Adapt the hardware and layer names to your real BSP and Yocto release.

**Note:** Exact `MACHINE` strings, layer names, and recipe names depend on your **vendor BSP** and **Yocto branch**. Always confirm against the BSP README and the release you pinned. For deep Jetson + Yocto production practice on this roadmap, see **Phase 4 Track B** (*Orin-Nano-Yocto-BSP-Production*).

---

## 1. Target hardware

**Product concept:** Edge AI camera node (video ingest + on-device inference).

| Item | Choice |
|------|--------|
| SoC | NVIDIA Jetson Orin Nano (example) |
| Architecture | AArch64 |
| Yocto | Vendor BSP (e.g. **meta-tegra** / NVIDIA-oriented layers) |
| Acceleration | GPU, Tensor cores (CUDA / TensorRT via vendor stacks where licensed and supported) |

**Yocto mapping**

- Set **`MACHINE`** to the value defined by your BSP (example placeholder: `jetson-orin-nano-devkit` — **verify in BSP docs**).
- Add the **BSP layer** (and its documented dependencies) to **`bblayers.conf`**.
- Kernel, firmware, and many userspace GPU pieces are **owned by vendor recipes** in that layer or companion layers.

---

## 2. Connectivity

**Required / desired interfaces**

- Ethernet (primary backhaul)
- Wi-Fi and BLE (optional product goal)
- USB host (peripherals)
- MIPI CSI-2 (camera)
- UART (serial console)

**Yocto mapping**

- **Kernel + device tree:** enable or carry the right drivers and DT nodes for your carrier and modules.
- **Userspace packages (examples):** `wpa-supplicant` or `iwd` for Wi-Fi, `bluez5` for Bluetooth, `iproute2` for networking; exact recipe names vary by layer.
- **Debug:** getty on UART is typically image / distro policy, not something you “apt install” after shipping.

---

## 3. Storage layout

**Assumption:** eMMC (or NVMe) for production; SD possible for bring-up.

**Intent**

- Boot artifacts (bootloader, kernel, DTB as required by platform)
- Root filesystem with **A/B** slots for OTA
- Writable **data** partition (logs, models, config)

**Yocto mapping**

- **`wic`** (`.wks`) or BSP-specific image types define partition tables.
- Your **image recipe** + **OTA layer** must agree on which partition is active, where the rootfs is copied, and how the bootloader selects A vs B.

Illustrative **concept only** (not a drop-in `.wks` for any specific BSP):

```
# Pseudocode — replace with BSP-correct sources and sizes
part /boot   --source bootimg-partition --size 256M
part /       --source rootfs --label rootfs_a
part /       --source rootfs --label rootfs_b
part /data   --size 1024M --fstype ext4
```

---

## 4. Update strategy

**Choice:** **Image-based OTA** with **A/B** rootfs and rollback.

**Typical stacks**

- **RAUC** (`meta-rauc` + integration work), or
- **Mender** (`meta-mender` + integration work)

**Yocto mapping**

- Add the OTA **meta-layer** and follow its **MACHINE** / **distro** integration guide.
- Bootloader (often U-Boot or platform-specific firmware) must support **switching** boot paths and failure policies you define.
- CI should produce **signed** or otherwise protected bundles if your threat model requires it (out of scope here, but plan for it).

---

## 5. Must-have userspace

**Core**

- **Init:** `systemd` (if that is your distro policy)
- **Remote access:** `openssh`
- **Logs:** journald (with `systemd`)

**Application / AI stack (product-dependent)**

- CUDA / TensorRT (usually **vendor recipes**; licensing and redistribution rules apply)
- **Python 3**
- **OpenCV** (recipe name may be `opencv`, `opencv-python`, or split packages — check your layers)
- **GStreamer** and plugins for camera pipelines

**Optional**

- **Containers:** OCI runtime / `docker` — often heavy; many teams defer to a dedicated meta-layer or vendor bundle. Treat as **explicit** image feature, not an afterthought.

**Real time**

- **Moderate** latency: often **PREEMPT** kernel is enough.
- **Hard real time:** separate exercise (PREEMPT_RT, CPU isolation, measurement). Do not assume it “for free” from a default BSP kernel.

**Example `local.conf` fragment (illustrative)**

Use **`IMAGE_INSTALL:append`** (syntax for recent Yocto) and **only** packages that exist in **your** configured layers:

```
IMAGE_INSTALL:append = " \
    openssh \
    python3 \
    python3-pip \
"
```

Add `opencv`, GStreamer packages, OTA client, etc., **after** you confirm recipe names with `bitbake-layers` / `oe-pkgdata-util` or layer documentation.

**Kernel (concept)**

- For preemptible kernel behavior, use **config fragments** or BSP-supported mechanisms; example symbol: `CONFIG_PREEMPT=y` (exact integration depends on kernel recipe).

---

## 6. Must have vs nice to have

**Must have (production-critical)**

- Boot chain + kernel + DTB for your board
- Camera path (CSI driver + userspace capture stack you will ship)
- Minimum network path (at least Ethernet for many products)
- SSH (or another controlled admin path) if operators need it
- Inference runtime you actually ship (CUDA/TensorRT or lighter stack)
- **OTA client + A/B** if you committed to image OTA
- **systemd** units (or your init policy) for the application

**Nice to have**

- Wi-Fi / BLE if not required on day one
- Docker if you can defer orchestration
- Debug tools (`strace`, `htop`, `tcpdump`) — often a **`debug`** image variant, not the production image
- GUI / Wayland — usually omitted on headless edge cameras

---

## Mindset (what this lab is training)

- Yocto builds **images** from **declarative metadata**; the question is **what is baked in**, not what you install later on a golden device.
- **Hardware alignment** flows through **MACHINE**, **BSP layers**, **kernel / DT**, and **image recipes**.
- **Reproducibility** means pinned layers, known **DISTRO** policy, and CI that rebuilds from the same inputs.

---

## Bonus: sketch of repo-facing files

**`conf/local.conf`** (fragment)

```
MACHINE ?= "YOUR_BSP_MACHINE_NAME"
DISTRO ?= "poky"
# Parallelism, download dir, sstate — set per team policy
```

**`conf/bblayers.conf`** (illustrative layer stack)

```
# Bottom-up: core + hardware + OTA + product
# Exact paths and layer names must match your checkout
BBPATH = "${TOPDIR}"
BBFILES ?= ""
```

You will add entries such as `meta`, `meta-poky`, `meta-oe`, **BSP meta**, **meta-rauc** or **meta-mender**, then **`meta-yourproduct`** for your image and bbappends.

**Custom image** (in your product layer), conceptually:

```
inherit core-image
IMAGE_INSTALL:append = "your-runtime-packages"
```

Name the image `yourproduct-image.bb` and `bitbake yourproduct-image` when the stack is wired.

---

## Next steps on this roadmap

1. Continue [Lecture 4 — Architecture](Lecture-04.md) (layers and configs).
2. When you move to Jetson-specific BSP depth, use **Phase 4 Track B** Yocto production material alongside this spec.

---

**Previous:** [Lecture 3](Lecture-03.md) | **Next:** [Lecture 4](Lecture-04.md)
