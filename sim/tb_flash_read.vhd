-- ============================================================================
-- tb_flash_read.vhd  -  media_player + spi_flash against a pretend flash chip
--
--   media_player --sclk/cs_n/mosi--> flash_model (contents: media_sim.hex)
--                <--------miso-----
--
-- media_sim.hex / media_sim_expect.txt come from
--     python tools\make_media.py sim\media_sim.bin --sim
-- Checks, in order:
--   1. the JEDEC ID read at power-up is 01 60 17
--   2. the header is found ("TDMF") with 3 items
--   3. item 0 (colour test card, 8 bits per pixel): after it loads, one
--      VGA frame is captured (sim\out\frame.ppm -> frame.png) and 15 pixels
--      are compared with the colours make_media.py expects
--   4. verify: the 4 KB LFSR block reads back with 0 errors
--   5. item 2 (1-bit picture + sound): all 4 records load, the 256 sound
--      samples come out in the right order, and the sound never ran dry
-- frame_tick here comes every 30,000 clocks (not every 833,333) so the
-- picture+sound item plays faster; make_media.py --sim uses matching numbers.
--
-- Run with:  tools\sim.bat tb_flash_read      (takes a few minutes)
-- ============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;

entity tb_flash_read is
end entity;

architecture sim of tb_flash_read is
  constant TICK_EVERY : integer := 30_000;

  signal clk        : std_logic := '0';
  signal done       : boolean := false;
  signal tick       : std_logic := '0';
  signal x, y       : unsigned(9 downto 0);
  signal video_on, hs, vs : std_logic;
  signal sclk, cs_n, mosi, miso : std_logic;

  signal play, stop, verify : std_logic := '0';
  signal item       : integer range 0 to 15 := 0;
  signal rgb        : std_logic_vector(11 downto 0);
  signal sample     : unsigned(7 downto 0);
  signal flash_id   : std_logic_vector(23 downto 0);
  signal head       : std_logic_vector(31 downto 0);
  signal found, playing : std_logic;
  signal n_items    : integer range 0 to 255;
  signal frame_bcd, load_bcd, under_bcd, err_bcd, ms_bcd : std_logic_vector(15 downto 0);
  signal ver_state  : integer range 0 to 2;

  -- the VGA signals delayed to line up with rgb (3 clocks later than x, y)
  signal hs_d, vs_d, von_d : std_logic_vector(2 downto 0) := (others => '1');

  type frame_t is array (0 to 479, 0 to 639) of integer range 0 to 4095;
  shared variable frame : frame_t;
  signal capture_req, capture_done : boolean := false;
begin

  clk <= not clk after 10 ns when not done else clk;

  process(clk)
    variable n : integer := 0;
  begin
    if rising_edge(clk) then
      tick <= '0';
      if n = TICK_EVERY - 1 then n := 0; tick <= '1'; else n := n + 1; end if;
      hs_d  <= hs_d(1 downto 0) & hs;
      vs_d  <= vs_d(1 downto 0) & vs;
      von_d <= von_d(1 downto 0) & video_on;
    end if;
  end process;

  u_sync : entity work.vga_sync
    port map (clk => clk, pix_en => open, x => x, y => y, video_on => video_on,
              hsync => hs, vsync => vs, frame_tick => open);

  dut : entity work.media_player
    port map (clk => clk, frame_tick => tick, half_period => 1,
              play => play, item => item, stop => stop, verify => verify,
              sclk => sclk, cs_n => cs_n, mosi => mosi, miso => miso,
              x => x, y => y, rgb => rgb, sample => sample,
              flash_id => flash_id, head => head, found => found, n_items => n_items,
              name => open, is_playing => playing, has_video => open,
              frame_bcd => frame_bcd, load_bcd => load_bcd, under_bcd => under_bcd,
              ver_state => ver_state, ver_err_bcd => err_bcd, ver_ms_bcd => ms_bcd);

  u_flash : entity work.flash_model
    generic map (FILE_NAME => "../media_sim.hex", SIZE => 49152)
    port map (sclk => sclk, cs_n => cs_n, mosi => mosi, miso => miso);

  -- ------------------------------------------------------------ frame capture
  -- like tb_vga_frame, but with the delayed sync signals
  capture : process
    file     f    : text;
    variable l    : line;
    variable n_hs : integer;
    variable row  : integer;
    variable v    : integer;
  begin
    wait until capture_req;
    wait until falling_edge(vs_d(2));
    n_hs := 0;
    row  := 0;
    while row < 480 loop
      wait until falling_edge(hs_d(2));
      if n_hs >= 34 then
        for k in 1 to 288 loop wait until rising_edge(clk); end loop;
        for px in 0 to 639 loop
          wait until falling_edge(clk);
          frame(row, px) := to_integer(unsigned(rgb));
          wait until rising_edge(clk);
          wait until rising_edge(clk);
        end loop;
        row := row + 1;
      end if;
      n_hs := n_hs + 1;
    end loop;
    file_open(f, "frame.ppm", write_mode);
    write(l, string'("P3")); writeline(f, l);
    write(l, string'("640 480")); writeline(f, l);
    write(l, string'("15")); writeline(f, l);
    for r in 0 to 479 loop
      for c in 0 to 639 loop
        v := frame(r, c);
        write(l, v / 256); write(l, string'(" "));
        write(l, (v / 16) mod 16); write(l, string'(" "));
        write(l, v mod 16); write(l, string'("  "));
      end loop;
      writeline(f, l);
    end loop;
    file_close(f);
    report "FRAME CAPTURED: frame.ppm (640x480)";
    capture_done <= true;
    wait;
  end process;

  -- ------------------------------------------------------------ the checks
  checker : process
    variable errors : integer := 0;
    file     f      : text;
    variable l      : line;
    variable px, py, er, eg, eb, got : integer;
    variable n_ok   : integer := 0;
    variable last   : integer;
    variable n_smp  : integer;

    procedure pulse(signal s : out std_logic) is
    begin
      wait until rising_edge(clk);
      s <= '1';
      wait until rising_edge(clk);
      s <= '0';
    end procedure;
  begin
    -- 1. ID
    wait for 20 us;
    if flash_id /= x"016017" then
      report "flash ID wrong" severity error; errors := errors + 1;
    else
      report "1. flash ID = 01 60 17 (S25FL064L)";
    end if;
    -- 2. header
    if found /= '1' or n_items /= 3 then
      report "header not found / wrong item count " & integer'image(n_items) severity error;
      errors := errors + 1;
    else
      report "2. header TDMF found, " & integer'image(n_items) & " items";
    end if;

    -- 3. the colour test card
    item <= 0;
    pulse(play);
    wait until frame_bcd = x"0001" for 20 ms;
    report "3. item 0 loaded in " & integer'image(to_integer(unsigned(load_bcd(15 downto 12)))) &
           integer'image(to_integer(unsigned(load_bcd(11 downto 8)))) &
           integer'image(to_integer(unsigned(load_bcd(7 downto 4)))) & "." &
           integer'image(to_integer(unsigned(load_bcd(3 downto 0)))) & " ms";
    capture_req <= true;
    wait until capture_done;
    file_open(f, "../media_sim_expect.txt", read_mode);
    while not endfile(f) loop
      readline(f, l);
      read(l, px); read(l, py); read(l, er); read(l, eg); read(l, eb);
      got := frame(py, px);
      if got /= er * 256 + eg * 16 + eb then
        report "pixel (" & integer'image(px) & "," & integer'image(py) & ") = " &
               integer'image(got) & ", expected " & integer'image(er * 256 + eg * 16 + eb) severity error;
        errors := errors + 1;
      else
        n_ok := n_ok + 1;
      end if;
    end loop;
    file_close(f);
    report "   " & integer'image(n_ok) & " test pixels have the right colour";

    -- 4. verify
    pulse(verify);
    wait until ver_state = 2 for 20 ms;
    if ver_state /= 2 or err_bcd /= x"0000" then
      report "verify: errors (BCD) " & integer'image(to_integer(unsigned(err_bcd))) severity error;
      errors := errors + 1;
    else
      report "4. verify: 4 KB, 0 errors";
    end if;

    -- 5. picture + sound
    item <= 2;
    pulse(play);
    wait until playing = '1';
    n_smp := 0;
    last  := to_integer(sample);
    while n_smp < 256 loop
      wait on sample for 2 ms;
      if to_integer(sample) = last then
        report "sound: no new sample for 2 ms (after " & integer'image(n_smp) & ")" severity error;
        errors := errors + 1;
        exit;
      end if;
      last := to_integer(sample);
      if last /= (n_smp * 7) mod 256 then
        report "sound sample " & integer'image(n_smp) & " = " & integer'image(last) &
               ", expected " & integer'image((n_smp * 7) mod 256) severity error;
        errors := errors + 1;
        exit;
      end if;
      n_smp := n_smp + 1;
    end loop;
    if frame_bcd /= x"0004" or under_bcd /= x"0000" then
      report "picture+sound: frames " & integer'image(to_integer(unsigned(frame_bcd))) &
             ", underruns " & integer'image(to_integer(unsigned(under_bcd))) severity error;
      errors := errors + 1;
    else
      report "5. picture+sound: 4 frames, " & integer'image(n_smp) & " samples in order, no underruns";
    end if;

    if errors = 0 then report "TEST PASSED"; else report "TEST FAILED" severity error; end if;
    done <= true;
    wait;
  end process;

end architecture;
