-- Runs the core's real SMS raster generator (rtl/video.vhd) for three NTSC
-- frames and writes HSync, VSync, HBlank, VBlank per clk_sys to video_pins.txt.
library ieee;
use ieee.std_logic_1164.all;
use std.textio.all;

entity tb_video is end;

architecture sim of tb_video is
	signal clk, ce_pix : std_logic := '0';
	signal hs, vs, hb, vb : std_logic;
	signal x, y : std_logic_vector(8 downto 0);
	signal vcc : std_logic_vector(7 downto 0);
	signal vst : std_logic_vector(21 downto 0);
begin
	dut : entity work.video port map (
		clk => clk, ce_pix => ce_pix, pal => '0', border => '0', ggres => '0',
		mask_column => '0', cut_mask => '0',
		smode_M1 => '0', smode_M2 => '1', smode_M3 => '0', smode_M4 => '1',
		video_state_out => vst, x => x, y => y, vcounter_cpu => vcc,
		hsync => hs, vsync => vs, hblank => hb, vblank => vb);

	process
		file f : text open write_mode is "video_pins.txt";
		variable l : line;
		variable clkd : integer := 0;
	begin
		for n in 0 to 3 * 262 * 3420 + 3420 loop
			-- ce_pix every 10 clk_sys, as SMS.sv (negedge-generated, so it is
			-- stable at the rising edge)
			if clkd = 9 or clkd = 19 or clkd = 29 then ce_pix <= '1'; else ce_pix <= '0'; end if;
			clkd := (clkd + 1) mod 30;
			clk <= '0'; wait for 9 ns;
			clk <= '1'; wait for 1 ns;
			write(l, std_logic'image(hs)(2)); write(l, std_logic'image(vs)(2));
			write(l, std_logic'image(hb)(2)); write(l, std_logic'image(vb)(2));
			writeline(f, l);
			wait for 8 ns;
		end loop;
		wait;
	end process;
end;
