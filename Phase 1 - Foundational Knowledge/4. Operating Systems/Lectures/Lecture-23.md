# Lecture 23: Containers, cgroups v2 & NVIDIA Container Runtime

## Containers vs Virtual Machines

Containers share the host kernel. Isolation is provided by Linux namespaces (visibility) and cgroups (resource limits). There is no hypervisor, no guest kernel, and no hardware emulation.

| Property | Container | VM |
|---|---|---|
| Kernel | Shared with host | Separate guest kernel |
| Startup time | 5–50 ms | 1–10 s |
| Overhead | ~1% CPU | 5–15% CPU (hypervisor) |
| Isolation | Namespace + cgroups | Full hardware virtualization |
| GPU access | Direct (passthrough) | Requires GPU virtualization (vGPU) |

For inference deployment, containers provide near-bare-metal GPU performance with reproducible software environments.

## Linux Namespaces

Seven namespace types isolate different aspects of the system environment. Each namespace is a kernel object; processes that share a namespace see the same view of that resource.

| Namespace | Isolates | Key detail |
|---|---|---|
| PID | Process tree | Container init = PID 1; cannot see host PIDs |
| Network | Network stack | Private interfaces, iptables, routing, ports |
| Mount | Filesystem view | `pivot_root` after overlayfs setup |
| UTS | Hostname, domain name | `uname -n` returns container name |
| IPC | System V IPC + POSIX shm | Prevents cross-container shared memory |
| User | UID/GID mapping | Container UID 0 → host UID 1000 (rootless) |
| Time (5.6+) | CLOCK_BOOTTIME/MONOTONIC offset | CRIU checkpoint/restore |

### Key Operations

```bash
unshare --pid --fork --mount-proc bash   # new PID namespace with fresh /proc
ip netns add myns                        # create network namespace
ip netns exec myns ip addr               # run command inside namespace
nsenter -t <PID> --net --pid bash        # enter existing process's namespaces
```

## cgroups v2 (Unified Hierarchy)

cgroups v2 replaced the per-subsystem hierarchy of v1 with a single unified hierarchy at `/sys/fs/cgroup/`. Controllers are enabled per-cgroup and inherited by children.

### Controller Reference

| Controller | Key file | Example value | Effect |
|---|---|---|---|
| `cpu` | `cpu.max` | `500000 1000000` | Limit to 50% of one CPU |
| `memory` | `memory.max` | `4G` | Hard memory limit; triggers OOM kill |
| `memory` | `memory.swap.max` | `0` | Disable swap for this cgroup |
| `cpuset` | `cpuset.cpus` | `4-7` | Restrict to cores 4–7 |
| `cpuset` | `cpuset.cpus.exclusive` | `1` | Exclusive assignment (Kubernetes static CPU) |
| `io` | `io.max` | `8:0 rbps=1073741824` | Limit to 1 GB/s read on device 8:0 |
| `pids` | `pids.max` | `256` | Maximum number of processes in cgroup |

### Creating and Managing cgroups

```bash
mkdir /sys/fs/cgroup/inference
echo "4-7" > /sys/fs/cgroup/inference/cpuset.cpus
echo "0"   > /sys/fs/cgroup/inference/cpuset.mems
echo "8G"  > /sys/fs/cgroup/inference/memory.max
echo "0"   > /sys/fs/cgroup/inference/memory.swap.max
echo $$    > /sys/fs/cgroup/inference/cgroup.procs   # move shell into cgroup
```

Kubernetes uses cgroups v2 for all resource enforcement. The kubelet creates a cgroup hierarchy per-Pod and per-container; the container runtime writes resource limits into the appropriate cgroup files.

## Container Runtimes

| Runtime | Role | Notes |
|---|---|---|
| `containerd` | High-level; manages images and snapshots | Default for Kubernetes (CRI) |
| `runc` | Low-level OCI runtime; creates namespaces and cgroups | Used by containerd |
| `crun` | C reimplementation of runc | 2–5× faster startup; lower memory |
| `kata-containers` | Lightweight VM per container | Stronger isolation; used for multi-tenant GPU |

`containerd` → `runc` → `clone()` with `CLONE_NEWPID | CLONE_NEWNET | CLONE_NEWNS` → set up overlayfs rootfs → `pivot_root` → write cgroup limits → exec container entrypoint.

## NVIDIA Container Runtime

`nvidia-container-toolkit` is an OCI runtime hook that runs before the container process starts. It:

1. Reads `NVIDIA_VISIBLE_DEVICES` env var (or `--gpus` flag)
2. Mounts the selected `/dev/nvidia*` device nodes into the container's mount namespace
3. Injects CUDA libraries (`libcuda.so.X`, `libnvrtc.so`, `libnvidia-ml.so`) from the host into the container at well-known paths
4. Sets up `/proc/driver/nvidia` and capability files

The container image does not need to contain CUDA; only the CUDA application code is packaged. Host driver version is exposed as-is. This allows a single container image to run on hosts with different driver versions, as long as the driver is compatible with the required CUDA toolkit version.

```bash
docker run --gpus all --rm nvidia/cuda:12.2-base nvidia-smi
docker run --gpus "device=0" -e NVIDIA_DRIVER_CAPABILITIES=compute,utility \
    my-trt-inference-server
```

## Multi-Instance GPU (MIG)

MIG is available on A100, H100, and Jetson Orin. It partitions one physical GPU into up to 7 independent GPU Instances (GIs), each with dedicated:

- Compute (SM partition)
- Memory (HBM slice with dedicated bandwidth)
- On-chip caches and decoders

Each GI appears as an independent GPU to CUDA. There is no time-sharing; GIs run truly in parallel.

```bash
nvidia-smi mig -lgip                        # list GPU instance profiles
nvidia-smi mig -cgi 3g.40gb,1g.10gb -C     # create instances
# Container gets one GI via: --gpus "MIG-GPU-<uuid>"
```

On Jetson Orin, MIG enables running multiple inference models (perception, occupancy, prediction) on isolated GPU partitions with guaranteed memory bandwidth.

## GPU Sharing Without MIG

CUDA MPS (Multi-Process Service) allows multiple CUDA processes to share a GPU through a single MPS server process:

- Processes submit work via the MPS server; it serializes and batches submissions
- Reduces context switch overhead compared to time-sharing without MPS
- No memory isolation between clients (contrast with MIG)
- Use case: many lightweight inference processes sharing one GPU in a serving cluster

```bash
nvidia-cuda-mps-control -d    # start MPS daemon
export CUDA_MPS_PIPE_DIRECTORY=/tmp/nvidia-mps
```

## Kubernetes for AI Inference

### NVIDIA Device Plugin

The device plugin runs as a DaemonSet on each GPU node. It:

- Calls `nvidia-smi` to enumerate GPUs and MIG instances
- Registers `nvidia.com/gpu` as an Extended Resource with the kubelet
- Allocates specific device nodes to pods scheduled on the node

### Pod Specification

```yaml
resources:
  limits:
    nvidia.com/gpu: "1"
    cpu: "4"
    memory: "16Gi"
```

### Key Components

- **Node Feature Discovery (NFD)**: labels nodes with GPU model, CUDA version, driver version; used by scheduler for GPU-type-aware placement
- **Triton Inference Server**: containerized; dynamic batching; backends: TensorRT, ONNX Runtime, PyTorch; exposes gRPC + HTTP endpoints
- **DCGM Exporter**: exports GPU metrics (utilization, memory, temperature, NVLink bandwidth) to Prometheus

## Summary

| Isolation mechanism | Kernel feature | Resource type | Primary tools |
|---|---|---|---|
| Process visibility | PID namespace | Process tree | `unshare`, `nsenter` |
| Network isolation | Network namespace | Interfaces, ports | `ip netns`, `veth` |
| Filesystem isolation | Mount namespace + overlayfs | Rootfs | `pivot_root`, `containerd` |
| CPU limits | cgroups v2 `cpu` controller | CPU time | `cpu.max`, kubelet |
| Memory limits | cgroups v2 `memory` controller | RAM + swap | `memory.max` |
| CPU pinning | cgroups v2 `cpuset` controller | CPU cores | `cpuset.cpus` |
| GPU access | NVIDIA Container Toolkit | Device nodes + libraries | `--gpus`, device plugin |
| GPU partitioning | MIG (hardware) | SM + HBM slices | `nvidia-smi mig` |

## AI Hardware Connection

- NVIDIA Container Runtime enables TensorRT and Triton inference containers to access GPU hardware at native performance; the host driver is injected at container start, eliminating the need to rebuild images per driver version
- MIG on A100/H100/Orin partitions the GPU for multi-tenant inference serving; each model gets a guaranteed memory bandwidth slice, preventing one workload from starving another
- cgroups v2 `cpuset.cpus.exclusive` in Kubernetes static CPU manager pins inference worker threads to dedicated cores, eliminating OS scheduler interference and reducing tail latency
- Rootless containers (user namespace UID remapping) are the correct security posture for edge AI deployments where the container user must not map to a privileged host account
- CUDA MPS enables high-concurrency serving scenarios where many lightweight inference processes (e.g., per-sensor model instances) share one GPU without the overhead of full context switches
- The full stack — cgroups v2 resource isolation + NVIDIA device plugin + Triton dynamic batching — is the production reference architecture for scalable GPU inference in Kubernetes
