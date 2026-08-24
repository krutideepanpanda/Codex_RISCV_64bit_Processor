// SPDX-License-Identifier: Apache-2.0
// frontend-001c-a: indirect confidence, destructive RAS recovery, and
// dual-lane history order/recovery are deliberately deferred to frontend-001c-b.
module fetch_predictor_tb;
  localparam int unsigned WINDOW_BYTES=32;
  logic clk_i,rst_ni,fetch_enable_i,flush_valid_i,redirect_valid_i,redirect_is_branch_i,redirect_taken_i;
  logic [63:0] flush_pc_i,redirect_pc_i,redirect_history_i; logic [3:0] redirect_ras_sp_i; logic [4:0] redirect_ras_count_i; logic [1023:0] redirect_ras_entries_i;
  logic request_valid_o,request_ready_i; logic [63:0] request_base_pc_o; logic response_valid_i,response_ready_o; logic [7:0] response_data_i[WINDOW_BYTES]; logic response_valid_bytes_i[WINDOW_BYTES],response_fault_i[WINDOW_BYTES];
  logic [1:0] packet_valid_o,packet_compressed_o,packet_illegal_compressed_o,packet_fetch_fault_o,packet_pred_taken_o; logic packet_ready_i;
  logic [1:0][63:0] packet_pc_o,packet_pred_target_o,packet_history_o; logic [1:0][31:0] packet_instruction_o,packet_raw_instruction_o; logic [1:0][1:0] packet_pred_kind_o; logic [1:0][3:0] packet_ras_sp_o; logic [1:0][4:0] packet_ras_count_o; logic [1:0][1023:0] packet_ras_entries_o;
  // The thirteen new metadata/provider-way interface signals are explicit.
  logic [1:0] packet_tage_prediction_o,packet_tage_alt_prediction_o,packet_tage_provider_way_o; logic [1:0][1:0] packet_tage_provider_o; logic [1:0][7:0] packet_tage_base_index_o; logic [1:0][6:0] packet_tage_comp0_index_o,packet_tage_comp1_index_o; logic [1:0][9:0] packet_tage_comp0_tag_o,packet_tage_comp1_tag_o; logic packet_indirect_meta_valid_o; logic [63:0] packet_indirect_meta_pc_o; logic [7:0] packet_indirect_meta_history_o;
  logic retire_btb_valid_i; logic [63:0] retire_btb_pc_i,retire_btb_target_i; logic [1:0] retire_btb_kind_i;
  logic retire_tage_valid_i,retire_tage_taken_i,retire_tage_provider_way_i,retire_tage_meta_valid_i,retire_tage_prediction_i,retire_tage_alt_prediction_i; logic [7:0] retire_tage_base_index_i; logic [6:0] retire_tage_comp0_index_i,retire_tage_comp1_index_i; logic [9:0] retire_tage_comp0_tag_i,retire_tage_comp1_tag_i; logic [1:0] retire_tage_provider_i;
  logic retire_indirect_valid_i,retire_indirect_meta_valid_i; logic [63:0] retire_indirect_pc_i,retire_indirect_target_i; logic [7:0] retire_indirect_history_i;
  logic [1:0] hold_valid,hold_taken,hold_tage,hold_way; logic [1:0][63:0] hold_pc; logic [1:0][7:0] hold_base; logic hold_meta; int unsigned checks;
  rv64_fetch_predictor dut(.*); always #5 clk_i=~clk_i;
  task automatic check(input logic c,input string s); checks++; if(!c)$fatal(1,"predictor: %s",s); endtask
  task automatic clear_rsp; begin for(int i=0;i<WINDOW_BYTES;i++) begin response_data_i[i]=0;response_valid_bytes_i[i]=1;response_fault_i[i]=0;end end endtask
  task automatic word(input int unsigned i,input logic[31:0] v); begin response_data_i[i]=v[7:0];response_data_i[i+1]=v[15:8];response_data_i[i+2]=v[23:16];response_data_i[i+3]=v[31:24];end endtask
  task automatic req(input logic[63:0] b); begin @(negedge clk_i);check(request_valid_o,"request valid");check(request_base_pc_o==b,"request base");request_ready_i=1;@(posedge clk_i);@(negedge clk_i);request_ready_i=0;end endtask
  task automatic rsp; begin @(negedge clk_i);response_valid_i=1;check(response_ready_o,"response ready");@(posedge clk_i);@(negedge clk_i);response_valid_i=0;end endtask
  task automatic consume; begin @(negedge clk_i);packet_ready_i=1;@(posedge clk_i);@(negedge clk_i);packet_ready_i=0;end endtask
  task automatic idle_train; begin retire_btb_valid_i=0;retire_tage_valid_i=0;retire_tage_meta_valid_i=0;retire_indirect_valid_i=0;retire_indirect_meta_valid_i=0;end endtask
  initial begin
    clk_i=0;rst_ni=0;checks=0;fetch_enable_i=1;flush_valid_i=0;redirect_valid_i=0;redirect_is_branch_i=0;redirect_taken_i=0;flush_pc_i=0;redirect_pc_i=0;redirect_history_i=0;redirect_ras_sp_i=0;redirect_ras_count_i=0;redirect_ras_entries_i=0;request_ready_i=0;response_valid_i=0;packet_ready_i=0;retire_btb_pc_i=0;retire_btb_target_i=0;retire_btb_kind_i=0;retire_tage_taken_i=0;retire_tage_provider_way_i=0;retire_tage_prediction_i=0;retire_tage_alt_prediction_i=0;retire_tage_base_index_i=0;retire_tage_comp0_index_i=0;retire_tage_comp1_index_i=0;retire_tage_comp0_tag_i=0;retire_tage_comp1_tag_i=0;retire_tage_provider_i=0;retire_indirect_pc_i=0;retire_indirect_target_i=0;retire_indirect_history_i=0;idle_train();clear_rsp();repeat(2)@(posedge clk_i);@(negedge clk_i);rst_ni=1;@(posedge clk_i);
    // Direct JAL and a retirement update while its packet is held.
    req(64'h1000);clear_rsp();word(0,32'h008000ef);word(4,32'h00100093);rsp();check(packet_valid_o==2'b01&&packet_pred_taken_o[0]&&packet_pred_target_o[0]==64'h1008,"direct JAL");
    hold_valid=packet_valid_o;hold_pc=packet_pc_o;hold_taken=packet_pred_taken_o;hold_tage=packet_tage_prediction_o;hold_way=packet_tage_provider_way_o;hold_base=packet_tage_base_index_o;hold_meta=packet_indirect_meta_valid_o;
    @(negedge clk_i);retire_tage_valid_i=1;retire_tage_meta_valid_i=1;retire_tage_taken_i=1;retire_tage_prediction_i=packet_tage_prediction_o[0];retire_tage_alt_prediction_i=packet_tage_alt_prediction_o[0];retire_tage_provider_i=packet_tage_provider_o[0];retire_tage_provider_way_i=packet_tage_provider_way_o[0];retire_tage_base_index_i=packet_tage_base_index_o[0];retire_tage_comp0_index_i=packet_tage_comp0_index_o[0];retire_tage_comp1_index_i=packet_tage_comp1_index_o[0];retire_tage_comp0_tag_i=packet_tage_comp0_tag_o[0];retire_tage_comp1_tag_i=packet_tage_comp1_tag_o[0];retire_btb_valid_i=1;retire_btb_pc_i=64'h1008;retire_btb_target_i=64'h1010;retire_btb_kind_i=2'b01;@(posedge clk_i);@(negedge clk_i);idle_train();
    check(packet_valid_o==hold_valid&&packet_pc_o==hold_pc&&packet_pred_taken_o==hold_taken,"training during stall stable");check(packet_tage_prediction_o==hold_tage&&packet_tage_provider_way_o==hold_way&&packet_tage_base_index_o==hold_base&&packet_indirect_meta_valid_o==hold_meta,"complete metadata stable");consume();
    // A direct-kind BTB entry cannot redirect a conditional. Fall-through is lane 1.
    req(64'h1000);clear_rsp();word(8,32'h00000063);word(12,32'h00100093);rsp();check(packet_valid_o==2'b01&&packet_pc_o[0]==64'h1008&&!packet_pred_taken_o[0],"conditional rejects mismatched BTB kind");consume();req(64'h1000);clear_rsp();word(12,32'h00100093);rsp();check(packet_pc_o[0]==64'h100c,"conditional miss preserves lane1 PC");consume();
    // Indirect and return misses are likewise terminal but refetch lane 1.
    @(negedge clk_i);redirect_valid_i=1;redirect_pc_i=64'h1200;@(posedge clk_i);@(negedge clk_i);redirect_valid_i=0;req(64'h1200);clear_rsp();word(0,32'h00010067);word(4,32'h00100093);rsp();check(packet_valid_o==2'b01&&!packet_pred_taken_o[0]&&packet_indirect_meta_valid_o&&packet_indirect_meta_pc_o==64'h1200,"indirect miss carries qualified metadata");consume();req(64'h1200);clear_rsp();word(4,32'h00100093);rsp();check(packet_pc_o[0]==64'h1204,"indirect miss preserves lane1 PC");consume();
    @(negedge clk_i);redirect_valid_i=1;redirect_pc_i=64'h1300;@(posedge clk_i);@(negedge clk_i);redirect_valid_i=0;req(64'h1300);clear_rsp();word(0,32'h00008067);rsp();check(packet_valid_o==2'b01&&!packet_pred_taken_o[0],"return miss");consume();req(64'h1300);clear_rsp();word(4,32'h00100093);rsp();check(packet_pc_o[0]==64'h1304,"return miss preserves lane1 PC");
    // Retirement metadata must train both direction and target at the original
    // branch PC; a later lookup proves this is functional wiring, not stimulus.
    @(negedge clk_i);redirect_valid_i=1;redirect_pc_i=64'h1400;@(posedge clk_i);@(negedge clk_i);redirect_valid_i=0;
    req(64'h1400);clear_rsp();word(0,32'h02000063);word(4,32'h00100093);rsp();
    check(packet_valid_o==2'b01&&!packet_pred_taken_o[0]&&packet_tage_provider_o[0]==2'b00,"cold conditional metadata");
    @(negedge clk_i);
    retire_tage_taken_i=1;retire_tage_prediction_i=packet_tage_prediction_o[0];retire_tage_alt_prediction_i=packet_tage_alt_prediction_o[0];
    retire_tage_provider_i=packet_tage_provider_o[0];retire_tage_provider_way_i=packet_tage_provider_way_o[0];retire_tage_base_index_i=packet_tage_base_index_o[0];
    retire_tage_comp0_index_i=packet_tage_comp0_index_o[0];retire_tage_comp1_index_i=packet_tage_comp1_index_o[0];
    retire_tage_comp0_tag_i=packet_tage_comp0_tag_o[0];retire_tage_comp1_tag_i=packet_tage_comp1_tag_o[0];
    retire_btb_pc_i=64'h1400;retire_btb_target_i=64'h1420;retire_btb_kind_i=2'b00;
    consume();
    @(negedge clk_i);retire_tage_valid_i=1;retire_tage_meta_valid_i=1;retire_btb_valid_i=1;@(posedge clk_i);@(negedge clk_i);idle_train();
    redirect_valid_i=1;redirect_pc_i=64'h1400;@(posedge clk_i);@(negedge clk_i);redirect_valid_i=0;
    req(64'h1400);clear_rsp();word(0,32'h02000063);word(4,32'h00100093);rsp();
    check(packet_pred_taken_o[0]&&packet_pred_target_o[0]==64'h1420&&packet_pred_kind_o[0]==2'b00,"retirement BTB and TAGE training affects later lookup");
    // Recovery while stalled, flush-over-redirect, response+recovery, and stale response.
    @(negedge clk_i);flush_valid_i=1;flush_pc_i=64'h2000;redirect_valid_i=1;redirect_pc_i=64'h3000;@(posedge clk_i);@(negedge clk_i);flush_valid_i=0;redirect_valid_i=0;check(packet_valid_o==0,"flush wins and clears stalled packet");@(posedge clk_i);req(64'h2000);
    @(negedge clk_i);redirect_valid_i=1;redirect_pc_i=64'h4000;response_valid_i=1;@(posedge clk_i);@(negedge clk_i);redirect_valid_i=0;response_valid_i=0;check(packet_valid_o==0&&!packet_indirect_meta_valid_o,"response plus recovery discarded and metadata invalid");@(posedge clk_i);req(64'h4000);@(negedge clk_i);redirect_valid_i=1;redirect_pc_i=64'h5000;@(posedge clk_i);@(negedge clk_i);redirect_valid_i=0;clear_rsp();rsp();check(packet_valid_o==0&&!packet_indirect_meta_valid_o,"stale response discarded");
    $display("PASS: %0d fetch-predictor checks",checks);$finish;
  end
endmodule
