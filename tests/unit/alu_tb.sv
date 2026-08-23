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
    check(ALU_SRA, 64'h8000_0000_0000_0000, 64'd63,
          64'hffff_ffff_ffff_ffff, "sra");
    check(ALU_SLT, 64'hffff_ffff_ffff_ffff, 64'd0, 64'd1, "slt-signed");
    check(ALU_SLTU, 64'hffff_ffff_ffff_ffff, 64'd0, 64'd0, "sltu");
    check(ALU_ADDW, 64'h0000_0000_7fff_ffff, 64'd1,
          64'hffff_ffff_8000_0000, "addw-sign-extension");
    check(ALU_ROR, 64'h0123_4567_89ab_cdef, 64'd8,
          64'hef01_2345_6789_abcd, "ror");
    check(ALU_CLZ, 64'h0000_0000_0000_0001, 64'd0, 64'd63, "clz");
    check(ALU_CTZ, 64'h8000_0000_0000_0000, 64'd0, 64'd63, "ctz");
    check(ALU_CPOP, 64'hf0f0_f0f0_f0f0_f0f0, 64'd0, 64'd32, "cpop");
    check(ALU_REV8, 64'h0123_4567_89ab_cdef, 64'd0,
          64'hefcd_ab89_6745_2301, "rev8");
    check(ALU_ORCB, 64'h0001_0000_8000_00ff, 64'd0,
          64'h00ff_0000_ff00_00ff, "orc-b");
    check(ALU_BSET, 64'd0, 64'd63, 64'h8000_0000_0000_0000, "bset");
    check(ALU_SH3ADD, 64'd3, 64'd7, 64'd31, "sh3add");
    $display("PASS: %0d ALU checks", checks);
    $finish;
  end
endmodule

