`timescale 1ns/1ps
`default_nettype none
// Every legal level 0..23: v6 and lookahead must strobe on the same edges.
// Runs each level for two full divider intervals plus margin (level 23: 16.8M clocks).
module tb_divider;
  reg clk = 0, rst_n = 0, ena = 1;
  reg [7:0] ui_in = 8'd200, uio_in = 0;
  wire [7:0] uo_a, uio_out_a, uio_oe_a, uo_b, uio_out_b, uio_oe_b;
  tt_um_sine_area_detector_v6 #(.HANDOFF_WAIT_CYCLES(80000)) gold (
    .ui_in(ui_in), .uo_out(uo_a), .uio_in(uio_in), .uio_out(uio_out_a), .uio_oe(uio_oe_a),
    .ena(ena), .clk(clk), .rst_n(rst_n));
  tt_um_sine_area_detector #(.HANDOFF_WAIT_CYCLES(80000)) dut (
    .ui_in(ui_in), .uo_out(uo_b), .uio_in(uio_in), .uio_out(uio_out_b), .uio_oe(uio_oe_b),
    .ena(ena), .clk(clk), .rst_n(rst_n));
  integer level, k, errors = 0, strobes, total = 0;
  reg [31:0] len;
  always #5 clk = ~clk;
  always @(negedge clk) if (rst_n) begin
    if ({uo_a, uio_out_a, uio_oe_a} !== {uo_b, uio_out_b, uio_oe_b} ||
        gold.take_sample !== dut.take_sample || gold.prescale_count !== dut.prescale_count) begin
      errors = errors + 1;
      if (errors < 10) $display("MISMATCH level %0d t=%0t", level, $time);
    end
  end
  initial begin
    for (level = 0; level <= 23; level = level + 1) begin
      rst_n = 0; uio_in = 8'd31; repeat (2) @(negedge clk);
      rst_n = 1; uio_in = level; @(negedge clk); uio_in = 8'hff;
      len = (32'd1 << level) * 2 + 8;
      strobes = 0;
      for (k = 0; k < len; k = k + 1) begin
        ui_in = k[7:0] ^ 8'h5a;
        @(negedge clk);
        if (gold.take_sample === 1'b1) strobes = strobes + 1;
      end
      total = total + len;
      $display("level %0d: %0d clocks, %0d strobes, errors so far %0d", level, len, strobes, errors);
    end
    $display("DIVIDER RESULT clocks=%0d errors=%0d", total, errors);
    $finish;
  end
endmodule
