---
name: linux-soc-bringup
description: Bring up or qualify OpenSBI, U-Boot, Linux, Debian, device tree, boot media, or simulation peripherals for this RV64 SoC.
---

# Linux and SoC bring-up

- Treat `docs/memory-map.md` and the versioned hardware/software contract as authoritative.
- Pin firmware, kernel, rootfs, compiler, and image inputs; record hashes and boot commands.
- Validate reset vector, SBI services, timer/interrupt topology, MMIO ordering, cacheability, UART, storage, networking, and time.
- Require repeated cold boot, shutdown, reboot, selftest, package, storage, and networking evidence before a milestone passes.
- Do not add PCIe, IOMMU, AIA, ROCm, or board-specific FPGA claims to v1.
