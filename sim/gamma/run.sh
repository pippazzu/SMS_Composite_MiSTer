#!/bin/sh
# gamma_fast against gamma_corr at the RGB and composite pixel rates.
set -e
cd "$(dirname "$0")"
iverilog -g2012 -o g.vvp tb_gamma.sv ../../sys/gamma_corr.sv
vvp -n g.vvp | grep pixels
