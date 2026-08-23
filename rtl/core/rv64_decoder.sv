// SPDX-License-Identifier: Apache-2.0
module rv64_decoder import rv64_pkg::*; (
  input  logic [31:0] instruction_i,
  input  logic        valid_i,
  output decode_t     decoded_o,
  output xlen_t       immediate_o
);
  localparam opcode_t OP_LOAD     = 7'b0000011;
  localparam opcode_t OP_MISC_MEM = 7'b0001111;
  localparam opcode_t OP_IMM      = 7'b0010011;
  localparam opcode_t OP_AUIPC    = 7'b0010111;
  localparam opcode_t OP_IMM_32   = 7'b0011011;
  localparam opcode_t OP_STORE    = 7'b0100011;
  localparam opcode_t OP_AMO      = 7'b0101111;
  localparam opcode_t OP_REG      = 7'b0110011;
  localparam opcode_t OP_LUI      = 7'b0110111;
  localparam opcode_t OP_REG_32   = 7'b0111011;
  localparam opcode_t OP_BRANCH   = 7'b1100011;
  localparam opcode_t OP_JALR     = 7'b1100111;
  localparam opcode_t OP_JAL      = 7'b1101111;
  localparam opcode_t OP_SYSTEM   = 7'b1110011;

  opcode_t opcode;
  logic [2:0] funct3;
  logic [6:0] funct7;
  logic [4:0] funct5;
  logic       legal_amo;
  logic       legal_system;

  always_comb begin
    opcode = instruction_i[6:0];
    funct3 = instruction_i[14:12];
    funct7 = instruction_i[31:25];
    funct5 = instruction_i[31:27];

    legal_amo = funct5 inside {5'b00000, 5'b00001, 5'b00010, 5'b00011,
                               5'b00100, 5'b01000, 5'b01100, 5'b10000,
                               5'b10100, 5'b11000, 5'b11100};
    if (funct5 == 5'b00010 && instruction_i[24:20] != 5'b00000)
      legal_amo = 1'b0;

    legal_system = 1'b0;
    if (funct3 == 3'b000) begin
      legal_system = ((instruction_i[19:7] == 13'b0) &&
                      (instruction_i[31:20] inside {12'h000, 12'h001,
                                                    12'h102, 12'h105,
                                                    12'h302})) ||
                     ((instruction_i[31:25] == 7'b0001001) &&
                      (instruction_i[11:7] == 5'b00000));
    end else begin
      legal_system = funct3 inside {3'b001, 3'b010, 3'b011,
                                    3'b101, 3'b110, 3'b111};
    end

    decoded_o = '0;
    decoded_o.valid = valid_i;
    decoded_o.illegal = valid_i;
    decoded_o.rs1 = instruction_i[19:15];
    decoded_o.rs2 = instruction_i[24:20];
    decoded_o.rs3 = instruction_i[31:27];
    decoded_o.rd = instruction_i[11:7];
    decoded_o.funct3 = funct3;
    decoded_o.alu_op = ALU_ADD;

    unique case (opcode)
      OP_LUI: begin
        decoded_o.illegal = 1'b0;
        decoded_o.uop_class = UOP_ALU;
        decoded_o.imm_kind = IMM_U;
        decoded_o.operand_a_sel = OPA_ZERO;
        decoded_o.operand_b_sel = OPB_IMM;
        decoded_o.writes_rd = 1'b1;
      end
      OP_AUIPC: begin
        decoded_o.illegal = 1'b0;
        decoded_o.uop_class = UOP_ALU;
        decoded_o.imm_kind = IMM_U;
        decoded_o.operand_a_sel = OPA_PC;
        decoded_o.operand_b_sel = OPB_IMM;
        decoded_o.writes_rd = 1'b1;
      end
      OP_JAL: begin
        decoded_o.illegal = 1'b0;
        decoded_o.uop_class = UOP_JUMP;
        decoded_o.imm_kind = IMM_J;
        decoded_o.operand_a_sel = OPA_PC;
        decoded_o.operand_b_sel = OPB_IMM;
        decoded_o.writes_rd = 1'b1;
      end
      OP_JALR: begin
        decoded_o.illegal = (funct3 != 3'b000);
        decoded_o.uop_class = UOP_JUMP;
        decoded_o.imm_kind = IMM_I;
        decoded_o.operand_a_sel = OPA_RS1;
        decoded_o.operand_b_sel = OPB_IMM;
        decoded_o.reads_rs1 = 1'b1;
        decoded_o.writes_rd = 1'b1;
      end
      OP_BRANCH: begin
        decoded_o.illegal = !(funct3 inside {3'b000, 3'b001, 3'b100,
                                             3'b101, 3'b110, 3'b111});
        decoded_o.uop_class = UOP_BRANCH;
        decoded_o.imm_kind = IMM_B;
        decoded_o.reads_rs1 = 1'b1;
        decoded_o.reads_rs2 = 1'b1;
        decoded_o.operand_a_sel = OPA_RS1;
        decoded_o.operand_b_sel = OPB_RS2;
      end
      OP_LOAD: begin
        decoded_o.illegal = !(funct3 inside {3'b000, 3'b001, 3'b010,
                                             3'b011, 3'b100, 3'b101,
                                             3'b110});
        decoded_o.uop_class = UOP_LOAD;
        decoded_o.imm_kind = IMM_I;
        decoded_o.reads_rs1 = 1'b1;
        decoded_o.operand_a_sel = OPA_RS1;
        decoded_o.operand_b_sel = OPB_IMM;
        decoded_o.writes_rd = 1'b1;
      end
      OP_STORE: begin
        decoded_o.illegal = !(funct3 inside {3'b000, 3'b001, 3'b010, 3'b011});
        decoded_o.uop_class = UOP_STORE;
        decoded_o.imm_kind = IMM_S;
        decoded_o.reads_rs1 = 1'b1;
        decoded_o.reads_rs2 = 1'b1;
        decoded_o.operand_a_sel = OPA_RS1;
        decoded_o.operand_b_sel = OPB_IMM;
      end
      OP_AMO: begin
        decoded_o.illegal = !(funct3 inside {3'b010, 3'b011}) || !legal_amo;
        decoded_o.uop_class = UOP_AMO;
        decoded_o.reads_rs1 = 1'b1;
        decoded_o.reads_rs2 = (funct5 != 5'b00010);
        decoded_o.operand_a_sel = OPA_RS1;
        decoded_o.operand_b_sel = OPB_RS2;
        decoded_o.writes_rd = 1'b1;
        decoded_o.serialize = 1'b1;
      end
      OP_MISC_MEM: begin
        decoded_o.illegal = !(funct3 inside {3'b000, 3'b001, 3'b010});
        decoded_o.uop_class = UOP_FENCE;
        decoded_o.serialize = 1'b1;
      end
      OP_SYSTEM: begin
        decoded_o.illegal = !legal_system;
        decoded_o.uop_class = (funct3 == 3'b000) ? UOP_SYSTEM : UOP_CSR;
        decoded_o.imm_kind = funct3[2] ? IMM_Z : IMM_NONE;
        decoded_o.reads_rs1 = (funct3 != 3'b000) && !funct3[2];
        decoded_o.writes_rd = (funct3 != 3'b000);
        decoded_o.serialize = 1'b1;
      end
      OP_IMM, OP_IMM_32: begin
        decoded_o.illegal = 1'b0;
        decoded_o.uop_class = UOP_ALU;
        decoded_o.imm_kind = IMM_I;
        decoded_o.reads_rs1 = 1'b1;
        decoded_o.operand_a_sel = OPA_RS1;
        decoded_o.operand_b_sel = OPB_IMM;
        decoded_o.writes_rd = 1'b1;
        decoded_o.word_op = (opcode == OP_IMM_32);
        unique case (funct3)
          3'b000: decoded_o.alu_op = (opcode == OP_IMM_32) ? ALU_ADDW : ALU_ADD;
          3'b010: begin
            decoded_o.alu_op = ALU_SLT;
            if (opcode == OP_IMM_32) decoded_o.illegal = 1'b1;
          end
          3'b011: begin
            decoded_o.alu_op = ALU_SLTU;
            if (opcode == OP_IMM_32) decoded_o.illegal = 1'b1;
          end
          3'b100: begin
            decoded_o.alu_op = ALU_XOR;
            if (opcode == OP_IMM_32) decoded_o.illegal = 1'b1;
          end
          3'b110: begin
            decoded_o.alu_op = ALU_OR;
            if (opcode == OP_IMM_32) decoded_o.illegal = 1'b1;
          end
          3'b111: begin
            decoded_o.alu_op = ALU_AND;
            if (opcode == OP_IMM_32) decoded_o.illegal = 1'b1;
          end
          3'b001: begin
            decoded_o.alu_op = (opcode == OP_IMM_32) ? ALU_SLLW : ALU_SLL;
            if ((opcode == OP_IMM_32 && instruction_i[31:25] != 7'b0000000) ||
                (opcode == OP_IMM && instruction_i[31:26] != 6'b000000))
              decoded_o.illegal = 1'b1;
          end
          3'b101: begin
            if (opcode == OP_IMM_32) begin
              decoded_o.alu_op = instruction_i[30] ? ALU_SRAW : ALU_SRLW;
              decoded_o.illegal = !(funct7 inside {7'b0000000, 7'b0100000});
            end else begin
              decoded_o.alu_op = instruction_i[30] ? ALU_SRA : ALU_SRL;
              decoded_o.illegal = !(instruction_i[31:26] inside {6'b000000,
                                                                 6'b010000});
            end
          end
          default: decoded_o.illegal = 1'b1;
        endcase
      end
      OP_REG, OP_REG_32: begin
        decoded_o.uop_class = (funct7 == 7'b0000001) ? UOP_MUL : UOP_ALU;
        decoded_o.reads_rs1 = 1'b1;
        decoded_o.reads_rs2 = 1'b1;
        decoded_o.operand_a_sel = OPA_RS1;
        decoded_o.operand_b_sel = OPB_RS2;
        decoded_o.writes_rd = 1'b1;
        decoded_o.word_op = (opcode == OP_REG_32);
        decoded_o.illegal = 1'b0;
        if (funct7 == 7'b0000001) begin
          if ((opcode == OP_REG_32) && (funct3 inside {3'b001, 3'b010, 3'b011}))
            decoded_o.illegal = 1'b1;
          if (funct3[2]) decoded_o.uop_class = UOP_DIV;
        end else begin
          unique case ({funct7, funct3})
            {7'b0000000, 3'b000}: decoded_o.alu_op =
              (opcode == OP_REG_32) ? ALU_ADDW : ALU_ADD;
            {7'b0100000, 3'b000}: decoded_o.alu_op =
              (opcode == OP_REG_32) ? ALU_SUBW : ALU_SUB;
            {7'b0000000, 3'b001}: decoded_o.alu_op =
              (opcode == OP_REG_32) ? ALU_SLLW : ALU_SLL;
            {7'b0000000, 3'b010}: decoded_o.alu_op = ALU_SLT;
            {7'b0000000, 3'b011}: decoded_o.alu_op = ALU_SLTU;
            {7'b0000000, 3'b100}: decoded_o.alu_op = ALU_XOR;
            {7'b0000000, 3'b101}: decoded_o.alu_op =
              (opcode == OP_REG_32) ? ALU_SRLW : ALU_SRL;
            {7'b0100000, 3'b101}: decoded_o.alu_op =
              (opcode == OP_REG_32) ? ALU_SRAW : ALU_SRA;
            {7'b0000000, 3'b110}: decoded_o.alu_op = ALU_OR;
            {7'b0000000, 3'b111}: decoded_o.alu_op = ALU_AND;
            default: decoded_o.illegal = 1'b1;
          endcase
          if ((opcode == OP_REG_32) &&
              !(funct3 inside {3'b000, 3'b001, 3'b101}))
            decoded_o.illegal = 1'b1;
        end
      end
      default: decoded_o.illegal = valid_i;
    endcase

    immediate_o = decode_imm(instruction_i, decoded_o.imm_kind);
    if (!valid_i) begin
      decoded_o = '0;
      immediate_o = '0;
    end
  end
endmodule
