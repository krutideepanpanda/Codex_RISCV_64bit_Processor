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

  task automatic assert_illegal_contained(input string message);
    assert_true(decoded.illegal && decoded.uop_class == UOP_SYSTEM &&
                !decoded.reads_rs1 && !decoded.reads_rs2 &&
                !decoded.reads_rs3 && !decoded.writes_rd &&
                decoded.csr_op == CSR_NONE && decoded.amo_op == AMO_NONE &&
                decoded.fence_op == FENCE_NONE && decoded.serialize,
                message);
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
    assert_illegal_contained("LR.D with nonzero rs2 must trap safely");
    apply(32'h1001_30af);
    assert_true(!decoded.illegal && decoded.amo_op == AMO_LR &&
                !decoded.reads_rs2 && !decoded.amo_aq && !decoded.amo_rl,
                "LR.D controls must be preserved");
    apply(32'h1e31_30af);
    assert_true(!decoded.illegal && decoded.amo_op == AMO_SC &&
                decoded.reads_rs2 && decoded.amo_aq && decoded.amo_rl,
                "SC.D aq/rl controls must be preserved");
    apply(32'h0000_4073);
    assert_illegal_contained("reserved SYSTEM funct3 must trap safely");

    // CSR address and operation survive decode.
    apply(32'h3003_22f3);
    assert_true(!decoded.illegal && decoded.uop_class == UOP_CSR &&
                decoded.csr_addr == 12'h300 && decoded.csr_op == CSR_SET &&
                decoded.reads_rs1 && decoded.writes_rd,
                "CSRRS metadata must be preserved");

    // Exact FENCE, FENCE.I, Zicbom, and Svinval legality.
    apply(32'h0330_000f);
    assert_true(!decoded.illegal && decoded.fence_op == FENCE_MEMORY &&
                decoded.fence_pred == 4'h3 && decoded.fence_succ == 4'h3,
                "FENCE metadata must be preserved");
    apply(32'h0000_100f);
    assert_true(!decoded.illegal && decoded.fence_op == FENCE_INSTRUCTION,
                "canonical FENCE.I must decode");
    apply(32'h0000_108f);
    assert_illegal_contained("FENCE.I with nonzero rd must trap safely");
    apply(32'h0011_200f);
    assert_true(!decoded.illegal && decoded.fence_op == FENCE_CBO_CLEAN &&
                decoded.reads_rs1 && decoded.rs1 == 5'd2,
                "CBO.CLEAN metadata must be preserved");
    apply(32'h0031_200f);
    assert_illegal_contained("reserved CBO encoding must trap safely");
    apply(32'h1800_0073);
    assert_true(!decoded.illegal && decoded.uop_class == UOP_SYSTEM,
                "SFENCE.W.INVAL must decode");
    apply(32'h1620_8073);
    assert_true(!decoded.illegal && decoded.uop_class == UOP_SYSTEM,
                "SINVAL.VMA must decode");

    // F/D loads, stores, arithmetic, conversions, and reserved rounding modes.
    apply(32'h0001_3087);
    assert_true(!decoded.illegal && decoded.uop_class == UOP_LOAD &&
                decoded.reads_rs1 && decoded.writes_fp_rd && !decoded.writes_rd,
                "FLD register-file controls");
    apply(32'h0021_3427);
    assert_true(!decoded.illegal && decoded.uop_class == UOP_STORE &&
                decoded.reads_rs1 && decoded.reads_fp_rs2,
                "FSD register-file controls");
    apply(32'h0252_01d3);
    assert_true(!decoded.illegal && decoded.uop_class == UOP_FPU &&
                decoded.fp_funct7 == 7'b0000001 &&
                decoded.reads_fp_rs1 && decoded.reads_fp_rs2 &&
                decoded.writes_fp_rd,
                "FADD.D controls");
    apply(32'h0252_51d3);
    assert_illegal_contained("reserved static FP rounding mode must trap safely");
    apply(32'h5a02_71d3);
    assert_true(!decoded.illegal && decoded.rounding_mode == 3'b111 &&
                decoded.reads_fp_rs1 && !decoded.reads_fp_rs2,
                "FSQRT.D dynamic rounding controls");
    apply(32'he202_11d3);
    assert_true(!decoded.illegal && decoded.writes_rd &&
                !decoded.writes_fp_rd && decoded.reads_fp_rs1,
                "FCLASS.D integer destination controls");
    apply(32'hf202_01d3);
    assert_true(!decoded.illegal && decoded.reads_rs1 &&
                !decoded.reads_fp_rs1 && decoded.writes_fp_rd,
                "FMV.D.X cross-register-file controls");

    // Invalid branch funct3=010.
    apply(32'h0020_a863);
    assert_illegal_contained("reserved branch must trap safely");

    $display("PASS: %0d decoder vectors", checks);
    $finish;
  end
endmodule
