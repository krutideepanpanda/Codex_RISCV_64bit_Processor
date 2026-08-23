// SPDX-License-Identifier: Apache-2.0
module decoder_tb;
  import rv64_pkg::*;

  logic [31:0] instruction;
  logic valid;
  decode_t decoded;
  xlen_t immediate;
  int unsigned checks;

  rv64_decoder dut (
    .instruction_i(instruction),
    .valid_i(valid),
    .decoded_o(decoded),
    .immediate_o(immediate)
  );

  task automatic apply(input logic [31:0] insn);
    begin
      instruction = insn;
      valid = 1'b1;
      #1;
      checks++;
    end
  endtask

  task automatic assert_true(input logic condition, input string message);
    if (!condition) $fatal(1, "%s: instruction=%08h", message, instruction);
  endtask

  initial begin
    checks = 0;
    instruction = '0;
    valid = 1'b0;
    #1;
    assert_true(!decoded.valid && !decoded.illegal, "invalid input must be inert");
    assert_true(!decoded.reads_rs1 && !decoded.reads_rs2 &&
                !decoded.writes_rd && decoded.uop_class == UOP_NONE,
                "invalid input side effects must be inert");

    // LUI and AUIPC require different first operands.
    apply(32'h0000_00b7);
    assert_true(!decoded.illegal && decoded.operand_a_sel == OPA_ZERO,
                "LUI uses zero operand");
    apply(32'h0000_0097);
    assert_true(!decoded.illegal && decoded.operand_a_sel == OPA_PC,
                "AUIPC uses PC operand");

    // addi x5, x6, -1
    apply(32'hfff3_0293);
    assert_true(!decoded.illegal, "ADDI legal");
    assert_true(decoded.uop_class == UOP_ALU && decoded.alu_op == ALU_ADD,
           "ADDI class/op");
    assert_true(decoded.rs1 == 5'd6 && decoded.rd == 5'd5,
           "ADDI register fields");
    assert_true(decoded.reads_rs1 && decoded.writes_rd && immediate == 64'hffff_ffff_ffff_ffff,
           "ADDI controls/immediate");

    // sd x7, -16(x8)
    apply(32'hfe74_3823);
    assert_true(!decoded.illegal && decoded.uop_class == UOP_STORE,
           "SD legal/class");
    assert_true(decoded.rs1 == 5'd8 && decoded.rs2 == 5'd7,
           "SD register fields");
    assert_true(immediate == 64'hffff_ffff_ffff_fff0, "SD immediate");

    // beq x1, x2, +16
    apply(32'h0020_8863);
    assert_true(!decoded.illegal && decoded.uop_class == UOP_BRANCH,
           "BEQ legal/class");
    assert_true(immediate == 64'd16, "BEQ immediate");

    // jal x1, -4
    apply(32'hffdff0ef);
    assert_true(!decoded.illegal && decoded.uop_class == UOP_JUMP,
           "JAL legal/class");
    assert_true(immediate == 64'hffff_ffff_ffff_fffc, "JAL immediate");

    // srai x3, x4, 63
    apply(32'h43f2_5193);
    assert_true(!decoded.illegal && decoded.alu_op == ALU_SRA, "SRAI decode");

    // mul x3, x4, x5
    apply(32'h0252_01b3);
    assert_true(!decoded.illegal && decoded.uop_class == UOP_MUL, "MUL decode");

    // divu x3, x4, x5
    apply(32'h0252_51b3);
    assert_true(!decoded.illegal && decoded.uop_class == UOP_DIV, "DIVU decode");

    // funct3=001 is reserved in OP-32 M encoding.
    apply(32'h0252_11bb);
    assert_true(decoded.illegal, "reserved M word operation must trap");

    // OP-IMM-32 has no SLTIW and OP-32 has no ANDW.
    apply(32'h0001_209b);
    assert_true(decoded.illegal, "reserved SLTIW encoding must trap");
    apply(32'h0031_70bb);
    assert_true(decoded.illegal, "reserved ANDW encoding must trap");

    // LR.D requires rs2=x0 and SYSTEM funct3=100 is reserved.
    apply(32'h1011_30af);
    assert_true(decoded.illegal, "LR.D with nonzero rs2 must trap");
    apply(32'h0000_4073);
    assert_true(decoded.illegal, "reserved SYSTEM funct3 must trap");

    // Invalid branch funct3=010.
    apply(32'h0020_a863);
    assert_true(decoded.illegal, "reserved branch must trap");

    $display("PASS: %0d decoder vectors", checks);
    $finish;
  end
endmodule
