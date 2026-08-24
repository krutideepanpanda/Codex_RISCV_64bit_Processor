// SPDX-License-Identifier: Apache-2.0
module spec_history_tb;
  localparam int unsigned HISTORY_W = 8;

  logic clk;
  logic rst_ni;
  logic [1:0] advance_valid;
  logic [1:0] advance_taken;
  logic recover_valid;
  logic [HISTORY_W-1:0] recover_history;
  logic recover_is_branch;
  logic recover_taken;
  logic flush_valid;
  logic [HISTORY_W-1:0] lane0_history;
  logic [HISTORY_W-1:0] lane1_history;
  logic [HISTORY_W-1:0] checkpoint_history;
  int unsigned checks;

  rv64_spec_history #(.HISTORY_W(HISTORY_W)) dut (
    .clk,
    .rst_ni,
    .advance_valid_i(advance_valid),
    .advance_taken_i(advance_taken),
    .recover_valid_i(recover_valid),
    .recover_history_i(recover_history),
    .recover_is_branch_i(recover_is_branch),
    .recover_taken_i(recover_taken),
    .flush_valid_i(flush_valid),
    .lane0_history_o(lane0_history),
    .lane1_history_o(lane1_history),
    .checkpoint_history_o(checkpoint_history)
  );

  always #5 clk = ~clk;

  task automatic step;
    begin
      @(posedge clk);
      #1;
    end
  endtask

  task automatic expect_history(
    input logic [HISTORY_W-1:0] expected,
    input string message
  );
    begin
      checks++;
      if (checkpoint_history !== expected)
        $fatal(1, "%s: expected=%02h actual=%02h",
               message, expected, checkpoint_history);
    end
  endtask

  initial begin
    clk = 1'b0;
    rst_ni = 1'b0;
    advance_valid = '0;
    advance_taken = '0;
    recover_valid = 1'b0;
    recover_history = '0;
    recover_is_branch = 1'b0;
    recover_taken = 1'b0;
    flush_valid = 1'b0;
    checks = 0;

    step();
    rst_ni = 1'b1;
    expect_history(8'h00, "reset");

    advance_valid = 2'b01;
    advance_taken = 2'b01;
    #1;
    checks++;
    if (lane0_history !== 8'h00 || lane1_history !== 8'h01)
      $fatal(1, "lane 1 must see lane 0 speculative outcome");
    step();
    expect_history(8'h01, "single lane advance");

    advance_valid = 2'b11;
    advance_taken = 2'b01; // oldest taken, younger not taken
    step();
    expect_history(8'h06, "dual ordered advance");

    advance_valid = 2'b10;
    advance_taken = 2'b10;
    step();
    expect_history(8'h0d, "sparse younger-lane advance");

    advance_valid = 2'b11;
    advance_taken = 2'b11;
    recover_valid = 1'b1;
    recover_history = 8'ha5;
    recover_is_branch = 1'b0;
    step();
    expect_history(8'ha5, "non-branch recovery restores exact checkpoint");

    recover_history = 8'h25;
    recover_is_branch = 1'b1;
    recover_taken = 1'b1;
    step();
    expect_history(8'h4b, "branch recovery appends resolved actual outcome");

    flush_valid = 1'b1;
    recover_history = 8'h5a;
    step();
    expect_history(8'h00, "flush overrides recovery");

    flush_valid = 1'b0;
    recover_valid = 1'b0;
    recover_is_branch = 1'b0;
    advance_valid = '0;
    step();
    expect_history(8'h00, "idle holds history");

    $display("PASS: %0d speculative-history checks", checks);
    $finish;
  end
endmodule
