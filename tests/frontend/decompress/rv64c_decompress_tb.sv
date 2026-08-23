// SPDX-License-Identifier: Apache-2.0
module rv64c_decompress_tb;
  logic [15:0] compressed;
  logic [31:0] instruction;
  logic legal;
  int unsigned checks;
  int unsigned legal_count;

  rv64c_decompress dut (
    .c_instruction_i(compressed),
    .instruction_o(instruction),
    .legal_o(legal)
  );

  task automatic check_vector(input logic [15:0] c_insn, input logic exp_legal,
                              input logic [31:0] exp_insn, input string name);
    begin
      compressed = c_insn;
      #1;
      checks++;
      if (legal != exp_legal || instruction != exp_insn)
        $fatal(1, "%s c=%04h: got legal=%0b insn=%08h, expected legal=%0b insn=%08h",
               name, c_insn, legal, instruction, exp_legal, exp_insn);
    end
  endtask

  initial begin
    checks = 0;
    legal_count = 0;
    compressed = '0;

    // One canonical vector per RV64C operation; constants are standard 32-bit encodings.
    check_vector(16'h0084, 1'b1, 32'h0401_0493, "C.ADDI4SPN");
    check_vector(16'h2088, 1'b1, 32'h0004_b507, "C.FLD");
    check_vector(16'h4088, 1'b1, 32'h0004_a503, "C.LW");
    check_vector(16'h6088, 1'b1, 32'h0004_b503, "C.LD");
    check_vector(16'h8085, 1'b1, 32'h0014_d493, "C.SRLI");
    check_vector(16'h8485, 1'b1, 32'h4014_d493, "C.SRAI");
    check_vector(16'h8885, 1'b1, 32'h0014_f493, "C.ANDI");
    check_vector(16'h8c89, 1'b1, 32'h40a4_84b3, "C.SUB");
    check_vector(16'h8ca9, 1'b1, 32'h00a4_c4b3, "C.XOR");
    check_vector(16'h8cc9, 1'b1, 32'h00a4_e4b3, "C.OR");
    check_vector(16'h8ce9, 1'b1, 32'h00a4_f4b3, "C.AND");
    check_vector(16'h9c89, 1'b1, 32'h40a4_84bb, "C.SUBW");
    check_vector(16'h9ca9, 1'b1, 32'h00a4_84bb, "C.ADDW");
    check_vector(16'ha088, 1'b1, 32'h00a4_b027, "C.FSD");
    check_vector(16'hc088, 1'b1, 32'h00a4_a023, "C.SW");
    check_vector(16'he088, 1'b1, 32'h00a4_b023, "C.SD");
    check_vector(16'h1485, 1'b1, 32'hfe14_8493, "C.ADDIW");
    check_vector(16'h4505, 1'b1, 32'h0010_0513, "C.LI");
    check_vector(16'h6141, 1'b1, 32'h0101_0113, "C.ADDI16SP");
    check_vector(16'h6505, 1'b1, 32'h0000_1537, "C.LUI");
    check_vector(16'h6005, 1'b1, 32'h0000_1037, "C.LUI x0 HINT");
    check_vector(16'ha001, 1'b1, 32'h0000_006f, "C.J");
    check_vector(16'hc001, 1'b1, 32'h0004_0063, "C.BEQZ");
    check_vector(16'he001, 1'b1, 32'h0004_1063, "C.BNEZ");
    check_vector(16'h0286, 1'b1, 32'h0012_9293, "C.SLLI");
    check_vector(16'h2482, 1'b1, 32'h0001_3487, "C.FLDSP");
    check_vector(16'h2002, 1'b1, 32'h0001_3007, "C.FLDSP f0");
    check_vector(16'h4482, 1'b1, 32'h0001_2483, "C.LWSP");
    check_vector(16'h6482, 1'b1, 32'h0001_3483, "C.LDSP");
    check_vector(16'h828a, 1'b1, 32'h0020_02b3, "C.MV");
    check_vector(16'h8282, 1'b1, 32'h0002_8067, "C.JR");
    check_vector(16'h9282, 1'b1, 32'h0002_80e7, "C.JALR");
    check_vector(16'h9002, 1'b1, 32'h0010_0073, "C.EBREAK");
    check_vector(16'h928a, 1'b1, 32'h0022_82b3, "C.ADD");
    check_vector(16'h8006, 1'b1, 32'h0010_0033, "C.MV x0 HINT");
    check_vector(16'h9006, 1'b1, 32'h0010_0033, "C.ADD x0 HINT");
    check_vector(16'ha206, 1'b1, 32'h1011_3027, "C.FSDSP");
    check_vector(16'hc206, 1'b1, 32'h0011_2223, "C.SWSP");
    check_vector(16'he206, 1'b1, 32'h1011_3023, "C.SDSP");

    // Reserved encodings, including the complete fourth quadrant, must be explicit illegal outputs.
    check_vector(16'h0000, 1'b0, 32'b0, "C.ADDI4SPN zero immediate");
    check_vector(16'h2001, 1'b0, 32'b0, "C.ADDIW rd zero");
    check_vector(16'h6101, 1'b0, 32'b0, "C.ADDI16SP zero immediate");
    check_vector(16'h6001, 1'b0, 32'b0, "C.LUI rd zero");
    check_vector(16'h9c61, 1'b0, 32'b0, "reserved C arithmetic");
    check_vector(16'h0002, 1'b1, 32'h0000_1013, "C.SLLI x0 HINT");
    check_vector(16'h4002, 1'b0, 32'b0, "C.LWSP rd zero");
    check_vector(16'h8002, 1'b0, 32'b0, "reserved C.JR x0");
    check_vector(16'hffff, 1'b0, 32'b0, "non-compressed length encoding");

    // Exhaustively exercise every 16-bit pattern. These protocol invariants catch
    // unclassified encodings and ensure illegal candidates cannot reach decode.
    for (int unsigned value = 0; value < 65536; value++) begin
      compressed = value[15:0];
      #1;
      checks++;
      if (legal) begin
        legal_count++;
        if (instruction[1:0] != 2'b11)
          $fatal(1, "legal compressed instruction c=%04h emitted non-32-bit encoding %08h",
                 compressed, instruction);
      end else if (instruction != 32'b0) begin
        $fatal(1, "illegal compressed instruction c=%04h emitted %08h", compressed, instruction);
      end
    end

    if (legal_count == 0 || legal_count == 49152)
      $fatal(1, "exhaustive legality partition is implausible: %0d legal encodings", legal_count);
    $display("PASS: %0d decompressor checks (%0d legal encodings)", checks, legal_count);
    $finish;
  end
endmodule
