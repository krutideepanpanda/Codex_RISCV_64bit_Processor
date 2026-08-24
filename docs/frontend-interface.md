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

The aligner retains missing-byte semantics for unit-level composition, but the
v0.1 controller response is a complete terminal window: on every accepted
response, each of the 32 byte positions must be either valid or faulted. The
instruction-memory/cache adapter must retain or refill partial beats before
presenting `response_valid_i`. This guarantee prevents an immutable buffered
window from deadlocking while preserving byte-attributable faults. A future
partial-window protocol requires an explicit transaction/refill interface
revision; the current controller does not infer or issue refills.

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

The v0.1 predictor primitives provide one BTB, indirect-predictor, and RAS
operation per cycle. Consequently, a packet may contain at most one control
transfer: any lane-0 control transfer suppresses lane 1, while lane 1 may be the
sole control transfer when lane 0 is ordinary. Suppression is a structural
throughput restriction, not an architectural drop; the younger PC is selected
for a later fetch packet. Removing this restriction requires a reviewed
multi-ported or replicated predictor interface revision.

`rv64_fetch_predictor` is the frontend-owned composition boundary for the fetch
controller, aligner, decompressor, BTB, TAGE-lite predictor, 32-entry indirect
predictor, 16-entry RAS, and 64-bit speculative history. It preserves the
controller request/response protocol and exposes a two-lane valid/ready packet.
The controller window is accepted only with the packet, so instruction and
prediction metadata remain stable together under downstream backpressure.

Integration is accepted in two bounded packets. `frontend-001c-a` closes packet
metadata, retirement-only BTB/TAGE training, backpressure stability, controller
stale-response handling, and flush/redirect priority. `frontend-001c-b` then
closes indirect-confidence training, destructive RAS snapshot recovery, and the
dual-lane speculative-history reference model. Neither subpacket alone completes
the v0.1 frontend milestone.

Predictor tables train only from in-order retired control transfers. Fetch
lookup and speculative history/RAS advancement never train a predictor table.
The recovery priority is frontend flush, resolved redirect, then ordinary
speculative advancement. Redirect restores the saved history and full RAS
snapshot before optionally appending the resolved branch outcome.

Speculative history advances only when an accepted packet contains a
non-faulting conditional branch, using that branch's predicted outcome. Because the current
single-port composition permits only one control transfer per packet, a live
lane-1 branch necessarily follows a non-control lane 0 and observes the same
pre-packet history. The underlying history primitive retains explicit lane-0
then lane-1 ordering for a later multi-control interface. A branch redirect
restores the branch's pre-branch checkpoint and appends its resolved outcome;
a non-branch redirect restores the checkpoint verbatim; a frontend flush clears
history.

RAS push/pop hints follow the unprivileged ISA link-register convention for
`x1` and `x5`. A JAL/JALR writing a link register pushes, a JALR reading a link
register and not writing that same register pops, and a JALR using different
link registers pops then pushes for coroutine switching. A zero-offset JALR
that pops—including a coroutine pop-plus-push—may use the popped RAS top as its
target. Every packet carries the full pre-operation stack snapshot, including
entries, so redirect recovery reverses destructive pop and pop-plus-push
operations exactly.

`redirect_ras_sp_i`, `redirect_ras_count_i`, and `redirect_ras_entries_i`
carry the backend-computed **post-resolved-instruction** RAS state. They are not
an unmodified copy of the redirecting packet's pre-operation snapshot. The
backend derives this corrected state from the packet snapshot and the resolved
JAL/JALR hint, including pop-then-push for a coroutine, before issuing redirect.
This makes recovery atomic without a second speculative RAS update in the
redirect cycle.

## Backpressure and stale responses

All packet payload and metadata remain stable while valid output is stalled.
Redirect and flush invalidate younger buffered output. The initial v0.1 fetch
controller permits one instruction-stream request at a time and associates each
response with its aligned request base; a delayed pre-redirect response must not
become visible after recovery.

Neither flush nor redirect can handshake the previously visible packet:
`packet_valid_o` is masked during either recovery operation, and ordinary
history/RAS advancement is disabled in the same cycle.

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
