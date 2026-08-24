// SPDX-License-Identifier: Apache-2.0
// Compact TAGE-style direction predictor in the VDD_CORE clock domain.
// Global history is deliberately supplied by fetch/recovery logic.  That owner
// checkpoints and restores speculative history; this block only stores tables.
module rv64_tage_lite #(
  parameter int unsigned FETCH_W = 2,
  parameter int unsigned ADDR_W = 64,
  parameter int unsigned HISTORY_W = 64,
  parameter int unsigned HIST0_LEN = 12,
  parameter int unsigned HIST1_LEN = 40,
  parameter int unsigned BASE_ENTRIES = 256,
  parameter int unsigned TAGGED_SETS = 128,
  parameter int unsigned TAGGED_WAYS = 2,
  parameter int unsigned TAG_W = 10,
  parameter int unsigned BASE_INDEX_W = (BASE_ENTRIES > 1) ? $clog2(BASE_ENTRIES) : 1,
  parameter int unsigned INDEX_W = (TAGGED_SETS > 1) ? $clog2(TAGGED_SETS) : 1,
  parameter int unsigned WAY_W = (TAGGED_WAYS > 1) ? $clog2(TAGGED_WAYS) : 1
) (
  input  logic                                            clk,
  input  logic                                            rst_ni,
  input  logic [FETCH_W-1:0][ADDR_W-1:0]                  lookup_pc,
  input  logic [FETCH_W-1:0][HISTORY_W-1:0]               lookup_history,
  output logic [FETCH_W-1:0]                              lookup_prediction,
  output logic [FETCH_W-1:0][1:0]                         lookup_provider,
  output logic [FETCH_W-1:0]                              lookup_alt_prediction,
  output logic [FETCH_W-1:0][BASE_INDEX_W-1:0]            lookup_base_index,
  output logic [FETCH_W-1:0][INDEX_W-1:0]                 lookup_comp0_index,
  output logic [FETCH_W-1:0][INDEX_W-1:0]                 lookup_comp1_index,
  output logic [FETCH_W-1:0][TAG_W-1:0]                   lookup_comp0_tag,
  output logic [FETCH_W-1:0][TAG_W-1:0]                   lookup_comp1_tag,
  output logic [FETCH_W-1:0][WAY_W-1:0]                   lookup_provider_way,
  input  logic                                            train_valid,
  input  logic                                            train_meta_valid,
  input  logic                                            train_taken,
  input  logic                                            train_prediction,
  input  logic                                            train_alt_prediction,
  input  logic [1:0]                                      train_provider,
  input  logic [WAY_W-1:0]                                train_provider_way,
  input  logic [BASE_INDEX_W-1:0]                         train_base_index,
  input  logic [INDEX_W-1:0]                              train_comp0_index,
  input  logic [INDEX_W-1:0]                              train_comp1_index,
  input  logic [TAG_W-1:0]                                train_comp0_tag,
  input  logic [TAG_W-1:0]                                train_comp1_tag,
  input  logic                                            flush_valid
);
  localparam logic [1:0] PROVIDER_BASE  = 2'd0;
  localparam logic [1:0] PROVIDER_COMP0 = 2'd1;
  localparam logic [1:0] PROVIDER_COMP1 = 2'd2;

  localparam int unsigned TAGGED_ENTRIES = TAGGED_SETS * TAGGED_WAYS;
  // Flat packed tables produce deterministic lowering in conservative Yosys.
  // SRAM mapping is deliberately deferred to the SRAM qualification gate.
  logic [BASE_ENTRIES*2-1:0] base_ctr_q;
  logic [TAGGED_ENTRIES*2-1:0] ctr0_q;
  logic [TAGGED_ENTRIES*2-1:0] ctr1_q;
  logic [TAGGED_ENTRIES*TAG_W-1:0] tag0_q;
  logic [TAGGED_ENTRIES*TAG_W-1:0] tag1_q;
  logic [TAGGED_ENTRIES-1:0] valid0_q;
  logic [TAGGED_ENTRIES-1:0] valid1_q;
  logic [TAGGED_ENTRIES-1:0] useful0_q;
  logic [TAGGED_ENTRIES-1:0] useful1_q;
  logic [TAGGED_SETS*WAY_W-1:0] repl0_q;
  logic [TAGGED_SETS*WAY_W-1:0] repl1_q;
  logic train_mispredict;
  logic provider0_live;
  logic provider1_live;
  logic [WAY_W-1:0] alloc_way;
  logic alloc_found;
  integer way_i;
  integer alloc_i;

  function automatic logic [INDEX_W-1:0] fold_index(
      input logic [HISTORY_W-1:0] history,
      input int unsigned history_len);
    logic [INDEX_W-1:0] folded;
    begin
      folded = '0;
      for (int unsigned bit_i = 0; bit_i < HISTORY_W; bit_i = bit_i + 1) begin
        if (bit_i < history_len) folded[bit_i % INDEX_W] = folded[bit_i % INDEX_W] ^ history[bit_i];
      end
      fold_index = folded;
    end
  endfunction

  function automatic logic [TAG_W-1:0] fold_tag(
      input logic [HISTORY_W-1:0] history,
      input int unsigned history_len);
    logic [TAG_W-1:0] folded;
    begin
      folded = '0;
      for (int unsigned bit_i = 0; bit_i < HISTORY_W; bit_i = bit_i + 1) begin
        if (bit_i < history_len) folded[bit_i % TAG_W] = folded[bit_i % TAG_W] ^ history[bit_i];
      end
      fold_tag = folded;
    end
  endfunction

  function automatic logic [1:0] sat_update(input logic [1:0] counter, input logic taken);
    begin
      if (taken) begin
        sat_update = (counter == 2'b11) ? counter : counter + 2'b01;
      end else begin
        sat_update = (counter == 2'b00) ? counter : counter - 2'b01;
      end
    end
  endfunction

  initial begin
    assert (FETCH_W == 2);
    assert (ADDR_W > BASE_INDEX_W + 2);
    assert (ADDR_W > INDEX_W + 2);
    assert (HISTORY_W >= HIST1_LEN);
    assert (HIST1_LEN > HIST0_LEN);
    assert (HIST0_LEN > 0);
    assert (BASE_ENTRIES >= 2 && ((BASE_ENTRIES & (BASE_ENTRIES - 1)) == 0));
    assert (TAGGED_SETS >= 2 && ((TAGGED_SETS & (TAGGED_SETS - 1)) == 0));
    assert (TAGGED_WAYS >= 2 && ((TAGGED_WAYS & (TAGGED_WAYS - 1)) == 0));
    assert (TAG_W > 0);
    assert (BASE_INDEX_W == $clog2(BASE_ENTRIES));
    assert (INDEX_W == $clog2(TAGGED_SETS));
    assert (WAY_W == $clog2(TAGGED_WAYS));
  end

  always_comb begin
    for (int unsigned lane = 0; lane < FETCH_W; lane = lane + 1) begin
      lookup_base_index[lane] = lookup_pc[lane][BASE_INDEX_W+1:2];
      lookup_comp0_index[lane] = lookup_pc[lane][INDEX_W+1:2] ^ fold_index(lookup_history[lane], HIST0_LEN);
      lookup_comp1_index[lane] = lookup_pc[lane][INDEX_W+1:2] ^ fold_index(lookup_history[lane], HIST1_LEN);
      lookup_comp0_tag[lane] = TAG_W'(lookup_pc[lane] >> (INDEX_W + 2)) ^ fold_tag(lookup_history[lane], HIST0_LEN);
      lookup_comp1_tag[lane] = TAG_W'(lookup_pc[lane] >> (INDEX_W + 2)) ^ fold_tag(lookup_history[lane], HIST1_LEN);
      lookup_prediction[lane] =
        base_ctr_q[(lookup_base_index[lane] * 2) + 1];
      lookup_alt_prediction[lane] = lookup_prediction[lane];
      lookup_provider[lane] = PROVIDER_BASE;
      lookup_provider_way[lane] = '0;
      // Scan each component separately so a component-0 hit in a later way
      // can never override a component-1 hit in an earlier way.
      for (int unsigned way = 0; way < TAGGED_WAYS; way = way + 1) begin
        if (valid0_q[lookup_comp0_index[lane]*TAGGED_WAYS + way] &&
            (tag0_q[((lookup_comp0_index[lane]*TAGGED_WAYS + way) * TAG_W) +: TAG_W] ==
             lookup_comp0_tag[lane])) begin
          lookup_alt_prediction[lane] =
            base_ctr_q[(lookup_base_index[lane] * 2) + 1];
          lookup_prediction[lane] =
            ctr0_q[((lookup_comp0_index[lane]*TAGGED_WAYS + way) * 2) + 1];
          lookup_provider[lane] = PROVIDER_COMP0;
          lookup_provider_way[lane] = WAY_W'(way);
        end
      end
      for (int unsigned way = 0; way < TAGGED_WAYS; way = way + 1) begin
        if (valid1_q[lookup_comp1_index[lane]*TAGGED_WAYS + way] &&
            (tag1_q[((lookup_comp1_index[lane]*TAGGED_WAYS + way) * TAG_W) +: TAG_W] ==
             lookup_comp1_tag[lane])) begin
          lookup_alt_prediction[lane] = (lookup_provider[lane] == PROVIDER_COMP0) ?
              lookup_prediction[lane] :
              base_ctr_q[(lookup_base_index[lane] * 2) + 1];
          lookup_prediction[lane] =
            ctr1_q[((lookup_comp1_index[lane]*TAGGED_WAYS + way) * 2) + 1];
          lookup_provider[lane] = PROVIDER_COMP1;
          lookup_provider_way[lane] = WAY_W'(way);
        end
      end
    end

    train_mispredict = train_prediction != train_taken;
    alloc_i = 0;
    provider0_live = valid0_q[train_comp0_index*TAGGED_WAYS + train_provider_way] &&
        (tag0_q[((train_comp0_index*TAGGED_WAYS + train_provider_way) * TAG_W) +: TAG_W] ==
         train_comp0_tag);
    provider1_live = valid1_q[train_comp1_index*TAGGED_WAYS + train_provider_way] &&
        (tag1_q[((train_comp1_index*TAGGED_WAYS + train_provider_way) * TAG_W) +: TAG_W] ==
         train_comp1_tag);
    alloc_way = '0;
    alloc_found = 1'b0;
    if (train_provider == PROVIDER_BASE) begin
      for (alloc_i = 0; alloc_i < TAGGED_WAYS; alloc_i = alloc_i + 1) begin
        if (!valid0_q[train_comp0_index*TAGGED_WAYS + alloc_i] && !alloc_found) begin
          alloc_way = WAY_W'(alloc_i);
          alloc_found = 1'b1;
        end else if (!useful0_q[train_comp0_index*TAGGED_WAYS + alloc_i] && !alloc_found) begin
          alloc_way = WAY_W'(alloc_i);
          alloc_found = 1'b1;
        end
      end
      if (!alloc_found)
        alloc_way = repl0_q[(train_comp0_index * WAY_W) +: WAY_W];
    end else if (train_provider == PROVIDER_COMP0) begin
      for (alloc_i = 0; alloc_i < TAGGED_WAYS; alloc_i = alloc_i + 1) begin
        if (!valid1_q[train_comp1_index*TAGGED_WAYS + alloc_i] && !alloc_found) begin
          alloc_way = WAY_W'(alloc_i);
          alloc_found = 1'b1;
        end else if (!useful1_q[train_comp1_index*TAGGED_WAYS + alloc_i] && !alloc_found) begin
          alloc_way = WAY_W'(alloc_i);
          alloc_found = 1'b1;
        end
      end
      if (!alloc_found)
        alloc_way = repl1_q[(train_comp1_index * WAY_W) +: WAY_W];
    end
  end

  always_ff @(posedge clk or negedge rst_ni) begin
    if (!rst_ni) begin
      base_ctr_q <= {BASE_ENTRIES{2'b01}};
      repl0_q <= '0;
      repl1_q <= '0;
      valid0_q <= '0;
      valid1_q <= '0;
      useful0_q <= '0;
      useful1_q <= '0;
      ctr0_q <= {TAGGED_ENTRIES{2'b01}};
      ctr1_q <= {TAGGED_ENTRIES{2'b01}};
      tag0_q <= '0;
      tag1_q <= '0;
    end else if (flush_valid) begin
      base_ctr_q <= {BASE_ENTRIES{2'b01}};
      repl0_q <= '0;
      repl1_q <= '0;
      valid0_q <= '0;
      valid1_q <= '0;
      useful0_q <= '0;
      useful1_q <= '0;
      ctr0_q <= {TAGGED_ENTRIES{2'b01}};
      ctr1_q <= {TAGGED_ENTRIES{2'b01}};
      tag0_q <= '0;
      tag1_q <= '0;
    end else if (train_valid && train_meta_valid) begin
      base_ctr_q[(train_base_index * 2) +: 2] <=
        sat_update(base_ctr_q[(train_base_index * 2) +: 2], train_taken);
      if ((train_provider == PROVIDER_COMP0) && provider0_live) begin
        ctr0_q[((train_comp0_index*TAGGED_WAYS + train_provider_way) * 2) +: 2] <=
            sat_update(
              ctr0_q[((train_comp0_index*TAGGED_WAYS + train_provider_way) * 2) +: 2],
              train_taken);
        if (train_prediction != train_alt_prediction) useful0_q[train_comp0_index*TAGGED_WAYS + train_provider_way] <= train_prediction == train_taken;
      end
      if ((train_provider == PROVIDER_COMP1) && provider1_live) begin
        ctr1_q[((train_comp1_index*TAGGED_WAYS + train_provider_way) * 2) +: 2] <=
            sat_update(
              ctr1_q[((train_comp1_index*TAGGED_WAYS + train_provider_way) * 2) +: 2],
              train_taken);
        if (train_prediction != train_alt_prediction) useful1_q[train_comp1_index*TAGGED_WAYS + train_provider_way] <= train_prediction == train_taken;
      end
      if (train_mispredict && (train_provider == PROVIDER_BASE)) begin
        if (alloc_found || !useful0_q[train_comp0_index*TAGGED_WAYS + alloc_way]) begin
          valid0_q[train_comp0_index*TAGGED_WAYS + alloc_way] <= 1'b1;
          useful0_q[train_comp0_index*TAGGED_WAYS + alloc_way] <= 1'b0;
          tag0_q[((train_comp0_index*TAGGED_WAYS + alloc_way) * TAG_W) +: TAG_W] <=
            train_comp0_tag;
          ctr0_q[((train_comp0_index*TAGGED_WAYS + alloc_way) * 2) +: 2] <=
            train_taken ? 2'b10 : 2'b01;
          repl0_q[(train_comp0_index * WAY_W) +: WAY_W] <=
            alloc_way + WAY_W'(1);
        end else begin
          for (way_i = 0; way_i < TAGGED_WAYS; way_i = way_i + 1) useful0_q[train_comp0_index*TAGGED_WAYS + way_i] <= 1'b0;
        end
      end else if (train_mispredict && (train_provider == PROVIDER_COMP0)) begin
        if (alloc_found || !useful1_q[train_comp1_index*TAGGED_WAYS + alloc_way]) begin
          valid1_q[train_comp1_index*TAGGED_WAYS + alloc_way] <= 1'b1;
          useful1_q[train_comp1_index*TAGGED_WAYS + alloc_way] <= 1'b0;
          tag1_q[((train_comp1_index*TAGGED_WAYS + alloc_way) * TAG_W) +: TAG_W] <=
            train_comp1_tag;
          ctr1_q[((train_comp1_index*TAGGED_WAYS + alloc_way) * 2) +: 2] <=
            train_taken ? 2'b10 : 2'b01;
          repl1_q[(train_comp1_index * WAY_W) +: WAY_W] <=
            alloc_way + WAY_W'(1);
        end else begin
          for (way_i = 0; way_i < TAGGED_WAYS; way_i = way_i + 1) useful1_q[train_comp1_index*TAGGED_WAYS + way_i] <= 1'b0;
        end
      end
    end
  end

  always @(posedge clk) begin
    if (rst_ni && train_valid && train_meta_valid) begin
      assert (train_provider <= PROVIDER_COMP1);
      assert (train_provider != PROVIDER_BASE || train_provider_way == '0);
    end
  end
endmodule
