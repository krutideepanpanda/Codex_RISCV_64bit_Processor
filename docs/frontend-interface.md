# v0.1 frontend interface contract

This document freezes the frontend semantics needed to integrate fetch,
prediction, decompression, and decode. It does not claim that the complete
frontend is implemented. Lane 0 is always older than lane 1.

## Clock and reset

Frontend RTL is in `VDD_CORE` and consumes `rst_ni` as the asynchronous-assert,
synchronous-deassert local core-domain reset. The raw pad reset is synchronized
before it reaches this interface; frontend blocks must never consume the raw pad
reset directly.

## Instruction-stream window

The v0.1 aligner consumes a 32-byte little-endian byte window. Byte zero is the
byte at `window_base_pc_i`, the base is 16-byte aligned, and `start_pc_i` is a
2-byte-aligned address in the first 16 bytes. The second half of the window
allows one 32-bit instruction beginning at byte 14 to cross a response boundary.

Each byte has independent valid and fault state. Fault takes precedence over
data validity. A lane is emitted only when all bytes needed to classify and form
that instruction are available. A fetch fault emits one attributable lane with
zero instruction payload and terminates the packet. Missing bytes stall packet
formation; they are not converted into illegal instructions.

Compressed encodings retain their original 16 bits, zero-extended in the raw
instruction field. Illegal compressed encodings remain attributable valid lanes,
set the illegal-compressed indication, and carry a zero decompressed instruction.
Native 32-bit instructions copy their raw bits unchanged. Lane 1 is considered
only after a valid, non-faulting lane 0.

## Prediction contract

BTB target kinds use the following fixed two-bit encoding:

| Value | Kind |
|---|---|
| `2'b00` | conditional branch |
| `2'b01` | direct jump or call |
| `2'b10` | indirect jump or call |
| `2'b11` | return |

The v1 indirect target cache is 32 entries. The current four-way primitive must
therefore be instantiated with `SETS=8` and `WAYS=4`; its larger module defaults
are not an integration configuration.

Prediction priority is direct JAL target, RAS return, confident indirect target,
BTB target for a predicted-taken control transfer, then sequential PC. A taken
lane 0 suppresses lane 1. Every emitted packet retains the TAGE, indirect,
history, and full RAS metadata needed for exact recovery and later training.

Predictor tables train only from in-order retired control transfers. Fetch
lookup and speculative history/RAS advancement never train a predictor table.
The recovery priority is frontend flush, resolved redirect, then ordinary
speculative advancement. Redirect restores the saved history and full RAS
snapshot before optionally appending the resolved branch outcome.

## Backpressure and stale responses

All packet payload and metadata remain stable while valid output is stalled.
Redirect and flush invalidate younger buffered output. The initial v0.1 fetch
controller permits one instruction-stream request at a time and associates each
response with its aligned request base; a delayed pre-redirect response must not
become visible after recovery.

## Fetch-controller handshake

`rv64_fetch_controller` owns one in-order, non-cancellable instruction-window
transaction. A request carries a 16-byte-aligned base and represents the 32-byte
window beginning at that address. The response has no transaction ID because no
second request may become outstanding. The controller records both the aligned
base and the exact start PC at request acceptance.

The controller exposes a buffered window-valid/window-ready interface to the
aligner. Its start PC, base, byte data, byte-valid state, and byte-fault state
remain stable until accepted. The accepting consumer supplies `next_pc_i`; that
PC becomes the next ordinary request PC. No request is issued while a response
window is buffered or another request is outstanding.

`flush_valid_i` with `flush_pc_i` has highest recovery priority, followed by
`redirect_valid_i` with `redirect_pc_i`, followed by an accepted window's next
PC. Flush and redirect both invalidate a buffered window. If either arrives
while a request is outstanding, that request becomes stale: its eventual
response is accepted and discarded, including when response and recovery occur
in the same cycle. Only then may a request for the recovery PC issue. Reset
starts from parameter `RESET_PC`, and `fetch_enable_i=0` prevents new requests
without dropping an already accepted transaction or buffered window.
