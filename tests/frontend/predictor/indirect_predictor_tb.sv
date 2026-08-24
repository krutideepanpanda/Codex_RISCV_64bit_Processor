// SPDX-License-Identifier: Apache-2.0
module indirect_predictor_tb;
  localparam int unsigned PATH_HIST_W = 4;
  logic clk;
  logic rst_ni;
  logic lookup_valid, predict_valid, lookup_meta_valid, train_valid, train_meta_valid, flush_valid;
  logic [63:0] lookup_pc, predict_target, lookup_meta_pc, train_meta_pc, train_target;
  logic [PATH_HIST_W-1:0] lookup_path_history, lookup_meta_path_history, train_meta_path_history;
  int unsigned checks;

  rv64_indirect_predictor #(.SETS(4), .WAYS(2), .PATH_HIST_W(PATH_HIST_W)) dut (.*);
  always #5 clk = ~clk;

  task automatic check(input logic condition, input string message);
    checks++;
    if (!condition) $fatal(1, "indirect predictor check failed: %s", message);
  endtask

  task automatic train_from_lookup(input logic [63:0] pc, input logic [PATH_HIST_W-1:0] history,
                                   input logic [63:0] target);
    @(negedge clk);
    lookup_valid = 1'b1; lookup_pc = pc; lookup_path_history = history;
    #1;
    check(lookup_meta_valid && lookup_meta_pc == pc && lookup_meta_path_history == history,
          "lookup metadata preserves delayed training context");
    train_meta_pc = lookup_meta_pc;
    train_meta_path_history = lookup_meta_path_history;
    @(negedge clk);
    train_valid = 1'b1; train_meta_valid = 1'b1; train_target = target;
    @(posedge clk);
    @(negedge clk);
    train_valid = 1'b0; train_meta_valid = 1'b0;
  endtask

  task automatic lookup(input logic [63:0] pc, input logic [PATH_HIST_W-1:0] history);
    @(negedge clk);
    lookup_valid = 1'b1; lookup_pc = pc; lookup_path_history = history;
    #1;
  endtask

  initial begin
    clk = 1'b0;
    rst_ni = 1'b0;
    checks = 0;
    lookup_valid = 0; lookup_pc = '0; lookup_path_history = '0;
    train_valid = 0; train_meta_valid = 0; train_meta_pc = '0;
    train_meta_path_history = '0; train_target = '0; flush_valid = 0;
    repeat (2) @(posedge clk);
    rst_ni = 1;

    lookup(64'h100, 4'h1);
    check(!predict_valid, "cold entry misses");
    train_from_lookup(64'h100, 4'h1, 64'h800);
    lookup(64'h100, 4'h1);
    check(!predict_valid, "one observation is below confidence gate");
    train_from_lookup(64'h100, 4'h1, 64'h800);
    lookup(64'h100, 4'h1);
    check(predict_valid && predict_target == 64'h800, "second matching retirement acquires confidence");
    train_from_lookup(64'h100, 4'h1, 64'h900);
    lookup(64'h100, 4'h1);
    check(!predict_valid, "conflicting target loses confidence");
    train_from_lookup(64'h100, 4'h1, 64'h900);
    lookup(64'h100, 4'h1);
    check(predict_valid && predict_target == 64'h900, "new target reacquires confidence");

    lookup(64'h110, 4'h1);
    check(!predict_valid, "same set but distinct PC tag rejects alias");
    lookup(64'h100, 4'h2);
    check(!predict_valid, "same PC with distinct path history rejects alias");

    train_from_lookup(64'h200, 4'h0, 64'ha00);
    train_from_lookup(64'h210, 4'h0, 64'hb00);
    train_from_lookup(64'h220, 4'h0, 64'hc00);
    lookup(64'h200, 4'h0);
    check(!predict_valid, "deterministic replacement evicts oldest same-set entry");
    train_from_lookup(64'h210, 4'h0, 64'hb00);
    lookup(64'h210, 4'h0);
    check(predict_valid && predict_target == 64'hb00, "surviving entry trains through delayed metadata");

    @(negedge clk); flush_valid = 1'b1; @(posedge clk); @(negedge clk); flush_valid = 1'b0;
    lookup(64'h210, 4'h0);
    check(!predict_valid, "flush deterministically invalidates predictor");
    $display("PASS: %0d indirect predictor checks", checks);
    $finish;
  end
endmodule
