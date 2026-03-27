# ODMDATA, pinmux, and GPIO on Jetson Linux

**Phase 4 — Track B — Nvidia Jetson** · L4T customization (companion note)

This note ties together **ODM data**, **UPHY / PCIe** configuration, and the **three different layers** people mean when they say “GPIO on Jetson”: **MB1 BCT pinmux**, **PADCTL register pokes (`devmem`)**, and **userspace GPIO** (`libgpiod`). It complements [Jetson-Module-Adaptation-Bring-Up-Orin-NX-Nano.md](Jetson-Module-Adaptation-Bring-Up-Orin-NX-Nano.md) (carrier bring-up) and [T23x-Deployment.md](T23x-Deployment.md) (BCT / MB1 DTS detail).

Always confirm **register meanings**, **flash variables**, and **sysfs paths** against the [Jetson Linux Developer Guide](https://docs.nvidia.com/jetson/) for **your JetPack line** and module (Orin NX/Nano vs Xavier, etc.).

---

## What is ODMDATA?

In **Jetson Linux** (the BSP people still often call **L4T**), **ODM data** is a **boot-time configuration** value the platform uses (with other BCT / firmware inputs) to select **SoC-level muxing and options** before Linux is fully up.

In practice, engineers talk about **`ODMDATA`** as the **string or value** you set from the **flash configuration** side so that **MB1 / BPMP / bootloader** pick the right **UPHY** preset (USB vs PCIe vs GBE lane maps), and related **feature** bits documented for your chip.

It is **not** the same thing as “a random `ioctl` at runtime”—it is **primarily decided when you build/flash** (or when you ship a known `.conf` + BCT set to the factory).

### Typical things ODMDATA (plus BCT / DT) helps steer

| Area | Idea (high level) |
|------|-------------------|
| **UPHY lane maps** | Which high-speed lanes are **USB3**, **PCIe**, **Ethernet (GBE)**, etc. |
| **PCIe roles** | Some presets interact with whether a controller is used as **root port** vs **endpoint** in a given design (exact mechanism is **SoC- and release-specific**—use NVIDIA’s PCIe endpoint topic for your module). |
| **Other boot knobs** | Platform-specific bits (watchdog, power, or strap-related options) appear in **official** docs as **bitfield** tables—do not guess from forum posts alone. |

For **Orin NX / Nano (T234)**, the adaptation guide expresses many UPHY choices as an **`ODMDATA="…"`** string in the **board `.conf`** (often **appended after** sourcing `p3767.conf.common`). See [UPHY lane configuration](Jetson-Module-Adaptation-Bring-Up-Orin-NX-Nano.md#uphy-lane-configuration) in the module adaptation note.

### How to **set** ODMDATA (production-style)

1. Work in **`Linux_for_Tegra/`** on the **host** that flashes the device.
2. Edit or extend your **board-specific** `*.conf` (NVIDIA pattern: set variables **after** `source ...conf.common` so you **override** defaults).
3. Set **`ODMDATA=`** to the **preset** from the guide for your carrier (HSIO / GBE strings on Orin are documented in the adaptation / flashing topics).
4. **Flash** with the supported script for your storage layout (`flash.sh`, `l4t_initrd_flash.sh`, etc.—see *Flashing support* in the developer guide).

Older posts sometimes mention passing a hex word via **`flash.sh`** flags for **older** modules (e.g. Xavier-era **PCIe endpoint** examples). Treat those as **hints**: the **supported** CLI and variable names change by **BSP version**—use **`flash.sh --help`** and the guide for **your** package.

### How to **inspect** ODM-related data after boot

Linux exposes **device-tree blobs** under **`/sys/firmware/devicetree/`**. NVIDIA and community posts often point to paths such as:

`/sys/firmware/devicetree/base/chosen/plugin-manager/odm-data/`

On a running system you can **discover** nodes (paths differ by release and boot chain):

```bash
find /sys/firmware/devicetree -iname '*odm*' 2>/dev/null | head
```

Properties are often **binary**; read with **`hexdump -C`** or **`od`** on the files inside those directories.

Use this to answer: “**What did the booted image think the ODM/plugin-manager view is?**” It does not replace **source control** of your **`.conf`** and **DT** in `Linux_for_Tegra/`.

---

## Three layers: pinmux vs `devmem` vs GPIO userspace

When you “make a pin GPIO” on Jetson, you usually touch **more than one layer**:

| Layer | What it controls | Persists? |
|-------|-------------------|-----------|
| **1. MB1 BCT pinmux (DTS)** | Whether a ball is **SFIO** (I2C, UART, …) or **GPIO**, pulls, etc. | **Yes** (after rebuild + reflash of BCT/related images) |
| **2. `devmem` / PADCTL** | **Hardware registers** that **mux** and **pad-configure** the pin | **No** if you only poke RAM-mapped registers from Linux—**lost on reset** unless firmware saved it (usually it did not) |
| **3. `libgpiod` / gpiochip** | **GPIO line** direction and level **once** the pin is already a **GPIO** in the pinmux | **N**/`A` at runtime; pinmux still wins on reboot |

**JetPack 6** direction: NVIDIA deprecates the old **GPIO sysfs** (`/sys/class/gpio`); use **`libgpiod`** on top of **`/dev/gpiochip*`** for **product** code.

---

## 1. `devmem` (direct MMIO)

**What it is:** A tiny utility (commonly **`busybox devmem`**) that **reads or writes a 32-bit word** at a **physical** (or bus-visible) **address** the kernel maps for you. On Jetson bring-up docs, it is used to **peek/poke PADCTL** and similar blocks while validating **pinmux** math from the **TRM**.

**When to use it**

- **Bring-up / debug**: confirm **base + offset** for a pin’s **PADCTL** register matches the **Orin TRM** and your spreadsheet.
- **Short experiments**: see if a **mux** change makes a **scope** or **logic analyzer** trace look right **before** you freeze the change in **BCT `.dtsi`**.

**Risks**

- You are **bypassing** the kernel’s normal driver model.
- Wrong addresses or values can **hang** the SoC, **glitch** power domains, or **damage** hardware if you fight enabled drivers.
- Changes are usually **volatile**—treat as **lab only** unless you mirror the same intent in **BCT** and reflash.

**Typical pattern** (from NVIDIA’s adaptation text):

```bash
sudo apt-get install -y busybox
sudo busybox devmem 0x02430080      # read
sudo busybox devmem 0x02430080 w 0x…  # write (syntax per busybox build)
```

**TRM:** [Jetson Orin SoC TRM](https://developer.nvidia.com/orin-series-soc-technical-reference-manual) — **Pinmux** / **PADCTL** chapters.

---

## 2. GPIO **sysfs** (`/sys/class/gpio`) — legacy

**What it was:** A **virtual filesystem** API under **`/sys/class/gpio/`**: **export** a line by **Linux GPIO number**, then set **direction** and **value** by writing to small text files.

**Status on JetPack 6**

- NVIDIA’s direction matches upstream Linux: **sysfs GPIO is deprecated** for new work.
- Old scripts and tutorials still show **`echo 396 > /sys/class/gpio/export`** style flows—they may **break** or **race** with **libgpiod**-aware drivers.

**When it still shows up**

- **Legacy** bring-up scripts, CI, or third-party libraries not yet ported.

**Production guidance:** plan **`libgpiod`** (or a kernel driver) instead of **sysfs**.

---

## 3. `libgpiod` — current standard

**What it is:** A **C library** and **CLI tools** for the **GPIO character device** API: **`/dev/gpiochipN`** (`GPIO_CDEV`). The kernel exposes **chips** and **lines** with stable **line names** where the DT provides them.

**Common CLI tools**

| Tool | Purpose |
|------|---------|
| **`gpiodetect`** | List **`gpiochip`** devices |
| **`gpioinfo`** | Lines, names, **used** / **unused**, **direction** |
| **`gpioget`** | Read a line |
| **`gpioset`** | Drive a line (often with **`--mode=wait`** for tests) |

**Why prefer it**

- **Atomic** and **race-resistant** compared to sysfs **export** games.
- Works with **line labels** from **device tree** (when present).
- Aligns with **mainline** Linux direction.

**Prerequisite:** the pin must already be **muxed as GPIO** in **MB1 BCT** (or a safe runtime equivalent you fully understand). **`gpioset`** does **not** replace **pinmux spreadsheet → `.dtsi`**.

**Docs:** [libgpiod](https://git.kernel.org/pub/scm/libs/libgpiod/libgpiod.git/about/) (kernel.org).

---

## Comparison (quick)

| Mechanism | You touch | Risk | Typical use |
|-----------|-----------|------|-------------|
| **`devmem`** | **SoC registers** (e.g. PADCTL) | **High** | TRM-aligned **debug**, prove an address, **temporary** mux experiments |
| **sysfs GPIO** | **Legacy** sysfs files | **Low** if it works | **Avoid** for new JetPack 6 designs |
| **`libgpiod`** | **`/dev/gpiochip*`** lines | **Low** (normal API) | **Apps**, **services**, **tests** once **pinmux** is correct |

---

## End-to-end mental model (JetPack 6, Orin-class)

1. **Product intent** — Pick **functions** per ball (UART, I2C, GPIO, CSI, PCIe, USB, …) in the **pinmux spreadsheet**; generate **`.dtsi`** for **MB1 BCT**; align **UPHY** choice via **`ODMDATA`** and related **DT** (see module adaptation + T23x BCT doc).
2. **Flash** — Board **`*.conf`** selects **BCT** fragments, **DTB**, and **`ODMDATA`** preset.
3. **Bring-up debug** — Use **`devmem`** only if you need **register-level** confirmation; document the **address** and **bit** meaning in your **engineering log**.
4. **Runtime GPIO** — Use **`libgpiod`** for **line** control in **userspace**; keep **pinmux** in **BCT**, not in **shell** `devmem` scripts, for **shipping** products.

---

## See also

- [Jetson-Module-Adaptation-Bring-Up-Orin-NX-Nano.md](Jetson-Module-Adaptation-Bring-Up-Orin-NX-Nano.md) — **UPHY**, **`ODMDATA`**, **PCIe**, **USB**, **flash**
- [T23x-Deployment.md](T23x-Deployment.md) — **MB1 BCT** DTS fragments (**ODM data for T234** appears in the BCT deployment guide)
- [Jetson Linux Developer Guide](https://docs.nvidia.com/jetson/) — **Flashing support**, **PCIe endpoint**, **GPIO** / **Jetson-IO** topics for your release
