# Lecture 18: Character Drivers, Interrupt-Driven I/O & V4L2

## Character Device Driver

### Registration

```c
alloc_chrdev_region(&devno, 0, 1, "mydev");   // dynamic major/minor
cdev_init(&mydev->cdev, &mydev_fops);
cdev_add(&mydev->cdev, devno, 1);
cls = class_create(THIS_MODULE, "mydev");
device_create(cls, NULL, devno, NULL, "mydev0");   // creates /dev/mydev0
```

### struct file_operations

| Operation | Signature | Purpose |
|-----------|-----------|---------|
| `open` | `(inode, file)` | Allocate per-file state; check permissions |
| `release` | `(inode, file)` | Free per-file state; flush hardware |
| `read` | `(file, buf, len, off)` | Copy data to user; block if unavailable |
| `write` | `(file, buf, len, off)` | Copy data from user; submit to device |
| `ioctl` / `unlocked_ioctl` | `(file, cmd, arg)` | Device-specific commands |
| `mmap` | `(file, vma)` | Map device/kernel memory into user VA |
| `poll` | `(file, poll_table)` | Report readiness for select/poll/epoll |

---

## ioctl Interface

```c
#define MYDEV_IOC_MAGIC  'M'
#define MYDEV_RESET      _IO(MYDEV_IOC_MAGIC,  0)       // no arg
#define MYDEV_GET_STATUS _IOR(MYDEV_IOC_MAGIC, 1, u32)  // read from device
#define MYDEV_SET_CONFIG _IOW(MYDEV_IOC_MAGIC, 2, struct mydev_cfg) // write

static long mydev_ioctl(struct file *f, unsigned int cmd, unsigned long arg)
{
    struct mydev_cfg cfg;
    if (copy_from_user(&cfg, (void __user *)arg, sizeof(cfg)))
        return -EFAULT;   // never dereference user pointer directly
    // ...
}
```

- Never dereference `(void *)arg` directly in kernel; always use `copy_from_user()` / `copy_to_user()`
- `copy_*_user` returns bytes not copied on error; check return value

---

## mmap in Drivers

Maps kernel or device memory directly into user VA space; enables zero-copy access.

```c
static int mydev_mmap(struct file *f, struct vm_area_struct *vma)
{
    vma->vm_page_prot = pgprot_noncached(vma->vm_page_prot); // for MMIO
    return remap_pfn_range(vma, vma->vm_start,
                           phys_addr >> PAGE_SHIFT,
                           vma->vm_end - vma->vm_start,
                           vma->vm_page_prot);
}
```

- `remap_pfn_range()`: maps contiguous physical range; used for DMA buffers and MMIO
- `vm_insert_page()`: maps individual pages; used for vmalloc-backed buffers
- `vm_ops->fault`: demand-map pages on access; used for large sparse buffers

---

## Interrupt-Driven I/O

```c
devm_request_irq(dev, irq, mydev_isr, IRQF_SHARED, "mydev", priv);

static irqreturn_t mydev_isr(int irq, void *data)
{
    struct mydev *dev = data;
    u32 status = readl(dev->base + STATUS_REG);
    if (!(status & MY_IRQ_BIT)) return IRQ_NONE;

    dev->data_ready = true;
    wake_up_interruptible(&dev->wait_q);   // unblock waiting readers
    return IRQ_HANDLED;
}
```

### Top Half / Bottom Half Split

| Mechanism | Context | Use |
|-----------|---------|-----|
| ISR (top half) | Interrupt; no sleep | Acknowledge IRQ; wake queue |
| `tasklet_schedule()` | Softirq; no sleep | Short deferred work |
| `queue_work()` | Kernel thread; can sleep | I/O, memory alloc, long work |

---

## Wait Queues

```c
wait_queue_head_t wq;
init_waitqueue_head(&wq);

// Producer (ISR): wake waiters
wake_up_interruptible(&wq);

// Consumer (read fop): sleep until condition
wait_event_interruptible(wq, dev->data_ready);
```

- `wait_event_interruptible()` returns `-ERESTARTSYS` if signal received; caller should return `-EINTR` to userspace
- `wait_event_interruptible_timeout()`: add deadline for polling fallback

---

## poll() / select() / epoll in Drivers

```c
static __poll_t mydev_poll(struct file *f, poll_table *wait)
{
    poll_wait(f, &dev->wait_q, wait);   // register wait queue
    if (dev->data_ready)
        return EPOLLIN | EPOLLRDNORM;
    return 0;
}
```

Userspace `epoll_wait()` returns when `EPOLLIN` is set; enables event-driven data pipelines without busy-polling.

---

## V4L2 (Video4Linux2)

Kernel subsystem for cameras and video capture devices. Header: `<linux/videodev2.h>`.

### Capture Sequence

```
VIDIOC_QUERYCAP     → verify capabilities
VIDIOC_S_FMT        → set pixel format, resolution
VIDIOC_REQBUFS      → allocate N buffers (MMAP or DMABUF)
VIDIOC_QBUF         → enqueue buffer (give to driver)
VIDIOC_STREAMON     → start streaming
poll() / select()   → wait for filled buffer
VIDIOC_DQBUF        → dequeue filled buffer; process frame
VIDIOC_QBUF         → re-enqueue for next frame
VIDIOC_STREAMOFF    → stop streaming
```

### Buffer Memory Types

| Type | Description | Zero-copy to GPU? |
|------|-------------|------------------|
| `V4L2_MEMORY_MMAP` | Kernel allocates; user mmap()s | No (CPU copy needed) |
| `V4L2_MEMORY_USERPTR` | User allocates; driver pins | Conditional |
| `V4L2_MEMORY_DMABUF` | Import external DMA-BUF fd | Yes (GPU imports same buf) |

### Media Controller

- `/dev/media0`: represents the full pipeline as an entity graph
- Entities: sensor → ISP → CSI bridge → V4L2 capture node
- `MEDIA_IOC_SETUP_LINK`: enable/disable data paths between entities
- `media-ctl` tool: configure pipeline from shell; inspect entity properties

### openpilot camerad Pipeline

```
IMX sensors → NVCSI → ISP (NvCamSrc) → V4L2/ISP API
    --> frame buffer (DMA-BUF or nvmap)
    --> VisionIPC shared memory
    --> modeld (neural network inference)
```

---

## Summary

| Driver type | Key fops | Kernel subsystem | Example use |
|-------------|----------|-----------------|------------|
| Char device | open/read/write/ioctl/mmap/poll | `cdev` | FPGA control, custom accelerator |
| V4L2 capture | VIDIOC_* ioctls | `videobuf2` | Camera sensor, USB UVC |
| V4L2 + DMA-BUF | REQBUFS(DMABUF) + DQ/QBUF | `videobuf2` + `dma-buf` | Jetson ISP → GPU pipeline |
| Platform + IRQ | ISR + waitqueue + poll | `platform_driver` | AI accelerator interrupt |

---

## AI Hardware Connection

- V4L2 with `V4L2_MEMORY_DMABUF` enables zero-copy camera frame delivery to CUDA on Jetson; buffer is imported by CUDA without any CPU memcpy.
- openpilot camerad uses the V4L2 / ISP API to capture frames from IMX sensors and passes DMA-BUF fds through VisionIPC to modeld for inference.
- Custom ioctl interface is the standard pattern for FPGA control plane: configure kernel parameters, trigger DMA, query hardware status.
- `mmap` in driver + `remap_pfn_range` enables userspace inference engines to read DMA output buffers at memory speed without syscall overhead per frame.
- Wait queues with `wake_up_interruptible` from the sensor ISR is the correct pattern for notifying inference threads of data-ready events with zero busy-wait CPU overhead.
- Media controller pipeline configuration is required for Jetson camera bring-up: sensor format, ISP processing stages, and output node must all be explicitly linked before streaming begins.
