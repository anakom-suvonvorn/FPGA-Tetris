-- ============================================================================
-- media_mix.vhd
-- The last stage of the picture: puts the media on top of (or behind) the
-- game that tetris_render drew, then drives the VGA pins.
--
--   tetris_render --colour, see_bg, keep (2 clocks after x, y)--+
--   media_engine  --picture colour, see, zone, sprite (3 clocks)-+--> media_mix --> VGA pins
--                                                                     (4 clocks after x, y)
-- So the game's colour waits one clock here (stage A) to meet the media
-- colours, and stage B chooses:
--   mode bg    (media attacks) the video shows where the game has background
--              or an empty field cell (see_bg), dimmed to 3/4 or 1/2
--   mode full  the picture covers everything except the result /
--              PRESS START bands (keep)
--   mode over  the picture covers the game except where its colour index
--              is 0 (see: the green screen of the jump scares)
--   mode panel a 96 x 88 picture at 2x in the right panel, with a 2 px
--              frame (gold if I won, red if I lost) and a dark gap
--   sprites    Jevil and the faces go on top of everything
--
-- JEVIL floats over the whole screen on a "Lissajous" path (two sine
-- waves with different speeds, one for x and one for y):
--     x = 272 + 230 sin(2 pi t / 6.1 s)        y = 190 + 150 sin(2 pi t / 3.7 s + 0.6)
-- Each sine has a 16-bit phase that grows every frame (65,536 = one turn:
-- +179 a frame = one turn in 366 frames = 6.1 s; +295 = 3.7 s). The sine
-- comes from a table of a quarter wave (128 values, the other 3 quarters
-- are mirror images). A new pose every 4th frame = 15 poses a second.
-- He is 48 x 50 pixels, drawn 2x = 96 x 100 on screen. For every screen
-- pixel inside him we ask media_engine for pose * 2400 + row * 48 + column.
-- ============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

entity media_mix is
  port (
    clk        : in  std_logic;
    frame_tick : in  std_logic;
    x, y       : in  unsigned(9 downto 0);
    -- the game picture (2 clocks after x, y)
    g_r, g_g, g_b : in std_logic_vector(3 downto 0);
    g_hs, g_vs : in  std_logic;
    see_bg     : in  std_logic;
    keep       : in  std_logic;
    -- what to show
    show       : in  std_logic;                  -- media_ctrl.show and the engine's pic_ok
    mode       : in  integer range 0 to 3;
    dim_half   : in  std_logic;
    won        : in  std_logic;
    jevil      : in  std_logic;                  -- Jevil floats (and the sprites are loaded)
    -- media_engine (3 clocks after x, y)
    m_rgb      : in  std_logic_vector(11 downto 0);
    m_see      : in  std_logic;
    m_zone     : in  integer range 0 to 3;
    s_on       : in  std_logic;
    s_rgb      : in  std_logic_vector(11 downto 0);
    -- Jevil's pixel, to media_engine (1 clock after x, y)
    j_en       : out std_logic;
    j_addr     : out unsigned(14 downto 0);
    -- VGA pins
    vga_r      : out std_logic_vector(3 downto 0);
    vga_g      : out std_logic_vector(3 downto 0);
    vga_b      : out std_logic_vector(3 downto 0);
    vga_hs     : out std_logic;
    vga_vs     : out std_logic
  );
end entity;

architecture rtl of media_mix is
  -- a quarter of a sine wave, 0..255: Q(k) = 255 sin(2 pi (k + 0.5) / 512)
  type quarter_t is array (0 to 127) of integer range 0 to 255;
  function make_quarter return quarter_t is
    variable q : quarter_t;
  begin
    for k in 0 to 127 loop
      q(k) := integer(round(255.0 * sin(2.0 * MATH_PI * (real(k) + 0.5) / 512.0)));
    end loop;
    return q;
  end function;
  constant QUARTER : quarter_t := make_quarter;

  -- sin of a 16-bit phase, -255..255 (bits 15..14 = which quarter)
  function sine(ph : unsigned(15 downto 0)) return integer is
    variable k : integer range 0 to 127;
  begin
    k := to_integer(ph(13 downto 7));
    case ph(15 downto 14) is
      when "00"   => return QUARTER(k);
      when "01"   => return QUARTER(127 - k);
      when "10"   => return -QUARTER(k);
      when others => return -QUARTER(127 - k);
    end case;
  end function;

  constant JW : integer := 96;                   -- Jevil on screen (2x)
  constant JH : integer := 100;

  signal ph_x  : unsigned(15 downto 0) := (others => '0');
  signal ph_y  : unsigned(15 downto 0) := to_unsigned(6258, 16);   -- 0.6 rad
  signal jx    : integer range 0 to 639 := 272;
  signal jy    : integer range 0 to 479 := 190;
  signal step  : integer range 0 to 2 := 0;
  signal sv    : integer range -255 to 255 := 0;
  signal ph_s  : unsigned(15 downto 0);          -- the phase that goes into the one sine table
  signal fcnt  : unsigned(1 downto 0) := (others => '0');
  signal pbase : integer range 0 to 19199 := 0;  -- pose * 2400

  -- stage A: the game, one clock later
  signal a_rgb : std_logic_vector(11 downto 0) := (others => '0');
  signal a_hs, a_vs, a_see, a_keep : std_logic := '1';

  function dim(c : std_logic_vector(11 downto 0); half : std_logic) return std_logic_vector is
    variable o : std_logic_vector(11 downto 0);
    variable v : unsigned(3 downto 0);
  begin
    for i in 0 to 2 loop
      v := unsigned(c(4*i + 3 downto 4*i));
      if half = '1' then
        v := shift_right(v, 1);                          -- 1/2
      else
        v := shift_right(v, 1) + shift_right(v, 2);      -- 3/4
      end if;
      o(4*i + 3 downto 4*i) := std_logic_vector(v);
    end loop;
    return o;
  end function;
begin

  -- ---------------------------------------------------------------- Jevil's path
  -- one sine look-up, shared: ph_x in step 0, ph_y in step 1
  ph_s <= ph_x when step = 0 else ph_y;

  process(clk)
    variable p : integer range -65536 to 65535;
  begin
    if rising_edge(clk) then
      case step is
        when 0 =>
          if frame_tick = '1' then
            ph_x <= ph_x + 179;
            ph_y <= ph_y + 295;
            sv   <= sine(ph_s);                         -- sin(ph_x)
            step <= 1;
            fcnt <= fcnt + 1;
            if fcnt = 3 then                             -- every 4th frame: next pose
              if pbase = 7 * 2400 then pbase <= 0; else pbase <= pbase + 2400; end if;
            end if;
          end if;
        when 1 =>
          p    := 230 * sv;
          jx   <= 272 + p / 256;
          sv   <= sine(ph_s);                           -- sin(ph_y)
          step <= 2;
        when others =>
          p    := 150 * sv;
          jy   <= 190 + p / 256;
          step <= 0;
      end case;
    end if;
  end process;

  -- the Jevil pixel under (x, y), 1 clock after x, y
  process(clk)
    variable dx, dy : unsigned(9 downto 0);
    variable a      : unsigned(14 downto 0);
  begin
    if rising_edge(clk) then
      dx := x - to_unsigned(jx, 10);
      dy := y - to_unsigned(jy, 10);
      -- row (dy / 2) * 48 + column (dx / 2), and 48 = 32 + 16
      a := to_unsigned(pbase, 15) + shift_left(resize(dy(6 downto 1), 15), 5)
           + shift_left(resize(dy(6 downto 1), 15), 4) + resize(dx(6 downto 1), 15);
      j_addr <= a;
      if jevil = '1' and x >= jx and x < jx + JW and y >= jy and y < jy + JH then
        j_en <= '1';
      else
        j_en <= '0';
      end if;
    end if;
  end process;

  -- ---------------------------------------------------------------- stages A and B
  process(clk)
    variable c : std_logic_vector(11 downto 0);
  begin
    if rising_edge(clk) then
      -- A: wait one clock for the media colours
      a_rgb  <= g_r & g_g & g_b;
      a_hs   <= g_hs;
      a_vs   <= g_vs;
      a_see  <= see_bg;
      a_keep <= keep;

      -- B: choose
      c := a_rgb;
      if show = '1' then
        case mode is
          when 0 =>                                      -- bg: behind the game
            if a_see = '1' and m_zone = 3 then c := dim(m_rgb, dim_half); end if;
          when 1 =>                                      -- full screen
            if m_zone = 3 and a_keep = '0' then c := m_rgb; end if;
          when 2 =>                                      -- over the game, index 0 see-through
            if m_zone = 3 and m_see = '0' then c := m_rgb; end if;
          when others =>                                 -- panel
            case m_zone is
              when 3      => c := m_rgb;
              when 2      => c := x"111";
              when 1      => if won = '1' then c := x"FD3"; else c := x"F44"; end if;
              when others => null;
            end case;
        end case;
      end if;
      if s_on = '1' then
        c := s_rgb;                                      -- Jevil / a face
      end if;
      vga_r  <= c(11 downto 8);
      vga_g  <= c(7 downto 4);
      vga_b  <= c(3 downto 0);
      vga_hs <= a_hs;
      vga_vs <= a_vs;
    end if;
  end process;

end architecture;
