`timescale 1ns/1ps
// Logs composite_decoder's comb input (c16) and delayed sample (prev) on
// every decoder sample, to check that the comb delay is exactly COMB_DLY.
module tb;
reg clk = 0;
always #9.312 clk = ~clk;

reg sc, hs, vs, hb, vb;
reg [7:0] r, g, b;
reg premium, chroma_std;
reg [2:0] bright;
reg [1:0] sharp;
wire pix, ohs, ovs, ohb, ovb;
wire [7:0] or_, og, ob;

mark3_tv dut(.clk(clk), .reset(n < 16), .sc_ref(sc), .chroma_std(chroma_std), .premium(premium),
	.brightness(bright), .sharpness(sharp), .r_in(r), .g_in(g), .b_in(b),
	.hs_in(hs), .vs_in(vs), .hb_in(hb), .vb_in(vb),
	.pix(pix), .r_out(or_), .g_out(og), .b_out(ob), .hs_out(ohs), .vs_out(ovs), .hb_out(ohb), .vb_out(ovb));

integer fs, fo, n, k, opt;
reg [8*64-1:0] oname;
reg [31:0] v[0:7];
initial begin
	if (!$value$plusargs("OPT=%d", opt)) opt = 0;
	premium = opt[0]; sharp = opt[2:1]; bright = opt[5:3]; chroma_std = opt[6];
	fs = $fopen("tv_stim.txt", "r");
	if (!$value$plusargs("OUT=%s", oname)) oname = "tv_rtl_out.txt";
	fo = $fopen(oname, "w");
	n = 0;
	while ($fscanf(fs, "%h %h %h %h %h %h %h %h\n", v[0], v[1], v[2], v[3], v[4], v[5], v[6], v[7]) == 8) begin
		{sc, hs, vs, hb, vb} = {v[0][0], v[1][0], v[2][0], v[3][0], v[4][0]};
		{r, g, b} = {v[5][7:0], v[6][7:0], v[7][7:0]};
		@(posedge clk); #1;
		if (dut.rs_ce && n > 100) $fdisplay(fo, "%0d %0d", $signed(dut.decoder.c16), $signed(dut.decoder.prev));
		n = n + 1;
	end
	$finish;
end
endmodule
