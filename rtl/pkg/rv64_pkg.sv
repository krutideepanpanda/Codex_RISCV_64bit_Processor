// SPDX-License-Identifier: Apache-2.0
package rv64_pkg;
  parameter int unsigned XLEN = 64;
  parameter int unsigned PLEN = 40;
  parameter int unsigned ISSUE_WIDTH = 2;
  parameter int unsigned ROB_ENTRIES = 64;
  parameter int unsigned INT_PHYS_REGS = 96;
  parameter int unsigned FP_PHYS_REGS = 96;

  typedef logic [XLEN-1:0] xlen_t;
  typedef logic [PLEN-1:0] paddr_t;
  typedef logic [4:0]       arch_reg_t;
  typedef logic [6:0]       opcode_t;

  typedef enum logic [5:0] {
    ALU_ADD,
    ALU_SUB,
    ALU_SLL,
    ALU_SLT,
    ALU_SLTU,
    ALU_XOR,
    ALU_SRL,
    ALU_SRA,
    ALU_OR,
    ALU_AND,
    ALU_ADDW,
    ALU_SUBW,
    ALU_SLLW,
    ALU_SRLW,
    ALU_SRAW,
    ALU_ANDN,
    ALU_ORN,
    ALU_XNOR,
    ALU_MIN,
    ALU_MINU,
    ALU_MAX,
    ALU_MAXU,
    ALU_CLZ,
    ALU_CTZ,
    ALU_CPOP,
    ALU_ROL,
    ALU_ROR,
    ALU_ROLW,
    ALU_RORW,
    ALU_SEXTB,
    ALU_SEXTH,
    ALU_ZEXTH,
    ALU_ORCB,
    ALU_REV8,
    ALU_BCLR,
    ALU_BEXT,
    ALU_BINV,
    ALU_BSET,
    ALU_SH1ADD,
    ALU_SH2ADD,
    ALU_SH3ADD
  } alu_op_e;

  typedef enum logic [3:0] {
    UOP_NONE,
    UOP_ALU,
    UOP_BRANCH,
    UOP_JUMP,
    UOP_LOAD,
    UOP_STORE,
    UOP_MUL,
    UOP_DIV,
    UOP_FPU,
    UOP_CSR,
    UOP_FENCE,
    UOP_SYSTEM,
    UOP_AMO
  } uop_class_e;

  typedef enum logic [2:0] {
    IMM_NONE,
    IMM_I,
    IMM_S,
    IMM_B,
    IMM_U,
    IMM_J,
    IMM_Z
  } imm_kind_e;

  typedef enum logic [1:0] {
    OPA_ZERO,
    OPA_RS1,
    OPA_PC
  } operand_a_sel_e;

  typedef enum logic [1:0] {
    OPB_ZERO,
    OPB_RS2,
    OPB_IMM
  } operand_b_sel_e;

  typedef struct packed {
    logic       valid;
    logic       illegal;
    uop_class_e uop_class;
    alu_op_e    alu_op;
    imm_kind_e  imm_kind;
    operand_a_sel_e operand_a_sel;
    operand_b_sel_e operand_b_sel;
    arch_reg_t  rs1;
    arch_reg_t  rs2;
    arch_reg_t  rs3;
    arch_reg_t  rd;
    logic [2:0] funct3;
    logic       reads_rs1;
    logic       reads_rs2;
    logic       reads_rs3;
    logic       writes_rd;
    logic       word_op;
    logic       serialize;
  } decode_t;

  function automatic xlen_t decode_imm(
    input logic [31:0] instruction,
    input imm_kind_e kind
  );
    unique case (kind)
      IMM_I: decode_imm = {{52{instruction[31]}}, instruction[31:20]};
      IMM_S: decode_imm = {{52{instruction[31]}}, instruction[31:25],
                          instruction[11:7]};
      IMM_B: decode_imm = {{51{instruction[31]}}, instruction[31],
                          instruction[7], instruction[30:25],
                          instruction[11:8], 1'b0};
      IMM_U: decode_imm = {{32{instruction[31]}}, instruction[31:12], 12'b0};
      IMM_J: decode_imm = {{43{instruction[31]}}, instruction[31],
                          instruction[19:12], instruction[20],
                          instruction[30:21], 1'b0};
      IMM_Z: decode_imm = {{59{1'b0}}, instruction[19:15]};
      default: decode_imm = '0;
    endcase
  endfunction
endpackage
