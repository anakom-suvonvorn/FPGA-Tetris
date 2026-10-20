-- ============================================================================
-- tb_media_engine.vhd  -  media_engine (+ spi_flash, adpcm_dec) against a
-- pretend flash chip holding a tiny "TDM2" file
--
--   media_engine --sclk/cs_n/mosi--> flash_model (contents: game_sim.hex)
--                <--------miso-----
--
-- game_sim.hex / game_sim_expect.txt come from
--     python tools\make_game_media.py --sim
-- (the expect file holds what the Python decoder gets out of the same file)
-- Checks:
--   1. header "TDM2" found, the group numbers, sprites loaded
--   2. item 0, sound only: every decoded sample, in order
--   3. item 0 again from record 2 ("resume"): the samples of record 2
--   4. item 1, picture + sound: its sound, then (after 3 delta pictures)
--      22 screen pixels
--   5. item 2, panel picture: 20 pixels in the panel, the frame and gap
--   6. item 3, 1-bit over picture: see-through exactly where index = 0
--   7. sprites: 20 Jevil pixels (see-through = off) and 20 face pixels
-- frame_tick comes every 20,000 clocks and a sound sample every 100 clocks
-- (not 833,333 / 3,125) so the test runs faster.
--
-- Run with:  tools\sim.bat tb_media_engine      (a few minutes)
-- ============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;

entity tb_media_engine is
end entity;

architecture sim of tb_media_engine is
  constant TICK_EVERY : integer := 20_000;

  signal clk        : std_logic := '0';
  signal done       : boolean := false;
  signal tick       : std_logic := '0';
  signal x, y       : unsigned(9 downto 0);
  signal video_on, hs, vs : std_logic;
  signal sclk, cs_n, mosi, miso : std_logic;

  signal play, stop : std_logic := '0';
  signal item       : integer range 0 to 31 := 0;
  signal from_rec   : unsigned(15 downto 0) := (others => '0');
  signal ready, spr_ok, busy, has_snd, pic_ok, dim_half, see, spr_on : std_logic;
  signal mus_first, mus_n, atk_first, lose_first, lose_n, win_first, win_n : integer range 0 to 31;
  signal mode, zone : integer range 0 to 3;
  signal rec_pos    : unsigned(15 downto 0);
  signal rgb, spr_rgb : std_logic_vector(11 downto 0);
  signal j_en, f_en : std_logic := '0';
  signal j_addr     : unsigned(14 downto 0) := (others => '0');
  signal f_addr     : unsigned(11 downto 0) := (others => '0');
  signal pcm        : signed(15 downto 0);

  signal hs_d, vs_d : std_logic_vector(2 downto 0) := (others => '1');

  -- every new sound value, in order
  type ints_t is array (0 to 1023) of integer;
  shared variable heard : ints_t;
  shared variable n_heard : integer := 0;

  type frame_t is array (0 to 479, 0 to 639) of integer;
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
      hs_d <= hs_d(1 downto 0) & hs;
      vs_d <= vs_d(1 downto 0) & vs;
    end if;
  end process;

  process(pcm)
  begin
    if n_heard < 1024 then
      heard(n_heard) := to_integer(pcm);
      n_heard := n_heard + 1;
    end if;
  end process;

  u_sync : entity work.vga_sync
    port map (clk => clk, pix_en => open, x => x, y => y, video_on => video_on,
              hsync => hs, vsync => vs, frame_tick => open);

  dut : entity work.media_engine
    generic map (SAMPLE_CLKS => 100)
    port map (clk => clk, frame_tick => tick, play => play, item => item, from_rec => from_rec,
              stop => stop, ready => ready, spr_ok => spr_ok,
              mus_first => mus_first, mus_n => mus_n, atk_first => atk_first,
              lose_first => lose_first, lose_n => lose_n, win_first => win_first, win_n => win_n,
              busy => busy, has_snd => has_snd, pic_ok => pic_ok, mode => mode, dim_half => dim_half,
              rec_pos => rec_pos, sclk => sclk, cs_n => cs_n, mosi => mosi, miso => miso,
              x => x, y => y, rgb => rgb, see => see, zone => zone,
              j_en => j_en, j_addr => j_addr, f_en => f_en, f_addr => f_addr,
              spr_on => spr_on, spr_rgb => spr_rgb, pcm => pcm);

  u_flash : entity work.flash_model
    generic map (FILE_NAME => "../game_sim.hex", SIZE => 65536)
    port map (sclk => sclk, cs_n => cs_n, mosi => mosi, miso => miso);

  -- ------------------------------------------------------------ frame capture
  -- one frame into 'frame': rgb + 4096 * see + 8192 * zone, per pixel
  capture : process
    variable n_hs : integer;
    variable row  : integer;
  begin
    loop
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
            if see = '1' then frame(row, px) := frame(row, px) + 4096; end if;
            frame(row, px) := frame(row, px) + 8192 * zone;
            wait until rising_edge(clk);
            wait until rising_edge(clk);
          end loop;
          row := row + 1;
        end if;
        n_hs := n_hs + 1;
      end loop;
      capture_done <= true;
      wait until not capture_req;
      capture_done <= false;
    end loop;
  end process;

  -- ------------------------------------------------------------ the checks
  checker : process
    variable errors : integer := 0;
    file     f      : text;
    variable l      : line;
    type exp_t is array (0 to 1023) of integer;
    variable e0, e1 : exp_t;
    variable n0, n1 : integer;
    variable px, py, er, eg, eb, ei, ep, got : integer;
    variable n_ok   : integer;
    variable k0     : integer;

    procedure pulse(signal s : out std_logic) is
    begin
      wait until rising_edge(clk);
      s <= '1';
      wait until rising_edge(clk);
      s <= '0';
    end procedure;

    -- compare what was heard (from index 'first') with expected samples
    -- e(lo..hi-1), the sound starting from value 'start'. Only CHANGES are
    -- seen, so equal neighbours are skipped on both sides.
    procedure check_sound(name : string; e : exp_t; lo, hi : integer; start : integer; first : integer) is
      variable prev, k, bad : integer;
    begin
      prev := start;
      k    := first;
      bad  := 0;
      for i in lo to hi - 1 loop
        if e(i) /= prev then
          if k >= n_heard or heard(k) /= e(i) then
            if bad = 0 then
              report name & ": sample " & integer'image(i) & " expected " & integer'image(e(i)) &
                     ", heard " & integer'image(heard(k)) severity error;
            end if;
            bad := bad + 1;
          end if;
          prev := e(i);
          k := k + 1;
        end if;
      end loop;
      if bad = 0 then
        report "   " & name & ": samples " & integer'image(lo) & ".." & integer'image(hi - 1) & " all right";
      else
        errors := errors + 1;
      end if;
    end procedure;

    procedure grab is
    begin
      capture_req <= true;
      wait until capture_done;
      capture_req <= false;
    end procedure;
  begin
    file_open(f, "../game_sim_expect.txt", read_mode);
    readline(f, l); read(l, n0);
    for i in 0 to n0 - 1 loop read(l, e0(i)); end loop;
    readline(f, l); read(l, n1);
    for i in 0 to n1 - 1 loop read(l, e1(i)); end loop;

    -- 1. header + sprites
    wait until spr_ok = '1' for 10 ms;
    if ready /= '1' or spr_ok /= '1' then
      report "header or sprites missing" severity error; errors := errors + 1;
    elsif mus_first /= 0 or mus_n /= 1 or atk_first /= 1 or lose_first /= 3 or lose_n /= 1
          or win_first /= 2 or win_n /= 1 then
      report "group numbers wrong" severity error; errors := errors + 1;
    else
      report "1. TDM2 header found, groups right, sprites loaded at " & time'image(now);
    end if;

    -- 2. sound only
    n_heard := 0;
    item <= 0; from_rec <= to_unsigned(0, 16);
    pulse(play);
    wait until busy = '1';
    wait until busy = '0' for 20 ms;
    wait for 1 us;                                 -- the last sample comes 3 clocks later
    report "2. item 0 (sound only) played, busy fell at " & time'image(now);
    check_sound("item 0", e0, 0, n0, 0, 0);

    -- 3. the same from record 2 (128 samples a record): the decoder must
    --    start from the state stored in record 2's header
    wait for 50 us;
    n_heard := 0;
    from_rec <= to_unsigned(2, 16);
    pulse(play);
    wait until busy = '1';
    wait until busy = '0' for 20 ms;
    wait for 1 us;                                 -- the last sample comes 3 clocks later
    -- (heard(0) may be the 0 from the restart, then comes record 2's state)
    k0 := 0;
    if heard(0) = 0 then k0 := 1; end if;
    if heard(k0) /= e0(255) then
      report "resume: decoder state " & integer'image(heard(k0)) & ", expected " &
             integer'image(e0(255)) severity error;
      errors := errors + 1;
    end if;
    report "3. item 0 from record 2:";
    check_sound("item 0 rec 2", e0, 256, n0, e0(255), k0 + 1);

    -- 4. picture + sound
    wait for 50 us;
    n_heard := 0;
    item <= 1; from_rec <= to_unsigned(0, 16);
    pulse(play);
    wait until busy = '1';
    wait until busy = '0' for 30 ms;
    wait for 1 us;
    report "4. item 1 (picture + sound) played, pic_ok = " & std_logic'image(pic_ok);
    k0 := 0;
    if heard(0) = 0 then k0 := 1; end if;          -- the restart's 0
    check_sound("item 1", e1, 0, n1, 0, k0);
    grab;
    readline(f, l);
    n_ok := 0;
    for i in 0 to 21 loop
      read(l, px); read(l, py); read(l, er); read(l, eg); read(l, eb);
      got := frame(py * 4 + 1, px * 4 + 1) mod 4096;
      if got /= er * 256 + eg * 16 + eb then
        report "item 1 pixel (" & integer'image(px) & "," & integer'image(py) & ") = " &
               integer'image(got) & ", expected " & integer'image(er * 256 + eg * 16 + eb) severity error;
        errors := errors + 1;
      else
        n_ok := n_ok + 1;
      end if;
    end loop;
    report "   " & integer'image(n_ok) & " of 22 pixels right after 3 delta pictures";

    -- 5. panel picture
    item <= 2;
    pulse(play);
    wait until pic_ok = '1' for 30 ms;
    if mode /= 3 then report "panel: mode " & integer'image(mode) severity error; errors := errors + 1; end if;
    grab;
    readline(f, l);
    n_ok := 0;
    for i in 0 to 19 loop
      read(l, px); read(l, py); read(l, er); read(l, eg); read(l, eb);
      got := frame(286 + py * 2 + 1, 430 + px * 2 + 1);
      if got mod 4096 /= er * 256 + eg * 16 + eb or got / 8192 /= 3 then
        report "panel pixel (" & integer'image(px) & "," & integer'image(py) & ") = " &
               integer'image(got mod 4096) & ", expected " & integer'image(er * 256 + eg * 16 + eb) severity error;
        errors := errors + 1;
      else
        n_ok := n_ok + 1;
      end if;
    end loop;
    if frame(300, 426) / 8192 /= 1 or frame(300, 428) / 8192 /= 2 or frame(300, 425) / 8192 /= 0
       or frame(463, 500) / 8192 /= 2 or frame(465, 500) / 8192 /= 1 then
      report "panel frame zones wrong" severity error; errors := errors + 1;
    end if;
    report "5. panel: " & integer'image(n_ok) & " of 20 pixels right, frame + gap in place";

    -- 6. 1-bit over picture: see-through where the index is 0
    item <= 3;
    pulse(play);
    wait until pic_ok = '0';
    wait until pic_ok = '1' for 30 ms;
    grab;
    readline(f, l);
    n_ok := 0;
    for i in 0 to 21 loop
      read(l, px); read(l, py); read(l, ei);
      got := (frame(py * 4 + 2, px * 4 + 2) / 4096) mod 2;
      if (ei = 0 and got /= 1) or (ei /= 0 and got /= 0) then
        report "see-through wrong at (" & integer'image(px) & "," & integer'image(py) & ")" severity error;
        errors := errors + 1;
      else
        n_ok := n_ok + 1;
      end if;
    end loop;
    report "6. 1-bit over picture: see-through right at " & integer'image(n_ok) & " of 22 spots";

    -- 7. sprites: address in at one clock edge, colour out 2 edges later
    readline(f, l);
    n_ok := 0;
    for i in 0 to 19 loop
      read(l, ep); read(l, px); read(l, py); read(l, ei); read(l, er); read(l, eg); read(l, eb);
      wait until rising_edge(clk);
      j_en <= '1'; f_en <= '0';
      j_addr <= to_unsigned(ep * 2400 + py * 48 + px, 15);
      wait until rising_edge(clk);
      j_en <= '0';
      wait until rising_edge(clk);
      wait until falling_edge(clk);
      if (ei = 0 and spr_on /= '0') or
         (ei /= 0 and (spr_on /= '1' or to_integer(unsigned(spr_rgb)) /= er * 256 + eg * 16 + eb)) then
        report "Jevil pose " & integer'image(ep) & " (" & integer'image(px) & "," & integer'image(py) &
               ") wrong" severity error;
        errors := errors + 1;
      else
        n_ok := n_ok + 1;
      end if;
    end loop;
    readline(f, l);
    for i in 0 to 19 loop
      read(l, ep); read(l, px); read(l, py); read(l, er); read(l, eg); read(l, eb);
      wait until rising_edge(clk);
      f_en <= '1';
      f_addr <= to_unsigned(ep * 1024 + py * 32 + px, 12);
      wait until rising_edge(clk);
      f_en <= '0';
      wait until rising_edge(clk);
      wait until falling_edge(clk);
      if spr_on /= '1' or to_integer(unsigned(spr_rgb)) /= er * 256 + eg * 16 + eb then
        report "face " & integer'image(ep) & " (" & integer'image(px) & "," & integer'image(py) &
               ") wrong" severity error;
        errors := errors + 1;
      else
        n_ok := n_ok + 1;
      end if;
    end loop;
    report "7. sprites: " & integer'image(n_ok) & " of 40 pixels right";
    file_close(f);

    if errors = 0 then report "TEST PASSED"; else report "TEST FAILED" severity error; end if;
    done <= true;
    wait;
  end process;

end architecture;
