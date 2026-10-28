// Resamples a composite stream from 15 to 12 samples per subcarrier cycle
// (53.69 MHz to 42.95 MHz worth of samples) for composite_decoder, which
// needs an even SPC. Linear interpolation; four output samples (ce) for
// every five input clocks, at input positions 0, 1.25, 2.5 and 3.75. The
// carrier is 3.6 MHz against a 53.7 MHz input, so the interpolation dips the
// carrier by 2% at most.

module cvbs_resample
(
	input                    clk,
	input      signed [23:0] din,   // one sample per clk
	output reg               ce,    // one output sample
	output reg signed [23:0] dout
);

reg  [2:0] k = 0;
reg signed [23:0] x1 = 0;

wire signed [25:0] d4 = (26'(din) - 26'(x1));   // x[n] - x[n-1]

always @(posedge clk) begin
	k  <= (k == 3'd4) ? 3'd0 : k + 3'd1;
	x1 <= din;
	ce <= (k != 3'd1);
	case (k)
		3'd0: dout <= din;                                     // position 0
		3'd2: dout <= 24'(26'(x1) + (d4 >>> 2));               // 1.25
		3'd3: dout <= 24'(26'(x1) + (d4 >>> 1));               // 2.5
		3'd4: dout <= 24'(26'(x1) + (d4 >>> 1) + (d4 >>> 2));  // 3.75
		default: ;
	endcase
end

endmodule
