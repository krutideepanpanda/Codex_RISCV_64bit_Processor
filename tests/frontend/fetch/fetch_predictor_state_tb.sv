// SPDX-License-Identifier: Apache-2.0
// CORE-001 / frontend-001c-b integration checks for predictor state that must
// survive speculation, backpressure, delayed retirement, and recovery.
module fetch_predictor_state_tb;
  localparam int unsigned WINDOW_BYTES = 32;

  logic clk_i;
  logic rst_ni;
  logic fetch_enable_i;
  logic flush_valid_i;
  logic [63:0] flush_pc_i;
  logic redirect_valid_i;
  logic [63:0] redirect_pc_i;
  logic redirect_is_branch_i;
  logic redirect_taken_i;
  logic [63:0] redirect_history_i;
  logic [3:0] redirect_ras_sp_i;
  logic [4:0] redirect_ras_count_i;
  logic [1023:0] redirect_ras_entries_i;
  logic request_valid_o;
  logic request_ready_i;
  logic [63:0] request_base_pc_o;
  logic response_valid_i;
  logic response_ready_o;
  logic [7:0] response_data_i [WINDOW_BYTES];
  logic response_valid_bytes_i [WINDOW_BYTES];
  logic response_fault_i [WINDOW_BYTES];
  logic [1:0] packet_valid_o;
  logic packet_ready_i;
  logic [1:0][63:0] packet_pc_o;
  logic [1:0][31:0] packet_instruction_o;
  logic [1:0][31:0] packet_raw_instruction_o;
  logic [1:0] packet_compressed_o;
  logic [1:0] packet_illegal_compressed_o;
  logic [1:0] packet_fetch_fault_o;
  logic [1:0] packet_pred_taken_o;
  logic [1:0][63:0] packet_pred_target_o;
  logic [1:0][1:0] packet_pred_kind_o;
  logic [1:0][63:0] packet_history_o;
  logic [1:0][3:0] packet_ras_sp_o;
  logic [1:0][4:0] packet_ras_count_o;
  logic [1:0][1023:0] packet_ras_entries_o;
  logic [1:0] packet_tage_prediction_o;
  logic [1:0] packet_tage_alt_prediction_o;
  logic [1:0][1:0] packet_tage_provider_o;
  logic [1:0] packet_tage_provider_way_o;
  logic [1:0][7:0] packet_tage_base_index_o;
  logic [1:0][6:0] packet_tage_comp0_index_o;
  logic [1:0][6:0] packet_tage_comp1_index_o;
  logic [1:0][9:0] packet_tage_comp0_tag_o;
  logic [1:0][9:0] packet_tage_comp1_tag_o;
  logic packet_indirect_meta_valid_o;
  logic [63:0] packet_indirect_meta_pc_o;
  logic [7:0] packet_indirect_meta_history_o;
  logic retire_btb_valid_i;
  logic [63:0] retire_btb_pc_i;
  logic [63:0] retire_btb_target_i;
  logic [1:0] retire_btb_kind_i;
  logic retire_tage_valid_i;
  logic retire_tage_taken_i;
  logic [7:0] retire_tage_base_index_i;
  logic [6:0] retire_tage_comp0_index_i;
  logic [6:0] retire_tage_comp1_index_i;
  logic [9:0] retire_tage_comp0_tag_i;
  logic [9:0] retire_tage_comp1_tag_i;
  logic [1:0] retire_tage_provider_i;
  logic retire_tage_provider_way_i;
  logic retire_tage_meta_valid_i;
  logic retire_tage_prediction_i;
  logic retire_tage_alt_prediction_i;
  logic retire_indirect_valid_i;
  logic [63:0] retire_indirect_pc_i;
  logic [7:0] retire_indirect_history_i;
  logic [63:0] retire_indirect_target_i;
  logic retire_indirect_meta_valid_i;

  logic [63:0] saved_indirect_pc;
  logic [7:0] saved_indirect_history;
  logic [3:0] saved_ras_sp;
  logic [4:0] saved_ras_count;
  logic [1023:0] saved_ras_entries;
  logic [3:0] post_coroutine_ras_sp;
  logic [4:0] post_coroutine_ras_count;
  logic [1023:0] post_coroutine_ras_entries;
  int unsigned checks;

  rv64_fetch_predictor dut (.*);

  always #5 clk_i = ~clk_i;

  task automatic check(input logic condition, input string message);
    begin
      checks++;
      if (!condition)
        $fatal(1, "fetch predictor state check %0d failed: %s", checks,
               message);
    end
  endtask

  task automatic clear_response;
    begin
      for (int unsigned byte_index = 0; byte_index < WINDOW_BYTES;
           byte_index++) begin
        response_data_i[byte_index] = 8'b0;
        response_valid_bytes_i[byte_index] = 1'b1;
        response_fault_i[byte_index] = 1'b0;
      end
    end
  endtask

  task automatic put_word(input int unsigned byte_offset,
                          input logic [31:0] instruction);
    begin
      response_data_i[byte_offset] = instruction[7:0];
      response_data_i[byte_offset + 1] = instruction[15:8];
      response_data_i[byte_offset + 2] = instruction[23:16];
      response_data_i[byte_offset + 3] = instruction[31:24];
    end
  endtask

  task automatic put_half(input int unsigned byte_offset,
                          input logic [15:0] instruction);
    begin
      response_data_i[byte_offset] = instruction[7:0];
      response_data_i[byte_offset + 1] = instruction[15:8];
    end
  endtask

  task automatic redirect_with_state(
      input logic [63:0] pc,
      input logic [63:0] history,
      input logic [3:0] ras_sp,
      input logic [4:0] ras_count,
      input logic [1023:0] ras_entries,
      input logic is_branch,
      input logic taken);
    begin
      @(negedge clk_i);
      redirect_pc_i = pc;
      redirect_history_i = history;
      redirect_ras_sp_i = ras_sp;
      redirect_ras_count_i = ras_count;
      redirect_ras_entries_i = ras_entries;
      redirect_is_branch_i = is_branch;
      redirect_taken_i = taken;
      redirect_valid_i = 1'b1;
      @(posedge clk_i);
      @(negedge clk_i);
      redirect_valid_i = 1'b0;
      redirect_is_branch_i = 1'b0;
      redirect_taken_i = 1'b0;
    end
  endtask

  task automatic redirect_preserving_state(input logic [63:0] pc);
    logic [63:0] history;
    logic [3:0] ras_sp;
    logic [4:0] ras_count;
    logic [1023:0] ras_entries;
    begin
      history = packet_history_o[0];
      ras_sp = packet_ras_sp_o[0];
      ras_count = packet_ras_count_o[0];
      ras_entries = packet_ras_entries_o[0];
      redirect_with_state(pc, history, ras_sp, ras_count, ras_entries,
                          1'b0, 1'b0);
    end
  endtask

  task automatic accept_request(input logic [63:0] expected_base);
    begin
      @(negedge clk_i);
      check(request_valid_o, "controller offers requested instruction window");
      check(request_base_pc_o == expected_base,
            "controller request has expected aligned base");
      request_ready_i = 1'b1;
      @(posedge clk_i);
      @(negedge clk_i);
      request_ready_i = 1'b0;
    end
  endtask

  task automatic return_response;
    begin
      @(negedge clk_i);
      response_valid_i = 1'b1;
      check(response_ready_o, "controller accepts sole outstanding response");
      @(posedge clk_i);
      @(negedge clk_i);
      response_valid_i = 1'b0;
    end
  endtask

  task automatic issue_window(input logic [63:0] pc,
                              input logic [31:0] lane0_instruction,
                              input logic [31:0] lane1_instruction);
    logic [63:0] base;
    int unsigned offset;
    begin
      base = {pc[63:4], 4'b0};
      offset = int'(pc - base);
      accept_request(base);
      clear_response();
      put_word(offset, lane0_instruction);
      put_word(offset + 4, lane1_instruction);
      return_response();
    end
  endtask

  task automatic issue_compressed_window(input logic [63:0] pc,
                                         input logic [15:0] instruction);
    logic [63:0] base;
    int unsigned offset;
    begin
      base = {pc[63:4], 4'b0};
      offset = int'(pc - base);
      accept_request(base);
      clear_response();
      put_half(offset, instruction);
      return_response();
    end
  endtask

  task automatic fetch_preserving_state(
      input logic [63:0] pc,
      input logic [31:0] lane0_instruction,
      input logic [31:0] lane1_instruction);
    begin
      redirect_preserving_state(pc);
      issue_window(pc, lane0_instruction, lane1_instruction);
    end
  endtask

  task automatic consume_packet;
    begin
      @(negedge clk_i);
      packet_ready_i = 1'b1;
      @(posedge clk_i);
      @(negedge clk_i);
      packet_ready_i = 1'b0;
    end
  endtask

  task automatic train_indirect(input logic [63:0] metadata_pc,
                                input logic [7:0] metadata_history,
                                input logic [63:0] target);
    begin
      @(negedge clk_i);
      retire_indirect_pc_i = metadata_pc;
      retire_indirect_history_i = metadata_history;
      retire_indirect_target_i = target;
      retire_indirect_meta_valid_i = 1'b1;
      retire_indirect_valid_i = 1'b1;
      @(posedge clk_i);
      @(negedge clk_i);
      retire_indirect_valid_i = 1'b0;
      retire_indirect_meta_valid_i = 1'b0;
    end
  endtask

  task automatic flush_to(input logic [63:0] pc);
    begin
      @(negedge clk_i);
      flush_pc_i = pc;
      flush_valid_i = 1'b1;
      @(posedge clk_i);
      @(negedge clk_i);
      flush_valid_i = 1'b0;
    end
  endtask

  initial begin : p_timeout
    repeat (2000) @(posedge clk_i);
    $fatal(1, "fetch predictor state test timed out");
  end

  initial begin
    clk_i = 1'b0;
    rst_ni = 1'b0;
    fetch_enable_i = 1'b1;
    flush_valid_i = 1'b0;
    flush_pc_i = '0;
    redirect_valid_i = 1'b0;
    redirect_pc_i = '0;
    redirect_is_branch_i = 1'b0;
    redirect_taken_i = 1'b0;
    redirect_history_i = '0;
    redirect_ras_sp_i = '0;
    redirect_ras_count_i = '0;
    redirect_ras_entries_i = '0;
    request_ready_i = 1'b0;
    response_valid_i = 1'b0;
    packet_ready_i = 1'b0;
    retire_btb_valid_i = 1'b0;
    retire_btb_pc_i = '0;
    retire_btb_target_i = '0;
    retire_btb_kind_i = '0;
    retire_tage_valid_i = 1'b0;
    retire_tage_taken_i = 1'b0;
    retire_tage_base_index_i = '0;
    retire_tage_comp0_index_i = '0;
    retire_tage_comp1_index_i = '0;
    retire_tage_comp0_tag_i = '0;
    retire_tage_comp1_tag_i = '0;
    retire_tage_provider_i = '0;
    retire_tage_provider_way_i = 1'b0;
    retire_tage_meta_valid_i = 1'b0;
    retire_tage_prediction_i = 1'b0;
    retire_tage_alt_prediction_i = 1'b0;
    retire_indirect_valid_i = 1'b0;
    retire_indirect_pc_i = '0;
    retire_indirect_history_i = '0;
    retire_indirect_target_i = '0;
    retire_indirect_meta_valid_i = 1'b0;
    saved_indirect_pc = '0;
    saved_indirect_history = '0;
    saved_ras_sp = '0;
    saved_ras_count = '0;
    saved_ras_entries = '0;
    post_coroutine_ras_sp = '0;
    post_coroutine_ras_count = '0;
    post_coroutine_ras_entries = '0;
    checks = 0;
    clear_response();

    repeat (2) @(posedge clk_i);
    @(negedge clk_i);
    rst_ni = 1'b1;
    @(posedge clk_i);

    // A delayed retirement must train the exact PC/path-history lookup
    // context emitted with the packet.  Confidence threshold two means the
    // first matching target remains unusable and the second becomes usable.
    redirect_with_state(64'h2000, 64'h0000_0000_0000_00a5,
                        4'b0, 5'b0, 1024'b0, 1'b0, 1'b0);
    issue_window(64'h2000, 32'h00010067, 32'h00100093); // jalr x0,0(x2)
    check(packet_valid_o == 2'b01 && !packet_pred_taken_o[0] &&
          packet_pred_kind_o[0] == 2'b10,
          "cold indirect lookup is terminal but not predicted taken");
    check(packet_indirect_meta_valid_o && packet_indirect_meta_pc_o == 64'h2000,
          "indirect lookup exports its exact PC metadata");
    check(packet_indirect_meta_history_o == 8'ha5,
          "indirect lookup exports its exact path-history metadata");
    saved_indirect_pc = packet_indirect_meta_pc_o;
    saved_indirect_history = packet_indirect_meta_history_o;
    train_indirect(saved_indirect_pc, saved_indirect_history, 64'h8800);
    check(!packet_pred_taken_o[0],
          "training cannot rewrite an already stalled fetch packet");
    consume_packet();

    fetch_preserving_state(64'h2000, 32'h00010067, 32'h00100093);
    check(!packet_pred_taken_o[0],
          "one matching indirect retirement remains below confidence gate");
    check(packet_indirect_meta_valid_o &&
          packet_indirect_meta_pc_o == saved_indirect_pc &&
          packet_indirect_meta_history_o == saved_indirect_history,
          "repeat lookup retains the same PC/path-history association");
    train_indirect(packet_indirect_meta_pc_o,
                   packet_indirect_meta_history_o, 64'h8800);
    check(!packet_pred_taken_o[0],
          "second training also leaves the held packet immutable");
    consume_packet();

    fetch_preserving_state(64'h2000, 32'h00010067, 32'h00100093);
    check(packet_pred_taken_o[0] && packet_pred_target_o[0] == 64'h8800 &&
          packet_pred_kind_o[0] == 2'b10,
          "second matching retirement enables the indirect target");
    redirect_with_state(64'h2000, 64'h0000_0000_0000_00a4,
                        packet_ras_sp_o[0], packet_ras_count_o[0],
                        packet_ras_entries_o[0], 1'b0, 1'b0);
    issue_window(64'h2000, 32'h00010067, 32'h00100093);
    check(!packet_pred_taken_o[0] && packet_indirect_meta_valid_o &&
          packet_indirect_meta_history_o == 8'ha4,
          "same indirect PC with different history cannot alias confidence");
    redirect_with_state(64'h2000, 64'h0000_0000_0000_00a5,
                        packet_ras_sp_o[0], packet_ras_count_o[0],
                        packet_ras_entries_o[0], 1'b0, 1'b0);
    issue_window(64'h2000, 32'h00010067, 32'h00100093);
    check(packet_pred_taken_o[0] && packet_pred_target_o[0] == 64'h8800,
          "restoring the trained history restores the confident target");
    fetch_preserving_state(64'h2040, 32'h00010067, 32'h00100093);
    check(!packet_pred_taken_o[0] && packet_indirect_meta_pc_o == 64'h2040,
          "different indirect PC cannot alias trained PC metadata");

    // Calls push their fall-through address.  Returns pop.  A coroutine JALR
    // with different link registers (jalr x5,0(x1)) pops the old return and
    // pushes its own link in one accepted operation.  Recovery must restore
    // entries as well as the stack pointer/count after that destructive write.
    flush_to(64'h3000);
    issue_window(64'h3000, 32'h008000ef, 32'h00100093); // jal x1,+8
    check(packet_ras_count_o[0] == 5'd0,
          "first call packet carries its pre-push RAS checkpoint");
    consume_packet();
    fetch_preserving_state(64'h3100, 32'h008000ef, 32'h00100093);
    check(packet_ras_count_o[0] == 5'd1,
          "accepted first call pushes one return address");
    consume_packet();
    saved_ras_sp = packet_ras_sp_o[0];
    saved_ras_count = packet_ras_count_o[0];
    saved_ras_entries = packet_ras_entries_o[0];
    check(saved_ras_count == 5'd2,
          "accepted second call pushes a second return address");

    fetch_preserving_state(64'h3200, 32'h00008067, 32'h00100093); // ret
    check(packet_pred_taken_o[0] && packet_pred_target_o[0] == 64'h3104 &&
          packet_pred_kind_o[0] == 2'b11,
          "return predicts the youngest call fall-through");
    check(packet_ras_count_o[0] == 5'd2,
          "return packet carries its pre-pop full checkpoint");
    consume_packet();
    check(packet_ras_count_o[0] == 5'd1,
          "accepted return pops one RAS entry");

    fetch_preserving_state(64'h3300, 32'h000082e7, 32'h00100093);
    check(packet_pred_taken_o[0] && packet_pred_target_o[0] == 64'h3004,
          "coroutine JALR predicts the return it pops");
    consume_packet();
    check(packet_ras_count_o[0] == 5'd1,
          "coroutine pop-plus-push preserves nonempty RAS depth");
    post_coroutine_ras_sp = packet_ras_sp_o[0];
    post_coroutine_ras_count = packet_ras_count_o[0];
    post_coroutine_ras_entries = packet_ras_entries_o[0];
    fetch_preserving_state(64'h3400, 32'h00008067, 32'h00100093);
    check(packet_pred_taken_o[0] && packet_pred_target_o[0] == 64'h3304,
          "coroutine push installs its own fall-through as new top");

    redirect_with_state(64'h3500, 64'h0, saved_ras_sp, saved_ras_count,
                        saved_ras_entries, 1'b0, 1'b0);
    issue_window(64'h3500, 32'h00008067, 32'h00100093);
    check(packet_ras_sp_o[0] == saved_ras_sp &&
          packet_ras_count_o[0] == saved_ras_count,
          "redirect restores saved RAS pointer and count");
    check(packet_ras_entries_o[0] == saved_ras_entries,
          "redirect restores all destructively modified RAS entries");
    check(packet_pred_taken_o[0] && packet_pred_target_o[0] == 64'h3104,
          "restored RAS predicts the checkpoint's original top");

    redirect_with_state(64'h3580, 64'h0, post_coroutine_ras_sp,
                        post_coroutine_ras_count, post_coroutine_ras_entries,
                        1'b0, 1'b0);
    issue_window(64'h3580, 32'h00008067, 32'h00100093);
    check(packet_pred_taken_o[0] && packet_pred_target_o[0] == 64'h3304,
          "backend-supplied post-coroutine redirect state retains resolved push");

    // Isolated RAS-hint matrix, including the opposite coroutine direction and
    // compressed JR/JALR decompression paths.  Each case starts with one entry.
    saved_ras_entries = '0;
    saved_ras_entries[63:0] = 64'hdead_0000;
    redirect_with_state(64'h3600, 64'h0, 4'd1, 5'd1,
                        saved_ras_entries, 1'b0, 1'b0);
    issue_window(64'h3600, 32'h00010067, 32'h00100093); // jalr x0,0(x2)
    consume_packet();
    check(packet_ras_count_o[0] == 5'd1,
          "JALR with neither link register leaves RAS unchanged");

    redirect_with_state(64'h3610, 64'h0, 4'd1, 5'd1,
                        saved_ras_entries, 1'b0, 1'b0);
    issue_window(64'h3610, 32'h000100e7, 32'h00100093); // jalr x1,0(x2)
    consume_packet();
    check(packet_ras_count_o[0] == 5'd2 &&
          packet_ras_entries_o[0][127:64] == 64'h3614,
          "JALR link destination with non-link source pushes");

    redirect_with_state(64'h3620, 64'h0, 4'd1, 5'd1,
                        saved_ras_entries, 1'b0, 1'b0);
    issue_window(64'h3620, 32'h00008067, 32'h00100093); // jalr x0,0(x1)
    consume_packet();
    check(packet_ras_count_o[0] == 5'd0,
          "JALR non-link destination with link source pops");

    redirect_with_state(64'h3630, 64'h0, 4'd1, 5'd1,
                        saved_ras_entries, 1'b0, 1'b0);
    issue_window(64'h3630, 32'h000080e7, 32'h00100093); // jalr x1,0(x1)
    consume_packet();
    check(packet_ras_count_o[0] == 5'd2 &&
          packet_ras_entries_o[0][127:64] == 64'h3634,
          "JALR using the same link register pushes without popping");

    redirect_with_state(64'h3640, 64'h0, 4'd1, 5'd1,
                        saved_ras_entries, 1'b0, 1'b0);
    issue_window(64'h3640, 32'h000280e7, 32'h00100093); // jalr x1,0(x5)
    check(packet_pred_taken_o[0] &&
          packet_pred_target_o[0] == 64'hdead_0000,
          "opposite-link coroutine predicts the popped target");
    consume_packet();
    check(packet_ras_count_o[0] == 5'd1 &&
          packet_ras_entries_o[0][63:0] == 64'h3644,
          "opposite-link coroutine pops then pushes");

    redirect_with_state(64'h3700, 64'h0, 4'd1, 5'd1,
                        saved_ras_entries, 1'b0, 1'b0);
    issue_compressed_window(64'h3700, 16'h8082); // c.jr x1
    check(packet_compressed_o[0] && packet_pred_taken_o[0] &&
          packet_pred_target_o[0] == 64'hdead_0000,
          "compressed JR uses the RAS pop target");
    consume_packet();
    check(packet_ras_count_o[0] == 5'd0,
          "compressed JR pops exactly once");

    redirect_with_state(64'h3710, 64'h0, 4'd1, 5'd1,
                        saved_ras_entries, 1'b0, 1'b0);
    issue_compressed_window(64'h3710, 16'h9082); // c.jalr x1
    check(packet_compressed_o[0], "compressed JALR is preserved in packet metadata");
    consume_packet();
    check(packet_ras_count_o[0] == 5'd2 &&
          packet_ras_entries_o[0][127:64] == 64'h3712,
          "compressed JALR pushes its two-byte fall-through");

    // Only accepted conditional branches enter global speculative history.
    // Lane 0 is older.  An ordinary lane 0 does not perturb lane 1's lookup;
    // a lane-0 branch suppresses lane 1 and therefore appends exactly once.
    flush_to(64'h4000);
    redirect_with_state(64'h4000, 64'h5, 4'b0, 5'b0, 1024'b0,
                        1'b0, 1'b0);
    issue_window(64'h4000, 32'h00100093, 32'h00000063);
    check(packet_valid_o == 2'b11 && packet_pc_o[1] == 64'h4004,
          "younger conditional is emitted behind an ordinary older lane");
    check(packet_history_o[0] == 64'h5 && packet_history_o[1] == 64'h5,
          "both lanes observe restored history when older lane is non-control");
    check(!packet_pred_taken_o[1], "cold younger conditional predicts not taken");
    consume_packet();

    fetch_preserving_state(64'h4100, 32'h00000063, 32'h00000063);
    check(packet_history_o[0] == 64'ha,
          "accepted not-taken younger branch appends an ordered zero");
    check(packet_valid_o == 2'b01,
          "oldest control suppresses the younger control lane");
    consume_packet();
    fetch_preserving_state(64'h4200, 32'h00100093, 32'h00100093);
    check(packet_history_o[0] == 64'h14,
          "suppressed lane never causes a second speculative append");

    redirect_with_state(64'h4300, 64'h25,
                        packet_ras_sp_o[0], packet_ras_count_o[0],
                        packet_ras_entries_o[0], 1'b1, 1'b1);
    issue_window(64'h4300, 32'h00100093, 32'h00100093);
    check(packet_history_o[0] == 64'h4b,
          "branch redirect restores checkpoint then appends resolved taken");
    redirect_with_state(64'h4400, 64'ha5,
                        packet_ras_sp_o[0], packet_ras_count_o[0],
                        packet_ras_entries_o[0], 1'b0, 1'b1);
    issue_window(64'h4400, 32'h00100093, 32'h00100093);
    check(packet_history_o[0] == 64'ha5,
          "non-branch redirect restores history without appending outcome");

    // A recovery masks a previously valid packet even when ready is high.
    redirect_with_state(64'h4480, 64'h33,
                        packet_ras_sp_o[0], packet_ras_count_o[0],
                        packet_ras_entries_o[0], 1'b0, 1'b0);
    issue_window(64'h4480, 32'h00000063, 32'h00100093);
    check(packet_valid_o == 2'b01, "conditional packet is visible before recovery");
    @(negedge clk_i);
    packet_ready_i = 1'b1;
    redirect_pc_i = 64'h4490;
    redirect_history_i = 64'h55;
    redirect_ras_sp_i = packet_ras_sp_o[0];
    redirect_ras_count_i = packet_ras_count_o[0];
    redirect_ras_entries_i = packet_ras_entries_o[0];
    redirect_is_branch_i = 1'b0;
    redirect_valid_i = 1'b1;
    #1;
    check(packet_valid_o == 2'b00 && !packet_indirect_meta_valid_o,
          "redirect masks a ready stalled packet and all qualified metadata");
    @(posedge clk_i);
    @(negedge clk_i);
    packet_ready_i = 1'b0;
    redirect_valid_i = 1'b0;
    issue_window(64'h4490, 32'h00100093, 32'h00100093);
    check(packet_history_o[0] == 64'h55,
          "masked recovery packet performs no speculative history append");

    // Faulted instruction bytes must never influence predictor state, even if
    // their returned data bits encode a conditional branch.
    redirect_with_state(64'h4800, 64'h3c,
                        packet_ras_sp_o[0], packet_ras_count_o[0],
                        packet_ras_entries_o[0], 1'b0, 1'b0);
    accept_request(64'h4800);
    clear_response();
    put_word(0, 32'h00000063);
    response_fault_i[0] = 1'b1;
    return_response();
    check(packet_valid_o == 2'b01 && packet_fetch_fault_o[0],
          "faulting branch-shaped bytes emit one attributable fault lane");
    consume_packet();
    check(packet_history_o[0] == 64'h3c,
          "faulting branch-shaped bytes do not advance speculative history");

    @(negedge clk_i);
    flush_pc_i = 64'h4500;
    flush_valid_i = 1'b1;
    redirect_valid_i = 1'b1;
    redirect_pc_i = 64'h4600;
    redirect_history_i = 64'hffff;
    redirect_is_branch_i = 1'b1;
    redirect_taken_i = 1'b1;
    @(posedge clk_i);
    @(negedge clk_i);
    flush_valid_i = 1'b0;
    redirect_valid_i = 1'b0;
    redirect_is_branch_i = 1'b0;
    redirect_taken_i = 1'b0;
    issue_window(64'h4500, 32'h00100093, 32'h00100093);
    check(packet_history_o[0] == 64'h0,
          "flush overrides redirect and resets speculative history");
    check(packet_ras_count_o[0] == 5'd0,
          "flush also empties speculative return-address state");

    $display("PASS: %0d fetch-predictor-state checks", checks);
    $finish;
  end
endmodule
