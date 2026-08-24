// SPDX-License-Identifier: Apache-2.0
module fetch_controller_tb;
  localparam int unsigned ADDR_W = 64;
  localparam int unsigned WINDOW_BYTES = 32;

  logic clk_i;
  logic rst_ni;
  logic fetch_enable_i;
  logic flush_valid_i;
  logic [ADDR_W-1:0] flush_pc_i;
  logic redirect_valid_i;
  logic [ADDR_W-1:0] redirect_pc_i;
  logic request_valid_o;
  logic request_ready_i;
  logic [ADDR_W-1:0] request_base_pc_o;
  logic response_valid_i;
  logic response_ready_o;
  logic [7:0] response_data_i [WINDOW_BYTES];
  logic response_valid_bytes_i [WINDOW_BYTES];
  logic response_fault_i [WINDOW_BYTES];
  logic window_valid_o;
  logic window_ready_i;
  logic [ADDR_W-1:0] window_start_pc_o;
  logic [ADDR_W-1:0] window_base_pc_o;
  logic [7:0] window_data_o [WINDOW_BYTES];
  logic window_valid_bytes_o [WINDOW_BYTES];
  logic window_fault_o [WINDOW_BYTES];
  logic [ADDR_W-1:0] next_pc_i;
  int unsigned checks;
  int unsigned request_handshakes;

  typedef enum logic [2:0] {
    MODEL_IDLE,
    MODEL_PENDING,
    MODEL_OUTSTANDING,
    MODEL_STALE,
    MODEL_WINDOW
  } model_state_t;
  model_state_t model_state_q;
  logic [ADDR_W-1:0] model_pc_q;
  logic [ADDR_W-1:0] model_request_start_q;
  logic [ADDR_W-1:0] model_request_base_q;

  rv64_fetch_controller #(.ADDR_W(ADDR_W), .WINDOW_BYTES(WINDOW_BYTES)) dut (.*);
  always #5 clk_i = ~clk_i;

  // Independent abstract transaction model. It intentionally uses only public
  // handshakes and controls, not DUT internal state.
  always @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      model_state_q <= MODEL_IDLE;
      model_pc_q <= 64'h1000;
      model_request_start_q <= '0;
      model_request_base_q <= '0;
      request_handshakes <= 0;
    end else begin
      if (request_valid_o && request_ready_i) request_handshakes <= request_handshakes + 1;
      if (flush_valid_i || redirect_valid_i) begin
        model_pc_q <= flush_valid_i ? flush_pc_i : redirect_pc_i;
        case (model_state_q)
          MODEL_OUTSTANDING, MODEL_STALE:
            model_state_q <= (response_valid_i && response_ready_o) ? MODEL_IDLE : MODEL_STALE;
          default: model_state_q <= MODEL_IDLE;
        endcase
      end else begin
        case (model_state_q)
          MODEL_IDLE: begin
            if (fetch_enable_i) begin
              model_state_q <= MODEL_PENDING;
              model_request_start_q <= model_pc_q;
              model_request_base_q <= {model_pc_q[ADDR_W-1:4], 4'b0};
            end
          end
          MODEL_PENDING: begin
            if (request_valid_o && request_ready_i) model_state_q <= MODEL_OUTSTANDING;
          end
          MODEL_OUTSTANDING: begin
            if (response_valid_i && response_ready_o) model_state_q <= MODEL_WINDOW;
          end
          MODEL_STALE: begin
            if (response_valid_i && response_ready_o) model_state_q <= MODEL_IDLE;
          end
          MODEL_WINDOW: begin
            if (window_valid_o && window_ready_i) begin
              model_state_q <= MODEL_IDLE;
              model_pc_q <= next_pc_i;
            end
          end
          default: model_state_q <= MODEL_IDLE;
        endcase
      end
    end
  end

  always @(negedge clk_i) begin : p_model_checks
    #1;
    if (!rst_ni) begin
      if (request_valid_o || response_ready_o || window_valid_o)
        $fatal(1, "fetch controller exposed a handshake during reset");
    end else begin
      case (model_state_q)
        MODEL_IDLE: begin
          if (request_valid_o || response_ready_o || window_valid_o)
            $fatal(1, "abstract model expected idle controller outputs");
        end
        MODEL_PENDING: begin
          if (request_valid_o != !((flush_valid_i || redirect_valid_i)) ||
              response_ready_o || window_valid_o ||
              request_base_pc_o != model_request_base_q)
            $fatal(1, "abstract model pending-request mismatch");
        end
        MODEL_OUTSTANDING, MODEL_STALE: begin
          if (request_valid_o || !response_ready_o || window_valid_o)
            $fatal(1, "abstract model outstanding-response mismatch");
        end
        MODEL_WINDOW: begin
          if (request_valid_o || response_ready_o || !window_valid_o ||
              window_start_pc_o != model_request_start_q ||
              window_base_pc_o != model_request_base_q)
            $fatal(1, "abstract model buffered-window mismatch");
        end
        default: $fatal(1, "abstract model entered invalid state");
      endcase
    end
  end

  task automatic check(input logic condition, input string message);
    checks++;
    if (!condition) $fatal(1, "fetch controller check failed: %s", message);
  endtask

  task automatic idle_inputs;
    begin
      fetch_enable_i = 1'b1;
      flush_valid_i = 1'b0;
      flush_pc_i = '0;
      redirect_valid_i = 1'b0;
      redirect_pc_i = '0;
      request_ready_i = 1'b1;
      response_valid_i = 1'b0;
      window_ready_i = 1'b0;
      next_pc_i = '0;
    end
  endtask

  task automatic set_response(input logic [7:0] seed, input logic fault_at_five);
    begin
      for (int unsigned byte_index = 0; byte_index < WINDOW_BYTES; byte_index = byte_index + 1) begin
        response_data_i[byte_index] = seed + byte_index[7:0];
        response_valid_bytes_i[byte_index] = byte_index[0];
        response_fault_i[byte_index] = fault_at_five && (byte_index == 5);
      end
    end
  endtask

  task automatic accept_request(input logic [63:0] expected_base, input string label);
    int unsigned wait_cycles;
    begin
      request_ready_i = 1'b0;
      wait_cycles = 0;
      while (!request_valid_o && wait_cycles < 3) begin
        @(posedge clk_i);
        @(negedge clk_i);
        #1;
        wait_cycles++;
      end
      #1;
      check(request_valid_o, {label, " request valid"});
      check(request_base_pc_o == expected_base, {label, " request base"});
      request_ready_i = 1'b1;
      @(posedge clk_i);
      @(negedge clk_i);
      check(!request_valid_o && response_ready_o, {label, " request outstanding"});
    end
  endtask

  task automatic send_response(input logic [7:0] seed, input logic fault_at_five);
    begin
      @(negedge clk_i);
      set_response(seed, fault_at_five);
      response_valid_i = 1'b1;
      check(response_ready_o, "response ready while outstanding");
      @(posedge clk_i);
      @(negedge clk_i);
      response_valid_i = 1'b0;
    end
  endtask

  task automatic check_window(input logic [63:0] expected_start, input logic [63:0] expected_base,
                              input logic [7:0] seed, input logic fault_at_five, input string label);
    begin
      check(window_valid_o, {label, " window valid"});
      check(window_start_pc_o == expected_start, {label, " window start"});
      check(window_base_pc_o == expected_base, {label, " window base"});
      for (int unsigned byte_index = 0; byte_index < WINDOW_BYTES; byte_index = byte_index + 1) begin
        check(window_data_o[byte_index] == seed + byte_index[7:0], $sformatf("%s data %0d", label, byte_index));
        check(window_valid_bytes_o[byte_index] == byte_index[0], $sformatf("%s valid %0d", label, byte_index));
        check(window_fault_o[byte_index] == (fault_at_five && byte_index == 5), $sformatf("%s fault %0d", label, byte_index));
      end
    end
  endtask

  initial begin
    clk_i = 1'b0;
    rst_ni = 1'b0;
    checks = 0;
    idle_inputs();
    set_response(8'h00, 1'b0);
    repeat (2) @(posedge clk_i);
    @(negedge clk_i);
    #1 check(!request_valid_o && !response_ready_o && !window_valid_o,
             "reset suppresses all handshakes");
    rst_ni = 1'b1;

    // Reset request and request-channel backpressure.
    request_ready_i = 1'b0;
    @(posedge clk_i);
    @(negedge clk_i);
    #1;
    check(request_valid_o && request_base_pc_o == 64'h1000, "reset request held under backpressure");
    repeat (2) begin
      @(posedge clk_i); @(negedge clk_i);
      check(request_valid_o && request_base_pc_o == 64'h1000, "request stable under backpressure");
    end
    flush_valid_i = 1'b1;
    flush_pc_i = 64'h1806;
    request_ready_i = 1'b1;
    #1 check(!request_valid_o, "recovery suppresses unaccepted old-PC request");
    @(posedge clk_i);
    @(negedge clk_i);
    flush_valid_i = 1'b0;
    accept_request(64'h1800, "reset recovery");
    check(request_handshakes == 1, "exactly one post-reset request accepted");

    // Normal response preserves every byte mask/fault bit and advances after acceptance.
    send_response(8'h40, 1'b1);
    check_window(64'h1806, 64'h1800, 8'h40, 1'b1, "normal response");
    repeat (2) begin
      @(posedge clk_i);
      @(negedge clk_i);
      check_window(64'h1806, 64'h1800, 8'h40, 1'b1, "stalled normal response");
    end
    request_ready_i = 1'b0;
    window_ready_i = 1'b1;
    next_pc_i = 64'h1026;
    @(posedge clk_i);
    @(negedge clk_i);
    window_ready_i = 1'b0;
    check(!window_valid_o, "accepted window advances next request PC");
    fetch_enable_i = 1'b0;
    request_ready_i = 1'b0;
    @(posedge clk_i);
    @(negedge clk_i);
    check(!request_valid_o, "disabled idle controller does not offer a request");
    fetch_enable_i = 1'b1;
    @(posedge clk_i);
    @(negedge clk_i);
    #1;
    check(request_valid_o && request_base_pc_o == 64'h1020,
          "enabled controller registers advanced request");
    fetch_enable_i = 1'b0;
    repeat (2) begin
      @(posedge clk_i);
      @(negedge clk_i);
      check(request_valid_o && request_base_pc_o == 64'h1020,
            "fetch disable cannot retract stalled request");
    end
    accept_request(64'h1020, "advanced");
    fetch_enable_i = 1'b1;

    // A redirect invalidates a buffered response before it can be consumed.
    send_response(8'h50, 1'b0);
    check_window(64'h1026, 64'h1020, 8'h50, 1'b0, "redirected buffered response");
    @(negedge clk_i);
    redirect_valid_i = 1'b1;
    redirect_pc_i = 64'h1a02;
    window_ready_i = 1'b1;
    next_pc_i = 64'hdead;
    @(posedge clk_i);
    @(negedge clk_i);
    redirect_valid_i = 1'b0;
    window_ready_i = 1'b0;
    #1;
    check(!window_valid_o, "redirect wins simultaneous buffered-window acceptance");
    accept_request(64'h1a00, "buffered redirect request");

    // Redirect while outstanding makes its delayed response stale and drains it.
    @(negedge clk_i);
    redirect_valid_i = 1'b1;
    redirect_pc_i = 64'h2006;
    @(posedge clk_i);
    @(negedge clk_i);
    redirect_valid_i = 1'b0;
    check(!request_valid_o && response_ready_o, "redirect retains stale outstanding request");
    send_response(8'h60, 1'b0);
    check(!window_valid_o, "stale response is discarded");
    accept_request(64'h2000, "redirect request");

    // Simultaneous response plus flush is consumed/discarded, and flush wins redirect.
    @(negedge clk_i);
    set_response(8'h70, 1'b0);
    response_valid_i = 1'b1;
    redirect_valid_i = 1'b1;
    redirect_pc_i = 64'h3002;
    flush_valid_i = 1'b1;
    flush_pc_i = 64'h4004;
    @(posedge clk_i);
    @(negedge clk_i);
    response_valid_i = 1'b0;
    redirect_valid_i = 1'b0;
    flush_valid_i = 1'b0;
    #1;
    check(!window_valid_o, "simultaneous response recovery discards and flush wins");
    accept_request(64'h4000, "flush request");

    // Repeated redirects while stale select the final recovery PC.
    @(negedge clk_i); redirect_valid_i = 1'b1; redirect_pc_i = 64'h5002; @(posedge clk_i);
    @(negedge clk_i); redirect_pc_i = 64'h600e; @(posedge clk_i);
    @(negedge clk_i); redirect_valid_i = 1'b0;
    send_response(8'h80, 1'b0);
    check(!window_valid_o, "latest stale redirect wins");

    // fetch_enable gates only new requests; it cannot drop a buffered response.
    fetch_enable_i = 1'b0;
    @(negedge clk_i);
    check(!request_valid_o, "fetch disable gates new request");
    fetch_enable_i = 1'b1;
    accept_request(64'h6000, "final request");
    fetch_enable_i = 1'b0;
    send_response(8'ha0, 1'b0);
    check_window(64'h600e, 64'h6000, 8'ha0, 1'b0, "disabled accepted response");
    @(negedge clk_i);
    check(window_valid_o, "fetch disable preserves buffered window");
    window_ready_i = 1'b1;
    next_pc_i = 64'h7000;
    @(posedge clk_i);
    @(negedge clk_i);
    window_ready_i = 1'b0;
    check(!window_valid_o && !request_valid_o, "fetch disable permits drain but no new request");
    fetch_enable_i = 1'b1;
    request_ready_i = 1'b0;
    @(posedge clk_i);
    @(negedge clk_i);
    #1 check(request_valid_o && request_base_pc_o == 64'h7000, "fetch re-enable issues retained next PC");

    $display("PASS: %0d fetch-controller checks", checks);
    $finish;
  end
endmodule
