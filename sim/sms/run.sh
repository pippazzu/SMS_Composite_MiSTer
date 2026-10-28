#!/bin/sh
# Master System (CXA1145) composite encoder.
#  1. coeffs.py: board network responses and the Q16 coefficients in
#     rtl/composite/sms_av_board.sv
#  2. tb_align.sv on the real raster (needs ../mark3/tv_stim.txt and
#     csync_sim.v from ../mark3/run.sh): both encoders' jack voltage, and the
#     bar edge that sets MS_DLY in mark3_tv.sv
# The decoded pictures come from ../mark3/run.sh's tb_tv.sv with OPT bit 7.
set -e
cd "$(dirname "$0")"
python3 coeffs.py
iverilog -g2012 -o align.vvp tb_align.sv ../../rtl/composite/mark3_tv.sv ../../rtl/composite/composite_decoder.sv \
	../../rtl/composite/cvbs_resample.sv ../../rtl/mark3_cvbs.sv ../../rtl/composite/sms_cxa_cvbs.sv \
	../../rtl/composite/cxa1145.sv ../../rtl/composite/sms_av_board.sv ../mark3/csync_sim.v
vvp -n align.vvp > /dev/null

python3 align.py
# False line starts (handoff 2026-10-27): needs line.txt from gen_line.py.
# Every pair of full-strength colours at 1/2/8 pixel steps, one line looped,
# line starts counted per line (pass = exactly 1): vvp -n fs.vvp +MS=0|1
# iverilog -g2012 -o fs.vvp tb_falsesync.sv <the rtl as for align.vvp>
