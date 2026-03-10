# Lecture 8: Multi-Core Scheduling, CPU Affinity & isolcpus

## SMP Scheduler Architecture

Linux SMP scheduler uses **per-CPU runqueues** (`struct rq`) to reduce contention:

- `load_balance()` triggered by: idle CPU detection, periodic `rebalance_domains()`, and explicit migration requests
- Load metric: sum of task weights (CFS nice-weighted) on each runqueue
- `migration/N` kernel threads execute the actual task moves on behalf of the scheduler
- Goal: equalize load across CPUs while respecting topology constraints (prefer same-core > same-package > same-NUMA node)

## CPU Topology Hierarchy

```
Physical Package (Socket)
  └── DIE
        └── MC (physical core)
              └── SMT Thread (hyperthreading — 2 logical CPUs per core)
```

Linux models this as a `struct sched_domain` hierarchy. Imbalance threshold and migration cost increase at higher domain levels; the scheduler is reluctant to migrate across NUMA boundaries.

### Topology Inspection

```bash
lscpu                                                     # summary + per-CPU table
lscpu -e                                                  # extended per-CPU table
cat /sys/devices/system/cpu/cpu0/topology/core_id         # physical core ID
cat /sys/devices/system/cpu/cpu0/topology/physical_package_id  # socket ID
cat /sys/devices/system/cpu/cpu0/topology/thread_siblings # sibling SMT bitmask
cat /sys/devices/system/cpu/cpu0/topology/core_cpus_list  # all logical CPUs on this core
```

SMT siblings share L1/L2 caches and execution units. Inference workloads should pin to physical cores (one thread per core), not to both siblings of an SMT pair, to avoid resource contention.

## CPU Affinity

Affinity mask: bitmask specifying which CPUs a task is allowed to execute on.

```c
// System call interface
cpu_set_t mask;
CPU_ZERO(&mask);
CPU_SET(2, &mask); CPU_SET(3, &mask);
sched_setaffinity(pid, sizeof(mask), &mask);
sched_getaffinity(pid, sizeof(mask), &mask);
```

```bash
taskset -c 2,3 ./inference_app      # launch process with affinity to CPUs 2 and 3
taskset -cp 2,3 <pid>               # apply affinity to an already-running process
cat /proc/<pid>/status | grep Cpus_allowed
```

Benefits of affinity pinning:
- Eliminates scheduler-induced migrations; preserves L1/L2 cache warmth
- Avoids TLB flush cost on migration (~thousands of cycles on x86)
- Reduces latency variance; makes timing more predictable

| Mechanism | Kernel Interface | Granularity | Persistence | Tool |
|---|---|---|---|---|
| CPU affinity | `sched_setaffinity` | Per-task | Until process exits | `taskset` |
| `isolcpus` | Boot parameter | Per-CPU | Boot-time | kernel cmdline |
| cpuset cgroup | `/sys/fs/cgroup/cpuset` | Per-cgroup | Until reconfigured | `cgset`, k8s |
| `numactl` | `numactl --cpunodebind` | Per-NUMA node | Per-invocation | `numactl` |
| Intel CAT | `/sys/fs/resctrl` | Per-LLC-way | Until reconfigured | `pqos`, `resctrl` |

## isolcpus — Removing CPUs from the General Scheduler

`isolcpus=` is a kernel boot parameter. CPUs listed are removed from the general scheduling pool permanently at boot. No task is placed on an isolated CPU unless explicitly assigned via `taskset` or `sched_setaffinity`.

Complementary parameters for full isolation:

```
isolcpus=2,3,4,5 nohz_full=2,3,4,5 rcu_nocbs=2,3,4,5 irqaffinity=0,1
```

| Parameter | Effect |
|---|---|
| `isolcpus=N` | Removes CPU N from general scheduler pool |
| `nohz_full=N` | Disables periodic scheduler tick on CPU N (tickless) |
| `rcu_nocbs=N` | Offloads RCU callbacks off CPU N to `rcuoc` kthreads |
| `irqaffinity=0,1` | Routes all hardware IRQs to CPUs 0 and 1 only |

Combined effect: OS jitter reduced from ~200µs worst-case to <10µs on isolated cores. After boot, verify with `cyclictest` and confirm no IRQs are delivered to isolated CPUs via `cat /proc/interrupts`.

`tuna`: command-line tool that wraps `isolcpus` and IRQ affinity management for runtime CPU shielding configuration.

## CPU Frequency Scaling

| Governor | Behavior | Use Case |
|---|---|---|
| `performance` | Always at maximum frequency | Deterministic RT / inference latency |
| `powersave` | Always at minimum frequency | Battery-constrained idle systems |
| `schedutil` | Tracks CFS utilization signal | General throughput workloads |
| `ondemand` | Ramps on load, scales down on idle | Legacy desktop |

```bash
# Set performance governor on all CPUs
echo performance > /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor
# Or via cpupower
cpupower frequency-set -g performance
```

Variable frequency causes timing jitter; frequency transitions add up to 200µs of latency. Always use `performance` governor on RT and inference cores.

## cpuset Cgroup Controller

Assigns a process group to a CPU and memory-node subset at runtime without kernel reboot.

```bash
mkdir /sys/fs/cgroup/cpuset/inference
echo "4-7" > /sys/fs/cgroup/cpuset/inference/cpuset.cpus
echo "0"   > /sys/fs/cgroup/cpuset/inference/cpuset.mems
echo <pid> > /sys/fs/cgroup/cpuset/inference/cgroup.procs
```

Kubernetes uses `cpu_manager_policy=static` to allocate exclusive CPUs to **Guaranteed QoS** pods via cpuset internally. Pair with `topologyManagerPolicy=single-numa-node` to align CPU and GPU PCIe topology for GPU pods.

## Cache Topology and Intel CAT

### Cache Sharing

- L1 (32–64 KB), L2 (256 KB–1 MB): private per physical core
- L3 / LLC (8–64 MB+): shared across all cores in a package
- SMT siblings share L1 + L2 + execution units; avoid co-locating competing workloads on same physical core

```bash
perf stat -e cache-misses,cache-references ./inference    # measure LLC miss rate
```

### Intel Cache Allocation Technology (CAT / RDT)

Partitions LLC ways between workloads using Capacity Bitmasks (CBM). Prevents co-located OS daemons from evicting hot model weights.

```bash
mount -t resctrl resctrl /sys/fs/resctrl
mkdir /sys/fs/resctrl/inference
# Allocate LLC ways 0–3 (4 ways) exclusively to inference group
echo "L3:0=0x000f" > /sys/fs/resctrl/inference/schemata
echo <pid> > /sys/fs/resctrl/inference/tasks
```

Management tool: `pqos` (Intel RDT OSS tools). Also supports Memory Bandwidth Allocation (MBA) to limit DRAM bandwidth consumed by background workloads.

## NUMA Affinity

```bash
# Pin process to socket 0 CPUs + socket 0 memory
numactl --cpunodebind=0 --membind=0 ./inference

# Show CPU <-> GPU PCIe topology
nvidia-smi topo -m

# Show per-process NUMA access stats
numastat -p <pid>

# Show NUMA hit/miss counters
numastat
```

AutoNUMA (`/proc/sys/kernel/numa_balancing`): disable on latency-sensitive inference nodes. Automatic page migration causes TLB shootdown IPIs that add jitter spikes.

## Summary

| Mechanism | Kernel/User? | Granularity | Persistence | Tool |
|---|---|---|---|---|
| `sched_setaffinity` | Kernel syscall | Per-task | Process lifetime | `taskset` |
| `isolcpus` | Kernel boot param | Per-CPU | Boot-time | kernel cmdline |
| `nohz_full` | Kernel boot param | Per-CPU | Boot-time | kernel cmdline |
| `rcu_nocbs` | Kernel boot param | Per-CPU | Boot-time | kernel cmdline |
| cpuset cgroup | Kernel cgroup | Per-cgroup | Dynamic | `cgset`, kubectl |
| `cpufreq performance` | Kernel driver | Per-CPU | Dynamic | `cpupower` |
| Intel CAT | Kernel resctrl | Per-LLC-way | Dynamic | `pqos` |
| `numactl` | Userspace wrapper | Per-NUMA node | Per-invocation | `numactl` |

## AI Hardware Connection

- `isolcpus=4-11 nohz_full=4-11 rcu_nocbs=4-11` on Jetson Orin dedicates 8 ARM cores exclusively to AI inference threads; the OS and sensor drivers run on cores 0–3, preventing OS jitter from entering the inference latency budget
- Kubernetes `cpu_manager_policy=static` uses cpuset cgroups to give TensorRT inference pods exclusive physical CPU cores, eliminating noisy-neighbor scheduler interference in multi-tenant inference clusters
- CPU affinity pinning for ROS2 real-time callback groups ensures deterministic execution of LiDAR processing and motion control nodes; scheduler migration would invalidate WCET measurements
- NUMA-aware memory binding (`numactl -m 0`) reduces first-inference latency on multi-socket servers where the GPU PCIe root port attaches to socket 0; model weights in socket-1 memory incur cross-NUMA fetch overhead on every forward pass
- Intel CAT partitions LLC so OS daemons cannot evict hot model layer weights during inference; without CAT, a `kworker` burst can flush 30–50% of LLC, causing a spike of LLC-miss latency at the start of the next forward pass
- `cpufreq performance` governor is non-negotiable on AV edge compute: frequency ramp-up delay from a low-power C-state can add 100–200µs to the first GPU kernel launch after an idle period
