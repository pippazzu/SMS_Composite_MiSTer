`timescale 1ns/1ps
// Counts decoder line starts per line for every pair of full-strength colours
// alternating in 1, 2 and 8 pixel steps, one line looped (+MS=0 Mark III,
// +MS=1 Master System). Pass: exactly 1 per line (20 counted lines).
module tb;
reg clk = 0;
always #9.312 clk = ~clk;
reg sc = 0, hs = 0, hb = 1;
reg [7:0] r = 0, g = 0, b = 0;
integer ms;
reg rst = 1;
mark3_tv dut(.clk(clk), .reset(rst), .sc_ref(sc), .chroma_std(1'b0), .ms(ms[0]), .premium(1'b0),
	.brightness(3'd0), .sharpness(2'd0), .r_in(r), .g_in(g), .b_in(b),
	.hs_in(hs), .vs_in(1'b0), .de_in(~hb), .hb_in(hb), .vb_in(1'b0),
	.pix(), .r_out(), .g_out(), .b_out(), .hs_out(), .vs_out(), .hb_out(), .vb_out());

reg [2:0] lt_sc[0:3419]; reg lt_hs[0:3419]; reg lt_hb[0:3419];
reg [7:0] cr[0:7], cg[0:7], cb[0:7];
integer fl, t, a, c, w, ln, x0, pix, starts, i, k, pairs, nbad;
reg ls_d;
real mn, v;
reg [31:0] x[0:2];
initial begin
	if (!$value$plusargs("MS=%d", ms)) ms = 0;
	fl = $fopen("line.txt", "r");
	for (t = 0; t < 3420; t = t + 1) begin
		k = $fscanf(fl, "%h %h %h\n", x[0], x[1], x[2]);
		lt_sc[t] = x[0][0]; lt_hs[t] = x[1][0]; lt_hb[t] = x[2][0];
	end
	for (i = 0; i < 8; i = i + 1) begin
		cr[i] = i[0] ? 8'd255 : 8'd0; cg[i] = i[1] ? 8'd255 : 8'd0; cb[i] = i[2] ? 8'd255 : 8'd0;
	end
	nbad = 0;
	for (a = 0; a < 8; a = a + 1) for (c = a + 1; c < 8; c = c + 1) for (w = 1; w <= 8; w = w * 2) if (w != 4) begin
		rst = 1; repeat (16) @(posedge clk); #1; rst = 0;
		starts = 0; mn = 9.0; ls_d = 0;
		for (ln = 0; ln < 24; ln = ln + 1) begin
			x0 = -1;
			for (t = 0; t < 3420; t = t + 1) begin
				sc = lt_sc[t]; hs = lt_hs[t]; hb = lt_hb[t];
				if (!hb && x0 < 0) x0 = t;
				pix = hb ? 0 : ((t - x0) / 10 / w) % 2;
				r = hb ? 0 : pix ? cr[c] : cr[a];
				g = hb ? 0 : pix ? cg[c] : cg[a];
				b = hb ? 0 : pix ? cb[c] : cb[a];
				@(posedge clk); #1;
				if (ln >= 4) begin
					if (dut.decoder.line_start && !ls_d) starts = starts + 1;
					if (!hb) begin v = $itor($signed(dut.enc)) / 2097152.0; if (v < mn) mn = v; end
				end
				ls_d = dut.decoder.line_start;
			end
		end
		if (starts != 20) nbad = nbad + 1;
		$display("%0d %0d w%0d starts %0d/20 lowest_in_picture %0.3f V %s", a, c, w, starts, mn, starts == 20 ? "ok" : "FALSE");
	end
	$display("patterns with false starts: %0d", nbad);
	$finish;
end
endmodule
