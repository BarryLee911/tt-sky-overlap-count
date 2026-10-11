`timescale 1ns/1ps
`default_nettype none
// Cycle-by-cycle pin equivalence: v6 (E070E865) vs lookahead revision.
module tb_equiv;
  parameter integer HANDOFF = 80000;
  parameter integer SEED = 1;
  parameter integer EPISODES = 40;
  reg clk = 0, rst_n = 0, ena = 1;
  reg [7:0] ui_in = 0, uio_in = 0;
  wire [7:0] uo_a, uio_out_a, uio_oe_a, uo_b, uio_out_b, uio_oe_b;
  tt_um_sine_area_detector_v6 #(.HANDOFF_WAIT_CYCLES(HANDOFF)) gold (
    .ui_in(ui_in), .uo_out(uo_a), .uio_in(uio_in), .uio_out(uio_out_a), .uio_oe(uio_oe_a),
    .ena(ena), .clk(clk), .rst_n(rst_n));
`ifdef GL_NETLIST
  // Synthesized netlist: parameters are already bound (default 80000).
  tt_um_sine_area_detector dut (
`else
  tt_um_sine_area_detector #(.HANDOFF_WAIT_CYCLES(HANDOFF)) dut (
`endif
    .ui_in(ui_in), .uo_out(uo_b), .uio_in(uio_in), .uio_out(uio_out_b), .uio_oe(uio_oe_b),
    .ena(ena), .clk(clk), .rst_n(rst_n));

  integer seed, seed0, cycles, errors, ep, i, n, level, mode, samples_seen, max_level;
  integer resets, tie_cycles, expire_hits;
  reg [7:0] mag; reg [31:0] r;
  reg started; reg rst_seen = 0; integer state_errors = 0, processed = 0, expiries = 0, refills = 0, ties = 0, peak_div = 0;

  task tick; begin
    #5 clk = 1; #1;
    cycles = cycles + 1;
    if (started) begin
      if ({uo_a, uio_out_a, uio_oe_a} !== {uo_b, uio_out_b, uio_oe_b} ||
          ^{uo_b, uio_out_b, uio_oe_b} === 1'bx) begin
        errors = errors + 1;
        if (errors < 10)
          $display("MISMATCH cycle %0d ep %0d: gold %h %h %h  new %h %h %h", cycles, ep,
                   uo_a, uio_out_a, uio_oe_a, uo_b, uio_out_b, uio_oe_b);
      end
    end
`ifndef PINS_ONLY
    if (started && rst_seen) begin
      // Every v6 register is kept in the new RTL; require identical internal state too.
      if ({gold.peak_first, gold.peak_second, gold.peak_buffer, gold.peak_first_position,
           gold.peak_second_position, gold.peak_buffer_position, gold.peak_history_valid,
           gold.peak_second_valid, gold.running_sum, gold.window_full, gold.history_pointer,
           gold.sample_valid, gold.sample_magnitude, gold.sample_position, gold.sample_overlap,
           gold.prescale_count, gold.prescale_terminal_latched, gold.config_latched_valid,
           gold.handoff_count, gold.output_ready, gold.take_sample} !==
          {dut.peak_first, dut.peak_second, dut.peak_buffer, dut.peak_first_position,
           dut.peak_second_position, dut.peak_buffer_position, dut.peak_history_valid,
           dut.peak_second_valid, dut.running_sum, dut.window_full, dut.history_pointer,
           dut.sample_valid, dut.sample_magnitude, dut.sample_position, dut.sample_overlap,
           dut.prescale_count, dut.prescale_terminal_latched, dut.config_latched_valid,
           dut.handoff_count, dut.output_ready, dut.take_sample}) begin
        state_errors = state_errors + 1;
        if (state_errors < 5) $display("STATE MISMATCH cycle %0d ep %0d", cycles, ep);
      end
      if (gold.window_full === 1'b1 && gold.overlap_history !== dut.overlap_history) begin
        state_errors = state_errors + 1;
        if (state_errors < 5) $display("HISTORY MISMATCH cycle %0d", cycles);
      end
      if (gold.backend_process === 1'b1) begin
        processed = processed + 1;
        if (gold.peak_history_valid && !gold.first_alive) expiries = expiries + 1;
        if (gold.fill_second) refills = refills + 1;
        if (gold.first_alive && gold.sample_magnitude == gold.peak_first) ties = ties + 1;
      end
    end
`endif
    if (!rst_n) rst_seen = 1;
    #4 clk = 0;
  end endtask

  function [7:0] adc_from; input [7:0] m; input positive; begin
    adc_from = positive ? (8'd128 + (m > 127 ? 127 : m)) : (8'd128 - (m > 128 ? 128 : m));
  end endfunction

  // Drive one cycle of ADC data according to mode.
  task drive_adc; input integer k; begin
    r = $random(seed);
    case (mode)
      0: ui_in = r[7:0];                                      // uniform random
      1: ui_in = 8'd128 + $rtoi(127.0*$sin(6.283185307*k/2048.0)); // sine, one reference period
      2: begin                                                // few distinct magnitudes: many ties
           mag = {5'd0, r[2:0]} + 8'd60; ui_in = adc_from(mag, r[8]);
         end
      3: begin                                                // sparse large spikes -> expiry/refill
           if (r[9:0] < 6) mag = 8'd100 + r[14:10]; else mag = {4'd0, r[13:10]};
           ui_in = adc_from(mag, r[15]);
         end
      4: ui_in = (r[3:0] == 0) ? (r[4] ? 8'd0 : 8'd255) : (r[5] ? 8'd128 : 8'd127); // extremes / midpoint
      5: begin                                                // slowly decaying envelope
           mag = 8'd127 - ((k >> 6) & 8'h7f); ui_in = adc_from(mag, r[0]);
         end
      6: begin mag = {6'd0, r[1:0]}; ui_in = adc_from(mag, r[2]); end            // 4-level alphabet
      7: begin mag = (r[7:0] < 3) ? 8'd9 : {5'd0, r[10:8]}; ui_in = adc_from(mag, r[11]); end
      8: begin mag = ((k % (1022 + (SEED % 5))) < 2) ? 8'd90 + (k % 3) : {6'd0, r[1:0]}; ui_in = adc_from(mag, r[3]); end // spikes near 1024 spacing
      9: begin mag = 8'd100 - ((k / 1024) % 90) + (r[1:0] == 0); ui_in = adc_from(mag, r[4]); end // staircase per window
      10: begin mag = (r[4:0] == 0) ? {4'd0, r[8:5]} + 8'd20 : ((k & 1) ? 8'd20 : 8'd19); ui_in = adc_from(mag, r[9]); end
      default: ui_in = r[7:0];
    endcase
  end endtask

  initial begin
    seed = SEED; if ($value$plusargs("seed=%d", seed)) ; seed0 = seed; cycles = 0; errors = 0; started = 0; resets = 0;
    // First edge must be a reset edge, as in the official test.
    rst_n = 0; uio_in = 8'd31; ui_in = 8'd127;
    started = 1;
    for (ep = 0; ep < EPISODES; ep = ep + 1) begin
      // Reset of random length (1..4), random ena.
      n = 1 + ($random(seed) & 3);
      for (i = 0; i < n; i = i + 1) begin
        rst_n = 0; ena = $random(seed); uio_in = $random(seed); ui_in = $random(seed); tick;
      end
      resets = resets + 1;
      rst_n = 1;
      // Choose a level: weighted to fast levels so windows fill.
      r = $random(seed);
      case (r[3:0])
        0,1,2,3,4,5: level = 0;
        6,7,8: level = 1;
        9: level = 2;
        10: level = 3;
        11: level = 4;
        12: level = 5;
        13: level = 6 + (r[7:4] % 4);
        default: level = 0;
      endcase
      mode = ($random(seed) & 32'h7fffffff) % 11;
      // Some invalid levels before the legal one.
      n = $random(seed) & 7;
      for (i = 0; i < n; i = i + 1) begin
        uio_in = {$random(seed)} % 8 + 24 + ((($random(seed)) & 1) << 5); // 24..31 (+bit5 noise)
        uio_in[4:3] = 2'b11; drive_adc(i); tick;
      end
      uio_in = {3'b000, level[4:0]} | ({$random(seed)} & 8'he0);
      drive_adc(0); tick;
      // Run: enough samples to wrap the 2048 window several times at level 0/1.
      n = (level == 0) ? (6000 + ({$random(seed)} % 9000)) :
          (level <= 2) ? 12000 + ({$random(seed)} % 6000) :
          (level <= 5) ? 20000 : 3000;
      if (HANDOFF > 1000 && level == 0) n = n + HANDOFF; // reach output handoff
      for (i = 0; i < n; i = i + 1) begin
        uio_in = $random(seed);              // level pins ignored after latching
        drive_adc(i);
        if (({$random(seed)} % 200000) == 0) begin rst_n = 0; tick; rst_n = 1; end // rare mid-run reset
        else tick;
      end
    end
    $display("RESULT seed=%0d handoff=%0d cycles=%0d episodes=%0d errors=%0d state_errors=%0d processed=%0d expiries=%0d refills=%0d ties=%0d", seed0, HANDOFF, cycles, EPISODES, errors, state_errors, processed, expiries, refills, ties);
    $finish;
  end
endmodule
