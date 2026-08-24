// SPDX-License-Identifier: Apache-2.0
module fetch_align_tb;
  localparam int unsigned ADDR_W = 64;
  localparam int unsigned WINDOW_BYTES = 32;
  localparam int unsigned RANDOM_CASES = 2048;
  localparam logic [31:0] RANDOM_SEED = 32'h5eed_1234;

  logic [ADDR_W-1:0] start_pc_i;
  logic [ADDR_W-1:0] window_base_pc_i;
  logic [7:0] window_data_i [WINDOW_BYTES];
  logic window_valid_i [WINDOW_BYTES];
  logic window_fault_i [WINDOW_BYTES];
  logic [1:0] instruction_valid_o;
  logic [1:0][ADDR_W-1:0] instruction_pc_o;
  logic [1:0][31:0] instruction_o;
  logic [1:0][31:0] raw_instruction_o;
  logic [1:0] compressed_o;
  logic [1:0] illegal_compressed_o;
  logic [1:0] fetch_fault_o;
  logic [ADDR_W-1:0] sequential_next_pc_o;
  int unsigned checks;
  logic [31:0] random_state;
  int unsigned random_success_hits [2];
  int unsigned random_missing_hits [2];
  int unsigned random_first_fault_hits [2];
  int unsigned random_tail_fault_hits [2];
  int unsigned random_offset_hits [8];

  rv64_fetch_align #(.ADDR_W(ADDR_W), .WINDOW_BYTES(WINDOW_BYTES)) dut (.*);

  task automatic check(input logic condition, input string message);
    checks++;
    if (!condition) $fatal(1, "fetch align check failed: %s", message);
  endtask

  task automatic clear_window;
    begin
      window_base_pc_i = 64'h1000;
      start_pc_i = 64'h1000;
      for (int unsigned index = 0; index < WINDOW_BYTES; index = index + 1) begin
        window_data_i[index] = 8'h00;
        window_valid_i[index] = 1'b1;
        window_fault_i[index] = 1'b0;
      end
    end
  endtask

  task automatic put_halfword(input int unsigned index, input logic [15:0] value);
    begin
      window_data_i[index] = value[7:0];
      window_data_i[index + 1] = value[15:8];
    end
  endtask

  task automatic put_word(input int unsigned index, input logic [31:0] value);
    begin
      window_data_i[index] = value[7:0];
      window_data_i[index + 1] = value[15:8];
      window_data_i[index + 2] = value[23:16];
      window_data_i[index + 3] = value[31:24];
    end
  endtask

  task automatic expect_lane(
    input int unsigned lane,
    input logic expected_valid,
    input logic expected_fault,
    input logic expected_compressed,
    input logic expected_illegal,
    input logic [63:0] expected_pc,
    input logic [31:0] expected_instruction,
    input logic [31:0] expected_raw,
    input string label
  );
    begin
      check(instruction_valid_o[lane] == expected_valid, {label, " valid"});
      check(fetch_fault_o[lane] == expected_fault, {label, " fault"});
      check(compressed_o[lane] == expected_compressed, {label, " compressed"});
      check(illegal_compressed_o[lane] == expected_illegal, {label, " illegal"});
      check(instruction_pc_o[lane] == expected_pc, {label, " pc"});
      check(instruction_o[lane] == expected_instruction, {label, " instruction"});
      check(raw_instruction_o[lane] == expected_raw, {label, " raw"});
    end
  endtask

  task automatic random_step;
    begin
      random_state = (random_state * 32'd1664525) + 32'd1013904223;
    end
  endtask

  task automatic check_random_native_reference(input int unsigned case_id);
    logic [1:0] expected_valid;
    logic [1:0] expected_fault;
    logic [1:0][63:0] expected_pc;
    logic [1:0][31:0] expected_raw;
    logic [63:0] expected_next;
    logic active;
    logic first_two_available;
    logic all_available;
    logic any_fault;
    int unsigned index;
    begin
      expected_valid = '0;
      expected_fault = '0;
      expected_pc = '0;
      expected_raw = '0;
      expected_next = start_pc_i;
      index = int'(start_pc_i - window_base_pc_i);
      active = 1'b1;
      for (int unsigned lane = 0; lane < 2; lane = lane + 1) begin
        if (active) begin
          first_two_available = (window_valid_i[index] || window_fault_i[index]) &&
                                (window_valid_i[index + 1] || window_fault_i[index + 1]);
          if (!first_two_available) begin
            random_missing_hits[lane]++;
            active = 1'b0;
          end else if (window_fault_i[index] || window_fault_i[index + 1]) begin
            random_first_fault_hits[lane]++;
            expected_valid[lane] = 1'b1;
            expected_fault[lane] = 1'b1;
            expected_pc[lane] = window_base_pc_i + 64'(index);
            active = 1'b0;
          end else begin
            all_available = 1'b1;
            any_fault = 1'b0;
            for (int unsigned byte_index = 0; byte_index < 4; byte_index = byte_index + 1) begin
              if (!(window_valid_i[index + byte_index] || window_fault_i[index + byte_index]))
                all_available = 1'b0;
              if (window_fault_i[index + byte_index]) any_fault = 1'b1;
            end
            if (!all_available) begin
              random_missing_hits[lane]++;
              active = 1'b0;
            end else if (any_fault) begin
              random_tail_fault_hits[lane]++;
              expected_valid[lane] = 1'b1;
              expected_fault[lane] = 1'b1;
              expected_pc[lane] = window_base_pc_i + 64'(index);
              active = 1'b0;
            end else begin
              random_success_hits[lane]++;
              expected_valid[lane] = 1'b1;
              expected_pc[lane] = window_base_pc_i + 64'(index);
              expected_raw[lane] = {window_data_i[index + 3], window_data_i[index + 2],
                                    window_data_i[index + 1], window_data_i[index]};
              index = index + 4;
              expected_next = window_base_pc_i + 64'(index);
            end
          end
        end
      end
      #1;
      for (int unsigned lane = 0; lane < 2; lane = lane + 1) begin
        check(instruction_valid_o[lane] == expected_valid[lane], $sformatf("random %0d lane %0d valid", case_id, lane));
        check(fetch_fault_o[lane] == expected_fault[lane], $sformatf("random %0d lane %0d fault", case_id, lane));
        check(instruction_pc_o[lane] == expected_pc[lane], $sformatf("random %0d lane %0d pc", case_id, lane));
        check(compressed_o[lane] == 1'b0, $sformatf("random %0d lane %0d native", case_id, lane));
        check(instruction_o[lane] == expected_raw[lane], $sformatf("random %0d lane %0d instruction", case_id, lane));
        check(raw_instruction_o[lane] == expected_raw[lane], $sformatf("random %0d lane %0d raw", case_id, lane));
      end
      check(sequential_next_pc_o == expected_next, $sformatf("random %0d next pc", case_id));
    end
  endtask

  initial begin
    checks = 0;
    for (int unsigned lane = 0; lane < 2; lane = lane + 1) begin
      random_success_hits[lane] = 0;
      random_missing_hits[lane] = 0;
      random_first_fault_hits[lane] = 0;
      random_tail_fault_hits[lane] = 0;
    end
    for (int unsigned offset = 0; offset < 8; offset = offset + 1)
      random_offset_hits[offset] = 0;
    clear_window();

    // 16 + 16
    put_halfword(0, 16'h0001); put_halfword(2, 16'h0001); #1;
    expect_lane(0, 1, 0, 1, 0, 64'h1000, 32'h00000013, 32'h00000001, "16+16 lane0");
    expect_lane(1, 1, 0, 1, 0, 64'h1002, 32'h00000013, 32'h00000001, "16+16 lane1");
    check(sequential_next_pc_o == 64'h1004, "16+16 next pc");

    // 16 + 32
    clear_window(); put_halfword(0, 16'h0001); put_word(2, 32'h00c585b3); #1;
    expect_lane(0, 1, 0, 1, 0, 64'h1000, 32'h00000013, 32'h00000001, "16+32 lane0");
    expect_lane(1, 1, 0, 0, 0, 64'h1002, 32'h00c585b3, 32'h00c585b3, "16+32 lane1");
    check(sequential_next_pc_o == 64'h1006, "16+32 next pc");

    // 32 + 16
    clear_window(); put_word(0, 32'h00c585b3); put_halfword(4, 16'h0001); #1;
    expect_lane(0, 1, 0, 0, 0, 64'h1000, 32'h00c585b3, 32'h00c585b3, "32+16 lane0");
    expect_lane(1, 1, 0, 1, 0, 64'h1004, 32'h00000013, 32'h00000001, "32+16 lane1");
    check(sequential_next_pc_o == 64'h1006, "32+16 next pc");

    // 32 + 32
    clear_window(); put_word(0, 32'h00c585b3); put_word(4, 32'h00100093); #1;
    expect_lane(0, 1, 0, 0, 0, 64'h1000, 32'h00c585b3, 32'h00c585b3, "32+32 lane0");
    expect_lane(1, 1, 0, 0, 0, 64'h1004, 32'h00100093, 32'h00100093, "32+32 lane1");
    check(sequential_next_pc_o == 64'h1008, "32+32 next pc");

    // A native instruction starting at byte 14 crosses the first 16-byte window.
    clear_window(); start_pc_i = 64'h100e; put_word(14, 32'h00100093); put_halfword(18, 16'h0001); #1;
    expect_lane(0, 1, 0, 0, 0, 64'h100e, 32'h00100093, 32'h00100093, "crossing lane0");
    expect_lane(1, 1, 0, 1, 0, 64'h1012, 32'h00000013, 32'h00000001, "crossing lane1");
    check(sequential_next_pc_o == 64'h1014, "crossing next pc");

    // Illegal compressed encoding remains visible through raw_instruction_o.
    clear_window(); put_halfword(0, 16'h6001); #1;
    expect_lane(0, 1, 0, 1, 1, 64'h1000, 32'h00000000, 32'h00006001, "illegal compressed lane0");
    check(instruction_valid_o[1], "illegal compressed may still permit lane1 assembly");

    // Native instruction with missing tail bytes produces no packet.
    clear_window(); put_word(0, 32'h00100093); window_valid_i[2] = 1'b0; #1;
    expect_lane(0, 0, 0, 0, 0, 64'h0, 32'h0, 32'h0, "missing tail lane0");
    expect_lane(1, 0, 0, 0, 0, 64'h0, 32'h0, 32'h0, "missing tail lane1");
    check(sequential_next_pc_o == 64'h1000, "missing tail retains start pc");

    // Fault in the first pair and a later native tail fault are both terminal.
    clear_window(); window_valid_i[0] = 1'b0; window_fault_i[0] = 1'b1; #1;
    expect_lane(0, 1, 1, 0, 0, 64'h1000, 32'h0, 32'h0, "initial fault lane0");
    expect_lane(1, 0, 0, 0, 0, 64'h0, 32'h0, 32'h0, "initial fault lane1");
    check(sequential_next_pc_o == 64'h1000, "initial fault retains start pc");

    clear_window(); put_word(0, 32'h00100093); window_valid_i[3] = 1'b0; window_fault_i[3] = 1'b1; #1;
    expect_lane(0, 1, 1, 0, 0, 64'h1000, 32'h0, 32'h0, "tail fault lane0");
    expect_lane(1, 0, 0, 0, 0, 64'h0, 32'h0, 32'h0, "tail fault lane1");
    check(sequential_next_pc_o == 64'h1000, "tail fault retains start pc");

    // Native-only randomized reference model: masks and all permitted offsets vary.
    random_state = RANDOM_SEED;
    for (int unsigned case_id = 0; case_id < RANDOM_CASES; case_id = case_id + 1) begin
      clear_window();
      start_pc_i = window_base_pc_i + 64'(int'(case_id % 8) * 2);
      random_offset_hits[case_id % 8]++;
      for (int unsigned index = 0; index < WINDOW_BYTES; index = index + 1) begin
        random_step(); window_data_i[index] = random_state[7:0];
        window_data_i[index][1:0] = 2'b11;
        random_step(); window_valid_i[index] = random_state[31:30] != 2'b00;
        random_step(); window_fault_i[index] = random_state[31:28] == 4'h0;
      end
      check_random_native_reference(case_id);
    end

    for (int unsigned lane = 0; lane < 2; lane = lane + 1) begin
      check(random_success_hits[lane] > 0, $sformatf("random lane %0d success coverage", lane));
      check(random_missing_hits[lane] > 0, $sformatf("random lane %0d missing coverage", lane));
      check(random_first_fault_hits[lane] > 0, $sformatf("random lane %0d first-pair fault coverage", lane));
      check(random_tail_fault_hits[lane] > 0, $sformatf("random lane %0d tail fault coverage", lane));
      $display("COVERAGE lane %0d: success=%0d missing=%0d first_fault=%0d tail_fault=%0d",
               lane, random_success_hits[lane], random_missing_hits[lane],
               random_first_fault_hits[lane], random_tail_fault_hits[lane]);
    end
    for (int unsigned offset = 0; offset < 8; offset = offset + 1)
      check(random_offset_hits[offset] > 0, $sformatf("random halfword offset %0d coverage", offset));

    $display("PASS: %0d fetch-align checks (random seed %08x)", checks, RANDOM_SEED);
    $finish;
  end
endmodule
