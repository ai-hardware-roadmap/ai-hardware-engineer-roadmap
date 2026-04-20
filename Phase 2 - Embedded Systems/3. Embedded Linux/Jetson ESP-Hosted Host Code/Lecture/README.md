# Jetson ESP-Hosted Host Code — lectures

Work through these in order. Each file is one session built around the real `esp_hosted_ng/host/` Linux host code.

**Hub:** [Jetson ESP-Hosted Host Code guide](../Guide.md)

| Lecture | Topic | Main kernel interfaces | Main concepts |
|---------|-------|------------------------|---------------|
| [Lecture-01](Lecture-01.md) | Linux mental model for this host stack | `cfg80211`, HCI, netdev, SPI transport split | subsystem boundaries |
| [Lecture-02](Lecture-02.md) | Build, load, and board policy on Jetson | kernel modules, `module_param`, `spidev` ownership | board policy vs driver code |
| [Lecture-03](Lecture-03.md) | SPI transport, GPIOs, and IRQ-driven bring-up | `gpio_to_irq`, `request_irq`, SPI device reuse | interrupt-driven transport |
| [Lecture-04](Lecture-04.md) | How Wi-Fi becomes `wlan0` | `wiphy_new`, `wiphy_register`, `register_netdevice` | Linux wireless subsystem integration |
| [Lecture-05](Lecture-05.md) | How BLE becomes `hci0` and how to validate the full path | `hci_alloc_dev`, `hci_register_dev`, `hci_recv_frame` | HCI and BLE host/controller split |
