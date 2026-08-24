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

  task automatic assert_alu(
    input logic [31:0] insn,
    input alu_op_e expected_op,
    input logic expected_word_op,
    input string message
  );
    begin
      apply(insn);
      assert_true(!decoded.illegal && decoded.uop_class == UOP_ALU &&
                  decoded.alu_op == expected_op &&
                  decoded.reads_rs1 && decoded.writes_rd &&
                  decoded.word_op == expected_word_op,
                  message);
    end
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
    assert_true(!decoded.illegal && decoded.uop_class == UOP_SYSTEM &&
                decoded.system_op == SYS_SFENCE_W_INVAL,
                "SFENCE.W.INVAL must decode");
    apply(32'h1620_8073);
    assert_true(!decoded.illegal && decoded.uop_class == UOP_SYSTEM &&
                decoded.system_op == SYS_SINVAL_VMA,
                "SINVAL.VMA must decode");
    apply(32'h1220_8073);
    assert_true(!decoded.illegal && decoded.system_op == SYS_SFENCE_VMA,
                "SFENCE.VMA must have an explicit selector");

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

    // Zba: all represented XLEN shift-and-add encodings.
    assert_alu({7'b0010000, 5'd3, 5'd2, 3'b010, 5'd1, 7'b0110011},
               ALU_SH1ADD, 1'b0, "SH1ADD decode");
    assert_true(decoded.reads_rs2 && decoded.operand_b_sel == OPB_RS2 &&
                decoded.imm_kind == IMM_NONE,
                "SH1ADD uses a register second operand");
    assert_alu({7'b0010000, 5'd3, 5'd2, 3'b100, 5'd1, 7'b0110011},
               ALU_SH2ADD, 1'b0, "SH2ADD decode");
    assert_alu({7'b0010000, 5'd3, 5'd2, 3'b110, 5'd1, 7'b0110011},
               ALU_SH3ADD, 1'b0, "SH3ADD decode");
    assert_alu({7'b0000100, 5'd3, 5'd2, 3'b000, 5'd1, 7'b0111011},
               ALU_ADD_UW, 1'b0, "ADD.UW decode");
    assert_alu({7'b0010000, 5'd3, 5'd2, 3'b010, 5'd1, 7'b0111011},
               ALU_SH1ADD_UW, 1'b0, "SH1ADD.UW decode");
    assert_alu({7'b0010000, 5'd3, 5'd2, 3'b100, 5'd1, 7'b0111011},
               ALU_SH2ADD_UW, 1'b0, "SH2ADD.UW decode");
    assert_alu({7'b0010000, 5'd3, 5'd2, 3'b110, 5'd1, 7'b0111011},
               ALU_SH3ADD_UW, 1'b0, "SH3ADD.UW decode");
    assert_alu({6'b000010, 6'd63, 5'd2, 3'b001, 5'd1, 7'b0011011},
               ALU_SLLI_UW, 1'b0, "SLLI.UW six-bit shift decode");
    assert_true(!decoded.reads_rs2 && decoded.operand_b_sel == OPB_IMM &&
                decoded.imm_kind == IMM_I,
                "SLLI.UW uses an immediate second operand");

    // Zbb R-type logical, min/max, and rotate encodings.
    assert_alu({7'b0100000, 5'd3, 5'd2, 3'b111, 5'd1, 7'b0110011},
               ALU_ANDN, 1'b0, "ANDN decode");
    assert_true(decoded.reads_rs2 && decoded.operand_b_sel == OPB_RS2 &&
                decoded.imm_kind == IMM_NONE,
                "ANDN uses a register second operand");
    assert_alu({7'b0100000, 5'd3, 5'd2, 3'b110, 5'd1, 7'b0110011},
               ALU_ORN, 1'b0, "ORN decode");
    assert_alu({7'b0100000, 5'd3, 5'd2, 3'b100, 5'd1, 7'b0110011},
               ALU_XNOR, 1'b0, "XNOR decode");
    assert_alu({7'b0000101, 5'd3, 5'd2, 3'b100, 5'd1, 7'b0110011},
               ALU_MIN, 1'b0, "MIN decode");
    assert_alu({7'b0000101, 5'd3, 5'd2, 3'b101, 5'd1, 7'b0110011},
               ALU_MINU, 1'b0, "MINU decode");
    assert_alu({7'b0000101, 5'd3, 5'd2, 3'b110, 5'd1, 7'b0110011},
               ALU_MAX, 1'b0, "MAX decode");
    assert_alu({7'b0000101, 5'd3, 5'd2, 3'b111, 5'd1, 7'b0110011},
               ALU_MAXU, 1'b0, "MAXU decode");
    assert_alu({7'b0110000, 5'd3, 5'd2, 3'b001, 5'd1, 7'b0110011},
               ALU_ROL, 1'b0, "ROL decode");
    assert_alu({7'b0110000, 5'd3, 5'd2, 3'b101, 5'd1, 7'b0110011},
               ALU_ROR, 1'b0, "ROR decode");
    assert_alu({7'b0110000, 5'd3, 5'd2, 3'b001, 5'd1, 7'b0111011},
               ALU_ROLW, 1'b1, "ROLW decode");
    assert_alu({7'b0110000, 5'd3, 5'd2, 3'b101, 5'd1, 7'b0111011},
               ALU_RORW, 1'b1, "RORW decode");

    // Zbb unary encodings must not expose their encoded immediate as an operand.
    assert_alu({12'h600, 5'd2, 3'b001, 5'd1, 7'b0010011},
               ALU_CLZ, 1'b0, "CLZ decode");
    assert_true(decoded.imm_kind == IMM_NONE && decoded.operand_b_sel == OPB_ZERO,
                "CLZ has no second operand");
    assert_true(!decoded.reads_rs2, "CLZ must not read encoded unary selector");
    assert_alu({12'h601, 5'd2, 3'b001, 5'd1, 7'b0010011},
               ALU_CTZ, 1'b0, "CTZ decode");
    assert_alu({12'h602, 5'd2, 3'b001, 5'd1, 7'b0010011},
               ALU_CPOP, 1'b0, "CPOP decode");
    assert_alu({12'h600, 5'd2, 3'b001, 5'd1, 7'b0011011},
               ALU_CLZW, 1'b1, "CLZW decode");
    assert_alu({12'h601, 5'd2, 3'b001, 5'd1, 7'b0011011},
               ALU_CTZW, 1'b1, "CTZW decode");
    assert_alu({12'h602, 5'd2, 3'b001, 5'd1, 7'b0011011},
               ALU_CPOPW, 1'b1, "CPOPW decode");
    assert_alu({12'h604, 5'd2, 3'b001, 5'd1, 7'b0010011},
               ALU_SEXTB, 1'b0, "SEXT.B decode");
    assert_alu({12'h605, 5'd2, 3'b001, 5'd1, 7'b0010011},
               ALU_SEXTH, 1'b0, "SEXT.H decode");
    assert_alu({7'b0000100, 5'd0, 5'd2, 3'b100, 5'd1, 7'b0111011},
               ALU_ZEXTH, 1'b0, "ZEXT.H decode");
    assert_true(!decoded.reads_rs2 && decoded.operand_b_sel == OPB_ZERO,
                "ZEXT.H requires and ignores rs2=x0");
    assert_alu({12'h287, 5'd2, 3'b101, 5'd1, 7'b0010011},
               ALU_ORCB, 1'b0, "ORC.B decode");
    assert_true(decoded.imm_kind == IMM_NONE && decoded.operand_b_sel == OPB_ZERO,
                "ORC.B has no second operand");
    assert_alu({12'h6b8, 5'd2, 3'b101, 5'd1, 7'b0010011},
               ALU_REV8, 1'b0, "REV8 decode");

    // Zbb and Zbs immediate forms use the exact RV64 six-bit shift/index field.
    assert_alu({6'b011000, 6'd63, 5'd2, 3'b101, 5'd1, 7'b0010011},
               ALU_ROR, 1'b0, "RORI shamt[5]=1 decode");
    assert_true(immediate[5:0] == 6'd63, "RORI preserves RV64 shift amount");
    assert_alu({7'b0110000, 5'd31, 5'd2, 3'b101, 5'd1, 7'b0011011},
               ALU_RORW, 1'b1, "RORIW decode");
    assert_true(immediate[4:0] == 5'd31, "RORIW preserves word shift amount");
    assert_alu({6'b001010, 6'd63, 5'd2, 3'b001, 5'd1, 7'b0010011},
               ALU_BSET, 1'b0, "BSETI index[5]=1 decode");
    assert_true(!decoded.reads_rs2 && decoded.operand_b_sel == OPB_IMM &&
                decoded.imm_kind == IMM_I,
                "BSETI uses an immediate bit index");
    assert_alu({6'b010010, 6'd63, 5'd2, 3'b001, 5'd1, 7'b0010011},
               ALU_BCLR, 1'b0, "BCLRI index[5]=1 decode");
    assert_alu({6'b011010, 6'd63, 5'd2, 3'b001, 5'd1, 7'b0010011},
               ALU_BINV, 1'b0, "BINVI index[5]=1 decode");
    assert_alu({6'b010010, 6'd63, 5'd2, 3'b101, 5'd1, 7'b0010011},
               ALU_BEXT, 1'b0, "BEXTI index[5]=1 decode");

    // Zbs register-indexed forms.
    assert_alu({7'b0010100, 5'd3, 5'd2, 3'b001, 5'd1, 7'b0110011},
               ALU_BSET, 1'b0, "BSET decode");
    assert_alu({7'b0100100, 5'd3, 5'd2, 3'b001, 5'd1, 7'b0110011},
               ALU_BCLR, 1'b0, "BCLR decode");
    assert_alu({7'b0100100, 5'd3, 5'd2, 3'b101, 5'd1, 7'b0110011},
               ALU_BEXT, 1'b0, "BEXT decode");
    assert_alu({7'b0110100, 5'd3, 5'd2, 3'b001, 5'd1, 7'b0110011},
               ALU_BINV, 1'b0, "BINV decode");

    // Near misses: wrong opcode family, malformed zext.h, and reserved forms.
    apply({7'b0000100, 5'd3, 5'd2, 3'b000, 5'd1, 7'b0110011});
    assert_illegal_contained("ADD.UW must not decode under OP");
    apply({6'b000011, 6'd1, 5'd2, 3'b001, 5'd1, 7'b0011011});
    assert_illegal_contained("reserved SLLI.UW prefix must trap safely");
    apply({12'h603, 5'd2, 3'b001, 5'd1, 7'b0011011});
    assert_illegal_contained("reserved word unary selector must trap safely");
    apply({12'h603, 5'd2, 3'b001, 5'd1, 7'b0010011});
    assert_illegal_contained("reserved XLEN unary selector 0x603 must trap safely");
    apply({12'h606, 5'd2, 3'b001, 5'd1, 7'b0010011});
    assert_illegal_contained("reserved XLEN unary selector 0x606 must trap safely");
    apply({12'h698, 5'd2, 3'b101, 5'd1, 7'b0010011});
    assert_illegal_contained("RV32 REV8 selector must trap in RV64");
    apply({7'b0110001, 5'd0, 5'd2, 3'b101, 5'd1, 7'b0011011});
    assert_illegal_contained("RORIW with reserved shamt bit 5 must trap safely");
    apply({7'b0000100, 5'd3, 5'd2, 3'b100, 5'd1, 7'b0111011});
    assert_illegal_contained("ZEXT.H with nonzero rs2 must trap safely");
    apply({7'b0110000, 5'd3, 5'd2, 3'b100, 5'd1, 7'b0111011});
    assert_illegal_contained("reserved OP-32 rotate funct3 must trap safely");
    apply({7'b0100000, 5'd3, 5'd2, 3'b100, 5'd1, 7'b0111011});
    assert_illegal_contained("XNOR is not an OP-32 instruction");
    apply({7'b0010100, 5'd3, 5'd2, 3'b001, 5'd1, 7'b0111011});
    assert_illegal_contained("BSET is not an OP-32 instruction");
    apply({6'b001010, 6'd0, 5'd2, 3'b101, 5'd1, 7'b0010011});
    assert_illegal_contained("Zbs opcode-family near miss must trap safely");

    // Invalid branch funct3=010.
    apply(32'h0020_a863);
    assert_illegal_contained("reserved branch must trap safely");

    $display("PASS: %0d decoder vectors", checks);
    $finish;
  end
endmodule
