// SPDX-License-Identifier: Apache-2.0
// Two-wide speculative branch-history register in the VDD_CORE clock domain.
// Lane 0 is older than lane 1. The owner stores pre-branch checkpoints.
// A branch-mispredict recovery restores that checkpoint and appends the
// resolved actual outcome; non-branch redirects restore it verbatim.
module rv64_spec_history #(
  parameter int unsigned HISTORY_W = 64
) (
  input  logic                 clk,
  input  logic                 rst_ni,
  input  logic [1:0]           advance_valid_i,
  input  logic [1:0]           advance_taken_i,
  input  logic                 recover_valid_i,
  input  logic [HISTORY_W-1:0] recover_history_i,
  input  logic                 recover_is_branch_i,
  input  logic                 recover_taken_i,
  input  logic                 flush_valid_i,
  output logic [HISTORY_W-1:0] lane0_history_o,
  output logic [HISTORY_W-1:0] lane1_history_o,
  output logic [HISTORY_W-1:0] checkpoint_history_o
);
  logic [HISTORY_W-1:0] history_q;
  logic [HISTORY_W-1:0] history_after_lane0;
  logic [HISTORY_W-1:0] history_after_lane1;

  initial begin
    assert (HISTORY_W >= 1);
  end

  always_comb begin
    lane0_history_o = history_q;
    history_after_lane0 = history_q;
    if (advance_valid_i[0]) begin
      history_after_lane0 = history_q << 1;
      history_after_lane0[0] = advance_taken_i[0];
    end
    lane1_history_o = history_after_lane0;
    history_after_lane1 = history_after_lane0;
    if (advance_valid_i[1]) begin
      history_after_lane1 = history_after_lane0 << 1;
      history_after_lane1[0] = advance_taken_i[1];
    end
    checkpoint_history_o = history_q;
  end

  always_ff @(posedge clk or negedge rst_ni) begin
    if (!rst_ni)
      history_q <= '0;
    else if (flush_valid_i)
      history_q <= '0;
    else if (recover_valid_i) begin
      if (recover_is_branch_i) begin
        history_q <= recover_history_i << 1;
        history_q[0] <= recover_taken_i;
      end else begin
        history_q <= recover_history_i;
      end
    end
    else
      history_q <= history_after_lane1;
  end
endmodule
