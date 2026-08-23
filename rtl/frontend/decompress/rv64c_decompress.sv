// SPDX-License-Identifier: Apache-2.0
// RV64C instruction decompressor. This block is combinational in VDD_CORE.
module rv64c_decompress (
  input  logic [15:0] c_instruction_i,
  output logic [31:0] instruction_o,
  output logic        legal_o
);
  localparam logic [6:0] OP_LOAD     = 7'b0000011;
  localparam logic [6:0] OP_IMM      = 7'b0010011;
  localparam logic [6:0] OP_STORE    = 7'b0100011;
  localparam logic [6:0] OP_OP       = 7'b0110011;
  localparam logic [6:0] OP_LUI      = 7'b0110111;
  localparam logic [6:0] OP_OP_IMM32 = 7'b0011011;
  localparam logic [6:0] OP_OP32     = 7'b0111011;
  localparam logic [6:0] OP_BRANCH   = 7'b1100011;
  localparam logic [6:0] OP_JALR     = 7'b1100111;
  localparam logic [6:0] OP_JAL      = 7'b1101111;
  localparam logic [6:0] OP_LOAD_FP  = 7'b0000111;
  localparam logic [6:0] OP_STORE_FP = 7'b0100111;

  function automatic logic [31:0] form_i(
    input logic [6:0] opcode, input logic [2:0] funct3,
    input logic [4:0] rd, input logic [4:0] rs1, input logic [11:0] imm
  );
    form_i = {imm, rs1, funct3, rd, opcode};
  endfunction

  function automatic logic [31:0] form_r(
    input logic [6:0] opcode, input logic [2:0] funct3, input logic [6:0] funct7,
    input logic [4:0] rd, input logic [4:0] rs1, input logic [4:0] rs2
  );
    form_r = {funct7, rs2, rs1, funct3, rd, opcode};
  endfunction

  function automatic logic [31:0] form_s(
    input logic [6:0] opcode, input logic [2:0] funct3,
    input logic [4:0] rs1, input logic [4:0] rs2, input logic [11:0] imm
  );
    form_s = {imm[11:5], rs2, rs1, funct3, imm[4:0], opcode};
  endfunction

  function automatic logic [31:0] form_b(
    input logic [2:0] funct3, input logic [4:0] rs1, input logic [4:0] rs2,
    input logic [12:0] imm
  );
    form_b = {imm[12], imm[10:5], rs2, rs1, funct3, imm[4:1], imm[11], OP_BRANCH};
    if (imm[0]) form_b = 32'b0;
  endfunction

  function automatic logic [31:0] form_j(
    input logic [4:0] rd, input logic [20:0] imm
  );
    form_j = {imm[20], imm[10:1], imm[11], imm[19:12], rd, OP_JAL};
    if (imm[0]) form_j = 32'b0;
  endfunction

  always_comb begin
    instruction_o = 32'b0;
    legal_o = 1'b0;

    unique case (c_instruction_i[1:0])
      2'b00: unique case (c_instruction_i[15:13])
        3'b000: begin // C.ADDI4SPN
          if (c_instruction_i[12:5] != 8'b0) begin
            instruction_o = form_i(OP_IMM, 3'b000, {2'b01, c_instruction_i[4:2]},
                                   5'd2, {2'b0, c_instruction_i[10:7],
                                         c_instruction_i[12:11], c_instruction_i[5],
                                         c_instruction_i[6], 2'b0});
            legal_o = 1'b1;
          end
        end
        3'b001, 3'b011: begin // C.FLD / C.LD
          instruction_o = form_i((c_instruction_i[15:13] == 3'b001) ? OP_LOAD_FP : OP_LOAD,
                                 3'b011, {2'b01, c_instruction_i[4:2]},
                                 {2'b01, c_instruction_i[9:7]},
                                 {4'b0, c_instruction_i[6:5], c_instruction_i[12:10], 3'b0});
          legal_o = 1'b1;
        end
        3'b010: begin // C.LW
          instruction_o = form_i(OP_LOAD, 3'b010, {2'b01, c_instruction_i[4:2]},
                                 {2'b01, c_instruction_i[9:7]},
                                 {5'b0, c_instruction_i[5], c_instruction_i[12:10],
                                  c_instruction_i[6], 2'b0});
          legal_o = 1'b1;
        end
        3'b101, 3'b111: begin // C.FSD / C.SD
          instruction_o = form_s((c_instruction_i[15:13] == 3'b101) ? OP_STORE_FP : OP_STORE,
                                 3'b011, {2'b01, c_instruction_i[9:7]},
                                 {2'b01, c_instruction_i[4:2]},
                                 {4'b0, c_instruction_i[6:5], c_instruction_i[12:10], 3'b0});
          legal_o = 1'b1;
        end
        3'b110: begin // C.SW
          instruction_o = form_s(OP_STORE, 3'b010, {2'b01, c_instruction_i[9:7]},
                                 {2'b01, c_instruction_i[4:2]},
                                 {5'b0, c_instruction_i[5], c_instruction_i[12:10], c_instruction_i[6], 2'b0});
          legal_o = 1'b1;
        end
        default: begin end
      endcase
      2'b01: unique case (c_instruction_i[15:13])
        3'b000: begin // C.ADDI / C.NOP and architectural HINTs
          instruction_o = form_i(OP_IMM, 3'b000, c_instruction_i[11:7], c_instruction_i[11:7],
                                 {{7{c_instruction_i[12]}}, c_instruction_i[6:2]});
          legal_o = 1'b1;
        end
        3'b001: if (c_instruction_i[11:7] != 5'b0) begin // C.ADDIW
          instruction_o = form_i(OP_OP_IMM32, 3'b000, c_instruction_i[11:7], c_instruction_i[11:7],
                                 {{7{c_instruction_i[12]}}, c_instruction_i[6:2]});
          legal_o = 1'b1;
        end
        3'b010: begin // C.LI and architectural HINTs
          instruction_o = form_i(OP_IMM, 3'b000, c_instruction_i[11:7], 5'b0,
                                 {{7{c_instruction_i[12]}}, c_instruction_i[6:2]});
          legal_o = 1'b1;
        end
        3'b011: if (c_instruction_i[11:7] == 5'd2) begin // C.ADDI16SP
          if ({c_instruction_i[12], c_instruction_i[6:2]} != 6'b0) begin
            instruction_o = form_i(OP_IMM, 3'b000, 5'd2, 5'd2,
                                   {{2{c_instruction_i[12]}}, c_instruction_i[12],
                                    c_instruction_i[4:3], c_instruction_i[5],
                                    c_instruction_i[2], c_instruction_i[6], 4'b0});
            legal_o = 1'b1;
          end
        end else if ({c_instruction_i[12], c_instruction_i[6:2]} != 6'b0) begin // C.LUI / HINT
          instruction_o = {{15{c_instruction_i[12]}}, c_instruction_i[6:2],
                           c_instruction_i[11:7], OP_LUI};
          legal_o = 1'b1;
        end
        3'b100: unique case (c_instruction_i[11:10])
          2'b00, 2'b01: begin // C.SRLI / C.SRAI
            instruction_o = form_i(OP_IMM, 3'b101, {2'b01, c_instruction_i[9:7]},
                                   {2'b01, c_instruction_i[9:7]},
                                   {(c_instruction_i[11:10] == 2'b01) ? 6'b010000 : 6'b000000,
                                    c_instruction_i[12], c_instruction_i[6:2]});
            legal_o = 1'b1;
          end
          2'b10: begin // C.ANDI
            instruction_o = form_i(OP_IMM, 3'b111, {2'b01, c_instruction_i[9:7]},
                                   {2'b01, c_instruction_i[9:7]},
                                   {{7{c_instruction_i[12]}}, c_instruction_i[6:2]});
            legal_o = 1'b1;
          end
          default: unique case ({c_instruction_i[12], c_instruction_i[6:5]})
            3'b000: begin instruction_o = form_r(OP_OP, 3'b000, 7'b0100000, {2'b01, c_instruction_i[9:7]}, {2'b01, c_instruction_i[9:7]}, {2'b01, c_instruction_i[4:2]}); legal_o = 1'b1; end
            3'b001: begin instruction_o = form_r(OP_OP, 3'b100, 7'b0000000, {2'b01, c_instruction_i[9:7]}, {2'b01, c_instruction_i[9:7]}, {2'b01, c_instruction_i[4:2]}); legal_o = 1'b1; end
            3'b010: begin instruction_o = form_r(OP_OP, 3'b110, 7'b0000000, {2'b01, c_instruction_i[9:7]}, {2'b01, c_instruction_i[9:7]}, {2'b01, c_instruction_i[4:2]}); legal_o = 1'b1; end
            3'b011: begin instruction_o = form_r(OP_OP, 3'b111, 7'b0000000, {2'b01, c_instruction_i[9:7]}, {2'b01, c_instruction_i[9:7]}, {2'b01, c_instruction_i[4:2]}); legal_o = 1'b1; end
            3'b100: begin instruction_o = form_r(OP_OP32, 3'b000, 7'b0100000, {2'b01, c_instruction_i[9:7]}, {2'b01, c_instruction_i[9:7]}, {2'b01, c_instruction_i[4:2]}); legal_o = 1'b1; end
            3'b101: begin instruction_o = form_r(OP_OP32, 3'b000, 7'b0000000, {2'b01, c_instruction_i[9:7]}, {2'b01, c_instruction_i[9:7]}, {2'b01, c_instruction_i[4:2]}); legal_o = 1'b1; end
            default: begin end
          endcase
        endcase
        3'b101: begin // C.J
          instruction_o = form_j(5'd0, {{9{c_instruction_i[12]}}, c_instruction_i[12],
                                  c_instruction_i[8], c_instruction_i[10:9], c_instruction_i[6],
                                  c_instruction_i[7], c_instruction_i[2], c_instruction_i[11],
                                  c_instruction_i[5:3], 1'b0});
          legal_o = 1'b1;
        end
        3'b110, 3'b111: begin // C.BEQZ / C.BNEZ
          instruction_o = form_b((c_instruction_i[15:13] == 3'b110) ? 3'b000 : 3'b001,
                                  {2'b01, c_instruction_i[9:7]}, 5'd0,
                                  {{4{c_instruction_i[12]}}, c_instruction_i[12],
                                   c_instruction_i[6:5], c_instruction_i[2],
                                   c_instruction_i[11:10], c_instruction_i[4:3], 1'b0});
          legal_o = 1'b1;
        end
        default: begin end
      endcase
      2'b10: unique case (c_instruction_i[15:13])
        3'b000: begin // C.SLLI / HINT when rd=x0
          instruction_o = form_i(OP_IMM, 3'b001, c_instruction_i[11:7], c_instruction_i[11:7],
                                 {6'b000000, c_instruction_i[12], c_instruction_i[6:2]});
          legal_o = 1'b1;
        end
        3'b001: begin // C.FLDSP (f0 is a valid destination)
          instruction_o = form_i(OP_LOAD_FP,
                                 3'b011, c_instruction_i[11:7], 5'd2,
                                 {3'b0, c_instruction_i[4:2], c_instruction_i[12],
                                  c_instruction_i[6:5], 3'b0});
          legal_o = 1'b1;
        end
        3'b011: if (c_instruction_i[11:7] != 5'b0) begin // C.LDSP
          instruction_o = form_i(OP_LOAD,
                                 3'b011, c_instruction_i[11:7], 5'd2,
                                 {3'b0, c_instruction_i[4:2], c_instruction_i[12],
                                  c_instruction_i[6:5], 3'b0});
          legal_o = 1'b1;
        end
        3'b010: if (c_instruction_i[11:7] != 5'b0) begin // C.LWSP
          instruction_o = form_i(OP_LOAD, 3'b010, c_instruction_i[11:7], 5'd2,
                                 {4'b0, c_instruction_i[3:2], c_instruction_i[12],
                                  c_instruction_i[6:4], 2'b0});
          legal_o = 1'b1;
        end
        3'b100: if (!c_instruction_i[12]) begin
          if (c_instruction_i[6:2] != 5'b0) begin // C.MV / HINT when rd=x0
            instruction_o = form_r(OP_OP, 3'b000, 7'b0000000, c_instruction_i[11:7], 5'd0,
                                   c_instruction_i[6:2]);
            legal_o = 1'b1;
          end else if (c_instruction_i[6:2] == 5'b0 && c_instruction_i[11:7] != 5'b0) begin // C.JR
            instruction_o = form_i(OP_JALR, 3'b000, 5'd0, c_instruction_i[11:7], 12'b0);
            legal_o = 1'b1;
          end
        end else if (c_instruction_i[6:2] == 5'b0) begin
          if (c_instruction_i[11:7] == 5'b0) instruction_o = 32'h0010_0073; // C.EBREAK
          else instruction_o = form_i(OP_JALR, 3'b000, 5'd1, c_instruction_i[11:7], 12'b0); // C.JALR
          legal_o = 1'b1;
        end else begin // C.ADD / HINT when rd=x0
          instruction_o = form_r(OP_OP, 3'b000, 7'b0000000, c_instruction_i[11:7],
                                 c_instruction_i[11:7], c_instruction_i[6:2]);
          legal_o = 1'b1;
        end
        3'b101, 3'b111: begin // C.FSDSP / C.SDSP
          instruction_o = form_s((c_instruction_i[15:13] == 3'b101) ? OP_STORE_FP : OP_STORE,
                                 3'b011, 5'd2, c_instruction_i[6:2],
                                 {3'b0, c_instruction_i[9:7], c_instruction_i[12:10], 3'b0});
          legal_o = 1'b1;
        end
        3'b110: begin // C.SWSP
          instruction_o = form_s(OP_STORE, 3'b010, 5'd2, c_instruction_i[6:2],
                                 {4'b0, c_instruction_i[8:7], c_instruction_i[12:9], 2'b0});
          legal_o = 1'b1;
        end
        default: begin end
      endcase
      default: begin end
    endcase
  end

  // Illegal compressed encodings have no candidate instruction for downstream decode.
  always_comb assert (legal_o || (instruction_o == 32'b0));
endmodule
