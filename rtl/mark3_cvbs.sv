//============================================================================
//  Sega Mark III composite encoder (BA7230LS video path)
//
//  Feeds the Composite Filter (rtl/composite/mark3_tv.sv). Output levels as
//  sys/yc_out.sv's CVBS (dout = {8'd0, CVBS, 8'd0}, blank at 64, white at
//  191.5, no sync); level_o is the same before rounding, 8-bit x 256.
//
//  What is modelled, from the Mark III schematic (171-5304) and the ROHM
//  BA7230LS datasheet, at clk = 53.693175 MHz = 15 x Fsc:
//   - Subcarrier = the Z80 clock (CLK -> R59/C60 -> VB pin 8). It is locked to
//     the core's ce_cpu, so a line is exactly 228 carrier cycles and a frame
//     a whole number of them: the artifact pattern stands still and does not
//     alternate line to line, as on the real console.
//   - BA7230LS matrix: Y = .30R + .59G + .11B, (R-Y)/1.14, (B-Y)/2.03.
//   - Rectangular 2-phase balanced modulation (square carriers, burst too),
//     burst on the -(B-Y) axis.
//   - Board networks as exact zero-order-hold state-space systems at clk
//     (A = exp(Ac T), B = Ac^-1 (A - I) Bc, see sim/mark3/coeffs.py),
//     Q16 coefficients, Q3.16 states, 18x19 multipliers:
//       luma trap R63/L64/C65/C66/R67 (56 uH || 33 pF, notch 3.70 MHz),
//       DC gain normalised to 1 (the BA7230LS +6 dB Y amp makes up the loss);
//       R-Y/B-Y lowpass R71/C72 and R78/C79 (1 k, 270 pF: 589 kHz);
//       video out bandwidth (BA7230LS fV 6 MHz typ.), one pole.
//   - No 7.5 IRE setup (NTSC-J): black = blanking.
//  Not modelled: component tolerances, the VCXO phase network (absolute
//  carrier phase vs. pixels is a fixed but unknown offset), clamp sag, DG/DP.
//============================================================================

module mark3_cvbs
(
	input             clk,
	input             sc_ref,     // one pulse per subcarrier cycle (ce_cpu)
	input             chroma_std, // 0: datasheet levels, 1: chroma x3/4

	input             hsync,
	input             vsync,
	input             csync,
	input             de,
	input      [23:0] din,

	output     [23:0] dout,
	output reg signed [18:0] level_o = 19'sd16384, // dout before rounding, 8-bit x 256
	output            hsync_o,
	output            vsync_o,
	output            csync_o,
	output            de_o
);

localparam LAT = 9;

// Square carriers box-averaged over each of the 15 samples of a cycle (x2).
// cos edges fall at 3.75 and 11.25 samples, sin edges at 0 and 7.5.
function automatic signed [2:0] sq_cos(input [3:0] p);
	case (p)
		0,1,2,12,13,14: sq_cos =  3'sd2;
		3,11:           sq_cos =  3'sd1;
		default:        sq_cos = -3'sd2;
	endcase
endfunction

function automatic signed [2:0] sq_sin(input [3:0] p);
	if      (p < 4'd7)  sq_sin =  3'sd2;
	else if (p == 4'd7) sq_sin =  3'sd0;
	else                sq_sin = -3'sd2;
endfunction

// Q16 coefficient (18 bit) x Q3.16 value (19 bit), rounded back to Q3.16.
function automatic signed [36:0] mul(input signed [17:0] k, input signed [18:0] x);
	mul = k * x;
endfunction

function automatic signed [18:0] q16(input signed [38:0] acc);
	q16 = 19'((acc + 39'sd32768) >>> 16);
endfunction

// Coefficients from sim/mark3/coeffs.py (Q16).
localparam signed [17:0] TA00 =  18'sd61309, TA01 =   18'sd3525, TA02 =  -18'sd1073;
localparam signed [17:0] TA10 = -18'sd82060, TA11 =  18'sd25030, TA12 =  -18'sd9980;
localparam signed [17:0] TA20 =  18'sd45781, TA21 = -18'sd18296, TA22 =   18'sd7276;
localparam signed [17:0] TB0  =   18'sd2224, TB1  =  18'sd36279, TB2  =  18'sd20299;
localparam signed [17:0] TC   = 18'sd103184;
localparam signed [17:0] CA   =  18'sd61168, CB   =   18'sd4368;
localparam signed [17:0] OA   =  18'sd32475, OB   =  18'sd33061;

// BA7230LS matrix outputs: (R-Y)/1.14 and (B-Y)/2.03, Q16.
localparam signed [17:0] KV   =  18'sd57488, KU   =  18'sd32284;

// Burst: square, 0.46 Vpp of 1.55 V white (BA7230LS VOB/VOY-VOS typ.):
// +-0.149 of white.
localparam signed [18:0] BURST = 19'sd9766;

// Carrier phase, restarted by the CPU clock enable.
reg [3:0] p = 0;
always @(posedge clk) p <= sc_ref ? 4'd0 : (p == 4'd14) ? 4'd0 : p + 4'd1;

// Burst gate: 9 cycles starting 32 clocks (0.6 us) after the end of HSync.
// No burst inside the vertical sync, where it would ride on the sync tip,
// nor on a line that starts in it.
reg        hs0 = 0, bok = 0;
reg [10:0] bcnt = 11'h7FF;
always @(posedge clk) begin
	hs0 <= hsync;
	if (hs0 & ~hsync)          bcnt <= 11'd0;
	else if (bcnt != 11'h7FF)  bcnt <= bcnt + 11'd1;
	if (hs0 & ~hsync)          bok <= ~vsync;
end
wire burst_gate = (bcnt >= 11'd32) && (bcnt < 11'd32 + 11'd135) && bok && ~vsync;
reg [4:0] gate_d = 0;

// All signal values are Q3.16, white luma = 1.0.
reg  [7:0] r0 = 0, g0 = 0, b0 = 0;     // s0 input
reg [15:0] yq1 = 0;                    // s1 luma, 8-bit x 256
reg  [7:0] r1 = 0, b1 = 0;
reg signed [18:0] ry2 = 0, by2 = 0, y2 = 0;              // s2
reg signed [18:0] v3 = 0, u3 = 0;                        // s3
reg signed [18:0] t0 = 0, t1 = 0, t2 = 0;                // trap states
reg signed [18:0] vf = 0, uf = 0, y4 = 0;                // s4
reg signed [18:0] c5 = 0, y5 = 0;                        // s5
reg signed [18:0] pre6 = 19'sd16384;                     // s6, 8-bit x 256
reg signed [18:0] o7 = 19'sd16384;                       // s7, 8-bit x 256
reg        [7:0]  out8 = 8'd64;                          // s8

// 8-bit x 257 / 256 -> Q16 with full scale = 1.0
wire signed [18:0] y16 = $signed({3'b0, yq1 + {8'd0, yq1[15:8]}});
wire signed [18:0] r16 = $signed({3'b0, r1, r1});
wire signed [18:0] b16 = $signed({3'b0, b1, b1});

wire signed [18:0] c_mod = 19'((uf * sq_sin(p) + vf * sq_cos(p)) >>> 1);
wire signed [18:0] c_lvl = chroma_std ? c_mod - (c_mod >>> 2) : c_mod;
wire signed [18:0] c_bst = 19'(-((BURST * sq_sin(p)) >>> 1));

wire signed [27:0] mix  = (y5 + c5) * 28'sd255;
wire signed [19:0] o_rnd = o7 + 20'sd128;

always @(posedge clk) begin
	r0 <= de ? din[23:16] : 8'd0;
	g0 <= de ? din[15:8]  : 8'd0;
	b0 <= de ? din[7:0]   : 8'd0;
	gate_d <= {gate_d[3:0], burst_gate};

	yq1 <= 8'd77 * r0 + 8'd151 * g0 + 8'd28 * b0;
	r1  <= r0;
	b1  <= b0;

	ry2 <= r16 - y16;
	by2 <= b16 - y16;
	y2  <= y16;

	v3  <= q16(mul(KV, ry2));
	u3  <= q16(mul(KU, by2));
	t0  <= q16(mul(TA00, t0) + mul(TA01, t1) + mul(TA02, t2) + mul(TB0, y2));
	t1  <= q16(mul(TA10, t0) + mul(TA11, t1) + mul(TA12, t2) + mul(TB1, y2));
	t2  <= q16(mul(TA20, t0) + mul(TA21, t1) + mul(TA22, t2) + mul(TB2, y2));

	vf  <= q16(mul(CA, vf) + mul(CB, v3));
	uf  <= q16(mul(CA, uf) + mul(CB, u3));
	y4  <= q16(mul(TC, t2));

	c5  <= gate_d[4] ? c_bst : c_lvl;
	y5  <= y4;

	// blank = 64, white = 64 + 127.5 (stock yc_out CVBS levels)
	pre6 <= 19'sd16384 + 19'(mix >>> 9);

	o7  <= q16(mul(OA, o7) + mul(OB, pre6));

	level_o <= o7;
	out8 <= o_rnd[19] ? 8'd0 : (o_rnd[18:8] > 11'd255) ? 8'd255 : o_rnd[15:8];
end

reg [LAT-1:0] hs_d = 0, vs_d = 0, cs_d = 0, de_d = 0;
always @(posedge clk) begin
	hs_d <= {hs_d[LAT-2:0], hsync};
	vs_d <= {vs_d[LAT-2:0], vsync};
	cs_d <= {cs_d[LAT-2:0], csync};
	de_d <= {de_d[LAT-2:0], de};
end

assign dout    = {8'd0, out8, 8'd0};
assign hsync_o = hs_d[LAT-1];
assign vsync_o = vs_d[LAT-1];
assign csync_o = cs_d[LAT-1];
assign de_o    = de_d[LAT-1];

endmodule
