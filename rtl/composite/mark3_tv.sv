// Composite filter for the digital outputs: the VDP picture is encoded by the
// Mark III encoder model (mark3_cvbs.sv), given the sync a MiSTer composite
// cable would add, and decoded by Kitrinx's composite_decoder (NES_MiSTer),
// all on clk_sys with no frame buffer. The decoded picture comes out at one
// pixel every two decoder samples, four per SMS pixel (21.48 MHz), with sync
// regenerated from the waveform.
//
// Levels follow the BA7230LS typicals: 0.65 V sync for 1.55 V white, so with
// white scaled to 0.714 V the sync is 0.299 V, and the set's gain follows
// the sync (contrast = 2856 x 0.2857 / 0.299 V).
//
// With ms set the Master System's encoder is used instead: the CXA1145 and
// its board networks (sms_cxa_cvbs.sv), whose sync at the jack is 0.232 V
// (contrast 3517).

module mark3_tv
(
	input         clk,          // 53.693175 MHz
	input         reset,
	input         sc_ref,       // ce_cpu
	input         chroma_std,
	input         ms,           // 0 Mark III (BA7230LS), 1 Master System (CXA1145)
	input         premium,      // 0 Budget TV (notch), 1 Premium TV (adaptive comb)
	input   [2:0] brightness,   // Japan, USA, More, Much More, Too Much
	input   [1:0] sharpness,    // Off, Low, Medium, High

	input   [7:0] r_in,
	input   [7:0] g_in,
	input   [7:0] b_in,
	input         hs_in,
	input         vs_in,
	input         de_in,        // picture to encode
	input         hb_in,        // crop: the RGB path's blanking
	input         vb_in,

	output        pix,          // one decoded pixel
	output  [7:0] r_out,
	output  [7:0] g_out,
	output  [7:0] b_out,
	output        hs_out,
	output        vs_out,
	output        hb_out,
	output        vb_out
);

// What a MiSTer composite cable gets: sys_top's csync from HS/VS.
wire cs_in;
csync csync_tv(clk, hs_in, vs_in, cs_in);

wire signed [18:0] level;
wire               cs_enc;
mark3_cvbs encoder
(
	.clk       (clk),
	.sc_ref    (sc_ref),
	.chroma_std(chroma_std),
	.hsync     (hs_in),
	.vsync     (vs_in),
	.csync     (cs_in),
	.de        (de_in),
	.din       ({r_in, g_in, b_in}),
	.dout      (),
	.level_o   (level),
	.hsync_o   (),
	.vsync_o   (),
	.csync_o   (cs_enc),
	.de_o      ()
);

// Volts, Q2.21: one DAC count (1/256 here) of the 127.5-count white is
// 0.714 V / 127.5 / 256 = 45.875 / 2^21 V. Blank is 0 V.
localparam signed [23:0] SYNC_V = 24'sd627920;      // 0.2994 V
wire signed [27:0] lv_m = (28'(level) - 28'sd16384) * 28'sd367;
reg  signed [23:0] comp = 0;
always @(posedge clk) comp <= 24'(lv_m >>> 3) - (cs_enc ? SYNC_V : 24'sd0);

wire signed [23:0] ms_cvbs;
sms_cxa_cvbs ms_encoder
(
	.clk   (clk),
	.reset (reset),
	.sc_ref(sc_ref),
	.csync (cs_in),
	.de    (de_in),
	.din   ({r_in, g_in, b_in}),
	.cvbs  (ms_cvbs)
);

// The Master System chain is shorter; MS_DLY lines its picture up with the
// Mark III's, so one crop fits both (sim/sms/run.sh).
localparam MS_DLY = 2;
reg signed [23:0] ms_d[MS_DLY];
always @(posedge clk) begin
	ms_d[0] <= ms_cvbs;
	for (int i = 1; i < MS_DLY; i++) ms_d[i] <= ms_d[i-1];
end
wire signed [23:0] enc = ms ? ms_d[MS_DLY-1] : comp;

wire               rs_ce;
wire signed [23:0] rs_comp;
cvbs_resample resample(.clk(clk), .din(enc), .ce(rs_ce), .dout(rs_comp));

// Brightness, Q2.13 volts, the NES_MiSTer list: Japan = black at blanking
// (right for the Mark III), USA = a set expecting 7.5 IRE setup.
wire [15:0] bright_v = brightness == 3'd1 ? 16'hFE49 : brightness == 3'd2 ? 16'd292 :
	brightness == 3'd3 ? 16'd643 : brightness == 3'd4 ? 16'd936 : 16'd0;

wire dec_hb, dec_vb;
composite_decoder #(
	.SPC     (12),
	.HCNT_W  (12),
	.LUMA_LP (6),
	.PIX_DIV (2),
	.COMB_DLY(2730)         // 227.5 cycles x 12
) decoder
(
	.clk          (clk),
	.reset        (reset),
	.ce           (rs_ce),
	.comp         (rs_comp),
	.sat          (8'd128),
	.hue          (8'd0),
	.chroma_trail (premium ? 4'd2 : 4'd3),
	.sharpness    ({sharpness, 2'b00}),
	.black_stretch(2'd0),
	.brightness   (bright_v),
	.contrast     (ms ? 16'd3517 : 16'd2725),
	.comb_mode    (premium ? 2'd2 : 2'd0),
	.ce_out       (),
	.pix_out      (pix),
	.hs_out       (hs_out),
	.vs_out       (vs_out),
	.hb_out       (dec_hb),
	.vb_out       (dec_vb),
	.r_out        (r_out),
	.g_out        (g_out),
	.b_out        (b_out)
);

// Crop to the RGB path's picture: the source blanking, delayed by the
// encoder + decoder latency (measured with sim/mark3/run.sh: bar edges land on their pixels), on top of
// the decoder's own blanking.
localparam CROP_DLY = 58;
reg [CROP_DLY-1:0] hb_d = 0, vb_d = 0;
always @(posedge clk) begin
	hb_d <= {hb_d[CROP_DLY-2:0], hb_in};
	vb_d <= {vb_d[CROP_DLY-2:0], vb_in};
end
reg hb_c = 1, vb_c = 1;
always @(posedge clk) if (pix) begin
	hb_c <= hb_d[CROP_DLY-1];
	vb_c <= vb_d[CROP_DLY-1];
end
assign hb_out = dec_hb | hb_c;
assign vb_out = dec_vb | vb_c;

endmodule
