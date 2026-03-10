# Lecture 21: Filesystems: ext4, btrfs, F2FS & overlayfs

## Filesystem Role and VFS

A filesystem organizes files into directories, provides persistence across power cycles, manages free space, and ensures metadata consistency after crashes.

### VFS (Virtual File System)

Linux VFS is an abstraction layer that presents a uniform API regardless of the underlying filesystem implementation.

Key data structures:

- `struct super_block`: per-mounted-filesystem state; points to root inode
- `struct inode`: per-file metadata (uid, gid, size, timestamps, block pointers); no filename
- `struct dentry`: name-to-inode cache entry; forms the directory tree in memory
- `struct file`: per-open-file state; current offset, flags; points to inode

Key operations table: `struct file_operations` — `open`, `read`, `write`, `mmap`, `ioctl`, `fsync`, `llseek`. Every filesystem registers its own implementation of these callbacks. `mmap` is critical for AI workloads: memory-mapped dataset files avoid read() syscalls entirely.

## ext4

ext4 is the default Linux filesystem; backward-compatible with ext2/ext3.

### Key Features

- **Extent-based allocation**: replaces indirect block maps; one extent = (logical block, physical block, length); reduces metadata for large contiguous files
- **64-bit block addresses**: supports volumes up to 1 EB
- **Delayed allocation** (`delalloc`): batch block allocation at writeback time; improves spatial locality; `nodelalloc` disables it
- **dir_index** (htree): large directories stored as hash B-tree; O(log n) lookup vs O(n) linear scan

### Journal Modes

| Mode | What is journaled | Data safety | Performance |
|---|---|---|---|
| `data=ordered` (default) | Metadata only; data written before commit | Good | Fast |
| `data=journal` | Metadata + data | Best | Slowest |
| `data=writeback` | Metadata only; data order not guaranteed | Weakest | Fastest |

Mount with `mount -o data=ordered /dev/mmcblk0p1 /mnt`. For Jetson rootfs, `data=ordered` is the standard.

Default journal size: 128 MB (tunable via `tune2fs -J size=N`). Journal is a circular log; on crash, uncommitted transactions are discarded; committed but not checkpointed are replayed.

## btrfs

btrfs is a Copy-on-Write B-tree filesystem with features designed for modern storage and system management.

### Core Features

- **Copy-on-Write (CoW)**: writes never overwrite existing data in place; new data is written to free space, then the B-tree root pointer is atomically updated
- **Snapshots**: O(1) creation; a snapshot is simply a new B-tree root pointing to the same leaf nodes; used for A/B rootfs in OTA update strategies
- **Subvolumes**: independent filesystem trees within the same btrfs pool; can be mounted separately or snapshotted individually
- **Checksums**: CRC32c (default), xxHash, SHA256, or Blake2 on both data and metadata; detects silent bit rot
- **RAID modes**: RAID 0, 1, 10, 5, 6 across multiple devices
- **Transparent compression**: zstd (best ratio), lzo (fastest), zlib; per-file or per-subvolume
- **send/receive**: compute a delta between two snapshots and stream it to another system; enables incremental OTA updates

### A/B Rootfs with btrfs Snapshots

```bash
# Create read-only snapshot before OTA
btrfs subvolume snapshot -r /rootfs /.snapshots/$(date +%Y%m%d)

# After update, create new snapshot from updated rootfs
btrfs subvolume snapshot /rootfs_new /.snapshots/new

# Rollback: delete new rootfs, restore from snapshot
```

`btrfs scrub start /`: verify all data blocks against stored checksums; background operation; critical for long-running edge AI devices where silent corruption is a concern.

## F2FS (Flash-Friendly File System)

F2FS is designed for NAND flash storage: eMMC, UFS, and NVMe SSDs. Developed by Samsung; merged into Linux 3.8.

### Design Principles

- **Log-structured with node/data separation**: node area (inodes and index) and data area are logged separately; reduces fragmentation from mixed updates
- **Adaptive logging**: switches between normal logging (high utilization) and threaded logging (low utilization) to balance write amplification and fragmentation
- **Reduced write amplification**: flash-aware allocation avoids partial block updates; aligns writes to flash erase block size
- **Optimized `fsync()` latency**: important for database workloads (SQLite on Android); uses a roll-forward recovery mechanism to avoid full checkpoint on every fsync

Use cases: Android (since Android 9 default on eMMC/UFS), Chromebooks, embedded AI devices with eMMC storage.

## overlayfs

overlayfs overlays two directory trees into a unified view:

- **lower**: read-only base layer (one or more stacked layers)
- **upper**: writable layer; receives all modifications
- **workdir**: temporary directory on the same filesystem as `upper`; used for atomic rename operations

On first write to a file from `lower`, the file is copied up to `upper` (copy-on-write). Subsequent writes go directly to `upper`.

### Mount Syntax

```bash
mount -t overlay overlay \
  -o lowerdir=/image/layer2:/image/layer1,\
     upperdir=/container/rw,\
     workdir=/container/work \
  /container/merged
```

### Use Cases

- **Docker/OCI containers**: image layers form the `lower` stack; the container's writable layer is `upper`; the container sees `/merged` as its rootfs
- **Jetson OTA**: new rootfs image as `lower`; persistent user data in `upper`; avoids a full rootfs copy for configuration
- **Read-only rootfs with writable overlay**: boot from read-only squashfs; mount overlayfs with tmpfs as `upper`; writable rootfs in RAM without modifying flash

## tmpfs: Filesystem in RAM

`tmpfs` uses anonymous pages (RAM + swap) for storage; no disk I/O for reads or writes.

```bash
mount -t tmpfs -o size=1G tmpfs /dev/shm
```

- `/dev/shm` and `/run` are tmpfs by default on systemd systems
- `shm_open()` / `mmap(MAP_SHARED)` use tmpfs for POSIX shared memory
- openpilot `cereal` msgq allocates shared memory segments via `shm_open()` on `/dev/shm`; all IPC between processes (modeld, plannerd, controlsd) traverses these RAM-backed segments

## TRIM and Flash Longevity

`fstrim` notifies the SSD of freed block ranges so the controller can reclaim them during idle time.

- `discard` mount option: issue TRIM inline on every `unlink()` (higher latency per delete)
- `systemd-fstrim.timer`: weekly `fstrim` sweep (preferred; batches TRIMs)
- Without TRIM, the FTL does not know which logical blocks are free; write amplification increases as the drive ages
- Critical for embedded AI devices with eMMC (dashcams, edge inference boxes) that write continuously and cannot be taken offline for maintenance

## Summary

| Filesystem | Journaling | CoW | Best for | Key limitation |
|---|---|---|---|---|
| ext4 | Yes (ordered/journal/writeback) | No | General-purpose Linux rootfs | No snapshot support |
| btrfs | No (CoW replaces journal) | Yes | A/B OTA, snapshot-based rollback | Higher CPU overhead |
| F2FS | Checkpointing | No | eMMC/UFS embedded devices | Not ideal for HDDs |
| overlayfs | Inherits from upper layer | On first write | Container rootfs, OTA overlay | upper/lower must differ |
| tmpfs | None (RAM) | No | IPC shared memory, /tmp | Lost on reboot/OOM |
| ext4 + F2FS | Yes | No | Mixed: rootfs (ext4) + data (F2FS) | Separate partitions needed |

## AI Hardware Connection

- btrfs snapshots provide O(1) A/B rootfs switching in openpilot Agnos and Jetson OTA update pipelines; on failed boot, the bootloader activates the previous snapshot without data movement
- F2FS on eMMC significantly reduces write amplification in embedded AI edge devices (dashcams, robotics controllers) that perform continuous camera recording
- overlayfs enables containerized TensorRT inference deployments where the base image layer is read-only and immutable while the container adds only runtime state in the upper layer
- tmpfs and `shm_open()` underpin openpilot cereal msgq IPC; all model outputs, trajectory plans, and control commands between processes traverse RAM-backed shared memory segments
- ext4 `data=ordered` mode is the standard for Jetson rootfs partitions; it provides the strongest crash consistency guarantee without the overhead of full data journaling
- `systemd-fstrim.timer` is a mandatory configuration item for any long-running eMMC-based AI edge device; without it, write amplification degrades throughput and reduces flash lifespan
