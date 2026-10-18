-- ============================================================================
-- tb_vga_frame.vhd  -  "see the screen without a monitor"
--
-- Simulates top_vga_bars and records one full 640x480 frame of whatever it
-- outputs into an image file (sim\out\frame.ppm, then converted to frame.png).
-- It also checks the VGA timing numbers:
--   * one line   = 800 pixels = 1600 clocks  (hsync to hsync)
--   * hsync low  = 96 pixels  = 192 clocks
--   * one frame  = 525 lines  = 840,000 clocks (vsync to vsync)
--   * vsync low  = 2 lines    = 3,200 clocks
--
-- How it finds pixel (0,0) from only the output wires, like a monitor does:
--   hsync falls 656 pixels into each line, so the first visible pixel of the
--   NEXT line comes 144 pixels (288 clocks) after each hsync fall.
--   vsync falls at line 490; counting hsync falls from there, fall number 34
--   is in line 524, so the pixels after it belong to line 0.
--
-- PATTERN generic (0..3) = the slide-switch setting: 0 bars, 1 ramps,
-- 2 Tetris grid, 3 bouncing square.   e.g.  tools\sim.bat tb_vga_frame 0
-- Run with:  tools\sim.bat tb_vga_frame
-- ============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;

entity tb_vga_frame is
  generic (PATTERN : integer range 0 to 3 := 2);
end entity;

architecture sim of tb_vga_frame is
  signal clk    : std_logic := '0';
  signal r, g, b: std_logic_vector(3 downto 0);
  signal hs, vs : std_logic;
  signal done   : boolean := false;
  signal sw     : std_logic_vector(1 downto 0) := std_logic_vector(to_unsigned(PATTERN, 2));
  signal t_done : boolean := false;              -- timing check finished

  function hex_digit(v : std_logic_vector(3 downto 0)) return integer is
  begin
    return to_integer(unsigned(v));
  end function;
begin

  clk <= not clk after 10 ns when not done else clk;

  dut : entity work.top_vga_bars
    port map (clk => clk, sw => sw, vga_r => r, vga_g => g, vga_b => b,
              vga_hs => hs, vga_vs => vs);

  -- ---------------------------------------------------------- timing checks
  timing : process
    variable t_fall, t_rise, t_prev : time := 0 ns;
    variable errors : integer := 0;
  begin
    -- skip the first, partial frame
    wait until falling_edge(vs);
    -- hsync: period and pulse width
    wait until falling_edge(hs);
    t_fall := now;
    wait until rising_edge(hs);
    t_rise := now;
    if t_rise - t_fall /= 192 * 20 ns then
      report "hsync low time wrong: " & time'image(t_rise - t_fall) severity error;
      errors := errors + 1;
    end if;
    wait until falling_edge(hs);
    if now - t_fall /= 1600 * 20 ns then
      report "line length wrong: " & time'image(now - t_fall) severity error;
      errors := errors + 1;
    end if;
    -- vsync: period and pulse width
    wait until falling_edge(vs);
    t_fall := now;
    wait until rising_edge(vs);
    if now - t_fall /= 3200 * 20 ns then
      report "vsync low time wrong: " & time'image(now - t_fall) severity error;
      errors := errors + 1;
    end if;
    wait until falling_edge(vs);
    if now - t_fall /= 840000 * 20 ns then
      report "frame length wrong: " & time'image(now - t_fall) severity error;
      errors := errors + 1;
    end if;
    if errors = 0 then
      report "TIMING PASSED: line 800 px, hsync 96 px, frame 525 lines, vsync 2 lines";
    else
      report "TIMING FAILED" severity error;
    end if;
    t_done <= true;
    wait;
  end process;

  -- ---------------------------------------------------------- frame capture
  capture : process
    file     f      : text;
    variable l      : line;
    variable n_hs   : integer;
    variable row    : integer;
    type row_t is array (0 to 639) of integer;
    variable rr, gg, bb : row_t;
  begin
    file_open(f, "frame.ppm", write_mode);
    write(l, string'("P3")); writeline(f, l);
    write(l, string'("640 480")); writeline(f, l);
    write(l, string'("15")); writeline(f, l);       -- max value per colour = 15

    wait until falling_edge(vs);                      -- line 490 has started
    n_hs := 0;
    row  := 0;
    while row < 480 loop
      wait until falling_edge(hs);
      if n_hs >= 34 then                              -- pixels after this belong to 'row'
        -- skip 288 clocks to the first visible pixel, then sample the
        -- middle of each 2-clock pixel
        for k in 1 to 288 loop
          wait until rising_edge(clk);
        end loop;
        for px in 0 to 639 loop
          wait until falling_edge(clk);
          rr(px) := hex_digit(r);
          gg(px) := hex_digit(g);
          bb(px) := hex_digit(b);
          wait until rising_edge(clk);                -- each pixel lasts
          wait until rising_edge(clk);                -- 2 clocks (25 MHz)
        end loop;
        for px in 0 to 639 loop
          write(l, rr(px)); write(l, string'(" "));
          write(l, gg(px)); write(l, string'(" "));
          write(l, bb(px)); write(l, string'("  "));
        end loop;
        writeline(f, l);
        row := row + 1;
      end if;
      n_hs := n_hs + 1;
    end loop;
    file_close(f);
    report "FRAME CAPTURED: frame.ppm (640x480)";
    if not t_done then
      wait until t_done;                              -- let the timing check finish
    end if;
    done <= true;
    wait;
  end process;

end architecture;
