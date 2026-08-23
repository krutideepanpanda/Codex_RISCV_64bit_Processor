# Dual-retirement and trap contract

This is the normative ordering contract for the ROB, architectural state, RVFI, differential model, interrupts, debug entry, and replay.

## Retirement group

Each cycle begins at a retirement-group boundary. Lane 0 is older than lane 1. Lane 1 may be valid only when lane 0 is valid, except for an explicitly documented verification-only idle-lane representation. When both lanes retire, their `rvfi_order` values are consecutive and lane 1 observes all architecturally visible effects of lane 0.

No instruction may retire twice. Squashed, replaying, speculative, or wrong-path instructions produce no architectural write, memory effect, CSR effect, or valid RVFI lane.

## Synchronous exceptions

- An exception on lane 0 suppresses lane 0 and lane 1 retirement. Trap state names lane 0 and no instruction in the group has side effects.
- An exception on lane 1 permits a non-excepting lane 0 to retire. Lane 1 has no architectural side effects, then trap state names lane 1 using architectural state after lane 0.
- A completed store becomes architecturally committed only with its retiring instruction. Faulting or squashed stores cannot escape the store queue.

## Asynchronous interrupts and debug entry

Interrupts and asynchronous debug halt requests are sampled at the retirement-group boundary before selecting that cycle's retirement lanes. If accepted, neither lane retires in that cycle and the saved PC is the next unretired instruction.

An interrupt that becomes observable after a two-instruction group has been selected is eligible at the next boundary, after both selected instructions retire. The reference model and RTL use the same boundary rule; this legal deferral must not be reported as an order mismatch.

Synchronous debug events follow synchronous-exception lane suppression. Single-step retires at most one instruction before entering debug.

## RVFI representation

Each lane reports its own instruction, PC before/after, register and CSR effects, memory masks/data, privilege mode, trap/debug indication, and monotonically increasing 64-bit order. Comparators normalize invalid lanes away and compare the ordered event stream rather than cycle packing.

Memory effects are reported at architectural commitment. Misaligned operations may use multiple internal accesses but produce one architectural RVFI event with the specified bytes. Interrupt pseudo-events are kept separate from retired instruction order.

## Recovery and replay

Branch recovery and memory-order replay restore the rename map, free lists, issue state, load/store state, and ROB tail to one precise checkpoint. Older instructions remain live; the violating load and all dependent younger instructions are replayed or squashed according to the recovery cause. Recovery cannot alter already retired state.
