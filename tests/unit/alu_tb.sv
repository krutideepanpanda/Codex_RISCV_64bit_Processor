// SPDX-License-Identifier: Apache-2.0
module alu_tb;
  import rv64_pkg::*;

  alu_op_e op;
  xlen_t lhs;
  xlen_t rhs;
  xlen_t result;
  int unsigned checks;

  rv64_alu dut (
    .op_i(op),
    .lhs_i(lhs),
    .rhs_i(rhs),
    .result_o(result)
  );

  task automatic check(
    input alu_op_e test_op,
    input xlen_t test_lhs,
    input xlen_t test_rhs,
    input xlen_t expected,
    input string name
  );
    begin
      op = test_op;
      lhs = test_lhs;
      rhs = test_rhs;
      #1;
      checks++;
      if (result !== expected)
        $fatal(1, "%s: lhs=%h rhs=%h expected=%h actual=%h",
               name, test_lhs, test_rhs, expected, result);
    end
  endtask

  initial begin
    checks = 0;
    check(ALU_ADD, 64'hffff_ffff_ffff_ffff, 64'd1, 64'd0, "add-wrap");
    check(ALU_SUB, 64'd1, 64'd2, 64'hffff_ffff_ffff_ffff, "sub");
    check(ALU_SLL, 64'd1, 64'd63, 64'h8000_0000_0000_0000, "sll");
    check(ALU_SRL, 64'h8000_0000_0000_0000, 64'd63, 64'd1, "srl");
    check(ALU_SRA, 64'h8000_0000_0000_0000, 64'd63,
          64'hffff_ffff_ffff_ffff, "sra");
    check(ALU_SLT, 64'hffff_ffff_ffff_ffff, 64'd0, 64'd1, "slt-signed");
    check(ALU_SLTU, 64'hffff_ffff_ffff_ffff, 64'd0, 64'd0, "sltu");
    check(ALU_XOR, 64'haa, 64'hff, 64'h55, "xor");
    check(ALU_OR, 64'ha0, 64'h0f, 64'haf, "or");
    check(ALU_AND, 64'haa, 64'h0f, 64'h0a, "and");
    check(ALU_ADDW, 64'h0000_0000_7fff_ffff, 64'd1,
          64'hffff_ffff_8000_0000, "addw-sign-extension");
    check(ALU_SUBW, 64'd0, 64'd1, 64'hffff_ffff_ffff_ffff, "subw");
    check(ALU_SLLW, 64'd1, 64'd31, 64'hffff_ffff_8000_0000, "sllw");
    check(ALU_SRLW, 64'hffff_ffff_8000_0000, 64'd31, 64'd1, "srlw");
    check(ALU_SRAW, 64'h0000_0000_8000_0000, 64'd31,
          64'hffff_ffff_ffff_ffff, "sraw");
    check(ALU_ANDN, 64'hff, 64'h0f, 64'hf0, "andn");
    check(ALU_ORN, 64'hf0, 64'h0f, 64'hffff_ffff_ffff_fff0, "orn");
    check(ALU_XNOR, 64'haa, 64'hff, 64'hffff_ffff_ffff_ffaa, "xnor");
    check(ALU_MIN, 64'hffff_ffff_ffff_ffff, 64'd1,
          64'hffff_ffff_ffff_ffff, "min");
    check(ALU_MINU, 64'd2, 64'd1, 64'd1, "minu");
    check(ALU_MAX, 64'hffff_ffff_ffff_ffff, 64'd1, 64'd1, "max");
    check(ALU_MAXU, 64'hffff_ffff_ffff_ffff, 64'd1,
          64'hffff_ffff_ffff_ffff, "maxu");
    check(ALU_ROL, 64'd1, 64'd63, 64'h8000_0000_0000_0000, "rol");
    check(ALU_ROR, 64'h0123_4567_89ab_cdef, 64'd8,
          64'hef01_2345_6789_abcd, "ror");
    check(ALU_ROLW, 64'd1, 64'd31, 64'hffff_ffff_8000_0000, "rolw");
    check(ALU_RORW, 64'h0000_0000_8000_0000, 64'd31, 64'd1, "rorw");
    check(ALU_CLZ, 64'h0000_0000_0000_0001, 64'd0, 64'd63, "clz");
    check(ALU_CTZ, 64'h8000_0000_0000_0000, 64'd0, 64'd63, "ctz");
    check(ALU_CPOP, 64'hf0f0_f0f0_f0f0_f0f0, 64'd0, 64'd32, "cpop");
    check(ALU_SEXTB, 64'h80, 64'd0, 64'hffff_ffff_ffff_ff80, "sext.b");
    check(ALU_SEXTH, 64'h8000, 64'd0, 64'hffff_ffff_ffff_8000, "sext.h");
    check(ALU_ZEXTH, 64'hffff_ffff_ffff_8000, 64'd0, 64'h8000, "zext.h");
    check(ALU_REV8, 64'h0123_4567_89ab_cdef, 64'd0,
          64'hefcd_ab89_6745_2301, "rev8");
    check(ALU_ORCB, 64'h0001_0000_8000_00ff, 64'd0,
          64'h00ff_0000_ff00_00ff, "orc-b");
    check(ALU_BSET, 64'd0, 64'd63, 64'h8000_0000_0000_0000, "bset");
    check(ALU_BCLR, 64'hffff_ffff_ffff_ffff, 64'd63,
          64'h7fff_ffff_ffff_ffff, "bclr");
    check(ALU_BEXT, 64'h8000_0000_0000_0000, 64'd63, 64'd1, "bext");
    check(ALU_BINV, 64'd0, 64'd63, 64'h8000_0000_0000_0000, "binv");
    check(ALU_SH1ADD, 64'd3, 64'd7, 64'd13, "sh1add");
    check(ALU_SH2ADD, 64'd3, 64'd7, 64'd19, "sh2add");
    check(ALU_SH3ADD, 64'd3, 64'd7, 64'd31, "sh3add");
    check(ALU_ADD_UW, 64'hffff_ffff_8000_0001, 64'd7,
          64'h0000_0000_8000_0008, "add.uw zero extends rs1 word");
    check(ALU_SH1ADD_UW, 64'hffff_ffff_8000_0001, 64'd7,
          64'h0000_0001_0000_0009, "sh1add.uw");
    check(ALU_SH2ADD_UW, 64'hffff_ffff_8000_0001, 64'd7,
          64'h0000_0002_0000_000b, "sh2add.uw");
    check(ALU_SH3ADD_UW, 64'hffff_ffff_8000_0001, 64'd7,
          64'h0000_0004_0000_000f, "sh3add.uw");
    check(ALU_SLLI_UW, 64'hffff_ffff_8000_0001, 64'd32,
          64'h8000_0001_0000_0000, "slli.uw uses six-bit shift");
    check(ALU_CLZW, 64'hffff_ffff_0000_0001, 64'd0, 64'd31,
          "clzw ignores upper word");
    check(ALU_CLZW, 64'hffff_ffff_0000_0000, 64'd0, 64'd32,
          "clzw zero");
    check(ALU_CTZW, 64'h0000_0001_8000_0000, 64'd0, 64'd31,
          "ctzw ignores upper word");
    check(ALU_CPOPW, 64'hffff_ffff_f0f0_f0f0, 64'd0, 64'd16,
          "cpopw ignores upper word");
    $display("PASS: %0d ALU checks", checks);
    $finish;
  end
endmodule
