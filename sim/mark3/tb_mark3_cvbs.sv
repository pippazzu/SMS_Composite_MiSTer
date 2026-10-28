`timescale 1ns/1ps
// Compares rtl/mark3_cvbs.sv against model.py sample by sample.
// +STD=0|1 selects the chroma level and expect0/expect1.txt.
module tb;
reg clk = 0;
always #9.312 clk = ~clk;

reg sc, hs, vs, cs, de, std;
reg [7:0] r, g, b;
wire [23:0] dout;
wire hso, vso, cso, deo;

mark3_cvbs dut(.clk(clk), .sc_ref(sc), .chroma_std(std), .hsync(hs), .vsync(vs), .csync(cs), .de(de),
	.din({r, g, b}), .dout(dout), .hsync_o(hso), .vsync_o(vso), .csync_o(cso), .de_o(deo));

integer fs, fe, fo, n, errs, exp_v, k, sel;
reg [31:0] v[0:7];
initial begin
	if (!$value$plusargs("STD=%d", sel)) sel = 0;
	std = sel[0];
	errs = 0; n = 0;
	fs = $fopen("stim.txt", "r");
	fe = $fopen(std ? "expect1.txt" : "expect0.txt", "r");
	fo = $fopen(std ? "rtl1.txt" : "rtl0.txt", "w");
	while ($fscanf(fs, "%h %h %h %h %h %h %h %h\n", v[0], v[1], v[2], v[3], v[4], v[5], v[6], v[7]) == 8) begin
		{sc, hs, vs, cs, de, r, g, b} = {v[0][0], v[1][0], v[2][0], v[3][0], v[4][0], v[5][7:0], v[6][7:0], v[7][7:0]};
		@(posedge clk); #1;
		k = $fscanf(fe, "%d\n", exp_v);
		$fdisplay(fo, "%0d %0d %0d %0d %0d %0d %0d %0d", dout[15:8], hso, deo, dut.o7, dut.pre6, dut.c5, dut.y5, dut.vf);
		if (dout !== {8'd0, exp_v[7:0], 8'd0}) begin
			if (errs < 10) $display("mismatch t=%0d got %0d exp %0d", n, dout[15:8], exp_v);
			errs = errs + 1;
		end
		n = n + 1;
	end
	$display("chroma_std=%0d: %0d samples, %0d mismatches", std, n, errs);
	$finish;
end
endmodule
