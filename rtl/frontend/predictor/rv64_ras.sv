// SPDX-License-Identifier: Apache-2.0
// Return-address stack in the VDD_CORE clock domain.
// rst_ni is the domain-synchronized active-low reset.  Checkpoint values are
// consumed by the owning fetch/recovery logic; entries above a checkpoint are
// deliberately left in place because sp/count make them unreachable.
module rv64_ras #(
  parameter int unsigned DEPTH = 16,
  parameter int unsigned ADDR_W = 64,
  parameter int unsigned SP_W = (DEPTH > 1) ? $clog2(DEPTH) : 1,
  parameter int unsigned COUNT_W = (DEPTH > 0) ? $clog2(DEPTH + 1) : 1,
  parameter int unsigned SNAPSHOT_W = ((DEPTH > 0) && (ADDR_W > 0)) ?
                                           DEPTH * ADDR_W : 1
) (
  input  logic                         clk,
  input  logic                         rst_ni,
  input  logic                         push_valid,
  input  logic [ADDR_W-1:0]            push_addr,
  input  logic                         pop_valid,
  output logic                         top_valid,
  output logic [ADDR_W-1:0]            top_addr,
  output logic [SP_W-1:0]              checkpoint_sp_o,
  output logic [COUNT_W-1:0]           checkpoint_count_o,
  output logic [SNAPSHOT_W-1:0]        checkpoint_entries_o,
  input  logic                         recover_valid,
  input  logic [SP_W-1:0]              recover_sp,
  input  logic [COUNT_W-1:0]           recover_count,
  input  logic [SNAPSHOT_W-1:0]        recover_entries,
  input  logic                         flush_valid
);
  // Packed storage keeps generic synthesis deterministic; entries are sliced
  // explicitly and remain checkpoint-compatible.
  logic [SNAPSHOT_W-1:0] stack_q;
  logic [SP_W-1:0]   sp_q;
  logic [COUNT_W-1:0] count_q;
  logic [SP_W-1:0] top_index;

  initial begin
    assert (DEPTH >= 2);
    assert ((DEPTH & (DEPTH - 1)) == 0);
    assert (ADDR_W > 0);
    assert (SP_W == $clog2(DEPTH));
    assert (COUNT_W == $clog2(DEPTH + 1));
    assert (SNAPSHOT_W == DEPTH * ADDR_W);
  end

  always_comb begin
    // SP points at the next push slot.  Fixed-width subtraction deliberately
    // wraps a full stack's SP=0 to DEPTH-1 without a negative part-select.
    top_index = sp_q - SP_W'(1);
    top_valid = (count_q != '0);
    top_addr = '0;
    if (top_valid) begin
      top_addr = stack_q[(int'(top_index) * ADDR_W) +: ADDR_W];
    end
    checkpoint_sp_o = sp_q;
    checkpoint_count_o = count_q;
    checkpoint_entries_o = stack_q;
  end

  always_ff @(posedge clk or negedge rst_ni) begin
    if (!rst_ni) begin
      sp_q <= '0;
      count_q <= '0;
      stack_q <= '0;
    end else if (flush_valid) begin
      sp_q <= '0;
      count_q <= '0;
    end else if (recover_valid) begin
      sp_q <= recover_sp;
      count_q <= recover_count;
      stack_q <= recover_entries;
    end else begin
      unique case ({push_valid, pop_valid})
        2'b10: if (count_q != COUNT_W'(DEPTH)) begin
          stack_q[(int'(sp_q) * ADDR_W) +: ADDR_W] <= push_addr;
          sp_q <= sp_q + SP_W'(1);
          count_q <= count_q + COUNT_W'(1);
        end
        2'b01: if (count_q != '0) begin
          sp_q <= sp_q - SP_W'(1);
          count_q <= count_q - COUNT_W'(1);
        end
        2'b11: if (count_q == '0) begin
          stack_q[(int'(sp_q) * ADDR_W) +: ADDR_W] <= push_addr;
          sp_q <= sp_q + SP_W'(1);
          count_q <= COUNT_W'(1);
        end else begin
          stack_q[(int'(top_index) * ADDR_W) +: ADDR_W] <= push_addr;
        end
        default: begin end
      endcase
    end
  end

  always @(posedge clk) begin
    if (rst_ni && recover_valid) assert (recover_count <= COUNT_W'(DEPTH));
    if (rst_ni) assert (count_q <= COUNT_W'(DEPTH));
  end
endmodule
