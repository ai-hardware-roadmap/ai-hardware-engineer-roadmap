# Project: 1080p → 4K Wireless Video on FPGA

**Parent:** [Phase 4 Track A — Xilinx FPGA](../1.%20Xilinx%20FPGA%20Development/Guide.md)

**Layers touched:** L3 (runtime/driver), L4 (firmware), L5 (hardware architecture), L6 (RTL/HLS)

**Prerequisites:** Track A §1–§4 (Vivado, Zynq, Advanced FPGA, HLS), Phase 2 (Embedded Linux, FreeRTOS).

---

## Overview

Two-phase project that builds a wireless video link on FPGA — starting with a rapid 1080p proof-of-concept using SDR + Raspberry Pi, then evolving into a fully integrated 4K system on Zynq UltraScale+ with custom PHY, bare-metal firmware, and an ASIC transition plan.

This project exercises nearly every Track A skill: Vivado IP integration, Zynq PS/PL co-design, HLS for video processing, Linux and bare-metal firmware, and runtime/driver development for DMA and streaming.

---

## Plan 1: 1080p Wireless Video Proof-of-Concept

**Timeline:** 2–3 weeks

**Goal:** Build a functional 1080p60 wireless video link using SDR (antsdr + openwifi) with external Raspberry Pi for H.265 encode/decode.

### Accelerated Approach

| Original step | Accelerated method |
|---------------|--------------------|
| Acquire hardware and set up openwifi | **Day 1**: Use pre-flashed openwifi SD card images (available for antsdr). Skip building from source. |
| Validate openwifi link | **Day 1–2**: Use iperf pre-installed on openwifi image; test link in minutes. |
| Set up Raspberry Pi video pipeline | **Day 1–2**: Use a ready-made GStreamer script. Parallel work with openwifi setup. |
| Custom forwarding script | **Day 2–3**: Use `socat` to forward UDP packets between Ethernet and `wlan0` — no coding needed. |
| Tune latency | **Day 3**: Use default settings; measure and accept. No extensive optimization for prototype. |
| Documentation | Continuous, final report by end of week 3. |

### Hardware

- 2x antsdr boards (or MicroPhase) with antennas and power supplies
- 2x Raspberry Pi 4 (or Pi 5) with camera and HDMI
- 1x Camera Module v2
- Ethernet cables, microSD cards

### Parallel Work Streams

**Stream A — SDR Link:**
- Flash pre-built openwifi images (from openwifi-hw-img repo) onto SD cards.
- Power up boards; they boot into Linux with openwifi loaded.
- Use provided scripts to set up ad-hoc network.
- Verify with `iperf -s` on one and `iperf -c` on the other — within 2 hours.

**Stream B — Raspberry Pi Video (TX):**
- Install Raspberry Pi OS on both Pis.
- On TX Pi: connect camera, install GStreamer (pre-compiled).
- Run pipeline:
  ```bash
  gst-launch-1.0 v4l2src device=/dev/video0 \
    ! video/x-h264,width=1920,height=1080,framerate=60/1 \
    ! h264parse ! rtph264pay \
    ! udpsink host=<sdr_tx_ip> port=5000
  ```

**Stream C — Forwarding:**
- On TX SDR: enable IP forwarding and route traffic from Ethernet interface to `wlan0` with `iptables` — no custom code.
- On RX SDR: similar reverse path.

**Stream D — Display (RX):**
```bash
gst-launch-1.0 udpsrc port=5000 \
  ! application/x-rtp ! rtph264depay ! h264parse \
  ! avdec_h264 ! autovideosink
```

### Timeline

| Week | Activity | Parallel tracks |
|------|----------|-----------------|
| **1** | Order hardware (day 1). Receive (day 3). Flash images, bring up SDR link (2 days). Set up Pis (1 day). | A, B, C run concurrently |
| **2** | Integrate: Route UDP from Pi to SDR and over wireless. Test video stream. | IP routing + GStreamer pipelines |
| **3** | Validate 1080p60 at short range. Measure latency. Document. | — |

### Success Criteria

- Live 1080p60 video stream from camera to display via wireless SDR link.
- End-to-end latency < 150 ms (acceptable for proof-of-concept).
- All steps documented for reproducibility.

---

## Plan 2: Integrated 4K Wireless Chip Prototype

**Timeline:** 3.5 months (14 weeks)

**Goal:** Build a fully integrated 4Kp60 wireless transmitter/receiver on Zynq UltraScale+ EV (ZCU106) with bare-metal control and low-latency custom PHY.

### Accelerated Approach

| Original step | Accelerated method |
|---------------|--------------------|
| Set up Vivado, VCU bare-metal | Use Xilinx Vitis pre-built examples for VCU on ZCU106. Start with Linux to validate VCU, then port to bare-metal. |
| MIPI I/O IP development | Use **Xilinx MIPI D-PHY RX/TX IP** (available in Vivado). No custom PHY development. |
| Wireless PHY design | Start from **openwifi PHY** already ported to Zynq UltraScale+. Modify only MAC for TDMA. |
| RF front-end integration | Use **FMCOMMS5** with AD9361 — existing Linux drivers and bare-metal examples exist. |
| Bare-metal scheduling | Use **FreeRTOS** as stepping stone — faster than bare-metal scheduler from scratch. |

### Hardware

- ZCU106 evaluation kit (includes ZU7EV)
- FMCOMMS5 (or ADRV-CRR) FMC card
- MIPI DSI camera module with FMC adapter
- HDMI display (via ZCU106 onboard HDMI TX)

### Phase 1 — Platform & VCU Validation (4 weeks, parallel)

| Team | Work |
|------|------|
| **A** | Set up Vivado/Vitis; build Linux image with VCU (use Xilinx VCU TRD). Validate 4Kp60 encode/decode with sample file. |
| **B** | Set up openwifi on ZCU106 + FMCOMMS5 (use pre-built openwifi for ZCU106). Verify link with iperf. |
| **C** | Develop bare-metal hello world on ZCU106; bring up UART, DDR, clocks. |

### Phase 2 — MIPI & Wireless Integration (4 weeks, parallel)

| Team | Work |
|------|------|
| **A** | Integrate MIPI D-PHY RX IP in PL, connect to VCU input. Capture live camera video under Linux, verify VCU encodes it. |
| **B** | Modify openwifi PHY for TDMA (remove CSMA/CA). Implement simple TDMA controller in PL/PS. Test with two boards. |
| **C** | Port VCU driver to FreeRTOS (using Xilinx VCU library). Get simple encode/decode loop running without Linux. |

### Phase 3 — System Integration & Bare-Metal (4 weeks)

- Merge all components into single design: MIPI → VCU → wireless packetizer → PHY → RF.
- Use FreeRTOS to manage data flow; implement TDMA slot scheduling.
- Validate full 4Kp60 wireless link between two ZCU106 boards (one TX, one RX).
- Measure latency (use GPIO toggles).
- Transition from FreeRTOS to minimal bare-metal (optional — FreeRTOS is acceptable for ASIC firmware).

### Phase 4 — Documentation & ASIC Roadmap (2 weeks)

- Document all IP blocks, interfaces, and firmware.
- Identify components to be hardened for custom ASIC.

### Timeline Summary

| Phase | Duration | Key deliverables |
|-------|----------|------------------|
| 1 — Platform & VCU | 4 weeks | Linux with VCU working, openwifi link, bare-metal base |
| 2 — MIPI & Wireless | 4 weeks | Live camera → VCU encode, TDMA PHY tested |
| 3 — Integration | 4 weeks | Full 4K wireless link, latency measured |
| 4 — Documentation | 2 weeks | Final report, ASIC plan |

### Risk & Mitigation

| Risk | Mitigation |
|------|------------|
| VCU bare-metal support missing | Use FreeRTOS as target; acceptable for ASIC firmware and faster to develop |
| MIPI I/O not working | Use Xilinx MIPI IP (validated). Include loopback test early |
| Wireless PHY complexity | Start with openwifi (already works on ZCU106); only modify MAC |
| TDMA synchronization | Use simple beacon-based synchronization; start with one-way video only |

### Path to ASIC

- The prototype produces synthesizable Verilog for MIPI I/O, wireless PHY/MAC, and packetizer.
- VCU will be replaced with a licensed H.265 IP or custom design.
- Firmware (FreeRTOS or bare-metal) ports to the ASIC's embedded processor.
- RF front-end integration follows the same interface as AD9361 (or direct RF if using integrated RF ASIC).

---

## Skills Exercised (Track A Modules)

| Track A Module | How this project uses it |
|---------------|------------------------|
| §1 Vivado | IP Integrator block design, bitstream generation, ILA debugging |
| §2 Zynq MPSoC | PS/PL co-design, VCU integration, AXI interconnect, Linux + bare-metal |
| §3 Advanced FPGA | CDC for multi-clock video/RF domains, floorplanning around VCU/PHY |
| §4 HLS | Video preprocessing (color convert, scale), packetizer/depacketizer |
| §5 Runtime & Driver | DMA transfers, Linux V4L2 drivers, bare-metal register access, GStreamer integration |
