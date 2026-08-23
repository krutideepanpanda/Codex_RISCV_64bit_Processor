# v1 physical memory map

| Region | Start | Size | Attributes |
|---|---:|---:|---|
| Debug ROM/data | `0x0000_0000` | 4 KiB | device, debug-only |
| Boot ROM | `0x0000_1000` | 60 KiB | read/execute |
| ACLINT MSWI | `0x0200_0000` | 16 KiB | device |
| ACLINT MTIMER | `0x0200_4000` | 48 KiB | device |
| PLIC | `0x0c00_0000` | 64 MiB | device |
| UART0 | `0x1000_0000` | 4 KiB | device |
| QSPI | `0x1000_1000` | 4 KiB | device |
| GPIO | `0x1000_2000` | 4 KiB | device |
| Simulation host | `0x1000_3000` | 4 KiB | device, absent in ASIC |
| External MMIO | `0x2000_0000` | 512 MiB | device |
| DRAM | `0x8000_0000` | up to 63.5 GiB | cacheable |

The implemented physical address width is 40 bits. Unmapped accesses raise an
access fault. Device regions are strongly ordered and never speculated past an
older device transaction.

