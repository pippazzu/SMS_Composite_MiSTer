// Master System board networks between the CXA1145's Y/C outputs and its
// Y/C MIX inputs, and the resulting composite video at the AV jack.
//
//   Luma   Y OUT - R33 1.5k - [L34 100uH || C35 18pF] - Y IN
//                                                  Y IN - C36 180pF - GND
//                                                  Y IN - R37 1k    - VREF
//   Chroma C OUT - R38 1k - A,  A - L39 12uH - GND,  A - C40 150pF - GND,
//          A - C41 18pF - L42 100uH - B,  B - R43 1k - GND,  B - C44 0.01uF - C IN
//
// Sega IC board schematic 171-5534 (PAL VA1). Its tuned capacitors (C35 12p,
// C40 100p, C41 12p) put the trap and both chroma resonators at 4.59 MHz for
// PAL; for this NTSC encode they are x1.5, all three at 3.75 MHz, the NTSC
// Mega Drive's 100uH || 18pF trap (sim/sms/coeffs.py). Y IN and C IN are
// base inputs and load nothing; C44 and VREF's decoupling are shorts at video
// rates.
//
// As md_av_board: exact zero-order-hold discretisation at the master clock,
// currents carried as volts across 1k, Q16 coefficients and Q3.16 states,
// every product 18 x 19. The CXA1145's mixer gain cancels against the
// encoder's jack-referred levels, so the jack voltage is the sum of the two
// network outputs driven with twice those levels.
//
// The coefficients are constants, so the products are built as shift-and-add
// logic: with the Mark III encoder and the decoder already in the core, the
// 32 products would not fit in the remaining DSP blocks.

(* multstyle = "logic" *)
module sms_av_board (
	input                    clk,
	input                    reset,
	input  signed [23:0]     y_in,     // Q2.21, jack-referred luma + sync
	input  signed [23:0]     c_in,     // Q2.21, jack-referred chroma + burst
	output reg signed [23:0] cvbs      // Q2.21 volts at the jack, 75R terminated
);

// Luma: states {tank voltage, L34 current x 1k, Y IN voltage}.
localparam signed [17:0] LA00 =  18'sd29812;
localparam signed [17:0] LA01 = -18'sd47803;
localparam signed [17:0] LA02 = -18'sd28948;
localparam signed [17:0] LA10 =  18'sd8604;
localparam signed [17:0] LA11 =  18'sd60513;
localparam signed [17:0] LA12 = -18'sd3154;
localparam signed [17:0] LA20 = -18'sd2895;
localparam signed [17:0] LA21 =  18'sd1752;
localparam signed [17:0] LA22 =  18'sd56254;
localparam signed [17:0] LB0  =  18'sd30700;
localparam signed [17:0] LB1  =  18'sd3271;
localparam signed [17:0] LB2  =  18'sd3012;

// Chroma: states {L39 current x 1k, A voltage, C41 voltage, L42 current x 1k};
// B = L42 current x R43 = the last state.
localparam signed [17:0] CA00 =  18'sd59582;
localparam signed [17:0] CA01 =  18'sd92270;
localparam signed [17:0] CA02 =  18'sd356;
localparam signed [17:0] CA03 = -18'sd5505;
localparam signed [17:0] CA10 = -18'sd7382;
localparam signed [17:0] CA11 =  18'sd51540;
localparam signed [17:0] CA12 =  18'sd661;
localparam signed [17:0] CA13 = -18'sd6484;
localparam signed [17:0] CA20 = -18'sd237;
localparam signed [17:0] CA21 =  18'sd5505;
localparam signed [17:0] CA22 =  18'sd59700;
localparam signed [17:0] CA23 =  18'sd59678;
localparam signed [17:0] CA30 = -18'sd661;
localparam signed [17:0] CA31 =  18'sd9726;
localparam signed [17:0] CA32 = -18'sd10742;
localparam signed [17:0] CA33 =  18'sd48298;
localparam signed [17:0] CB0  =  18'sd5954;
localparam signed [17:0] CB1  =  18'sd7382;
localparam signed [17:0] CB2  =  18'sd237;
localparam signed [17:0] CB3  =  18'sd661;

function automatic signed [18:0] sat19(input signed [24:0] v);
	if      (v >  25'sd262143) sat19 =  19'sd262143;
	else if (v < -25'sd262144) sat19 = 19'sh40000;
	else                       sat19 =  v[18:0];
endfunction

// One state row of up to four states and the input.
function automatic signed [18:0] row(
	input signed [17:0] a0, input signed [18:0] x0,
	input signed [17:0] a1, input signed [18:0] x1,
	input signed [17:0] a2, input signed [18:0] x2,
	input signed [17:0] a3, input signed [18:0] x3,
	input signed [17:0] bb, input signed [18:0] u);
	/* verilator lint_off UNUSEDSIGNAL */
	reg signed [41:0] acc;
	/* verilator lint_on UNUSEDSIGNAL */
	begin
		acc = (a0 * x0 + a1 * x1) + (a2 * x2 + a3 * x3) + bb * u;
		row = sat19(acc[40:16]);
	end
endfunction

// Q2.21 in, doubled to the pin level, Q3.16.
wire signed [18:0] uy = y_in[22:4];
wire signed [18:0] uc = c_in[22:4];

reg signed [18:0] l0, l1, l2;
reg signed [18:0] k0, k1, k2, k3;

always @(posedge clk) begin
	if (reset) begin
		{l0, l1, l2} <= 57'd0;
		{k0, k1, k2, k3} <= 76'd0;
	end else begin
		l0 <= row(LA00, l0, LA01, l1, LA02, l2, 18'sd0, 19'sd0, LB0, uy);
		l1 <= row(LA10, l0, LA11, l1, LA12, l2, 18'sd0, 19'sd0, LB1, uy);
		l2 <= row(LA20, l0, LA21, l1, LA22, l2, 18'sd0, 19'sd0, LB2, uy);
		k0 <= row(CA00, k0, CA01, k1, CA02, k2, CA03, k3, CB0, uc);
		k1 <= row(CA10, k0, CA11, k1, CA12, k2, CA13, k3, CB1, uc);
		k2 <= row(CA20, k0, CA21, k1, CA22, k2, CA23, k3, CB2, uc);
		k3 <= row(CA30, k0, CA31, k1, CA32, k2, CA33, k3, CB3, uc);
	end
end

wire signed [19:0] mix = l2 + k3;

always @(posedge clk) begin
	if (reset)                     cvbs <= 24'sd0;
	else if (mix >  20'sd262143)   cvbs <= 24'sd8388576;
	else if (mix < -20'sd262144)   cvbs <= 24'sh800000;
	else                           cvbs <= {mix[18:0], 5'd0};
end

endmodule
