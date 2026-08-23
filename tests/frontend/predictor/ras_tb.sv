// SPDX-License-Identifier: Apache-2.0
module ras_tb;
  localparam int unsigned DEPTH = 4;
  localparam int unsigned SP_W = $clog2(DEPTH);
  localparam int unsigned COUNT_W = $clog2(DEPTH + 1);
  localparam int unsigned SNAPSHOT_W = DEPTH * 64;
  logic clk = 1'b0;
  logic rst_ni = 1'b0;
  logic push_valid, pop_valid, recover_valid, flush_valid;
  logic [63:0] push_addr, top_addr;
  logic top_valid;
  logic [SP_W-1:0] checkpoint_sp_o, recover_sp;
  logic [COUNT_W-1:0] checkpoint_count_o, recover_count;
  logic [SNAPSHOT_W-1:0] checkpoint_entries_o, recover_entries;
  int unsigned checks = 0;

  rv64_ras #(.DEPTH(DEPTH)) dut (.*);
  always #5 clk = ~clk;

  task automatic check(input logic condition, input string message);
    checks++;
    if (!condition) $fatal(1, "RAS check failed: %s", message);
  endtask
  task automatic idle_cycle;
    @(negedge clk);
    push_valid = 0; pop_valid = 0; recover_valid = 0; flush_valid = 0;
    @(posedge clk);
  endtask

  initial begin
    push_valid = 0; pop_valid = 0; recover_valid = 0; flush_valid = 0;
    push_addr = '0; recover_sp = '0; recover_count = '0; recover_entries = '0;
    repeat (2) @(posedge clk);
    rst_ni = 1;
    idle_cycle();
    check(!top_valid, "reset leaves stack empty");
    @(negedge clk); push_valid = 1; push_addr = 64'h1004; @(posedge clk); idle_cycle();
    @(negedge clk); push_valid = 1; push_addr = 64'h2008; @(posedge clk); idle_cycle();
    check(top_valid && top_addr == 64'h2008, "last pushed address is top");
    recover_sp = checkpoint_sp_o; recover_count = checkpoint_count_o;
    recover_entries = checkpoint_entries_o;
    @(negedge clk); push_valid = 1; push_addr = 64'h300c; @(posedge clk); idle_cycle();
    check(top_addr == 64'h300c, "speculative push visible before recovery");
    @(negedge clk); recover_valid = 1; @(posedge clk); idle_cycle();
    check(top_valid && top_addr == 64'h2008, "recovery restores checkpoint top");
    recover_sp = checkpoint_sp_o; recover_count = checkpoint_count_o;
    recover_entries = checkpoint_entries_o;
    @(negedge clk); pop_valid = 1; @(posedge clk); idle_cycle();
    @(negedge clk); push_valid = 1; push_addr = 64'hdeadc0de; @(posedge clk); idle_cycle();
    check(top_addr == 64'hdeadc0de, "speculative push overwrites popped slot");
    @(negedge clk); recover_valid = 1; @(posedge clk); idle_cycle();
    check(top_valid && top_addr == 64'h2008,
          "full-state recovery repairs a destructively overwritten slot");
    @(negedge clk); pop_valid = 1; @(posedge clk); idle_cycle();
    check(top_valid && top_addr == 64'h1004, "pop reveals prior address");
    @(negedge clk); push_valid = 1; push_addr = 64'h2010; @(posedge clk); idle_cycle();
    @(negedge clk); push_valid = 1; push_addr = 64'h3010; @(posedge clk); idle_cycle();
    @(negedge clk); push_valid = 1; push_addr = 64'h4010; @(posedge clk); idle_cycle();
    check(checkpoint_count_o == COUNT_W'(DEPTH), "stack reaches full depth");
    @(negedge clk);
    push_valid = 1; pop_valid = 1; push_addr = 64'h500c;
    @(posedge clk); idle_cycle();
    check(checkpoint_count_o == COUNT_W'(DEPTH) && top_addr == 64'h500c,
          "simultaneous return/call replaces top at full depth");
    @(negedge clk); flush_valid = 1; @(posedge clk); idle_cycle();
    check(!top_valid, "flush empties stack");
    $display("PASS: %0d RAS checks", checks);
    $finish;
  end
endmodule
