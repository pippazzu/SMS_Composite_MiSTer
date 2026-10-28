// From pippazzu/MegaDrive_MiSTer-Composite 7e4b5ba, unchanged. In this core
// sms_cxa_cvbs.sv feeds it and sms_av_board.sv takes the place of md_av_board.
//
// Sony CXA1145 RGB encoder, NTSC mode, one sample per VDP master clock.
//
// Levels, matrix, burst timing and phases are the typical values of the Sony
// CXA1145P/M data sheet, which specifies them at the jack with its reference
// Y delay line and chroma BPF, each 1k in and 1k out. Outputs here are those
// jack-referred levels; md_av_board doubles them to the Y OUT and C OUT pins
// and applies the Mega Drive's own networks instead.
//
//   R/G/B in      1 Vp-p = 100%, clamped to the level seen in the burst flag
//   White         0.71 V      Y = 0.299 R + 0.587 G + 0.114 B
//   Sync          0.29 V      added in the Y path while C SYNC IN is low
//   Burst         0.29 Vp-p   180 deg, 0.5 us after the C SYNC rising edge, 2.75 us
//   Chroma        0.493 (B-Y) and 0.877 (R-Y): R 104, G 241, B 347 deg
//
// The VDP's DAC levels are read as volts at the RGB inputs, full scale being
// 1 V: the 5.6k pull-up and 4.7k / 1.2k divider on each line are what Nuked's
// DAC table already describes.
//
// The subcarrier comes from SBCR through 10k / 1k and 100 pF to X IN, which
// lags it by 63.9 degrees; the table below carries that lag. The modulators
// are taken as ideal multipliers of the fundamental.

module cxa1145 (
	input                clk,
	input                reset,

	input          [8:0] r2,        // two-tick DAC sums, 510 = 1 V
	input          [8:0] g2,
	input          [8:0] b2,
	input          [1:0] s2,        // ticks C SYNC IN was low
	input          [5:0] ang,       // subcarrier angle, 6 degree steps

	output reg signed [23:0] y_out,  // Q2.21 volts, jack-referred, with sync
	output reg signed [23:0] c_out   // Q2.21 volts, jack-referred, with burst
);

// 0.71 V / 510 per DAC step in Q2.21, split by the luma weights.
localparam signed [12:0] KYR = 13'sd873;
localparam signed [12:0] KYG = 13'sd1714;
localparam signed [12:0] KYB = 13'sd333;
localparam signed [12:0] K   = 13'sd2920;
// Colour difference weights, Q16.
localparam signed [16:0] KU  = 17'sd32309;     // 0.493
localparam signed [16:0] KV  = 17'sd57475;     // 0.877
// Sync tip 0.29 V, Q2.21, and burst peak 0.145 V, Q2.16.
localparam signed [23:0] SYNC_TICK  = 24'sd304087;  // per tick, two per sample
localparam signed [18:0] BURST_PEAK = 19'sd9503;

// Burst flag from the C SYNC rising edge, in master clocks.
localparam [7:0]  BF_DELAY = 8'd27;      // 0.50 us
localparam [7:0]  BF_WIDTH = 8'd148;     // 2.76 us
// Half-H killer: a rising edge within 0.75 H of the last is not a line.
localparam [11:0] HALF_H_KILL = 12'd2565;

// ------------------------------------------------------------ sine table

// 2047 * sin(n * 6 deg - 63.94 deg)
function automatic signed [11:0] carrier(input [5:0] n);
	case (n)
		6'd0 : carrier = -12'sd1839;  6'd1 : carrier = -12'sd1735;  6'd2 : carrier = -12'sd1612;
		6'd3 : carrier = -12'sd1471;  6'd4 : carrier = -12'sd1314;  6'd5 : carrier = -12'sd1143;
		6'd6 : carrier = -12'sd959;   6'd7 : carrier = -12'sd765;   6'd8 : carrier = -12'sd562;
		6'd9 : carrier = -12'sd353;   6'd10: carrier = -12'sd141;   6'd11: carrier = 12'sd74;
		6'd12: carrier = 12'sd287;    6'd13: carrier = 12'sd497;    6'd14: carrier = 12'sd702;
		6'd15: carrier = 12'sd899;    6'd16: carrier = 12'sd1087;   6'd17: carrier = 12'sd1262;
		6'd18: carrier = 12'sd1424;   6'd19: carrier = 12'sd1570;   6'd20: carrier = 12'sd1698;
		6'd21: carrier = 12'sd1808;   6'd22: carrier = 12'sd1899;   6'd23: carrier = 12'sd1968;
		6'd24: carrier = 12'sd2016;   6'd25: carrier = 12'sd2042;   6'd26: carrier = 12'sd2046;
		6'd27: carrier = 12'sd2027;   6'd28: carrier = 12'sd1986;   6'd29: carrier = 12'sd1923;
		6'd30: carrier = 12'sd1839;   6'd31: carrier = 12'sd1735;   6'd32: carrier = 12'sd1612;
		6'd33: carrier = 12'sd1471;   6'd34: carrier = 12'sd1314;   6'd35: carrier = 12'sd1143;
		6'd36: carrier = 12'sd959;    6'd37: carrier = 12'sd765;    6'd38: carrier = 12'sd562;
		6'd39: carrier = 12'sd353;    6'd40: carrier = 12'sd141;    6'd41: carrier = -12'sd74;
		6'd42: carrier = -12'sd287;   6'd43: carrier = -12'sd497;   6'd44: carrier = -12'sd702;
		6'd45: carrier = -12'sd899;   6'd46: carrier = -12'sd1087;  6'd47: carrier = -12'sd1262;
		6'd48: carrier = -12'sd1424;  6'd49: carrier = -12'sd1570;  6'd50: carrier = -12'sd1698;
		6'd51: carrier = -12'sd1808;  6'd52: carrier = -12'sd1899;  6'd53: carrier = -12'sd1968;
		6'd54: carrier = -12'sd2016;  6'd55: carrier = -12'sd2042;  6'd56: carrier = -12'sd2046;
		6'd57: carrier = -12'sd2027;  6'd58: carrier = -12'sd1986;  default: carrier = -12'sd1923;
	endcase
endfunction

// ------------------------------------------------------------ burst flag

wire sync_in = |s2;
reg  sync_d;
reg [11:0] since_line;
reg  [7:0] bf_cnt;
reg        bf_run;

wire line_edge = sync_d & ~sync_in & (since_line >= HALF_H_KILL);
wire bf = bf_run && (bf_cnt >= BF_DELAY);

always @(posedge clk) begin
	if (reset) begin
		sync_d <= 1'b0;
		since_line <= 12'd0;
		bf_cnt <= 8'd0;
		bf_run <= 1'b0;
	end else begin
		sync_d <= sync_in;
		if (line_edge) since_line <= 12'd0;
		else if (~&since_line) since_line <= since_line + 12'd1;

		if (line_edge) begin
			bf_cnt <= 8'd0;
			bf_run <= 1'b1;
		end else if (bf_run) begin
			bf_cnt <= bf_cnt + 8'd1;
			if (bf_cnt == BF_DELAY + BF_WIDTH - 8'd1) bf_run <= 1'b0;
		end
	end
end

// ------------------------------------------------------------ input clamp

// The inputs are AC coupled and clamped while the burst flag is up; the
// level found there is black for the rest of the line.
reg [15:0] acc_r, acc_g, acc_b;
reg  [8:0] blk_r, blk_g, blk_b;
reg  [7:0] clamp_n;

always @(posedge clk) begin
	if (reset) begin
		{acc_r, acc_g, acc_b} <= 48'd0;
		{blk_r, blk_g, blk_b} <= 27'd0;
		clamp_n <= 8'd0;
	end else if (line_edge) begin
		{acc_r, acc_g, acc_b} <= 48'd0;
		clamp_n <= 8'd0;
	end else if (bf && !clamp_n[7]) begin
		acc_r <= acc_r + r2;
		acc_g <= acc_g + g2;
		acc_b <= acc_b + b2;
		clamp_n <= clamp_n + 8'd1;
		if (clamp_n == 8'd127) begin
			blk_r <= (acc_r + r2) >> 7;
			blk_g <= (acc_g + g2) >> 7;
			blk_b <= (acc_b + b2) >> 7;
		end
	end
end

// ------------------------------------------------------------ matrix

wire signed [9:0] rn = $signed({1'b0, r2}) - $signed({1'b0, blk_r});
wire signed [9:0] gn = $signed({1'b0, g2}) - $signed({1'b0, blk_g});
wire signed [9:0] bn = $signed({1'b0, b2}) - $signed({1'b0, blk_b});

reg signed [23:0] y1, rq1, bq1, sync1;
reg               bf1;
reg signed [11:0] sin1, cos1;

always @(posedge clk) begin
	y1    <= rn * KYR + gn * KYG + bn * KYB;
	rq1   <= rn * K;
	bq1   <= bn * K;
	sync1 <= s2[1] ? SYNC_TICK + SYNC_TICK : s2[0] ? SYNC_TICK : 24'sd0;
	bf1   <= bf;
	sin1  <= carrier(ang);
	cos1  <= carrier((ang >= 6'd45) ? ang - 6'd45 : ang + 6'd15);
end

// ------------------------------------------------------------ colour difference

// Colour differences and chroma in Q2.16, so every product is 18 x 19.
/* verilator lint_off UNUSEDSIGNAL */
wire signed [24:0] by = bq1 - y1;
wire signed [24:0] ry = rq1 - y1;
wire signed [36:0] u_m = $signed(by[23:5]) * KU;
wire signed [36:0] v_m = $signed(ry[23:5]) * KV;
/* verilator lint_on UNUSEDSIGNAL */

reg signed [18:0] u2, v2;
reg signed [23:0] y2;
reg signed [11:0] sin2, cos2;

always @(posedge clk) begin
	u2   <= u_m[34:16] - (bf1 ? BURST_PEAK : 19'sd0);
	v2   <= v_m[34:16];
	y2   <= y1 - sync1;
	sin2 <= sin1;
	cos2 <= cos1;
end

// ------------------------------------------------------------ modulators

/* verilator lint_off UNUSEDSIGNAL */
wire signed [31:0] c_m = u2 * sin2 + v2 * cos2;
/* verilator lint_on UNUSEDSIGNAL */

always @(posedge clk) begin
	y_out <= y2;
	c_out <= c_m[29:6];
end

endmodule
