// SPDX-License-Identifier: Apache-2.0
module btb_tb;
  logic clk = 1'b0;
  logic rst_ni = 1'b0;
  logic [63:0] lookup_pc, lookup_target, update_pc, update_target;
  logic [1:0] lookup_kind, update_kind;
  logic lookup_hit, update_valid, flush_valid;
  int unsigned checks = 0;

  rv64_btb #(.SETS(4), .WAYS(2)) dut (.*);
  always #5 clk = ~clk;

  task automatic check(input logic condition, input string message);
    checks++;
    if (!condition) $fatal(1, "BTB check failed: %s", message);
  endtask
  task automatic update(input logic [63:0] pc, input logic [63:0] target, input logic [1:0] kind);
    @(negedge clk);
    update_valid = 1; update_pc = pc; update_target = target; update_kind = kind;
    @(posedge clk);
    @(negedge clk);
    update_valid = 0;
  endtask

  initial begin
    lookup_pc = '0; update_valid = 0; update_pc = '0; update_target = '0;
    update_kind = '0; flush_valid = 0;
    repeat (2) @(posedge clk);
    rst_ni = 1;
    @(negedge clk);
    lookup_pc = 64'h100;
    #1 check(!lookup_hit, "reset lookup misses");
    update(64'h100, 64'h800, 2'b01);
    #1 check(lookup_hit && lookup_target == 64'h800 && lookup_kind == 2'b01,
             "update creates matching target and kind");
    update(64'h100, 64'h900, 2'b10);
    #1 check(lookup_hit && lookup_target == 64'h900 && lookup_kind == 2'b10,
             "matching update replaces target");
    update(64'h110, 64'ha00, 2'b01);
    update(64'h120, 64'hb00, 2'b01);
    lookup_pc = 64'h100;
    #1 check(!lookup_hit, "round-robin replacement evicts oldest way");
    lookup_pc = 64'h110;
    #1 check(lookup_hit && lookup_target == 64'ha00, "other way survives replacement");
    @(negedge clk); flush_valid = 1; @(posedge clk); @(negedge clk); flush_valid = 0;
    #1 check(!lookup_hit, "flush invalidates all BTB entries");
    $display("PASS: %0d BTB checks", checks);
    $finish;
  end
endmodule
