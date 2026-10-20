-- ============================================================================
-- text_multi.vhd
-- Draws SEVERAL lines of text, like several text_layer blocks, but with ONE
-- font ROM for all of them.
--
-- WHY: every text_layer has its own copy of the font (64 characters x 35
-- bits = about 45 LUTs of ROM + bit picking). The game had 12 of them. A
-- pixel can only be on one line of text at a time, so one ROM is enough:
-- first find which line (x, y) is on and which character of it, then look
-- that ONE character up.
--
-- Generics, one entry per line k (0 .. N-1), meaning as in text_layer:
--   X0S(k), Y0S(k)  top-left pixel     LENS(k)  number of characters
--   SHIFTS(k)       size: every font pixel is 2^SHIFT x 2^SHIFT
-- 'chars' = all the lines' character codes one after the other: line 0's
-- LENS(0) codes first (lowest bits), then line 1's, ...
-- 'en(k)' = line k may be drawn. Where two lines overlap (the WIN! and the
-- GAME OVER text), only the enabled one counts.
-- 'pix(k)' = the pixel is part of a letter of line k. Registered, one
-- clock after x, y: the same timing as text_layer.
-- ============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.text_pkg.all;

entity text_multi is
  generic (
    N      : integer;
    X0S    : int_list;
    Y0S    : int_list;
    LENS   : int_list;
    SHIFTS : int_list
  );
  port (
    clk   : in  std_logic;
    x, y  : in  unsigned(9 downto 0);
    chars : in  std_logic_vector;
    en    : in  std_logic_vector(N - 1 downto 0);
    pix   : out std_logic_vector(N - 1 downto 0)
  );
end entity;

architecture rtl of text_multi is
  -- where line k's codes start in 'chars' (in bits)
  function offsets return int_list is
    variable o : int_list(0 to N - 1);
    variable a : integer := 0;
  begin
    for k in 0 to N - 1 loop
      o(k) := a;
      a := a + 6 * LENS(k);
    end loop;
    return o;
  end function;
  constant OFF : int_list(0 to N - 1) := offsets;

  signal pix_r : std_logic_vector(N - 1 downto 0) := (others => '0');
begin

  process(clk)
    variable xi, yi : integer range 0 to 1023;
    variable dx, dy : integer range 0 to 1023;
    variable ci     : integer range 0 to 255;   -- which character
    variable cc     : integer range 0 to 7;     -- column inside it
    variable s_dy   : integer range 0 to 7;     -- the row and column of the line we're on
    variable s_cc   : integer range 0 to 7;
    variable code   : char_t;
    variable line   : integer range 0 to N;     -- N = no line here
    variable gl     : font_glyph_t;
    variable sz     : integer;
  begin
    if rising_edge(clk) then
      xi := to_integer(x);
      yi := to_integer(y);
      line := N;
      code := (others => '0');
      s_dy := 0;
      s_cc := 5;
      -- 1. which line, which character, which font pixel in it
      for k in 0 to N - 1 loop
        sz := 2 ** SHIFTS(k);
        if en(k) = '1' and xi >= X0S(k) and xi < X0S(k) + LENS(k) * 6 * sz
           and yi >= Y0S(k) and yi < Y0S(k) + 7 * sz then
          dx := (xi - X0S(k)) / sz;              -- position in font pixels
          dy := (yi - Y0S(k)) / sz;
          ci := dx / 6;                          -- character number
          cc := dx mod 6;                        -- column in the 6-wide cell
          for i in 0 to LENS(k) - 1 loop         -- that character's code
            if i = ci then
              code := chars(chars'low + OFF(k) + 6*i + 5 downto chars'low + OFF(k) + 6*i);
            end if;
          end loop;
          line := k;
          s_dy := dy;
          s_cc := cc;
        end if;
      end loop;
      -- 2. the one font look-up
      gl := glyph_of(code);
      pix_r <= (others => '0');
      if line < N and s_cc < 5 then
        pix_r(line) <= gl(5 * s_dy + s_cc);
      end if;
    end if;
  end process;

  pix <= pix_r;

end architecture;
