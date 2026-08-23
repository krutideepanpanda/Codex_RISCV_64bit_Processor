// SPDX-License-Identifier: Apache-2.0
// Set-associative direct-target BTB in the VDD_CORE clock domain.
// Updates are accepted only from resolved, non-speculative control flow.
module rv64_btb #(
  parameter int unsigned SETS = 32,
  parameter int unsigned WAYS = 4,
  parameter int unsigned ADDR_W = 64,
  parameter int unsigned TARGET_KIND_W = 2,
  parameter int unsigned INDEX_W = (SETS > 1) ? $clog2(SETS) : 1,
  parameter int unsigned WAY_W = (WAYS > 1) ? $clog2(WAYS) : 1,
  parameter int unsigned TAG_W = (ADDR_W > INDEX_W + 2) ?
                                      ADDR_W - INDEX_W - 2 : 1
) (
  input  logic                       clk,
  input  logic                       rst_ni,
  input  logic [ADDR_W-1:0]          lookup_pc,
  output logic                       lookup_hit,
  output logic [ADDR_W-1:0]          lookup_target,
  output logic [TARGET_KIND_W-1:0]   lookup_kind,
  input  logic                       update_valid,
  input  logic [ADDR_W-1:0]          update_pc,
  input  logic [ADDR_W-1:0]          update_target,
  input  logic [TARGET_KIND_W-1:0]   update_kind,
  input  logic                       flush_valid
);
  logic [TAG_W-1:0] tag_q [0:SETS-1][0:WAYS-1];
  logic [ADDR_W-1:0] target_q [0:SETS-1][0:WAYS-1];
  logic [TARGET_KIND_W-1:0] kind_q [0:SETS-1][0:WAYS-1];
  logic valid_q [0:SETS-1][0:WAYS-1];
  logic [WAY_W-1:0] repl_q [0:SETS-1];
  logic [INDEX_W-1:0] lookup_index;
  logic [INDEX_W-1:0] update_index;
  logic [TAG_W-1:0] lookup_tag;
  logic [TAG_W-1:0] update_tag;
  logic [WAY_W-1:0] update_way;
  logic update_hit;
  logic invalid_way_found;
  integer set_i;
  integer way_i;

  initial begin
    assert (SETS >= 2);
    assert ((SETS & (SETS - 1)) == 0);
    assert (WAYS >= 2);
    assert ((WAYS & (WAYS - 1)) == 0);
    assert (ADDR_W > INDEX_W + 2);
    assert (TARGET_KIND_W > 0);
    assert (INDEX_W == $clog2(SETS));
    assert (WAY_W == $clog2(WAYS));
    assert (TAG_W == ADDR_W - INDEX_W - 2);
  end

  always_comb begin
    lookup_index = lookup_pc[INDEX_W+1:2];
    update_index = update_pc[INDEX_W+1:2];
    lookup_tag = lookup_pc[ADDR_W-1:INDEX_W+2];
    update_tag = update_pc[ADDR_W-1:INDEX_W+2];
    lookup_hit = 1'b0;
    lookup_target = '0;
    lookup_kind = '0;
    update_hit = 1'b0;
    update_way = repl_q[update_index];
    invalid_way_found = 1'b0;
    for (int unsigned way = 0; way < WAYS; way = way + 1) begin
      if (valid_q[lookup_index][way] && (tag_q[lookup_index][way] == lookup_tag) && !lookup_hit) begin
        lookup_hit = 1'b1;
        lookup_target = target_q[lookup_index][way];
        lookup_kind = kind_q[lookup_index][way];
      end
      if (valid_q[update_index][way] && (tag_q[update_index][way] == update_tag) && !update_hit) begin
        update_hit = 1'b1;
        update_way = WAY_W'(way);
      end
      if (!valid_q[update_index][way] && !invalid_way_found && !update_hit) begin
        invalid_way_found = 1'b1;
        update_way = WAY_W'(way);
      end
    end
  end

  always_ff @(posedge clk or negedge rst_ni) begin
    if (!rst_ni) begin
      for (set_i = 0; set_i < SETS; set_i = set_i + 1) begin
        repl_q[set_i] <= '0;
        for (way_i = 0; way_i < WAYS; way_i = way_i + 1) begin
          valid_q[set_i][way_i] <= 1'b0;
          tag_q[set_i][way_i] <= '0;
          target_q[set_i][way_i] <= '0;
          kind_q[set_i][way_i] <= '0;
        end
      end
    end else if (flush_valid) begin
      for (set_i = 0; set_i < SETS; set_i = set_i + 1) begin
        repl_q[set_i] <= '0;
        for (way_i = 0; way_i < WAYS; way_i = way_i + 1) begin
          valid_q[set_i][way_i] <= 1'b0;
        end
      end
    end else if (update_valid) begin
      valid_q[update_index][update_way] <= 1'b1;
      tag_q[update_index][update_way] <= update_tag;
      target_q[update_index][update_way] <= update_target;
      kind_q[update_index][update_way] <= update_kind;
      repl_q[update_index] <= update_way + WAY_W'(1);
    end
  end

  always @(posedge clk) begin
    if (rst_ni && update_valid) assert ((update_pc[0] == 1'b0) && (update_target[0] == 1'b0));
  end
endmodule
