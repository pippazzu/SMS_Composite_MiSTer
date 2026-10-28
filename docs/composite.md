# Composite video: technical notes

## Mark III and Master System composite output (BA7230LS, CXA1145)

Sources: Sega's Mark III schematic (171-5304), the ROHM BA7230LS data sheet, Sega's Master System IC board schematic (171-5534, PAL VA1), the Sony CXA1145 data sheet, and the electrolytic capacitor list of the NTSC Master System board (837-6067). No console has been measured yet: every figure below comes from these documents.

1. **The VDP** (315-5124) outputs R, G and B and the horizontal and vertical sync. A line is 342 pixels, exactly 228 cycles of the colour subcarrier rather than NTSC's 227.5, so the carrier has the same phase on every line and colour artifacts stand still instead of alternating from line to line.
2. **The subcarrier** is the Z80 clock, the VDP clock divided by 3 (3.58 MHz), so it is locked to the pixels. On the Mark III it reaches the BA7230LS through R59/C60 (schematic). The PAL Master System has its own 53.2 MHz crystal, divided for both the VDP and the CXA1145. On the NTSC Master System the Z80 clock is assumed, as on the Mark III: its parts list differs from the PAL board around the subcarrier input (C22 is a 100 µF electrolytic, 82 pF on PAL), and no NTSC schematic has been checked. The carrier's absolute phase against the pixels is not known on either console.
3. **The Mark III's BA7230LS encoder** (data sheet): Y = 0.30 R + 0.59 G + 0.11 B, (R−Y)/1.14 and (B−Y)/2.03, no setup pedestal. Its balanced modulators switch the two colour differences with rectangular carriers 90° apart, not sine waves, and the burst is square too, on the −(B−Y) axis, with none in the vertical sync. At the typical levels sync is 0.65 V for 1.55 V white and the colour comes out about 1.34× a standard set's saturation (the data sheet allows ±2 dB on these gains). Output bandwidth 6 MHz.
4. **The Mark III board's filters** (schematic): R−Y and B−Y each leave the chip through 1 kΩ / 270 pF (R71/C72, R78/C79), a 589 kHz low-pass that puts the colour about 1.5 pixels behind the brightness. Luma goes through the R63/L64/C65/C66/R67 trap, 56 µH ∥ 33 pF, a notch at 3.70 MHz that is −4 dB at 2 MHz.
5. **The Master System's CXA1145 encoder** (data sheet): RGB comes in through 2.2 kΩ / 4.7 kΩ dividers and 0.1 µF (R9/R12/R15, schematic). Y = 0.299 R + 0.587 G + 0.114 B, white 0.71 V and sync 0.29 V at the chip, no setup pedestal, 0.493 (B−Y) / 0.877 (R−Y) sine modulators, a 0.29 Vp-p burst at 180° from 0.5 µs after the C-SYNC rising edge for 2.75 µs, and a half-H killer. The burst is sent on every line, the vertical serrations included.
6. **The Master System board's filters** (schematic) sit between the CXA1145's Y/C outputs and its mixer inputs:
   * luma: R33 1.5k into L34 100 µH ∥ C35, then C36 180 pF and R37 1k. A low-pass with a trap. The 1.5k / 1k divider leaves white at 0.568 V and sync at 0.232 V at the jack.
   * chroma: R38 1k into L39 12 µH ∥ C40, then C41 and L42 100 µH in series into R43 1k. A narrow band-pass.
   * On the PAL board C35 is 12 pF, C40 100 pF and C41 12 pF, which put all three resonances at 4.59 MHz, above PAL's 4.43. For NTSC they are taken 1.5× larger (18, 150 and 18 pF), which moves all three to 3.75 MHz, where Sega put the NTSC Mega Drive's identical 100 µH ∥ 18 pF trap. The NTSC Master System's values are not confirmed: the 837-6067 list covers only the electrolytics. Its C28 (100 µF, video out coupling) and C4 match the PAL board.

Not known: the NTSC Master System's filter capacitors and subcarrier wiring, the carrier's absolute phase, part tolerances on any one console.

## How it is implemented

1. **VDP pins**: the core's VDP RGB, and its HSync and VSync combined into composite sync as the MiSTer's own C-SYNC is. Everything runs on the 53.693175 MHz system clock, 15 times the subcarrier, with the carrier's phase taken from the Z80 clock enable.
2. **Mark III encoder** (`rtl/mark3_cvbs.sv`): the data sheet's typical values, square-wave modulation, and the board's networks solved as exact zero-order-hold state-space systems at the system clock, with Q16 coefficients and Q3.16 states (`sim/mark3/coeffs.py`).
3. **Master System encoder** (`rtl/composite/sms_cxa_cvbs.sv`): `rtl/composite/cxa1145.sv` is the Mega Drive composite core's CXA1145 model without its correction for fine coloured detail, which is fitted to one Mega Drive's measurements. The carrier advances 24° per clock. The board's networks (`rtl/composite/sms_av_board.sv`, `sim/sms/coeffs.py`) are solved the same way as the Mark III's, every product 18 × 19 bits, built from shifts and adds because the DSP blocks are used up by the other stages. Two clocks of delay line its picture up with the Mark III's, so one crop serves both.
4. **Resampling** (`rtl/composite/cvbs_resample.sv`): from 15 to 12 samples per subcarrier cycle by linear interpolation, because the decoder needs an even count. The carrier loses at most 2%.
5. **Composite filters**: Kitrinx's composite decoder from the NES core, at 12 samples per subcarrier cycle, with a 6-sample luma low-pass and two output pixels per SMS pixel, with the changes listed below (`rtl/composite/mark3_tv.sv`). Its contrast input is what a set's sync AGC gives for each console's sync level: 2725 for the Mark III, 3517 for the Master System. Comp. Brightness uses the NES core's list; Japan puts black at blanking. The picture is cropped to the RGB path's blanking, delayed by the 58-clock latency of encoder and decoder.

Not implemented: PAL (the decoder is NTSC only), Game Gear (an LCD), the HC132 that shapes the Master System's sync, part tolerances.

In simulation (Icarus Verilog, GHDL): `sim/mark3/run.sh` checks the Mark III encoder bit for bit against a Python model, runs the core's `rtl/video.vhd` for the real raster, checks levels and timing, and renders the decoded picture to PNGs. `sim/sms/run.sh` computes the Master System board coefficients, checks both encoders' jack voltage and the alignment of their pictures, and runs `tb_falsesync.sv`: every pair of full-strength colours from {black, red, green, blue, yellow, cyan, magenta, white}, alternating in 1, 2 and 8 pixel steps, gives exactly one line start per line on both encoders (84 patterns each). The lowest point in the picture is −0.326 V on the Mark III (sync tip −0.299 V) and −0.297 V on the Master System (sync tip −0.232 V).

## Changes to Kitrinx's composite decoder

The decoder is Kitrinx's from the NES core at 49a0a66 (MIT licence; the changes are MIT too), in `rtl/composite/composite_decoder.sv`, with each change marked "SMS:". It is not the same file as the Mega Drive core's.

* **Premium TV comb** uses a set's fixed 227.5-cycle delay instead of one line of the source. SMS lines are 228 cycles, so a delay of one source line would meet chroma in phase and cancel the burst and the colour.
* **The comb's line store** is a RAM inside the decoder whose read is held by the sample enable, rather than the core's dpram. The resampler gives four samples in every five clocks, and the comb stays aligned.
* **The sync tip** is tracked on the signal averaged over one subcarrier cycle, as a set's sync separator sees it through its low-pass. On the Master System the narrow chroma band-pass carries the burst on the vertical serrations into the next sync, ringing down to −0.376 V against a −0.232 V tip; the raw tip followed it and the TV lost vertical sync. The slicer still compares the raw signal against the tip, so its timing is unchanged. The Mark III picture is identical with and without this change.
* **Sync integrator**: a sync has to stay below the slice for 16 samples (0.37 µs) before a line starts. The Mark III's square-wave chroma on saturated reds dips about 0.3 V below blanking for part of a carrier cycle, which the bare slicer took for sync. The line start, and every gate timed from it, comes 0.37 µs after the leading edge of sync.

With standard NTSC timing the decoder gives the original's picture, 0.37 µs later against its regenerated sync.

## Build

Quartus 17.0.2 Lite, seed 1. Logic 72%, DSP blocks 93/112, RAM blocks 497/553. Worst setup slack is +0.481 ns and hold slack +0.242 ns, so timing passes.
