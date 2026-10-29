`timescale 1ns/1ps
// gamma_fast (SMS.sv) against video_mixer's gamma_corr, with a random curve
// loaded and gamma on: the RGB path's pixel every 10 clocks, and the composite
// path's every 2 or 3 (four decoder samples in five clocks, one pixel per two).
// Prints the mismatches of each module against the curve applied to its input
// one pixel earlier.
module tb;
reg clk = 0;
always #9.312 clk = ~clk;

reg        ce = 0, gwr = 0, hs = 0;
reg  [9:0] gaddr;
reg  [7:0] gval;
reg [23:0] rgb = 0;
reg  [7:0] curve[768];

wire [21:0] gbus;
assign gbus[20:0] = {clk, 1'b1, gwr, gaddr, gval};
wire [23:0] out_c, out_f;
wire hs_c, hs_f;

gamma_corr gc(.clk_sys(clk), .clk_vid(clk), .ce_pix(ce), .gamma_en(1'b1), .gamma_wr(gwr),
	.gamma_wr_addr(gaddr), .gamma_value(gval), .HSync(hs), .VSync(1'b0), .HBlank(1'b0), .VBlank(1'b0),
	.RGB_in(rgb), .HSync_out(hs_c), .VSync_out(), .HBlank_out(), .VBlank_out(), .RGB_out(out_c));
gamma_fast gf(.clk_vid(clk), .ce_pix(ce), .gamma_bus(gbus), .HSync(hs), .VSync(1'b0), .HBlank(1'b0),
	.VBlank(1'b0), .DE(1'b0), .RGB_in(rgb), .HSync_out(hs_f), .VSync_out(), .HBlank_out(), .VBlank_out(),
	.DE_out(), .RGB_out(out_f));

integer i, n, mode, k, bad_c, bad_f, hsbad;
reg [23:0] prev1;
reg        hprev1;
initial begin
	for (i = 0; i < 768; i++) begin
		curve[i] = $urandom;
		@(posedge clk); #1 gwr = 1; gaddr = i; gval = curve[i];
	end
	@(posedge clk); #1 gwr = 0;
	for (mode = 0; mode < 2; mode++) begin
		bad_c = 0; bad_f = 0; hsbad = 0; n = 0; k = 0;
		for (i = 0; i < 20000; i++) begin
			@(posedge clk); #1;
			// check the outputs latched at the previous enable
			if (ce && n > 2) begin
				if (out_c != {curve[prev1[23:16]], curve[256 + prev1[15:8]], curve[512 + prev1[7:0]]}) bad_c++;
				if (out_f != {curve[prev1[23:16]], curve[256 + prev1[15:8]], curve[512 + prev1[7:0]]}) bad_f++;
				if (hs_c != hprev1 || hs_f != hprev1) hsbad++;
			end
			ce = mode ? (k == 0 || k == 2) : (k == 0);
			k = (k + 1) % (mode ? 5 : 10);
			if (ce) begin
				prev1 = rgb; hprev1 = hs;
				rgb = $urandom; hs = $urandom; n++;
			end
		end
		$display("%s: %0d pixels, gamma_corr mismatches %0d, gamma_fast mismatches %0d, sync mismatches %0d",
			mode ? "composite, a pixel every 2-3 clocks" : "RGB, a pixel every 10 clocks", n, bad_c, bad_f, hsbad);
	end
	$finish;
end
endmodule
