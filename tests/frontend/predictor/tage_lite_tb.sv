// SPDX-License-Identifier: Apache-2.0
module tage_lite_tb;
  localparam int unsigned FETCH_W = 2;
  localparam int unsigned BASE_ENTRIES = 4;
  localparam int unsigned TAGGED_SETS = 4;
  localparam int unsigned TAGGED_WAYS = 2;
  localparam int unsigned HISTORY_W = 16;
  localparam int unsigned TAG_W = 8;
  localparam int unsigned BASE_INDEX_W = $clog2(BASE_ENTRIES);
  localparam int unsigned INDEX_W = $clog2(TAGGED_SETS);
  localparam int unsigned WAY_W = $clog2(TAGGED_WAYS);
  localparam logic [1:0] PROVIDER_BASE = 2'd0;
  localparam logic [1:0] PROVIDER_COMP0 = 2'd1;
  localparam logic [1:0] PROVIDER_COMP1 = 2'd2;

  logic clk;
  logic rst_ni;
  logic [FETCH_W-1:0][63:0] lookup_pc;
  logic [FETCH_W-1:0][HISTORY_W-1:0] lookup_history;
  logic [FETCH_W-1:0] lookup_prediction, lookup_alt_prediction;
  logic [FETCH_W-1:0][1:0] lookup_provider;
  logic [FETCH_W-1:0][BASE_INDEX_W-1:0] lookup_base_index;
  logic [FETCH_W-1:0][INDEX_W-1:0] lookup_comp0_index, lookup_comp1_index;
  logic [FETCH_W-1:0][TAG_W-1:0] lookup_comp0_tag, lookup_comp1_tag;
  logic [FETCH_W-1:0][WAY_W-1:0] lookup_provider_way;
  logic train_valid, train_meta_valid, train_taken;
  logic train_prediction, train_alt_prediction, flush_valid;
  logic [1:0] train_provider;
  logic [WAY_W-1:0] train_provider_way;
  logic [BASE_INDEX_W-1:0] train_base_index;
  logic [INDEX_W-1:0] train_comp0_index, train_comp1_index;
  logic [TAG_W-1:0] train_comp0_tag, train_comp1_tag;
  int unsigned checks;

  rv64_tage_lite #(
    .BASE_ENTRIES(BASE_ENTRIES), .TAGGED_SETS(TAGGED_SETS), .TAGGED_WAYS(TAGGED_WAYS),
    .HISTORY_W(HISTORY_W), .HIST0_LEN(4), .HIST1_LEN(12), .TAG_W(TAG_W)
  ) dut (.*);
  always #5 clk = ~clk;

  task automatic check(input logic condition, input string message);
    checks++;
    if (!condition) $fatal(1, "TAGE-lite check failed: %s", message);
  endtask

  task automatic retire_lookup(input logic taken);
    begin
      @(negedge clk);
      train_valid = 1'b1;
      train_taken = taken;
      train_prediction = lookup_prediction[0];
      train_alt_prediction = lookup_alt_prediction[0];
      train_provider = lookup_provider[0];
      train_provider_way = lookup_provider_way[0];
      train_base_index = lookup_base_index[0];
      train_comp0_index = lookup_comp0_index[0];
      train_comp1_index = lookup_comp1_index[0];
      train_comp0_tag = lookup_comp0_tag[0];
      train_comp1_tag = lookup_comp1_tag[0];
      @(posedge clk);
      @(negedge clk);
      train_valid = 1'b0;
    end
  endtask

  task automatic set_lookup(input logic [63:0] pc, input logic [HISTORY_W-1:0] history);
    begin
      @(negedge clk);
      lookup_pc[0] = pc;
      lookup_history[0] = history;
      lookup_pc[1] = pc + 64'd4;
      lookup_history[1] = history;
      #1;
    end
  endtask

  initial begin
    clk = 1'b0;
    rst_ni = 1'b0;
    checks = 0;
    lookup_pc = '0; lookup_history = '0; train_valid = 0;
    train_meta_valid = 1; train_taken = 0;
    train_prediction = 0; train_alt_prediction = 0; train_provider = '0;
    train_provider_way = '0; train_base_index = '0; train_comp0_index = '0;
    train_comp1_index = '0; train_comp0_tag = '0; train_comp1_tag = '0; flush_valid = 0;
    repeat (2) @(posedge clk);
    rst_ni = 1;

    set_lookup(64'h100, 16'h0000);
    check(!lookup_prediction[0] && lookup_provider[0] == PROVIDER_BASE,
          "cold predictor uses weak-not-taken bimodal base");
    check(lookup_provider[1] == PROVIDER_BASE, "second lookup lane is independently available");
    @(negedge clk);
    train_valid = 1'b1;
    train_meta_valid = 1'b0;
    train_taken = 1'b1;
    @(posedge clk);
    @(negedge clk);
    train_valid = 1'b0;
    train_meta_valid = 1'b1;
    check(dut.base_ctr_q[(lookup_base_index[0]*2) +: 2] == 2'b01,
          "invalid or squashed metadata cannot train predictor state");
    retire_lookup(1'b1);
    check(dut.base_ctr_q[(lookup_base_index[0]*2) +: 2] == 2'b10,
          "base counter trains toward taken");
    check(dut.valid0_q[lookup_comp0_index[0]*TAGGED_WAYS], "base mispredict allocates first tagged component");

    set_lookup(64'h100, 16'h0000);
    check(lookup_provider[0] == PROVIDER_COMP0 && lookup_prediction[0],
          "allocated tagged entry provides taken prediction");
    retire_lookup(1'b0);
    check(dut.valid1_q[lookup_comp1_index[0]*TAGGED_WAYS], "component-zero mispredict allocates longer component");

    set_lookup(64'h100, 16'h0000);
    check(lookup_provider[0] == PROVIDER_COMP1 && !lookup_prediction[0],
          "longest matching component has priority over shorter provider");

    // Save metadata, change the live lookup inputs, then train from the saved data.
    train_prediction = lookup_prediction[0]; train_alt_prediction = lookup_alt_prediction[0];
    train_provider = lookup_provider[0]; train_provider_way = lookup_provider_way[0];
    train_base_index = lookup_base_index[0]; train_comp0_index = lookup_comp0_index[0];
    train_comp1_index = lookup_comp1_index[0]; train_comp0_tag = lookup_comp0_tag[0];
    train_comp1_tag = lookup_comp1_tag[0];
    set_lookup(64'h1a0, 16'h00f3);
    @(negedge clk); train_valid = 1; train_taken = 1; @(posedge clk); @(negedge clk); train_valid = 0;
    check(dut.ctr1_q[((train_comp1_index*TAGGED_WAYS + train_provider_way)*2) +: 2] == 2'b10,
          "delayed retirement metadata updates original provider, not live lookup");

    set_lookup(64'h100, 16'h0000);
    repeat (3) retire_lookup(1'b1);
    check(dut.ctr1_q[((lookup_comp1_index[0]*TAGGED_WAYS +
                       lookup_provider_way[0])*2) +: 2] == 2'b11,
          "tagged provider counter saturates toward taken");
    repeat (5) retire_lookup(1'b0);
    check(dut.ctr1_q[((lookup_comp1_index[0]*TAGGED_WAYS +
                       lookup_provider_way[0])*2) +: 2] == 2'b00,
          "tagged provider counter saturates toward not-taken");

    // Repeatedly train one base entry to both saturation endpoints.
    set_lookup(64'h200, 16'h0000);
    repeat (5) retire_lookup(1'b1);
    check(dut.base_ctr_q[(lookup_base_index[0]*2) +: 2] == 2'b11,
          "taken base counter saturates");
    repeat (6) retire_lookup(1'b0);
    check(dut.base_ctr_q[(lookup_base_index[0]*2) +: 2] == 2'b00,
          "not-taken base counter saturates");

    // 0x110 aliases 0x100's indexed tables but has a different tag.
    set_lookup(64'h110, 16'h0000);
    check(lookup_provider[0] == PROVIDER_BASE, "tag mismatch rejects indexed alias");

    @(negedge clk); flush_valid = 1; @(posedge clk); @(negedge clk); flush_valid = 0;
    set_lookup(64'h100, 16'h0000);
    check(!lookup_prediction[0] && lookup_provider[0] == PROVIDER_BASE,
          "flush deterministically invalidates tags and resets base state");
    $display("PASS: %0d TAGE-lite checks", checks);
    $finish;
  end
endmodule
