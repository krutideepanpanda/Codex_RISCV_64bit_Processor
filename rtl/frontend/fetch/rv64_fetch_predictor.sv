// SPDX-License-Identifier: Apache-2.0
// Bounded VDD_CORE fetch/predictor integration.  One oldest control transfer
// is handled per packet because BTB, indirect predictor, and RAS are single-port.
module rv64_fetch_predictor #(
  parameter int unsigned ADDR_W = 64,
  parameter int unsigned WINDOW_BYTES = 32,
  parameter logic [ADDR_W-1:0] RESET_PC = 64'h1000
) (
  input logic clk_i, input logic rst_ni, input logic fetch_enable_i,
  input logic flush_valid_i, input logic [ADDR_W-1:0] flush_pc_i,
  input logic redirect_valid_i, input logic [ADDR_W-1:0] redirect_pc_i,
  input logic redirect_is_branch_i, input logic redirect_taken_i,
  input logic [63:0] redirect_history_i, input logic [3:0] redirect_ras_sp_i,
  input logic [4:0] redirect_ras_count_i, input logic [1023:0] redirect_ras_entries_i,
  output logic request_valid_o, input logic request_ready_i, output logic [ADDR_W-1:0] request_base_pc_o,
  input logic response_valid_i, output logic response_ready_o,
  input logic [7:0] response_data_i [WINDOW_BYTES], input logic response_valid_bytes_i [WINDOW_BYTES],
  input logic response_fault_i [WINDOW_BYTES],
  output logic [1:0] packet_valid_o, input logic packet_ready_i,
  output logic [1:0][ADDR_W-1:0] packet_pc_o, output logic [1:0][31:0] packet_instruction_o,
  output logic [1:0][31:0] packet_raw_instruction_o, output logic [1:0] packet_compressed_o,
  output logic [1:0] packet_illegal_compressed_o, output logic [1:0] packet_fetch_fault_o,
  output logic [1:0] packet_pred_taken_o, output logic [1:0][ADDR_W-1:0] packet_pred_target_o,
  output logic [1:0][1:0] packet_pred_kind_o, output logic [1:0][63:0] packet_history_o,
  output logic [1:0][3:0] packet_ras_sp_o, output logic [1:0][4:0] packet_ras_count_o,
  output logic [1:0][1023:0] packet_ras_entries_o,
  output logic [1:0] packet_tage_prediction_o, output logic [1:0] packet_tage_alt_prediction_o,
  output logic [1:0][1:0] packet_tage_provider_o, output logic [1:0] packet_tage_provider_way_o,
  output logic [1:0][7:0] packet_tage_base_index_o, output logic [1:0][6:0] packet_tage_comp0_index_o,
  output logic [1:0][6:0] packet_tage_comp1_index_o, output logic [1:0][9:0] packet_tage_comp0_tag_o,
  output logic [1:0][9:0] packet_tage_comp1_tag_o,
  output logic packet_indirect_meta_valid_o, output logic [ADDR_W-1:0] packet_indirect_meta_pc_o,
  output logic [7:0] packet_indirect_meta_history_o,
  input logic retire_btb_valid_i, input logic [ADDR_W-1:0] retire_btb_pc_i,
  input logic [ADDR_W-1:0] retire_btb_target_i, input logic [1:0] retire_btb_kind_i,
  input logic retire_tage_valid_i, input logic retire_tage_taken_i,
  input logic [7:0] retire_tage_base_index_i, input logic [6:0] retire_tage_comp0_index_i,
  input logic [6:0] retire_tage_comp1_index_i, input logic [9:0] retire_tage_comp0_tag_i,
  input logic [9:0] retire_tage_comp1_tag_i, input logic [1:0] retire_tage_provider_i,
  input logic retire_tage_provider_way_i, input logic retire_tage_meta_valid_i,
  input logic retire_tage_prediction_i, input logic retire_tage_alt_prediction_i,
  input logic retire_indirect_valid_i, input logic [ADDR_W-1:0] retire_indirect_pc_i,
  input logic [7:0] retire_indirect_history_i, input logic [ADDR_W-1:0] retire_indirect_target_i,
  input logic retire_indirect_meta_valid_i
);
  logic window_valid, window_ready;
  logic [ADDR_W-1:0] window_start, window_base, next_pc;
  logic [7:0] window_data [WINDOW_BYTES]; logic window_bytes [WINDOW_BYTES], window_fault [WINDOW_BYTES];
  logic [1:0] align_valid, align_compressed, align_illegal, align_fault;
  logic [1:0][ADDR_W-1:0] align_pc; logic [1:0][31:0] align_instruction, align_raw;
  logic [ADDR_W-1:0] align_next;
  logic [1:0] tage_prediction, tage_alt; logic [1:0][1:0] tage_provider;
  logic [1:0][7:0] tage_base; logic [1:0][6:0] tage_c0, tage_c1; logic [1:0][9:0] tage_t0, tage_t1;
  logic [1:0] tage_way;
  logic [63:0] hist0, hist1, hist_checkpoint;
  logic btb_hit; logic [ADDR_W-1:0] btb_target; logic [1:0] btb_kind;
  logic indirect_valid; logic [ADDR_W-1:0] indirect_target; logic indirect_meta_valid;
  logic [ADDR_W-1:0] indirect_meta_pc; logic [7:0] indirect_meta_history;
  logic ras_top_valid; logic [ADDR_W-1:0] ras_top; logic [3:0] ras_sp; logic [4:0] ras_count; logic [1023:0] ras_entries;
  logic [1:0] control, conditional, direct_jal, return_jalr, indirect_jalr, call;
  logic selected_lane, packet_accept, selected_control, btb_kind_match;
  logic [ADDR_W-1:0] selected_pc, selected_history, direct_target;
  logic [1:0] selected_kind;
  logic packet_stalled_q;
  logic [1:0][63:0] packet_pc_prev_q, packet_pred_target_prev_q;
  logic [1:0][31:0] packet_instruction_prev_q, packet_raw_prev_q;
  logic [1:0] packet_valid_prev_q, packet_compressed_prev_q, packet_illegal_prev_q, packet_fault_prev_q;
  logic [1:0] packet_pred_taken_prev_q, packet_tage_prediction_prev_q, packet_tage_alt_prev_q;
  logic [1:0][1:0] packet_pred_kind_prev_q;
  logic [1:0][63:0] packet_history_prev_q;
  logic [1:0][3:0] packet_ras_sp_prev_q;
  logic [1:0][4:0] packet_ras_count_prev_q;
  logic [1:0][1023:0] packet_ras_entries_prev_q;
  logic [1:0][1:0] packet_provider_prev_q;
  logic [1:0] packet_way_prev_q;
  logic [1:0][7:0] packet_base_prev_q;
  logic [1:0][6:0] packet_c0_prev_q, packet_c1_prev_q;
  logic [1:0][9:0] packet_t0_prev_q, packet_t1_prev_q;
  logic indirect_valid_prev_q; logic [ADDR_W-1:0] indirect_pc_prev_q; logic [7:0] indirect_history_prev_q;

  function automatic logic [ADDR_W-1:0] jal_target(input logic [ADDR_W-1:0] pc, input logic [31:0] insn);
    logic [20:0] imm;
    begin imm = {insn[31],insn[19:12],insn[20],insn[30:21],1'b0}; jal_target = pc + {{43{imm[20]}},imm}; end
  endfunction

  rv64_fetch_controller #(.ADDR_W(ADDR_W),.WINDOW_BYTES(WINDOW_BYTES),.RESET_PC(RESET_PC)) u_controller (.*,
    .window_valid_o(window_valid),.window_ready_i(window_ready),.window_start_pc_o(window_start),.window_base_pc_o(window_base),
    .window_data_o(window_data),.window_valid_bytes_o(window_bytes),.window_fault_o(window_fault),.next_pc_i(next_pc));
  rv64_fetch_align #(.ADDR_W(ADDR_W),.WINDOW_BYTES(WINDOW_BYTES)) u_align (
    .start_pc_i(window_start),.window_base_pc_i(window_base),.window_data_i(window_data),.window_valid_i(window_bytes),.window_fault_i(window_fault),
    .instruction_valid_o(align_valid),.instruction_pc_o(align_pc),.instruction_o(align_instruction),.raw_instruction_o(align_raw),
    .compressed_o(align_compressed),.illegal_compressed_o(align_illegal),.fetch_fault_o(align_fault),.sequential_next_pc_o(align_next));
  // 001c-a captures and restores history but defers speculative dual-lane
  // advancement/order scenarios to frontend-001c-b.
  rv64_spec_history u_history (.clk(clk_i),.rst_ni(rst_ni),.advance_valid_i('0),
    .advance_taken_i('0),.recover_valid_i(redirect_valid_i),.recover_history_i(redirect_history_i),
    .recover_is_branch_i(redirect_is_branch_i),.recover_taken_i(redirect_taken_i),.flush_valid_i(flush_valid_i),
    .lane0_history_o(hist0),.lane1_history_o(hist1),.checkpoint_history_o(hist_checkpoint));
  rv64_tage_lite u_tage (.clk(clk_i),.rst_ni(rst_ni),.lookup_pc(align_pc),.lookup_history({hist1,hist0}),.lookup_prediction(tage_prediction),
    .lookup_provider(tage_provider),.lookup_alt_prediction(tage_alt),.lookup_base_index(tage_base),.lookup_comp0_index(tage_c0),.lookup_comp1_index(tage_c1),
    .lookup_comp0_tag(tage_t0),.lookup_comp1_tag(tage_t1),.lookup_provider_way(tage_way),.train_valid(retire_tage_valid_i),.train_meta_valid(retire_tage_meta_valid_i),
    .train_taken(retire_tage_taken_i),.train_prediction(retire_tage_prediction_i),.train_alt_prediction(retire_tage_alt_prediction_i),.train_provider(retire_tage_provider_i),
    .train_provider_way(retire_tage_provider_way_i),.train_base_index(retire_tage_base_index_i),.train_comp0_index(retire_tage_comp0_index_i),.train_comp1_index(retire_tage_comp1_index_i),
    .train_comp0_tag(retire_tage_comp0_tag_i),.train_comp1_tag(retire_tage_comp1_tag_i),.flush_valid(flush_valid_i));
  rv64_btb u_btb (.clk(clk_i),.rst_ni(rst_ni),.lookup_pc(selected_pc),.lookup_hit(btb_hit),.lookup_target(btb_target),.lookup_kind(btb_kind),
    .update_valid(retire_btb_valid_i),.update_pc(retire_btb_pc_i),.update_target(retire_btb_target_i),.update_kind(retire_btb_kind_i),.flush_valid(flush_valid_i));
  rv64_indirect_predictor #(.SETS(8),.WAYS(4)) u_indirect (.clk(clk_i),.rst_ni(rst_ni),.lookup_valid(selected_control && indirect_jalr[selected_lane]),
    .lookup_pc(selected_pc),.lookup_path_history(selected_history[7:0]),.predict_valid(indirect_valid),.predict_target(indirect_target),.lookup_meta_valid(indirect_meta_valid),
    .lookup_meta_pc(indirect_meta_pc),.lookup_meta_path_history(indirect_meta_history),.train_valid(retire_indirect_valid_i),.train_meta_valid(retire_indirect_meta_valid_i),
    .train_meta_pc(retire_indirect_pc_i),.train_meta_path_history(retire_indirect_history_i),.train_target(retire_indirect_target_i),.flush_valid(flush_valid_i));
  rv64_ras u_ras (.clk(clk_i),.rst_ni(rst_ni),.push_valid(packet_accept && selected_control && call[selected_lane]),
    .push_addr(selected_pc + (align_compressed[selected_lane] ? ADDR_W'(2) : ADDR_W'(4))),.pop_valid(packet_accept && selected_control && return_jalr[selected_lane]),
    .top_valid(ras_top_valid),.top_addr(ras_top),.checkpoint_sp_o(ras_sp),.checkpoint_count_o(ras_count),.checkpoint_entries_o(ras_entries),
    .recover_valid(redirect_valid_i),.recover_sp(redirect_ras_sp_i),.recover_count(redirect_ras_count_i),.recover_entries(redirect_ras_entries_i),.flush_valid(flush_valid_i));

  // Classification is deliberately isolated from predictor-result selection.
  // It provides stable lookup addresses/history without feeding table outputs.
  always_comb begin : p_classify
    for (int unsigned lane=0; lane<2; lane++) begin
      conditional[lane] = align_instruction[lane][6:0] == 7'b1100011;
      direct_jal[lane] = align_instruction[lane][6:0] == 7'b1101111;
      return_jalr[lane] = (align_instruction[lane][6:0] == 7'b1100111) && (align_instruction[lane][11:7] == 5'b0) &&
                          ((align_instruction[lane][19:15] == 5'd1) || (align_instruction[lane][19:15] == 5'd5)) && (align_instruction[lane][31:20] == 12'b0);
      indirect_jalr[lane] = (align_instruction[lane][6:0] == 7'b1100111) && !return_jalr[lane];
      call[lane] = (direct_jal[lane] || (align_instruction[lane][6:0] == 7'b1100111)) &&
                   ((align_instruction[lane][11:7] == 5'd1) || (align_instruction[lane][11:7] == 5'd5));
      control[lane] = conditional[lane] || direct_jal[lane] || return_jalr[lane] || indirect_jalr[lane];
    end
    selected_lane = control[0] ? 1'b0 : 1'b1;
    selected_control = window_valid && align_valid[selected_lane] && control[selected_lane] && !align_fault[selected_lane];
    selected_pc = align_pc[selected_lane]; selected_history = selected_lane ? hist1 : hist0;
    selected_kind = conditional[selected_lane] ? 2'b00 : direct_jal[selected_lane] ? 2'b01 : return_jalr[selected_lane] ? 2'b11 : 2'b10;
    direct_target = jal_target(selected_pc,align_instruction[selected_lane]);
  end

  // Keep BTB result matching out of the address/classification process.  This
  // avoids a false combinational cycle in conservative Verilator versions:
  // selected_pc -> BTB lookup -> btb_kind -> kind match.
  always_comb begin : p_btb_kind_match
    btb_kind_match = (conditional[selected_lane] && (btb_kind == 2'b00)) ||
                     (indirect_jalr[selected_lane] && (btb_kind == 2'b10)) ||
                     (return_jalr[selected_lane] && (btb_kind == 2'b11));
  end

  always_comb begin : p_select
    packet_valid_o = window_valid ? align_valid : '0;
    if (control[0]) packet_valid_o[1] = 1'b0;
    packet_pc_o = align_pc; packet_instruction_o = align_instruction; packet_raw_instruction_o = align_raw;
    packet_compressed_o = align_compressed; packet_illegal_compressed_o = align_illegal; packet_fetch_fault_o = align_fault;
    packet_pred_taken_o = '0; packet_pred_target_o = '0; packet_pred_kind_o = '0;
    if (selected_control) begin
      packet_pred_kind_o[selected_lane] = selected_kind;
      if (direct_jal[selected_lane]) begin packet_pred_taken_o[selected_lane]=1'b1; packet_pred_target_o[selected_lane]=direct_target; end
      else if (return_jalr[selected_lane] && ras_top_valid) begin packet_pred_taken_o[selected_lane]=1'b1; packet_pred_target_o[selected_lane]=ras_top; end
      else if (indirect_jalr[selected_lane] && indirect_valid) begin packet_pred_taken_o[selected_lane]=1'b1; packet_pred_target_o[selected_lane]=indirect_target; end
      else if (btb_hit && btb_kind_match &&
               (!conditional[selected_lane] || tage_prediction[selected_lane])) begin
        packet_pred_taken_o[selected_lane]=1'b1; packet_pred_target_o[selected_lane]=btb_target; packet_pred_kind_o[selected_lane]=btb_kind;
      end
    end
    packet_history_o[0]=hist0; packet_history_o[1]=hist1;
    packet_ras_sp_o = {ras_sp,ras_sp}; packet_ras_count_o = {ras_count,ras_count}; packet_ras_entries_o = {ras_entries,ras_entries};
    packet_tage_prediction_o=tage_prediction; packet_tage_alt_prediction_o=tage_alt; packet_tage_provider_o=tage_provider;
    packet_tage_provider_way_o=tage_way; packet_tage_base_index_o=tage_base; packet_tage_comp0_index_o=tage_c0;
    packet_tage_comp1_index_o=tage_c1; packet_tage_comp0_tag_o=tage_t0; packet_tage_comp1_tag_o=tage_t1;
    packet_indirect_meta_valid_o=indirect_meta_valid && selected_control && indirect_jalr[selected_lane];
    packet_indirect_meta_pc_o=indirect_meta_pc; packet_indirect_meta_history_o=indirect_meta_history;
    // A stalled packet is a registered bundle.  Retirement-side updates can
    // change predictor tables, but never the packet or metadata being held.
    if (packet_stalled_q && !flush_valid_i && !redirect_valid_i) begin
      packet_valid_o=packet_valid_prev_q; packet_pc_o=packet_pc_prev_q;
      packet_instruction_o=packet_instruction_prev_q; packet_raw_instruction_o=packet_raw_prev_q;
      packet_compressed_o=packet_compressed_prev_q; packet_illegal_compressed_o=packet_illegal_prev_q; packet_fetch_fault_o=packet_fault_prev_q;
      packet_pred_taken_o=packet_pred_taken_prev_q; packet_pred_target_o=packet_pred_target_prev_q; packet_pred_kind_o=packet_pred_kind_prev_q;
      packet_history_o=packet_history_prev_q; packet_ras_sp_o=packet_ras_sp_prev_q; packet_ras_count_o=packet_ras_count_prev_q; packet_ras_entries_o=packet_ras_entries_prev_q;
      packet_tage_prediction_o=packet_tage_prediction_prev_q; packet_tage_alt_prediction_o=packet_tage_alt_prev_q;
      packet_tage_provider_o=packet_provider_prev_q; packet_tage_provider_way_o=packet_way_prev_q; packet_tage_base_index_o=packet_base_prev_q;
      packet_tage_comp0_index_o=packet_c0_prev_q; packet_tage_comp1_index_o=packet_c1_prev_q; packet_tage_comp0_tag_o=packet_t0_prev_q; packet_tage_comp1_tag_o=packet_t1_prev_q;
      packet_indirect_meta_valid_o=indirect_valid_prev_q; packet_indirect_meta_pc_o=indirect_pc_prev_q; packet_indirect_meta_history_o=indirect_history_prev_q;
    end
    packet_accept = packet_valid_o[0] && packet_ready_i;
    window_ready = packet_accept;
    next_pc = align_next;
    // Oldest control is packet-terminal.  A miss/not-taken lane 0 restarts at
    // its fall-through rather than skipping suppressed lane 1.
    if (packet_valid_o[0] && control[0]) begin
      next_pc = packet_pred_taken_o[0] ? packet_pred_target_o[0] :
                packet_pc_o[0] + (packet_compressed_o[0] ? ADDR_W'(2) : ADDR_W'(4));
    end
    else if (packet_pred_taken_o[1]) next_pc = packet_pred_target_o[1];
  end

  always @(posedge clk_i) if (rst_ni) begin
    assert (!packet_valid_o[1] || packet_valid_o[0]);
    if (control[0]) assert (!packet_valid_o[1]);
    if (packet_accept && packet_pred_taken_o[0]) assert (!packet_valid_o[1]);
    if (packet_accept && selected_control) assert (selected_pc[0] == 1'b0);
    if (retire_btb_valid_i) assert (retire_btb_pc_i[0] == 1'b0 && retire_btb_target_i[0] == 1'b0);
    if (retire_tage_valid_i) begin
      assert (retire_tage_meta_valid_i);
      assert (retire_tage_provider_i <= 2'b10);
    end
    if (retire_indirect_valid_i) begin
      assert (retire_indirect_meta_valid_i);
      assert (retire_indirect_pc_i[0] == 1'b0 && retire_indirect_target_i[0] == 1'b0);
    end
    if (packet_indirect_meta_valid_o) begin
      assert (packet_valid_o[selected_lane] && selected_control && indirect_jalr[selected_lane]);
      assert (packet_indirect_meta_pc_o == packet_pc_o[selected_lane]);
    end
    // v0.1 response-completeness contract: a 32-byte response is atomic.
    // Refill of partially valid windows is deferred beyond this packet.
    if (response_valid_i && response_ready_o) begin
      for (int unsigned byte_index=0; byte_index<WINDOW_BYTES; byte_index++)
        assert (response_valid_bytes_i[byte_index] || response_fault_i[byte_index]);
    end
    if (packet_stalled_q && !flush_valid_i && !redirect_valid_i) begin
      assert (packet_valid_o == packet_valid_prev_q && packet_pc_o == packet_pc_prev_q);
      assert (packet_instruction_o == packet_instruction_prev_q && packet_raw_instruction_o == packet_raw_prev_q);
      assert (packet_compressed_o == packet_compressed_prev_q && packet_illegal_compressed_o == packet_illegal_prev_q && packet_fetch_fault_o == packet_fault_prev_q);
      assert (packet_pred_taken_o == packet_pred_taken_prev_q && packet_pred_target_o == packet_pred_target_prev_q);
      assert (packet_pred_kind_o == packet_pred_kind_prev_q && packet_history_o == packet_history_prev_q);
      assert (packet_ras_sp_o == packet_ras_sp_prev_q && packet_ras_count_o == packet_ras_count_prev_q && packet_ras_entries_o == packet_ras_entries_prev_q);
      assert (packet_tage_prediction_o == packet_tage_prediction_prev_q && packet_tage_alt_prediction_o == packet_tage_alt_prev_q);
      assert (packet_tage_provider_o == packet_provider_prev_q && packet_tage_provider_way_o == packet_way_prev_q);
      assert (packet_tage_base_index_o == packet_base_prev_q && packet_tage_comp0_index_o == packet_c0_prev_q && packet_tage_comp1_index_o == packet_c1_prev_q);
      assert (packet_tage_comp0_tag_o == packet_t0_prev_q && packet_tage_comp1_tag_o == packet_t1_prev_q);
      assert (packet_indirect_meta_valid_o == indirect_valid_prev_q && packet_indirect_meta_pc_o == indirect_pc_prev_q && packet_indirect_meta_history_o == indirect_history_prev_q);
    end
  end
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      packet_stalled_q<=0; packet_pc_prev_q<='0; packet_instruction_prev_q<='0; packet_raw_prev_q<='0;
      packet_valid_prev_q<='0; packet_compressed_prev_q<='0; packet_illegal_prev_q<='0; packet_fault_prev_q<='0;
      packet_pred_taken_prev_q<='0; packet_pred_target_prev_q<='0; packet_pred_kind_prev_q<='0; packet_history_prev_q<='0;
      packet_ras_sp_prev_q<='0; packet_ras_count_prev_q<='0; packet_ras_entries_prev_q<='0;
      packet_tage_prediction_prev_q<='0; packet_tage_alt_prev_q<='0; packet_provider_prev_q<='0; packet_way_prev_q<='0;
      packet_base_prev_q<='0; packet_c0_prev_q<='0; packet_c1_prev_q<='0; packet_t0_prev_q<='0; packet_t1_prev_q<='0;
      indirect_valid_prev_q<=0; indirect_pc_prev_q<='0; indirect_history_prev_q<='0;
    end else begin
      packet_stalled_q<=packet_valid_o[0]&&!packet_ready_i&&!flush_valid_i&&!redirect_valid_i; packet_pc_prev_q<=packet_pc_o; packet_instruction_prev_q<=packet_instruction_o;
      packet_raw_prev_q<=packet_raw_instruction_o; packet_valid_prev_q<=packet_valid_o; packet_compressed_prev_q<=packet_compressed_o;
      packet_illegal_prev_q<=packet_illegal_compressed_o; packet_fault_prev_q<=packet_fetch_fault_o; packet_pred_taken_prev_q<=packet_pred_taken_o;
      packet_pred_target_prev_q<=packet_pred_target_o; packet_pred_kind_prev_q<=packet_pred_kind_o; packet_history_prev_q<=packet_history_o;
      packet_ras_sp_prev_q<=packet_ras_sp_o; packet_ras_count_prev_q<=packet_ras_count_o; packet_ras_entries_prev_q<=packet_ras_entries_o;
      packet_tage_prediction_prev_q<=packet_tage_prediction_o; packet_tage_alt_prev_q<=packet_tage_alt_prediction_o;
      packet_provider_prev_q<=packet_tage_provider_o; packet_way_prev_q<=packet_tage_provider_way_o; packet_base_prev_q<=packet_tage_base_index_o;
      packet_c0_prev_q<=packet_tage_comp0_index_o; packet_c1_prev_q<=packet_tage_comp1_index_o; packet_t0_prev_q<=packet_tage_comp0_tag_o;
      packet_t1_prev_q<=packet_tage_comp1_tag_o; indirect_valid_prev_q<=packet_indirect_meta_valid_o;
      indirect_pc_prev_q<=packet_indirect_meta_pc_o; indirect_history_prev_q<=packet_indirect_meta_history_o;
    end
  end
endmodule
