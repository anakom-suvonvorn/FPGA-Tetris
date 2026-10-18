-- ============================================================================
-- top_flash_read.vhd  -  Test 06: can we read pictures, animations and sound
--                        out of the board's SPI flash chip?
--
-- Before loading this test, put the media file into the flash once:
--     python tools\make_media.py media\media.bin --demo
--     tools\flash_media.bat media\media.bin
-- (see tests\06_flash_read\README.md). Then load this design as usual.
--
-- What you should see: the flash chip's ID, "MEDIA OK", and the first item
-- (a colour test card) filling the screen, with some text on top.
--
-- Buttons (the cross):
--   SW14 left / SW20 right   previous / next item (starts playing it)
--   SW18 centre              play the item again / stop it
--   SW16 top                 VERIFY: read the 256 KB test block, count wrong bytes
--   SW23 bottom              hide / show the text
-- Slide switches:
--   SW2, SW4   SPI clock: off/off 25 MHz, SW2 on 12.5 MHz, SW4 on 6.25 MHz,
--              both on 3.125 MHz
--   SW5        sound on (audio jack; plug in headphones or speakers)
-- 7-segment: the last two bytes of the flash ID ("6017" = the right chip).
--   Right dot = media file found, next dot = playing.
-- ============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.common_pkg.all;
use work.text_pkg.all;
library unisim;
use unisim.vcomponents.all;

entity top_flash_read is
  port (
    clk       : in  std_logic;                       -- H11
    btn_left  : in  std_logic;                       -- J14 SW14
    btn_up    : in  std_logic;                       -- J13 SW16
    btn_mid   : in  std_logic;                       -- J12 SW18
    btn_right : in  std_logic;                       -- J11 SW20
    btn_down  : in  std_logic;                       -- L13 SW23
    sw_spd0   : in  std_logic;                       -- K11 SW2
    sw_spd1   : in  std_logic;                       -- M11 SW4
    sw_sound  : in  std_logic;                       -- N14 SW5
    -- the flash chip (its clock goes through STARTUPE2, see below)
    flash_cs_n  : out std_logic;                     -- C11 FCS_B
    flash_mosi  : out std_logic;                     -- B11 D00
    flash_miso  : in  std_logic;                     -- B12 D01
    flash_wp_n  : out std_logic;                     -- D10 D02, keep high
    flash_hold_n: out std_logic;                     -- C10 D03, keep high
    audio_l   : out std_logic;                       -- A13
    audio_r   : out std_logic;                       -- B13
    vga_r     : out std_logic_vector(3 downto 0);
    vga_g     : out std_logic_vector(3 downto 0);
    vga_b     : out std_logic_vector(3 downto 0);
    vga_hs    : out std_logic;
    vga_vs    : out std_logic;
    seg_n     : out std_logic_vector(7 downto 0);
    dig       : out std_logic_vector(3 downto 0)
  );
end entity;

architecture rtl of top_flash_read is
  constant LEN : integer := 27;                      -- characters per text line
  subtype line_t is std_logic_vector(6 * LEN - 1 downto 0);
  type lines_t is array (0 to 9) of line_t;

  signal x, y       : unsigned(9 downto 0);
  signal video_on, hs, vs, frame_tick : std_logic;
  signal hs_d, vs_d, von_d : std_logic_vector(2 downto 0) := (others => '0');

  signal p_left, p_up, p_mid, p_right, p_down : std_logic;
  signal sw_s1, sw_s : std_logic_vector(2 downto 0) := (others => '0');
  signal half       : integer range 1 to 8;

  signal sclk, cs_n, mosi : std_logic;
  signal play, stop, verify : std_logic := '0';
  signal item       : integer range 0 to 15 := 0;
  signal rgb        : std_logic_vector(11 downto 0);
  signal sample     : unsigned(7 downto 0);
  signal flash_id   : std_logic_vector(23 downto 0);
  signal head       : std_logic_vector(31 downto 0);
  signal found, playing, has_video : std_logic;
  signal n_items    : integer range 0 to 255;
  signal name       : std_logic_vector(95 downto 0);
  signal frame_bcd, load_bcd, under_bcd, err_bcd, ms_bcd : std_logic_vector(15 downto 0);
  signal ver_state  : integer range 0 to 2;
  signal found_d    : std_logic := '0';
  signal show_text  : std_logic := '1';

  signal txt        : lines_t;
  signal t_pix      : std_logic_vector(9 downto 0);
  signal inb       : std_logic;
  signal bnd_d     : std_logic_vector(2 downto 0) := (others => '0');
  type tpix_dly_t is array (0 to 1) of std_logic_vector(9 downto 0);
  signal td        : tpix_dly_t := (others => (others => '0'));
  signal acc        : unsigned(8 downto 0) := (others => '0');
  signal g3, g2, g1, g0 : glyph_t;

  -- put character code c at position i of a line
  function put(l : line_t; i : integer; c : integer) return line_t is
    variable r : line_t := l;
  begin
    r(6 * i + 5 downto 6 * i) := std_logic_vector(to_unsigned(c, 6));
    return r;
  end function;

  -- put 2 hex digits (one byte) at position i; codes 0..15 = '0'..'F'
  function put_hex(l : line_t; i : integer; v : std_logic_vector(7 downto 0)) return line_t is
  begin
    return put(put(l, i, to_integer(unsigned(v(7 downto 4)))), i + 1, to_integer(unsigned(v(3 downto 0))));
  end function;

  -- put 4 BCD digits at position i
  function put_bcd(l : line_t; i : integer; v : std_logic_vector(15 downto 0)) return line_t is
  begin
    return put_hex(put_hex(l, i, v(15 downto 8)), i + 2, v(7 downto 0));
  end function;
begin

  -- ------------------------------------------------------------ video timing
  u_sync : entity work.vga_sync
    port map (clk => clk, pix_en => open, x => x, y => y, video_on => video_on,
              hsync => hs, vsync => vs, frame_tick => frame_tick);

  -- ------------------------------------------------------------ inputs
  u_b0 : entity work.debounce generic map (STABLE_CYCLES => 250_000)
    port map (clk => clk, btn_in => btn_left,  level => open, pressed => p_left);
  u_b1 : entity work.debounce generic map (STABLE_CYCLES => 250_000)
    port map (clk => clk, btn_in => btn_up,    level => open, pressed => p_up);
  u_b2 : entity work.debounce generic map (STABLE_CYCLES => 250_000)
    port map (clk => clk, btn_in => btn_mid,   level => open, pressed => p_mid);
  u_b3 : entity work.debounce generic map (STABLE_CYCLES => 250_000)
    port map (clk => clk, btn_in => btn_right, level => open, pressed => p_right);
  u_b4 : entity work.debounce generic map (STABLE_CYCLES => 250_000)
    port map (clk => clk, btn_in => btn_down,  level => open, pressed => p_down);

  process(clk)
  begin
    if rising_edge(clk) then
      sw_s1 <= sw_sound & sw_spd1 & sw_spd0;
      sw_s  <= sw_s1;
    end if;
  end process;

  with sw_s(1 downto 0) select half <=
    1 when "00",        -- 25 MHz
    2 when "01",        -- 12.5 MHz
    4 when "10",        -- 6.25 MHz
    8 when others;      -- 3.125 MHz

  -- ------------------------------------------------------------ what the buttons do
  process(clk)
  begin
    if rising_edge(clk) then
      play   <= '0';
      stop   <= '0';
      verify <= '0';
      found_d <= found;
      if found = '1' and found_d = '0' then
        play <= '1';                                 -- media found: start item 0
      end if;
      if p_right = '1' and n_items > 0 then
        if item >= n_items - 1 or item = 15 then item <= 0; else item <= item + 1; end if;
        play <= '1';
      end if;
      if p_left = '1' and n_items > 0 then
        if item = 0 then
          if n_items > 16 then item <= 15; else item <= n_items - 1; end if;
        else
          item <= item - 1;
        end if;
        play <= '1';
      end if;
      if p_mid = '1' then
        if playing = '1' then stop <= '1'; else play <= '1'; end if;
      end if;
      if p_up = '1' then verify <= '1'; end if;
      if p_down = '1' then show_text <= not show_text; end if;
    end if;
  end process;

  -- ------------------------------------------------------------ the player
  u_player : entity work.media_player
    port map (clk => clk, frame_tick => frame_tick, half_period => half,
              play => play, item => item, stop => stop, verify => verify,
              sclk => sclk, cs_n => cs_n, mosi => mosi, miso => flash_miso,
              x => x, y => y, rgb => rgb, sample => sample,
              flash_id => flash_id, head => head, found => found, n_items => n_items,
              name => name, is_playing => playing, has_video => has_video,
              frame_bcd => frame_bcd, load_bcd => load_bcd, under_bcd => under_bcd,
              ver_state => ver_state, ver_err_bcd => err_bcd, ver_ms_bcd => ms_bcd);

  flash_cs_n   <= cs_n;
  flash_mosi   <= mosi;
  flash_wp_n   <= '1';
  flash_hold_n <= '1';

  -- The flash clock pin is the FPGA's own configuration clock pin (CCLK).
  -- After configuration, user logic can only reach it through STARTUPE2:
  -- whatever goes into USRCCLKO comes out on CCLK.
  u_startup : STARTUPE2
    generic map (PROG_USR => "FALSE", SIM_CCLK_FREQ => 0.0)
    port map (
      CFGCLK    => open, CFGMCLK => open, EOS => open, PREQ => open,
      CLK       => '0',
      GSR       => '0',
      GTS       => '0',
      KEYCLEARB => '1',
      PACK      => '0',
      USRCCLKO  => sclk,           -- our SPI clock -> CCLK pin
      USRCCLKTS => '0',            -- '0' = drive the pin
      USRDONEO  => '1',            -- keep the DONE LED on
      USRDONETS => '0'
    );

  -- ------------------------------------------------------------ text
  process(flash_id, found, head, n_items, item, name, frame_bcd, load_bcd, under_bcd,
          half, ver_state, err_bcd, ms_bcd, playing, has_video)
    variable t : lines_t;
  begin
    t(0) := to_codes("TEST 06  FLASH READ        ");
    -- line 1: the chip
    if flash_id = x"016017" then
      t(1) := to_codes("ID 000000  S25FL064L 8 MB  ");
    else
      t(1) := to_codes("ID 000000  UNKNOWN CHIP?   ");
    end if;
    t(1) := put_hex(put_hex(put_hex(t(1), 3, flash_id(23 downto 16)), 5, flash_id(15 downto 8)), 7, flash_id(7 downto 0));
    -- line 2: the media file
    if found = '1' then
      t(2) := to_codes("MEDIA FILE OK   ITEMS 00   ");
      t(2) := put_hex(t(2), 22, std_logic_vector(to_unsigned(n_items, 8)));
    else
      t(2) := to_codes("NO MEDIA  HEAD 00000000    ");
      t(2) := put_hex(put_hex(put_hex(put_hex(t(2), 15, head(31 downto 24)), 17, head(23 downto 16)),
                      19, head(15 downto 8)), 21, head(7 downto 0));
    end if;
    -- line 3: the item
    t(3) := to_codes("ITEM 0                     ");
    t(3) := put(t(3), 5, item);
    for i in 0 to 15 loop
      t(3) := put(t(3), 7 + i, to_integer(unsigned(name(6 * i + 5 downto 6 * i))));
    end loop;
    -- line 4: frames and load time
    t(4) := to_codes("FRAMES 0000  LOAD 000.0 MS ");
    t(4) := put_bcd(t(4), 7, frame_bcd);
    t(4) := put(put(put(put(t(4), 18, to_integer(unsigned(load_bcd(15 downto 12)))),
                        19, to_integer(unsigned(load_bcd(11 downto 8)))),
                    20, to_integer(unsigned(load_bcd(7 downto 4)))),
                22, to_integer(unsigned(load_bcd(3 downto 0))));
    -- line 5: sound
    t(5) := to_codes("SOUND RAN DRY 0000 TIMES   ");
    t(5) := put_bcd(t(5), 14, under_bcd);
    -- line 6: SPI speed
    case half is
      when 1      => t(6) := to_codes("SPI 25.0 MHZ = 3.1 MB A SEC");
      when 2      => t(6) := to_codes("SPI 12.5 MHZ = 1.6 MB A SEC");
      when 4      => t(6) := to_codes("SPI 6.25 MHZ = 0.8 MB A SEC");
      when others => t(6) := to_codes("SPI 3.13 MHZ = 0.4 MB A SEC");
    end case;
    -- line 7: verify
    case ver_state is
      when 0      => t(7) := to_codes("VERIFY: PRESS TOP BUTTON   ");
      when 1      => t(7) := to_codes("VERIFY: READING...         ");
      when others =>
        t(7) := to_codes("VERIFY 0000 BAD  0000 MS   ");
        t(7) := put_bcd(put_bcd(t(7), 7, err_bcd), 17, ms_bcd);
    end case;
    t(8) := to_codes("L R ITEM  MID PLAY  TOP VER");
    t(9) := to_codes("BOTTOM TEXT  SW2 SW4 SPEED ");
    txt <= t;
  end process;

  g_text : for i in 0 to 9 generate
    u_t : entity work.text_layer
      generic map (X0 => 12, Y0 => 10 + 20 * i, LEN => LEN, SHIFT => 1)
      port map (clk => clk, x => x, y => y, chars => txt(i), pix => t_pix(i));
  end generate;

  -- ------------------------------------------------------------ picture out
  -- media_player's rgb is 3 clocks behind x, y; text_layer's pix 1 clock.
  -- Everything else is delayed to line up with rgb: the sync signals and
  -- the "behind the text" band by 3 clocks, the text pixels by 2 more.
  inb <= '1' when x >= 6 and x < 336 and y >= 4 and y < 210 else '0';

  process(clk)
  begin
    if rising_edge(clk) then
      hs_d  <= hs_d(1 downto 0) & hs;
      vs_d  <= vs_d(1 downto 0) & vs;
      von_d <= von_d(1 downto 0) & video_on;
      bnd_d <= bnd_d(1 downto 0) & inb;
      td(0) <= t_pix;
      td(1) <= td(0);
    end if;
  end process;

  process(clk)
    variable c : std_logic_vector(11 downto 0);
  begin
    if rising_edge(clk) then
      c := rgb;
      if has_video = '0' then c := x"113"; end if;          -- sound only: dark blue
      if show_text = '1' and bnd_d(2) = '1' then
        c := '0' & c(11 downto 9) & '0' & c(7 downto 5) & '0' & c(3 downto 1);  -- half as bright
        if td(1) /= "0000000000" then c := x"FF8"; end if;
      end if;
      if von_d(2) = '0' then c := x"000"; end if;
      vga_r  <= c(11 downto 8);
      vga_g  <= c(7 downto 4);
      vga_b  <= c(3 downto 0);
      vga_hs <= hs_d(2);
      vga_vs <= vs_d(2);
    end if;
  end process;

  -- ------------------------------------------------------------ sound out
  -- first-order sigma-delta: add the sample to an 8-bit bucket every clock;
  -- the carry out is the pin. Its average = sample / 256.
  process(clk)
  begin
    if rising_edge(clk) then
      acc <= ('0' & acc(7 downto 0)) + ('0' & sample);
    end if;
  end process;
  audio_l <= acc(8) when sw_s(2) = '1' else '0';
  audio_r <= acc(8) when sw_s(2) = '1' else '0';

  -- ------------------------------------------------------------ 7-segment
  g3 <= hex7(flash_id(15 downto 12));
  g2 <= hex7(flash_id(11 downto 8));
  g1 <= hex7(flash_id(7 downto 4));
  g0 <= hex7(flash_id(3 downto 0));
  u_seg : entity work.seg7_scan
    port map (clk => clk, d3 => g3, d2 => g2, d1 => g1, d0 => g0,
              dp => "00" & playing & found, seg_n => seg_n, dig => dig);

end architecture;
