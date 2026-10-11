`timescale 1ns/1ps
`default_nettype none
module tb_gl_short;
  reg clk = 0, rst_n = 0, ena = 1; reg [7:0] ui_in = 0, uio_in = 8'd31;
  wire [7:0] uo_a, uio_out_a, uio_oe_a, uo_b, uio_out_b, uio_oe_b;
  tt_um_sine_area_detector_v6 #(.HANDOFF_WAIT_CYCLES(40)) gold (.ui_in(ui_in), .uo_out(uo_a), .uio_in(uio_in), .uio_out(uio_out_a), .uio_oe(uio_oe_a), .ena(ena), .clk(clk), .rst_n(rst_n));
  tt_um_sine_area_detector dut (.ui_in(ui_in), .uo_out(uo_b), .uio_in(uio_in), .uio_out(uio_out_b), .uio_oe(uio_oe_b), .ena(ena), .clk(clk), .rst_n(rst_n));
  integer i, errors = 0, cycles = 0, seed = 5, ph; reg [31:0] r;
  always #5 clk = ~clk;
  always @(negedge clk) begin
    cycles = cycles + 1;
    if (cycles > 1 && ({uo_a, uio_out_a, uio_oe_a} !== {uo_b, uio_out_b, uio_oe_b} || ^{uo_b,uio_out_b,uio_oe_b} === 1'bx)) begin
      errors = errors + 1; if (errors < 5) $display("MISMATCH %0d: %h %h %h / %h %h %h", cycles, uo_a, uio_out_a, uio_oe_a, uo_b, uio_out_b, uio_oe_b);
    end
  end
  task run(input integer level, input integer n); begin
    @(negedge clk); rst_n = 0; uio_in = 8'd31; repeat (3) @(negedge clk);
    rst_n = 1; uio_in = level; @(negedge clk);
    for (i = 0; i < n; i = i + 1) begin
      r = $random(seed); uio_in = r[15:8];
      ph = i % 3000;
      ui_in = (ph < 1500) ? r[7:0] : ((r[3:0] == 0) ? 8'd250 : 8'd120 + r[2:0]);
      @(negedge clk);
    end
  end endtask
  initial begin
    run(0, 300);
    $display("GL RESULT cycles=%0d errors=%0d", cycles, errors); $finish;
  end
endmodule
