# Lecture 22: Embedded Storage: eMMC, UFS, NVMe & OTA Partitioning

## Storage Hierarchy for Embedded AI Devices

Three storage technologies appear in AI edge hardware, chosen by cost, form factor, and throughput requirements:

| Technology | Interface | Seq Read | Random IOPS | Form Factor |
|---|---|---|---|---|
| eMMC 5.1 | Parallel (8-bit HS400) | ~400 MB/s | ~15K | Soldered BGA |
| UFS 3.1 | Serial MIPI M-PHY | ~2100 MB/s | ~70K | Soldered / socket |
| UFS 4.0 | Serial MIPI M-PHY | ~4200 MB/s | ~130K | Soldered / socket |
| NVMe Gen4 x4 | PCIe | ~7000 MB/s | ~1M | M.2 / BGA |

## eMMC (embedded MultiMediaCard)

eMMC implements the JEDEC JESD84 standard. The flash controller, wear leveling, ECC, and bad block management are all integrated inside the package.

### Internal Partition Structure

Every eMMC device exposes fixed partitions:

- **BOOT0 / BOOT1**: two independent boot areas, each up to 4 MB; write-protected after provisioning; hold bootloader (U-Boot SPL, UEFI)
- **RPMB (Replay Protected Memory Block)**: 4 MB authenticated storage; read/write protected by HMAC-SHA256 using a device-unique key provisioned at manufacturing
- **User Data Area (UDA)**: the main storage region; GPT-partitioned by the OS

### RPMB Security Properties

RPMB prevents rollback attacks on firmware. The secure world (OP-TEE, ARM TrustZone) increments a write counter on each write; the eMMC controller rejects any write that does not carry a valid HMAC and a counter value ≥ current. Used in Jetson secure boot to store:

- Firmware version counter (anti-rollback)
- Encryption key material for full-disk encryption

### eMMC Reliability

- Consumer grade: 3K–10K P/E cycles per cell (MLC); 1K–3K (TLC)
- Enterprise grade (JEDEC JESD84-B51): 16 PBW (petabytes written) rated
- Over-provisioning: 10–28% of raw capacity reserved for wear leveling and bad block replacement

## UFS (Universal Flash Storage)

UFS uses a serial, full-duplex MIPI M-PHY physical layer with a SCSI-based command set (UFS Transport Protocol). Key advantages over eMMC:

- **Command queuing**: up to 32 commands in flight (vs eMMC single-command); critical for random I/O latency
- **Full duplex**: simultaneous read and write; improves mixed workload throughput
- **Lower CPU overhead**: command processing offloaded to UFS device controller

UFS uses the same logical partition structure as eMMC (BOOT, RPMB, UDA). It is the standard on Qualcomm Snapdragon platforms. The comma 3X (openpilot primary hardware) uses a Snapdragon 845 with UFS storage for camera recording and OS.

## NVMe on Embedded Platforms

Jetson Orin exposes an M.2 Key M slot connected to PCIe Gen4 x4 (~7 GB/s):

- Supports standard NVMe 2280 and 2230 form-factor SSDs
- Used when large-scale dataset logging, replay, or high-frequency sensor recording is needed
- `blk-mq` with per-CPU NVMe queues; combine with `io_uring` + `O_DIRECT` for maximum throughput
- `nvme list` to enumerate devices; `nvme smart-log /dev/nvme0` for health and wear indicators

## OTA Partition Layouts

Over-the-air update strategy determines recovery behavior and downtime on failure.

### A/B Seamless Update

Two full system partition sets (slot A and slot B). The inactive slot receives the update while the active slot runs normally.

```
/dev/mmcblk0p1  boot_a      (active)
/dev/mmcblk0p2  boot_b      (inactive → receives new image)
/dev/mmcblk0p3  system_a    (active rootfs)
/dev/mmcblk0p4  system_b    (inactive → receives new rootfs)
/dev/mmcblk0p5  userdata    (persistent, not updated)
```

On reboot: bootloader marks slot B as active, tries to boot. If boot count exceeds threshold (typically 3) without a successful boot marker, bootloader reverts to slot A. Used in: Android A/B, openpilot Agnos, Jetson UEFI capsule update.

### Recovery Partition Update

Single active partition + a small recovery image. Update process: download new image → reboot into recovery → flash system partition → reboot into new system. No rollback without a backup image. Used in older Android devices and simple embedded systems.

### OSTree: Git-Like Atomic Updates

OSTree maintains a content-addressed object store of filesystem trees, analogous to git. Deployed updates are hard-linked from the object store; atomic switchover via a symlink update. Used in Automotive Grade Linux (AGL) and automotive ECU Linux platforms. Compatible with ext4 (hard links) and btrfs.

## Partition Tools and Kernel Interfaces

- `parted` / `sgdisk`: create and modify GPT partition tables
- `partprobe /dev/mmcblk0`: re-read partition table without reboot
- `/proc/partitions`: kernel's view of all block devices and partitions
- `/sys/block/mmcblk0/mmcblk0p1/size`: partition size in 512-byte sectors
- `/dev/mmcblk0p1`, `/dev/nvme0n1p1`: device nodes for partition access

## Wear Leveling and Write Amplification

Flash storage degrades with Program/Erase (P/E) cycles. The Flash Translation Layer (FTL) manages longevity:

- **Dynamic wear leveling**: preferentially writes to least-worn blocks; effective for frequently updated data
- **Static wear leveling**: periodically migrates cold data from worn blocks to fresh ones; prevents hot/cold imbalance
- **Write Amplification Factor (WAF)**: physical writes / logical writes; WAF of 1.0 is ideal; random small writes to consumer SSDs can produce WAF of 10–50 without filesystem cooperation
- Minimize WAF with: sequential writes, large block sizes, F2FS or btrfs, and proper TRIM configuration

## Storage Diagnostics

```bash
iostat -x 1          # per-device: util%, await (ms), r/s, w/s, rMB/s, wMB/s
blktrace -d /dev/mmcblk0 -o trace    # per-request block I/O events
blkparse trace.blktrace.0            # parse and display timing breakdown
```

`await` in `iostat` output is the average I/O service time including queue wait. A rising `await` under camera recording load indicates the storage is saturated. `blktrace` identifies which process is responsible for latency spikes.

## Summary

| Storage type | Interface | Sequential read | Random IOPS | Typical use in AI hardware |
|---|---|---|---|---|
| eMMC 5.1 | 8-bit parallel HS400 | ~400 MB/s | ~15K | Jetson Nano, low-cost edge devices |
| UFS 3.1 | MIPI M-PHY serial | ~2100 MB/s | ~70K | comma 3X (Snapdragon), mid-range SoC |
| UFS 4.0 | MIPI M-PHY serial | ~4200 MB/s | ~130K | Flagship mobile AI SoC |
| NVMe Gen4 x4 | PCIe Gen4 | ~7000 MB/s | ~1M | Jetson Orin (M.2 slot), dataset logging |
| NVMe Gen3 x4 | PCIe Gen3 | ~3500 MB/s | ~500K | Workstation AI dev, cloud training node |

## AI Hardware Connection

- A/B OTA partition layout is the foundation of openpilot Agnos update strategy; the active slot continues running while the new firmware is written to the inactive slot, with automatic rollback on failed boot
- RPMB authenticated storage is how Jetson secure boot prevents firmware downgrade attacks; the TrustZone secure world increments the anti-rollback counter on each successful firmware update
- UFS on the Snapdragon 845 (comma 3X) provides the random IOPS needed to sustain simultaneous recording from three cameras while running inference
- NVMe on Jetson Orin enables large-scale on-device dataset logging for continuous learning pipelines; PCIe P2P allows the logged data to be pre-processed directly in GPU memory
- F2FS on eMMC is the correct filesystem choice for long-running edge AI dashcam devices; it minimizes write amplification and extends eMMC lifespan compared to ext4
- `iostat -x 1` is the first diagnostic tool to run when a camera recording pipeline drops frames; `await` rising above the camera frame period indicates a storage bottleneck
