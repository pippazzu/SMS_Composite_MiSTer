#!/bin/sh
# Mark III composite: encoder model checks and the full encode/decode chain.
#  1. rtl/mark3_cvbs.sv bit for bit against model.py
#  2. the core's rtl/video.vhd run in GHDL for the real raster (video_pins.txt)
#  3. numeric checks (checks.py) and a TV-style decode of colour bars
#  4. rtl/composite/mark3_tv.sv (encoder + composite_decoder) in Icarus on the
#     real raster, decoded pictures as PNGs: tv_rtl_<opt>.png
set -e
cd "$(dirname "$0")"
python3 model.py
iverilog -g2012 -o tb.vvp tb_mark3_cvbs.sv ../../rtl/mark3_cvbs.sv
vvp -n tb.vvp +STD=0 | grep mismatches
vvp -n tb.vvp +STD=1 | grep mismatches
mkdir -p work_ghdl
ghdl -a --std=08 -fsynopsys --workdir=work_ghdl -frelaxed ../../rtl/video.vhd tb_video.vhd
ghdl -e --std=08 -fsynopsys --workdir=work_ghdl -frelaxed tb_video
ghdl -r --std=08 -fsynopsys --workdir=work_ghdl -frelaxed tb_video
python3 checks.py
python3 decode_check.py
python3 tv_rtl.py stim
sed -n '/^module csync/,/^endmodule/p' ../../sys/sys_top.v > csync_sim.v
iverilog -g2012 -o tv.vvp tb_tv.sv ../../rtl/composite/mark3_tv.sv ../../rtl/composite/composite_decoder.sv \
	../../rtl/composite/cvbs_resample.sv ../../rtl/mark3_cvbs.sv ../../rtl/composite/sms_cxa_cvbs.sv \
	../../rtl/composite/cxa1145.sv ../../rtl/composite/sms_av_board.sv csync_sim.v
# comb delay: prev must be c16 exactly 2730 decoder samples (227.5 cycles) back
head -300000 tv_stim.txt > tv_stim_short.txt
sed 's/tv_stim.txt/tv_stim_short.txt/' tb_comb.sv > tb_comb_short.sv
iverilog -g2012 -o comb.vvp tb_comb_short.sv ../../rtl/composite/mark3_tv.sv ../../rtl/composite/composite_decoder.sv \
	../../rtl/composite/cvbs_resample.sv ../../rtl/mark3_cvbs.sv ../../rtl/composite/sms_cxa_cvbs.sv \
	../../rtl/composite/cxa1145.sv ../../rtl/composite/sms_av_board.sv csync_sim.v
vvp -n comb.vvp +OPT=1 +OUT=comb_out.txt > /dev/null
python3 -c "
import numpy as np
a = np.loadtxt('comb_out.txt', dtype=int); c, p = a[:, 0], a[:, 1]
e = {D: np.mean(np.abs(p[20000:] - c[20000 - D:-D])) for D in (2729, 2730, 2731)}
print(('PASS' if e[2730] == 0 else 'FAIL') + ' comb delay: mean |prev - c16[-D]| %s' % e)"
# OPT bits: [0] Premium, [2:1] sharpness, [5:3] brightness, [6] standard chroma, [7] Master System
for opt in 0 1 128 129; do
	vvp -n tv.vvp +OPT=$opt +OUT=out_$opt.txt > /dev/null &
done
wait
for opt in 0 1 128 129; do python3 tv_rtl.py png tv_rtl_$opt out_$opt.txt; done
