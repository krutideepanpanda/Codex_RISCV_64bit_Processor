// SPDX-License-Identifier: Apache-2.0
// Tagged, set-associative indirect-branch target predictor in the VDD_CORE
// clock domain.  lookup metadata is combinational and must be captured by the
// fetch packet.  Only a resolved, in-order-retirement train_valid transaction
// carrying that captured metadata may change predictor state; speculative
// lookups never update it.
module rv64_indirect_predictor #(
  parameter int unsigned SETS = 32,
  parameter int unsigned WAYS = 4,
  parameter int unsigned ADDR_W = 64,
  parameter int unsigned PATH_HIST_W = 8,
  parameter int unsigned CONF_W = 2,
  parameter int unsigned CONFIDENCE_THRESHOLD = 2,
  parameter int unsigned INDEX_W = (SETS > 1) ? $clog2(SETS) : 1,
  parameter int unsigned WAY_W = (WAYS > 1) ? $clog2(WAYS) : 1,
  parameter int unsigned TAG_W = (ADDR_W > INDEX_W + 2) ?
                                      ADDR_W - INDEX_W - 2 : 1
) (
  input  logic                    clk,
  input  logic                    rst_ni,
  input  logic                    lookup_valid,
  input  logic [ADDR_W-1:0]       lookup_pc,
  input  logic [PATH_HIST_W-1:0]  lookup_path_history,
  output logic                    predict_valid,
  output logic [ADDR_W-1:0]       predict_target,
  output logic                    lookup_meta_valid,
  output logic [ADDR_W-1:0]       lookup_meta_pc,
  output logic [PATH_HIST_W-1:0]  lookup_meta_path_history,
  input  logic                    train_valid,
  input  logic                    train_meta_valid,
  input  logic [ADDR_W-1:0]       train_meta_pc,
  input  logic [PATH_HIST_W-1:0]  train_meta_path_history,
  input  logic [ADDR_W-1:0]       train_target,
  input  logic                    flush_valid
);
  // Flat packed tables avoid tool-dependent lowering of resettable
  // multidimensional memories. SRAM qualification/mapping is a later gate.
  logic [SETS*WAYS*TAG_W-1:0] tag_q;
  logic [SETS*WAYS*PATH_HIST_W-1:0] history_q;
  logic [SETS*WAYS*ADDR_W-1:0] target_q;
  logic [SETS*WAYS*CONF_W-1:0] confidence_q;
  logic [SETS*WAYS-1:0] valid_q;
  logic [SETS*WAY_W-1:0] repl_q;
  logic [INDEX_W-1:0] lookup_index;
  logic [TAG_W-1:0] lookup_tag;
  logic [INDEX_W-1:0] train_index;
  logic [TAG_W-1:0] train_tag;
  logic train_hit;
  logic [WAY_W-1:0] train_way;
  logic invalid_way_found;
  logic [CONF_W-1:0] train_next_confidence;
  int unsigned train_conf_index;
  int unsigned train_conf_bit;
  localparam logic [CONF_W-1:0] CONF_ONE = {{(CONF_W-1){1'b0}}, 1'b1};
  localparam logic [CONF_W-1:0] CONFIDENCE_THRESHOLD_VALUE = CONFIDENCE_THRESHOLD[CONF_W-1:0];

  initial begin
    assert (SETS >= 2);
    assert ((SETS & (SETS - 1)) == 0);
    assert (WAYS >= 2);
    assert ((WAYS & (WAYS - 1)) == 0);
    assert (ADDR_W > INDEX_W + 2);
    assert (PATH_HIST_W >= INDEX_W);
    assert (CONF_W > 0);
    assert ((CONFIDENCE_THRESHOLD > 0) &&
            (CONFIDENCE_THRESHOLD <= ((1 << CONF_W) - 1)));
    assert (INDEX_W == $clog2(SETS));
    assert (WAY_W == $clog2(WAYS));
    assert (TAG_W == ADDR_W - INDEX_W - 2);
  end

  always_comb begin
    lookup_index = lookup_pc[INDEX_W+1:2] ^ lookup_path_history[INDEX_W-1:0];
    lookup_tag = lookup_pc[ADDR_W-1:INDEX_W+2];
    train_index = train_meta_pc[INDEX_W+1:2] ^ train_meta_path_history[INDEX_W-1:0];
    train_tag = train_meta_pc[ADDR_W-1:INDEX_W+2];
    predict_valid = 1'b0;
    predict_target = '0;
    lookup_meta_valid = lookup_valid;
    lookup_meta_pc = lookup_pc;
    lookup_meta_path_history = lookup_path_history;
    train_hit = 1'b0;
    train_way = repl_q[(train_index * WAY_W) +: WAY_W];
    invalid_way_found = 1'b0;
    for (int unsigned way = 0; way < WAYS; way = way + 1) begin
      if (lookup_valid && valid_q[lookup_index * WAYS + way] &&
          (tag_q[((lookup_index * WAYS + way) * TAG_W) +: TAG_W] == lookup_tag) &&
          (history_q[((lookup_index * WAYS + way) * PATH_HIST_W) +: PATH_HIST_W] ==
           lookup_path_history) &&
          (confidence_q[((lookup_index * WAYS + way) * CONF_W) +: CONF_W] >= CONFIDENCE_THRESHOLD_VALUE) &&
          !predict_valid) begin
        predict_valid = 1'b1;
        predict_target =
          target_q[((lookup_index * WAYS + way) * ADDR_W) +: ADDR_W];
      end
      if (valid_q[train_index * WAYS + way] &&
          (tag_q[((train_index * WAYS + way) * TAG_W) +: TAG_W] == train_tag) &&
          (history_q[((train_index * WAYS + way) * PATH_HIST_W) +: PATH_HIST_W] ==
           train_meta_path_history) && !train_hit) begin
        train_hit = 1'b1;
        train_way = WAY_W'(way);
      end
      if (!valid_q[train_index * WAYS + way] && !invalid_way_found && !train_hit) begin
        invalid_way_found = 1'b1;
        train_way = WAY_W'(way);
      end
    end
    train_conf_index = (int'(train_index) * WAYS) + int'(train_way);
    train_conf_bit = train_conf_index * CONF_W;
    train_next_confidence = confidence_q[train_conf_bit +: CONF_W];
    if (!train_hit) begin
      train_next_confidence = CONF_ONE;
    end else if (target_q[(train_conf_index * ADDR_W) +: ADDR_W] == train_target) begin
      if (confidence_q[train_conf_bit +: CONF_W] != '1) begin
        train_next_confidence = confidence_q[train_conf_bit +: CONF_W] + CONF_ONE;
      end
    end else begin
      train_next_confidence = CONF_ONE;
    end
  end

  always_ff @(posedge clk or negedge rst_ni) begin
    if (!rst_ni) begin
      confidence_q <= '0;
      repl_q <= '0;
      valid_q <= '0;
      tag_q <= '0;
      history_q <= '0;
      target_q <= '0;
    end else if (flush_valid) begin
      repl_q <= '0;
      valid_q <= '0;
    end else if (train_valid && train_meta_valid) begin
      valid_q[train_conf_index] <= 1'b1;
      tag_q[(train_conf_index * TAG_W) +: TAG_W] <= train_tag;
      history_q[(train_conf_index * PATH_HIST_W) +: PATH_HIST_W] <=
        train_meta_path_history;
      repl_q[(train_index * WAY_W) +: WAY_W] <= train_way + WAY_W'(1);
      target_q[(train_conf_index * ADDR_W) +: ADDR_W] <= train_target;
      confidence_q[train_conf_bit +: CONF_W] <= train_next_confidence;
    end
  end

  always @(posedge clk or negedge rst_ni) begin
    if (rst_ni && train_valid) begin
      assert (train_meta_valid);
      assert ((train_meta_pc[0] == 1'b0) && (train_target[0] == 1'b0));
    end
  end
endmodule
