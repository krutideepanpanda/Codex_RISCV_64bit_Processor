// SPDX-License-Identifier: Apache-2.0
// One-outstanding, in-order instruction-window controller in VDD_CORE.
// rst_ni is the local asynchronous-assert, synchronous-deassert core reset.
module rv64_fetch_controller #(
  parameter int unsigned ADDR_W = 64,
  parameter int unsigned WINDOW_BYTES = 32,
  parameter logic [ADDR_W-1:0] RESET_PC = 64'h0000_0000_0000_1000
) (
  input  logic                     clk_i,
  input  logic                     rst_ni,
  input  logic                     fetch_enable_i,
  input  logic                     flush_valid_i,
  input  logic [ADDR_W-1:0]        flush_pc_i,
  input  logic                     redirect_valid_i,
  input  logic [ADDR_W-1:0]        redirect_pc_i,
  output logic                     request_valid_o,
  input  logic                     request_ready_i,
  output logic [ADDR_W-1:0]        request_base_pc_o,
  input  logic                     response_valid_i,
  output logic                     response_ready_o,
  input  logic [7:0]               response_data_i [WINDOW_BYTES],
  input  logic                     response_valid_bytes_i [WINDOW_BYTES],
  input  logic                     response_fault_i [WINDOW_BYTES],
  output logic                     window_valid_o,
  input  logic                     window_ready_i,
  output logic [ADDR_W-1:0]        window_start_pc_o,
  output logic [ADDR_W-1:0]        window_base_pc_o,
  output logic [7:0]               window_data_o [WINDOW_BYTES],
  output logic                     window_valid_bytes_o [WINDOW_BYTES],
  output logic                     window_fault_o [WINDOW_BYTES],
  input  logic [ADDR_W-1:0]        next_pc_i
);
  logic [ADDR_W-1:0] next_pc_q;
  logic request_pending_q;
  logic request_outstanding_q;
  logic request_stale_q;
  logic [ADDR_W-1:0] request_start_pc_q;
  logic [ADDR_W-1:0] request_base_pc_q;

  logic recover_valid;
  logic [ADDR_W-1:0] recover_pc;
  logic request_accept;
  logic response_accept;
  logic window_accept;
  logic request_stalled_prev_q;
  logic window_stalled_prev_q;
  logic discard_expected_q;
  logic recovery_window_clear_expected_q;
  logic [ADDR_W-1:0] request_base_prev_q;
  logic [ADDR_W-1:0] window_start_prev_q;
  logic [ADDR_W-1:0] window_base_prev_q;
  logic [WINDOW_BYTES-1:0][7:0] window_data_prev_q;
  logic [WINDOW_BYTES-1:0] window_valid_bytes_prev_q;
  logic [WINDOW_BYTES-1:0] window_fault_prev_q;

  initial begin
    assert (ADDR_W == 64);
    assert (WINDOW_BYTES == 32);
    assert (RESET_PC[3:0] == 4'b0);
  end

  always_comb begin
    recover_valid = flush_valid_i || redirect_valid_i;
    recover_pc = redirect_pc_i;
    if (flush_valid_i) recover_pc = flush_pc_i;

    request_valid_o = rst_ni && request_pending_q && !recover_valid;
    request_base_pc_o = request_base_pc_q;
    response_ready_o = request_outstanding_q;
    request_accept = request_valid_o && request_ready_i;
    response_accept = response_valid_i && response_ready_o;
    window_accept = window_valid_o && window_ready_i;
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      next_pc_q <= RESET_PC;
      request_pending_q <= 1'b0;
      request_outstanding_q <= 1'b0;
      request_stale_q <= 1'b0;
      request_start_pc_q <= '0;
      request_base_pc_q <= '0;
      window_valid_o <= 1'b0;
      window_start_pc_o <= '0;
      window_base_pc_o <= '0;
      for (int unsigned byte_index = 0; byte_index < WINDOW_BYTES; byte_index = byte_index + 1) begin
        window_data_o[byte_index] <= '0;
        window_valid_bytes_o[byte_index] <= 1'b0;
        window_fault_o[byte_index] <= 1'b0;
      end
    end else begin
      // An accepted response always completes the sole outstanding request.
      if (response_accept) begin
        request_outstanding_q <= 1'b0;
        request_stale_q <= 1'b0;
        if (request_stale_q || recover_valid) begin
          window_valid_o <= 1'b0;
        end else begin
          window_valid_o <= 1'b1;
          window_start_pc_o <= request_start_pc_q;
          window_base_pc_o <= request_base_pc_q;
          for (int unsigned byte_index = 0; byte_index < WINDOW_BYTES; byte_index = byte_index + 1) begin
            window_data_o[byte_index] <= response_data_i[byte_index];
            window_valid_bytes_o[byte_index] <= response_valid_bytes_i[byte_index];
            window_fault_o[byte_index] <= response_fault_i[byte_index];
          end
        end
      end

      // Ordinary completion advances only when no recovery wins this cycle.
      if (window_accept && !recover_valid) begin
        window_valid_o <= 1'b0;
        next_pc_q <= next_pc_i;
      end

      if (request_accept) begin
        request_pending_q <= 1'b0;
        request_outstanding_q <= 1'b1;
        request_stale_q <= 1'b0;
      end

      // Register an offered request so valid/base remain stable until accepted.
      if (!request_pending_q && !request_outstanding_q && !window_valid_o &&
          fetch_enable_i && !recover_valid) begin
        request_pending_q <= 1'b1;
        request_start_pc_q <= next_pc_q;
        request_base_pc_q <= {next_pc_q[ADDR_W-1:4], 4'b0};
      end

      // Flush has precedence over redirect by construction of recover_pc.
      if (recover_valid) begin
        next_pc_q <= recover_pc;
        request_pending_q <= 1'b0;
        window_valid_o <= 1'b0;
        if (request_outstanding_q && !response_accept) request_stale_q <= 1'b1;
      end
    end
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin : p_temporal_state
    if (!rst_ni) begin
      request_stalled_prev_q <= 1'b0;
      window_stalled_prev_q <= 1'b0;
      discard_expected_q <= 1'b0;
      recovery_window_clear_expected_q <= 1'b0;
      request_base_prev_q <= '0;
      window_start_prev_q <= '0;
      window_base_prev_q <= '0;
      for (int unsigned byte_index = 0; byte_index < WINDOW_BYTES; byte_index = byte_index + 1) begin
        window_data_prev_q[byte_index] <= '0;
        window_valid_bytes_prev_q[byte_index] <= 1'b0;
        window_fault_prev_q[byte_index] <= 1'b0;
      end
    end else begin
      request_stalled_prev_q <= request_valid_o && !request_ready_i && !recover_valid;
      window_stalled_prev_q <= window_valid_o && !window_ready_i && !recover_valid;
      discard_expected_q <= response_accept && (request_stale_q || recover_valid);
      recovery_window_clear_expected_q <= recover_valid && window_valid_o;
      request_base_prev_q <= request_base_pc_o;
      window_start_prev_q <= window_start_pc_o;
      window_base_prev_q <= window_base_pc_o;
      for (int unsigned byte_index = 0; byte_index < WINDOW_BYTES; byte_index = byte_index + 1) begin
        window_data_prev_q[byte_index] <= window_data_o[byte_index];
        window_valid_bytes_prev_q[byte_index] <= window_valid_bytes_o[byte_index];
        window_fault_prev_q[byte_index] <= window_fault_o[byte_index];
      end
    end
  end

  always @(posedge clk_i) begin : p_invariants
    if (rst_ni) begin
      assert (next_pc_q[0] == 1'b0);
      assert (request_base_pc_o[3:0] == 4'b0);
      assert (!request_valid_o || (request_pending_q && !request_outstanding_q && !window_valid_o));
      if (recover_valid) assert (!request_valid_o);
      assert (!response_ready_o || request_outstanding_q);
      assert (!(request_pending_q && request_outstanding_q));
      assert (!(request_pending_q && window_valid_o));
      assert (!(request_outstanding_q && window_valid_o));
      if (request_pending_q || request_outstanding_q) begin
        assert (request_base_pc_q[3:0] == 4'b0);
        assert (request_start_pc_q[0] == 1'b0);
        assert ((request_start_pc_q >= request_base_pc_q) &&
                (request_start_pc_q < (request_base_pc_q + ADDR_W'(16))));
      end
      if (request_stale_q) assert (request_outstanding_q);
      if (request_stalled_prev_q && !recover_valid) begin
        assert (request_valid_o);
        assert (request_base_pc_o == request_base_prev_q);
      end
      if (window_stalled_prev_q) begin
        assert (window_valid_o);
        assert (window_start_pc_o == window_start_prev_q);
        assert (window_base_pc_o == window_base_prev_q);
        for (int unsigned byte_index = 0; byte_index < WINDOW_BYTES; byte_index = byte_index + 1) begin
          assert (window_data_o[byte_index] == window_data_prev_q[byte_index]);
          assert (window_valid_bytes_o[byte_index] == window_valid_bytes_prev_q[byte_index]);
          assert (window_fault_o[byte_index] == window_fault_prev_q[byte_index]);
        end
      end
      if (discard_expected_q) assert (!window_valid_o);
      if (recovery_window_clear_expected_q) assert (!window_valid_o);
      if (flush_valid_i && redirect_valid_i) assert (recover_pc == flush_pc_i);
    end
  end
endmodule
