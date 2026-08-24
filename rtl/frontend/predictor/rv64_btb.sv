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
  logic [SETS*WAYS*TAG_W-1:0] tag_q;
  logic [SETS*WAYS*ADDR_W-1:0] target_q;
  logic [SETS*WAYS*TARGET_KIND_W-1:0] kind_q;
  logic [SETS*WAYS-1:0] valid_q;
  logic [SETS*WAY_W-1:0] repl_q;
  logic [INDEX_W-1:0] lookup_index;
  logic [INDEX_W-1:0] update_index;
  logic [TAG_W-1:0] lookup_tag;
  logic [TAG_W-1:0] update_tag;
  logic [WAY_W-1:0] update_way;
  logic update_hit;
  logic invalid_way_found;

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
    update_way = repl_q[(update_index * WAY_W) +: WAY_W];
    invalid_way_found = 1'b0;
    for (int unsigned way = 0; way < WAYS; way = way + 1) begin
      if (valid_q[lookup_index * WAYS + way] &&
          (tag_q[((lookup_index * WAYS + way) * TAG_W) +: TAG_W] == lookup_tag) &&
          !lookup_hit) begin
        lookup_hit = 1'b1;
        lookup_target =
          target_q[((lookup_index * WAYS + way) * ADDR_W) +: ADDR_W];
        lookup_kind =
          kind_q[((lookup_index * WAYS + way) * TARGET_KIND_W) +: TARGET_KIND_W];
      end
      if (valid_q[update_index * WAYS + way] &&
          (tag_q[((update_index * WAYS + way) * TAG_W) +: TAG_W] == update_tag) &&
          !update_hit) begin
        update_hit = 1'b1;
        update_way = WAY_W'(way);
      end
      if (!valid_q[update_index * WAYS + way] &&
          !invalid_way_found && !update_hit) begin
        invalid_way_found = 1'b1;
        update_way = WAY_W'(way);
      end
    end
  end

  always_ff @(posedge clk or negedge rst_ni) begin
    if (!rst_ni) begin
      repl_q <= '0;
      valid_q <= '0;
      tag_q <= '0;
      target_q <= '0;
      kind_q <= '0;
    end else if (flush_valid) begin
      repl_q <= '0;
      valid_q <= '0;
    end else if (update_valid) begin
      valid_q[int'(update_index) * WAYS + int'(update_way)] <= 1'b1;
      tag_q[(((int'(update_index) * WAYS) + int'(update_way)) * TAG_W)
            +: TAG_W] <=
        update_tag;
      target_q[(((int'(update_index) * WAYS) + int'(update_way)) * ADDR_W)
               +: ADDR_W] <=
        update_target;
      kind_q[(((int'(update_index) * WAYS) + int'(update_way)) * TARGET_KIND_W)
             +: TARGET_KIND_W] <= update_kind;
      repl_q[(int'(update_index) * WAY_W) +: WAY_W] <=
        update_way + WAY_W'(1);
    end
  end

  always @(posedge clk) begin
    if (rst_ni && update_valid) assert ((update_pc[0] == 1'b0) && (update_target[0] == 1'b0));
  end
endmodule
