// SPDX-License-Identifier: Apache-2.0
module rv64_alu import rv64_pkg::*; (
  input  alu_op_e op_i,
  input  xlen_t   lhs_i,
  input  xlen_t   rhs_i,
  output xlen_t   result_o
);
  logic [5:0] shamt;
  logic [4:0] shamt_w;
  logic [31:0] lhs_w;
  logic [31:0] rhs_w;
  logic [31:0] result_w;

  function automatic logic [6:0] count_leading_zeros(input xlen_t value);
    logic found;
    begin
      count_leading_zeros = 7'd64;
      found = 1'b0;
      for (int i = 63; i >= 0; i--) begin
        if (!found && value[i]) begin
          count_leading_zeros = 7'(63 - i);
          found = 1'b1;
        end
      end
    end
  endfunction

  function automatic logic [6:0] count_trailing_zeros(input xlen_t value);
    logic found;
    begin
      count_trailing_zeros = 7'd64;
      found = 1'b0;
      for (int i = 0; i < 64; i++) begin
        if (!found && value[i]) begin
          count_trailing_zeros = 7'(i);
          found = 1'b1;
        end
      end
    end
  endfunction

  function automatic logic [6:0] population_count(input xlen_t value);
    logic [6:0] total;
    begin
      total = '0;
      for (int i = 0; i < 64; i++) total = total + 7'(value[i]);
      return total;
    end
  endfunction

  function automatic xlen_t byte_or_combine(input xlen_t value);
    xlen_t combined;
    begin
      combined = '0;
      for (int i = 0; i < 8; i++)
        combined[i*8 +: 8] = (|value[i*8 +: 8]) ? 8'hff : 8'h00;
      return combined;
    end
  endfunction

  function automatic xlen_t reverse_bytes(input xlen_t value);
    xlen_t reversed;
    begin
      for (int i = 0; i < 8; i++) reversed[i*8 +: 8] = value[(7-i)*8 +: 8];
      return reversed;
    end
  endfunction

  always_comb begin
    shamt = rhs_i[5:0];
    shamt_w = rhs_i[4:0];
    lhs_w = lhs_i[31:0];
    rhs_w = rhs_i[31:0];
    result_w = '0;
    result_o = '0;

    unique case (op_i)
      ALU_ADD:    result_o = lhs_i + rhs_i;
      ALU_SUB:    result_o = lhs_i - rhs_i;
      ALU_SLL:    result_o = lhs_i << shamt;
      ALU_SLT:    result_o = xlen_t'($signed(lhs_i) < $signed(rhs_i));
      ALU_SLTU:   result_o = xlen_t'(lhs_i < rhs_i);
      ALU_XOR:    result_o = lhs_i ^ rhs_i;
      ALU_SRL:    result_o = lhs_i >> shamt;
      ALU_SRA:    result_o = xlen_t'($signed(lhs_i) >>> shamt);
      ALU_OR:     result_o = lhs_i | rhs_i;
      ALU_AND:    result_o = lhs_i & rhs_i;
      ALU_ANDN:   result_o = lhs_i & ~rhs_i;
      ALU_ORN:    result_o = lhs_i | ~rhs_i;
      ALU_XNOR:   result_o = ~(lhs_i ^ rhs_i);
      ALU_MIN:    result_o = ($signed(lhs_i) < $signed(rhs_i)) ? lhs_i : rhs_i;
      ALU_MINU:   result_o = (lhs_i < rhs_i) ? lhs_i : rhs_i;
      ALU_MAX:    result_o = ($signed(lhs_i) > $signed(rhs_i)) ? lhs_i : rhs_i;
      ALU_MAXU:   result_o = (lhs_i > rhs_i) ? lhs_i : rhs_i;
      ALU_CLZ:    result_o = xlen_t'(count_leading_zeros(lhs_i));
      ALU_CTZ:    result_o = xlen_t'(count_trailing_zeros(lhs_i));
      ALU_CPOP:   result_o = xlen_t'(population_count(lhs_i));
      ALU_ROL:    result_o = (lhs_i << shamt) | (lhs_i >> ((-shamt) & 6'h3f));
      ALU_ROR:    result_o = (lhs_i >> shamt) | (lhs_i << ((-shamt) & 6'h3f));
      ALU_SEXTB:  result_o = {{56{lhs_i[7]}}, lhs_i[7:0]};
      ALU_SEXTH:  result_o = {{48{lhs_i[15]}}, lhs_i[15:0]};
      ALU_ZEXTH:  result_o = {48'b0, lhs_i[15:0]};
      ALU_ORCB:   result_o = byte_or_combine(lhs_i);
      ALU_REV8:   result_o = reverse_bytes(lhs_i);
      ALU_BCLR:   result_o = lhs_i & ~(64'b1 << shamt);
      ALU_BEXT:   result_o = xlen_t'((lhs_i >> shamt) & 64'b1);
      ALU_BINV:   result_o = lhs_i ^ (64'b1 << shamt);
      ALU_BSET:   result_o = lhs_i | (64'b1 << shamt);
      ALU_SH1ADD: result_o = (lhs_i << 1) + rhs_i;
      ALU_SH2ADD: result_o = (lhs_i << 2) + rhs_i;
      ALU_SH3ADD: result_o = (lhs_i << 3) + rhs_i;
      ALU_ADDW: begin
        result_w = lhs_w + rhs_w;
        result_o = {{32{result_w[31]}}, result_w};
      end
      ALU_SUBW: begin
        result_w = lhs_w - rhs_w;
        result_o = {{32{result_w[31]}}, result_w};
      end
      ALU_SLLW: begin
        result_w = lhs_w << shamt_w;
        result_o = {{32{result_w[31]}}, result_w};
      end
      ALU_SRLW: begin
        result_w = lhs_w >> shamt_w;
        result_o = {{32{result_w[31]}}, result_w};
      end
      ALU_SRAW: begin
        result_w = 32'($signed(lhs_w) >>> shamt_w);
        result_o = {{32{result_w[31]}}, result_w};
      end
      ALU_ROLW: begin
        result_w = (lhs_w << shamt_w) | (lhs_w >> ((-shamt_w) & 5'h1f));
        result_o = {{32{result_w[31]}}, result_w};
      end
      ALU_RORW: begin
        result_w = (lhs_w >> shamt_w) | (lhs_w << ((-shamt_w) & 5'h1f));
        result_o = {{32{result_w[31]}}, result_w};
      end
      default: result_o = '0;
    endcase
  end
endmodule

