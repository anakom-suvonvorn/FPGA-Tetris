-- ============================================================================
-- text_pkg.vhd
-- A tiny 5x7 pixel font, and helpers to turn VHDL strings into character
-- codes for text_layer.vhd.
--
-- CHARACTER CODES (6 bits each)
--   0..9   = '0'..'9'      10..35 = 'A'..'Z'
--   36 = ' '   37 = '-'   38 = '!'   39 = ':'   40 = '.'   41 = '?'
--   anything else draws as a blank.
--   Digits are their own value, so a BCD digit d is simply character code d.
--
-- GLYPHS
--   Each character is a 5 wide x 7 tall picture = 35 bits:
--       bit (5*r + c) = row r (0 = top), column c (0 = left)
--   Written as text pictures (like the piece shapes in tetris_pkg), 'X' = on.
--   The picture is only turned into bits while compiling; in hardware the
--   font is a ROM of 64 x 35 bits.
-- ============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package text_pkg is

  subtype font_glyph_t is std_logic_vector(34 downto 0);
  subtype char_t  is std_logic_vector(5 downto 0);

  constant CH_SPACE : integer := 36;

  -- the font ROM lookup
  function glyph_of(code : char_t) return font_glyph_t;

  -- one character -> its code
  function char_code(ch : character) return integer;

  -- a whole string -> codes, character 1 of the string in the lowest 6 bits
  -- (so text_layer's character 0 is the first, leftmost one)
  function to_codes(s : string) return std_logic_vector;

end package text_pkg;


package body text_pkg is

  function g(r0, r1, r2, r3, r4, r5, r6 : string) return font_glyph_t is
    variable s : string(1 to 35) := r0 & r1 & r2 & r3 & r4 & r5 & r6;
    variable b : font_glyph_t := (others => '0');
  begin
    for i in 0 to 34 loop
      if s(i + 1) = 'X' then
        b(i) := '1';
      end if;
    end loop;
    return b;
  end function;

  type font_t is array (0 to 63) of font_glyph_t;
  constant BLANK : font_glyph_t := (others => '0');
  constant FONT : font_t := (
     0 => g(".XXX.", "X...X", "X..XX", "X.X.X", "XX..X", "X...X", ".XXX."),
     1 => g("..X..", ".XX..", "..X..", "..X..", "..X..", "..X..", ".XXX."),
     2 => g(".XXX.", "X...X", "....X", "...X.", "..X..", ".X...", "XXXXX"),
     3 => g("XXXXX", "...X.", "..X..", "...X.", "....X", "X...X", ".XXX."),
     4 => g("...X.", "..XX.", ".X.X.", "X..X.", "XXXXX", "...X.", "...X."),
     5 => g("XXXXX", "X....", "XXXX.", "....X", "....X", "X...X", ".XXX."),
     6 => g("..XX.", ".X...", "X....", "XXXX.", "X...X", "X...X", ".XXX."),
     7 => g("XXXXX", "....X", "...X.", "..X..", ".X...", ".X...", ".X..."),
     8 => g(".XXX.", "X...X", "X...X", ".XXX.", "X...X", "X...X", ".XXX."),
     9 => g(".XXX.", "X...X", "X...X", ".XXXX", "....X", "...X.", ".XX.."),
    10 => g(".XXX.", "X...X", "X...X", "XXXXX", "X...X", "X...X", "X...X"),  -- A
    11 => g("XXXX.", "X...X", "X...X", "XXXX.", "X...X", "X...X", "XXXX."),  -- B
    12 => g(".XXX.", "X...X", "X....", "X....", "X....", "X...X", ".XXX."),  -- C
    13 => g("XXX..", "X..X.", "X...X", "X...X", "X...X", "X..X.", "XXX.."),  -- D
    14 => g("XXXXX", "X....", "X....", "XXXX.", "X....", "X....", "XXXXX"),  -- E
    15 => g("XXXXX", "X....", "X....", "XXXX.", "X....", "X....", "X...."),  -- F
    16 => g(".XXX.", "X...X", "X....", "X.XXX", "X...X", "X...X", ".XXXX"),  -- G
    17 => g("X...X", "X...X", "X...X", "XXXXX", "X...X", "X...X", "X...X"),  -- H
    18 => g(".XXX.", "..X..", "..X..", "..X..", "..X..", "..X..", ".XXX."),  -- I
    19 => g("..XXX", "...X.", "...X.", "...X.", "...X.", "X..X.", ".XX.."),  -- J
    20 => g("X...X", "X..X.", "X.X..", "XX...", "X.X..", "X..X.", "X...X"),  -- K
    21 => g("X....", "X....", "X....", "X....", "X....", "X....", "XXXXX"),  -- L
    22 => g("X...X", "XX.XX", "X.X.X", "X.X.X", "X...X", "X...X", "X...X"),  -- M
    23 => g("X...X", "X...X", "XX..X", "X.X.X", "X..XX", "X...X", "X...X"),  -- N
    24 => g(".XXX.", "X...X", "X...X", "X...X", "X...X", "X...X", ".XXX."),  -- O
    25 => g("XXXX.", "X...X", "X...X", "XXXX.", "X....", "X....", "X...."),  -- P
    26 => g(".XXX.", "X...X", "X...X", "X...X", "X.X.X", "X..X.", ".XX.X"),  -- Q
    27 => g("XXXX.", "X...X", "X...X", "XXXX.", "X.X..", "X..X.", "X...X"),  -- R
    28 => g(".XXXX", "X....", "X....", ".XXX.", "....X", "....X", "XXXX."),  -- S
    29 => g("XXXXX", "..X..", "..X..", "..X..", "..X..", "..X..", "..X.."),  -- T
    30 => g("X...X", "X...X", "X...X", "X...X", "X...X", "X...X", ".XXX."),  -- U
    31 => g("X...X", "X...X", "X...X", "X...X", "X...X", ".X.X.", "..X.."),  -- V
    32 => g("X...X", "X...X", "X...X", "X.X.X", "X.X.X", "X.X.X", ".X.X."),  -- W
    33 => g("X...X", "X...X", ".X.X.", "..X..", ".X.X.", "X...X", "X...X"),  -- X
    34 => g("X...X", "X...X", ".X.X.", "..X..", "..X..", "..X..", "..X.."),  -- Y
    35 => g("XXXXX", "....X", "...X.", "..X..", ".X...", "X....", "XXXXX"),  -- Z
    37 => g(".....", ".....", ".....", "XXXXX", ".....", ".....", "....."),  -- -
    38 => g("..X..", "..X..", "..X..", "..X..", "..X..", ".....", "..X.."),  -- !
    39 => g(".....", ".XX..", ".XX..", ".....", ".XX..", ".XX..", "....."),  -- :
    40 => g(".....", ".....", ".....", ".....", ".....", ".XX..", ".XX.."),  -- .
    41 => g(".XXX.", "X...X", "....X", "...X.", "..X..", ".....", "..X.."),  -- ?
    others => BLANK
  );

  function glyph_of(code : char_t) return font_glyph_t is
  begin
    return FONT(to_integer(unsigned(code)));
  end function;

  function char_code(ch : character) return integer is
  begin
    if ch >= '0' and ch <= '9' then
      return character'pos(ch) - character'pos('0');
    elsif ch >= 'A' and ch <= 'Z' then
      return character'pos(ch) - character'pos('A') + 10;
    elsif ch >= 'a' and ch <= 'z' then
      return character'pos(ch) - character'pos('a') + 10;    -- lowercase shown as capitals
    end if;
    case ch is
      when '-'    => return 37;
      when '!'    => return 38;
      when ':'    => return 39;
      when '.'    => return 40;
      when '?'    => return 41;
      when others => return CH_SPACE;
    end case;
  end function;

  function to_codes(s : string) return std_logic_vector is
    variable r : std_logic_vector(6 * s'length - 1 downto 0);
  begin
    for i in 0 to s'length - 1 loop
      r(6*i + 5 downto 6*i) := std_logic_vector(to_unsigned(char_code(s(s'low + i)), 6));
    end loop;
    return r;
  end function;

end package body text_pkg;
