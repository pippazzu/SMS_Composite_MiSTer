`timescale 1ns/1ps
// Dumps both encoders' jack voltage (Q2.21, before the resampler) for the
// first 40 lines of the real raster, to line up the Master System chain.
module tb;
reg clk = 0;
always #9.312 clk = ~clk;
reg sc, hs, vs, hb, vb;
reg [7:0] r, g, b;
mark3_tv dut(.clk(clk), .reset(n < 16), .sc_ref(sc), .chroma_std(1'b0), .ms(1'b1), .premium(1'b0),
	.brightness(3'd0), .sharpness(2'd0), .r_in(r), .g_in(g), .b_in(b),
	.hs_in(hs), .vs_in(vs), .de_in(~(hb | vb)), .hb_in(hb), .vb_in(vb),
	.pix(), .r_out(), .g_out(), .b_out(), .hs_out(), .vs_out(), .hb_out(), .vb_out());
integer fs, fo, n;
reg [31:0] v[0:7];
initial begin
	fs = $fopen("../mark3/tv_stim.txt", "r");
	fo = $fopen("align.txt", "w");
	n = 0;
	while (n < 3420 * 300 && $fscanf(fs, "%h %h %h %h %h %h %h %h\n", v[0], v[1], v[2], v[3], v[4], v[5], v[6], v[7]) == 8) begin
		{sc, hs, vs, hb, vb} = {v[0][0], v[1][0], v[2][0], v[3][0], v[4][0]};
		{r, g, b} = {v[5][7:0], v[6][7:0], v[7][7:0]};
		@(posedge clk); #1;
		$fdisplay(fo, "%0d %0d %0d %0d", n, hb | vb, dut.comp, dut.ms_d[0]);
		n = n + 1;
	end
	$finish;
end
endmodule
