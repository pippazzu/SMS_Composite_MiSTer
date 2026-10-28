// Master System composite encoder: the Sony CXA1145 (cxa1145.sv, from the
// Mega Drive core) and the Master System board's Y/C networks
// (sms_av_board.sv), at clk = 53.693175 MHz = 15 x Fsc.
//
//   RGB in   R9/R12/R15 2.2k into 4.7k and 0.1uF to R/G/B IN. Full scale
//            (255) is taken as the data sheet's 1 Vp-p = 100%.
//   C SYNC   the VDP's composite sync (the HC132 shaper is not modelled).
//   XO IN    the NTSC subcarrier is the Z80 clock (VDP clock / 3), locked to
//            ce_cpu like the Mark III, so a line is exactly 228 cycles.
//            Its absolute phase against the pixels is a fixed but unknown
//            offset; ang counts from the ce_cpu pulse.
//
// Output: volts at the jack, Q2.21, sync and burst included. White lands at
// 0.71 V x 0.8 = 0.568 V and sync at 0.232 V: the luma network's 1.5k / 1k
// divider is 0.8 of the pin level, where the data sheet's 1k / 1k is 1.

module sms_cxa_cvbs (
	input                    clk,
	input                    reset,
	input                    sc_ref,    // one pulse per subcarrier cycle (ce_cpu)
	input                    csync,     // high in sync
	input                    de,
	input             [23:0] din,
	output signed     [23:0] cvbs
);

reg [3:0] p = 0;
always @(posedge clk) p <= sc_ref ? 4'd0 : (p == 4'd14) ? 4'd0 : p + 4'd1;

// Two-tick sums of the MD front end: 510 = 1 V.
reg [8:0] r2 = 0, g2 = 0, b2 = 0;
reg [1:0] s2 = 0;
reg [5:0] ang = 0;
always @(posedge clk) begin
	r2  <= de ? {din[23:16], 1'b0} : 9'd0;
	g2  <= de ? {din[15:8],  1'b0} : 9'd0;
	b2  <= de ? {din[7:0],   1'b0} : 9'd0;
	s2  <= {csync, csync};
	ang <= {p, 2'b00};                       // 24 degrees per clock
end

wire signed [23:0] y_pin, c_pin;
cxa1145 cxa1145
(
	.clk  (clk),
	.reset(reset),
	.r2   (r2),
	.g2   (g2),
	.b2   (b2),
	.s2   (s2),
	.ang  (ang),
	.y_out(y_pin),
	.c_out(c_pin)
);

sms_av_board sms_av_board
(
	.clk  (clk),
	.reset(reset),
	.y_in (y_pin),
	.c_in (c_pin),
	.cvbs (cvbs)
);

endmodule
