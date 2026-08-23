# Deferred v2 ROCm/GPU work

v1 makes no ROCm compatibility claim. After an exact FPGA board and AMD GPU are
available, v2 will target a vendor PCIe Gen3 x8 root-port wrapper, RISC-V IOMMU,
APLIC/IMSIC, PASID/ATS/PRI, MSI-X, PCIe atomics, 64-bit coherent DMA, Linux
AMDGPU validation, and a riscv64 ROCm/HSA/HIP port. These remain research and
porting objectives until demonstrated on the selected hardware. The v1 AXI
memory system and inclusive L2 reserve integration points for that work.
