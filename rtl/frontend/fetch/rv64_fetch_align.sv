// SPDX-License-Identifier: Apache-2.0
// Two-wide instruction aligner for a 32-byte VDD_CORE instruction window.
// This block is combinational. Byte zero is the least-significant byte at
// window_base_pc_i; faults are terminal and never expose instruction payload.
module rv64_fetch_align #(
  parameter int unsigned ADDR_W = 64,
  parameter int unsigned WINDOW_BYTES = 32
) (
  input  logic [ADDR_W-1:0]              start_pc_i,
  input  logic [ADDR_W-1:0]              window_base_pc_i,
  input  logic [7:0]                     window_data_i [WINDOW_BYTES],
  input  logic                           window_valid_i [WINDOW_BYTES],
  input  logic                           window_fault_i [WINDOW_BYTES],
  output logic [1:0]                     instruction_valid_o,
  output logic [1:0][ADDR_W-1:0]         instruction_pc_o,
  output logic [1:0][31:0]               instruction_o,
  output logic [1:0][31:0]               raw_instruction_o,
  output logic [1:0]                     compressed_o,
  output logic [1:0]                     illegal_compressed_o,
  output logic [1:0]                     fetch_fault_o,
  output logic [ADDR_W-1:0]              sequential_next_pc_o
);
  logic [1:0][15:0] compressed_halfword;
  logic [1:0][31:0] decompressed_instruction;
  logic [1:0] compressed_legal;

  initial begin
    assert (ADDR_W == 64);
    assert (WINDOW_BYTES == 32);
  end

  for (genvar lane = 0; lane < 2; lane = lane + 1) begin : g_decompress
    assign compressed_halfword[lane] = raw_instruction_o[lane][15:0];
    rv64c_decompress u_decompress (
      .c_instruction_i(compressed_halfword[lane]),
      .instruction_o(decompressed_instruction[lane]),
      .legal_o(compressed_legal[lane])
    );
  end

  always_comb begin : p_align
    logic continue_fetch;
    logic first_two_available;
    logic any_required_fault;
    logic all_required_available;
    logic is_compressed;
    int unsigned current_index;
    int unsigned instruction_bytes;

    instruction_valid_o = '0;
    instruction_pc_o = '0;
    raw_instruction_o = '0;
    compressed_o = '0;
    fetch_fault_o = '0;
    sequential_next_pc_o = start_pc_i;
    first_two_available = 1'b0;
    any_required_fault = 1'b0;
    all_required_available = 1'b0;
    is_compressed = 1'b0;
    instruction_bytes = 0;

    current_index = int'(start_pc_i - window_base_pc_i);
    continue_fetch = 1'b1;
    for (int unsigned lane = 0; lane < 2; lane = lane + 1) begin
      if (continue_fetch) begin
        first_two_available = (current_index < WINDOW_BYTES) &&
                              ((current_index + 1) < WINDOW_BYTES) &&
                              (window_valid_i[current_index] || window_fault_i[current_index]) &&
                              (window_valid_i[current_index + 1] || window_fault_i[current_index + 1]);
        if (!first_two_available) begin
          continue_fetch = 1'b0;
        end else if (window_fault_i[current_index] || window_fault_i[current_index + 1]) begin
          instruction_valid_o[lane] = 1'b1;
          instruction_pc_o[lane] = window_base_pc_i + ADDR_W'(current_index);
          fetch_fault_o[lane] = 1'b1;
          continue_fetch = 1'b0;
        end else begin
          is_compressed = window_data_i[current_index][1:0] != 2'b11;
          instruction_bytes = is_compressed ? 2 : 4;
          all_required_available = 1'b1;
          any_required_fault = window_fault_i[current_index] ||
                               window_fault_i[current_index + 1];
          if (!is_compressed) begin
            if ((current_index + 3) >= WINDOW_BYTES) begin
              all_required_available = 1'b0;
            end else begin
              all_required_available =
                  (window_valid_i[current_index + 2] || window_fault_i[current_index + 2]) &&
                  (window_valid_i[current_index + 3] || window_fault_i[current_index + 3]);
              any_required_fault = any_required_fault ||
                                   window_fault_i[current_index + 2] ||
                                   window_fault_i[current_index + 3];
            end
          end
          if (!all_required_available) begin
            continue_fetch = 1'b0;
          end else if (any_required_fault) begin
            instruction_valid_o[lane] = 1'b1;
            instruction_pc_o[lane] = window_base_pc_i + ADDR_W'(current_index);
            fetch_fault_o[lane] = 1'b1;
            continue_fetch = 1'b0;
          end else begin
            instruction_valid_o[lane] = 1'b1;
            instruction_pc_o[lane] = window_base_pc_i + ADDR_W'(current_index);
            compressed_o[lane] = is_compressed;
            raw_instruction_o[lane][7:0] = window_data_i[current_index];
            raw_instruction_o[lane][15:8] = window_data_i[current_index + 1];
            if (!is_compressed) begin
              raw_instruction_o[lane][23:16] = window_data_i[current_index + 2];
              raw_instruction_o[lane][31:24] = window_data_i[current_index + 3];
            end
            current_index = current_index + instruction_bytes;
            sequential_next_pc_o = window_base_pc_i + ADDR_W'(current_index);
          end
        end
      end
    end
  end

  always_comb begin : p_payload
    instruction_o = '0;
    illegal_compressed_o = '0;
    for (int unsigned lane = 0; lane < 2; lane = lane + 1) begin
      if (instruction_valid_o[lane] && !fetch_fault_o[lane]) begin
        if (compressed_o[lane]) begin
          instruction_o[lane] = decompressed_instruction[lane];
          illegal_compressed_o[lane] = !compressed_legal[lane];
        end else begin
          instruction_o[lane] = raw_instruction_o[lane];
        end
      end
    end
  end

  always_comb begin : p_invariants
    assert (window_base_pc_i[3:0] == 4'b0);
    assert (start_pc_i[0] == 1'b0);
    assert ((start_pc_i >= window_base_pc_i) &&
            (start_pc_i < (window_base_pc_i + ADDR_W'(16))));
    assert (!instruction_valid_o[1] || instruction_valid_o[0]);
    if (instruction_valid_o[1])
      assert (instruction_pc_o[1] == instruction_pc_o[0] +
              (compressed_o[0] ? ADDR_W'(2) : ADDR_W'(4)));
    if (fetch_fault_o[0]) assert (!instruction_valid_o[1]);
    for (int unsigned lane = 0; lane < 2; lane = lane + 1) begin
      if (!instruction_valid_o[lane]) assert (instruction_pc_o[lane] == '0);
      if (instruction_valid_o[lane]) assert (instruction_pc_o[lane][0] == 1'b0);
      if (!instruction_valid_o[lane] || fetch_fault_o[lane]) begin
        assert (instruction_o[lane] == 32'b0);
        assert (raw_instruction_o[lane] == 32'b0);
        assert (compressed_o[lane] == 1'b0);
        assert (illegal_compressed_o[lane] == 1'b0);
      end
      if (illegal_compressed_o[lane]) begin
        assert (instruction_valid_o[lane] && !fetch_fault_o[lane]);
        assert (compressed_o[lane] && !compressed_legal[lane]);
        assert (raw_instruction_o[lane][31:16] == 16'b0);
        assert (instruction_o[lane] == 32'b0);
      end
      if (instruction_valid_o[lane] && !fetch_fault_o[lane] && !compressed_o[lane])
        assert (instruction_o[lane] == raw_instruction_o[lane]);
    end
  end
endmodule
