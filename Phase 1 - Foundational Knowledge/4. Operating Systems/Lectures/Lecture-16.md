# Lecture 16: NUMA Topology & HPC Memory Optimization

## NUMA Architecture

NUMA (Non-Uniform Memory Access) is the memory topology of multi-socket servers. Each CPU socket (NUMA node) has a directly attached DRAM bank accessible at local latency and full bandwidth. Accessing DRAM attached to a different socket requires traversing the socket interconnect (Intel QPI/UPI, AMD Infinity Fabric, IBM X-Bus), incurring additional latency and reduced bandwidth.

| Access type | Latency | Bandwidth (DDR5 2-socket Xeon) |
|-------------|---------|-------------------------------|
| Local DRAM | ~80 ns | ~200 GB/s per socket |
| Remote DRAM (1 QPI hop) | ~150–200 ns | ~100 GB/s |
| Remote DRAM (2 hops, 4-socket) | ~250+ ns | ~60 GB/s |

A process running on socket 0 that accesses data allocated on socket 1 pays the remote penalty on every cache miss — 2× to 3× the latency and half the bandwidth of local access.

### Topology Discovery

```bash
numactl --hardware       # nodes, CPUs per node, memory per node, distance matrix
lstopo                   # graphical topology: sockets, cores, L3 cache, NUMA nodes, PCIe devices
numastat                 # per-node allocation hit/miss counters (system-wide)
cat /sys/devices/system/node/node0/distance   # raw NUMA distance factors
```

Distance matrix: local access is 10 (normalized); remote 1-hop typically 20–40; 2-hop 60–80.

---

## Linux NUMA Memory Policies

### Default: First-Touch

The kernel allocates a page on the NUMA node of the CPU that first faults (accesses) it. This is efficient when the initializing thread is the consuming thread. It becomes a problem when a main thread on node 0 initializes a data structure later consumed exclusively by threads on node 1.

Critical pattern for AI workloads:
```c
/* Wrong: main thread (node 0) initializes, worker (node 1) consumes */
float *weights = malloc(model_size);
memset(weights, 0, model_size);   /* allocated on node 0 */

/* Correct: initialize on the thread that will use the data */
/* Pin worker thread to node 1, then fault the pages */
numa_run_on_node(1);
numa_set_membind(node1_mask);
float *weights = malloc(model_size);
memset(weights, 0, model_size);   /* allocated on node 1 */
```

### Memory Policy Types

| Policy | Mode constant | Behavior |
|--------|--------------|----------|
| Default (first-touch) | `MPOL_DEFAULT` | Inherit from parent; local node preferred |
| Bind | `MPOL_BIND` | Strictly allocate only from named nodes; fail if full |
| Preferred | `MPOL_PREFERRED` | Prefer named node; fall back to others if needed |
| Interleave | `MPOL_INTERLEAVE` | Round-robin pages across named nodes |

### System Calls

```c
/* Per-process policy */
set_mempolicy(MPOL_INTERLEAVE, &all_nodes_mask, max_node);

/* Per-VMA policy (overrides process policy for this address range) */
mbind(addr, len, MPOL_BIND, &node0_mask, max_node, MPOL_MF_MOVE);
```

`MPOL_MF_MOVE`: migrate existing pages in the VMA to the target node immediately.

---

## numactl: Command-Line Policy Control

```bash
# Bind process to CPUs and memory of node 0 (GPU on node 0 socket)
numactl --cpunodebind=0 --membind=0 ./inference_server

# Interleave allocations across all nodes (bandwidth-bound all-reduce)
numactl --interleave=all ./allreduce_benchmark

# Prefer node 1 but allow fallback (mixed workload)
numactl --preferred=1 ./data_loader

# Interleave across nodes 0 and 1 only
numactl --interleave=0,1 ./matmul_benchmark
```

---

## libnuma API (Programmatic Control)

```c
#include <numa.h>

int node = numa_node_of_cpu(sched_getcpu());   /* which node am I on? */
void *p = numa_alloc_onnode(size, node);       /* allocate on specific node */
numa_free(p, size);                            /* release */

numa_bind(nodemask);                           /* bind calling thread's CPU+memory */
numa_set_interleave_mask(&all_nodes);          /* interleave for future allocs */
numa_set_membind(&node_mask);                  /* memory-only bind */
```

---

## AutoNUMA Balancing

The kernel's automatic NUMA balancer periodically scans process page tables, temporarily removes present bits from PTEs, and re-faults pages to observe which CPU accesses which pages. "Hot" pages migrate to the NUMA node of the accessing CPU.

- Enable/disable: `echo 1 > /proc/sys/kernel/numa_balancing`
- Overhead: ~1% CPU for scanning; migration stalls the faulting thread briefly
- Beneficial for long-running processes with stable, localizable working sets
- Harmful for latency-sensitive inference: unpredictable migration bursts cause tail latency spikes

**Recommendation**: disable AutoNUMA (`numa_balancing=0` in kernel parameters) on real-time and latency-sensitive inference servers. Use explicit `mbind`/`numactl` instead.

---

## Multi-GPU NUMA Affinity

In a 2-socket server, GPU cards are connected to one socket's PCIe root complex. Every CPU-to-GPU memory transfer from a remote socket crosses the socket interconnect, adding 60–100 ns of latency per cache line.

```bash
nvidia-smi topo -m    # GPU-GPU and CPU-GPU interconnect topology
```

Example 2-socket output:
```
        GPU0  GPU1  GPU2  GPU3  CPU Affinity
GPU0     X    NV4   SYS   SYS   0-23
GPU1    NV4    X    SYS   SYS   0-23
GPU2    SYS   SYS    X    NV4   24-47
GPU3    SYS   SYS   NV4    X    24-47
```

`SYS` = traverses QPI/UPI (slow); `NV4` = NVLink 4 (fast). Bind the inference process to the CPU affinity range collocated with the target GPU to avoid `SYS` crossings.

---

## HPC Memory Optimization Patterns

### Binding (Latency-Bound Inference)

Pin all model weight allocations and the inference process to the NUMA node local to the GPU. Use first-touch by the pinned worker thread, or `mbind(MPOL_BIND)` after allocation.

```bash
echo 256 > /sys/devices/system/node/node0/hugepages/hugepages-2048kB/nr_hugepages
numactl --cpunodebind=0 --membind=0 ./inferenced
```

### Interleaving (Bandwidth-Bound Training)

For GEMM operations that exceed single-node memory bandwidth, interleave the weight matrix across all nodes. Aggregate bandwidth = N × per-node bandwidth.

```bash
numactl --interleave=all ./training_process
```

### Huge Pages + NUMA

Pre-allocate huge pages per NUMA node for model weight buffers. HugeTLBFS supports per-node allocation via `/sys/devices/system/node/nodeN/hugepages/`. Combine with `madvise(MADV_WILLNEED)` to pre-fault pages local before inference starts.

---

## Memory Bandwidth Measurement

```bash
stream                                               # STREAM TRIAD benchmark per node
numastat -p $(pidof inferenced)                      # per-process NUMA hit/miss stats
perf stat -e cache-misses,LLC-load-misses ./workload # LLC miss rate (proxy for remote access)
perf mem record -- ./workload && perf mem report     # memory access latency profiling
```

`numastat -p` fields:
- `numa_hit`: pages allocated on the intended node
- `numa_miss`: pages allocated on a different node due to pressure
- `numa_foreign`: pages intended for this node but allocated elsewhere

---

## Summary

| Policy | Behavior | Best for | Command | Caveat |
|--------|----------|----------|---------|--------|
| Default (first-touch) | Alloc on faulting CPU's node | General workloads | (implicit) | Wrong if initializer ≠ consumer |
| `MPOL_BIND` | Strict: only named nodes | Latency-sensitive inference | `numactl --membind=N` | OOM if node is full |
| `MPOL_INTERLEAVE` | Round-robin across nodes | Bandwidth-bound GEMM, all-reduce | `numactl --interleave=all` | Higher latency per access |
| `MPOL_PREFERRED` | Prefer node; allow fallback | Mixed workloads | `numactl --preferred=N` | May silently go remote |
| AutoNUMA | Migrate hot pages automatically | Long-running stable workloads | `echo 1 > .../numa_balancing` | Unpredictable latency spikes |

---

## AI Hardware Connection

- Multi-GPU inference servers require NUMA binding so that CPU pre-processing threads, pinned host memory, and the target GPU share the same PCIe root complex, avoiding QPI/UPI penalty on every H2D transfer
- First-touch initialization must occur on the thread pinned to the correct NUMA node; PyTorch DataLoader workers that initialize weight tensors on the wrong node silently degrade bandwidth by 2× for the lifetime of the process
- NUMA interleave across all nodes maximizes aggregate memory bandwidth for distributed training all-reduce passes where the bottleneck is memory throughput rather than latency
- `numastat -p` is the primary diagnostic for identifying remote memory access in a deployed inference pipeline; `numa_miss` values above 5% indicate a NUMA placement bug
- AutoNUMA must be disabled on latency-sensitive inference servers to prevent tail latency spikes caused by background page migration competing with inference kernel execution
- Jetson Orin has a single NUMA node (unified CPU-GPU DRAM); NUMA policies do not apply, but CPU-cluster affinity between the Cortex-A78 cluster and Cortex-X1 cores still affects LLC sharing and bandwidth
