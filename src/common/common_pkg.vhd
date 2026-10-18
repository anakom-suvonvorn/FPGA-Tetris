-- ============================================================================
-- common_pkg.vhd
-- Shared constants and helper functions used by every design in this project.
--
-- A VHDL "package" is a bag of things (constants, types, functions) that any
-- other file can use by writing:   use work.common_pkg.all;
-- It must be compiled BEFORE the files that use it, so it is always listed
-- first in each test's project.txt.
-- ============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package common_pkg is

  -- The EDGE Spartan-7 board has a 50 MHz oscillator on pin H11.
  constant CLK_HZ : integer := 50_000_000;

  -- Serial link speed used everywhere (PC link and board-to-board link).
  -- 50,000,000 / 115,200 = 434.03, so one bit lasts 434 clock cycles.
  constant BAUD          : integer := 115_200;
  constant CLKS_PER_BIT  : integer := CLK_HZ / BAUD;   -- = 434

  -- --------------------------------------------------------------------------
  -- 7-segment glyphs.
  -- Bit order is "gfedcba": bit 0 = segment a (top), bit 6 = segment g (middle).
  -- '1' here means "segment ON". The display driver (seg7_scan) inverts this,
  -- because the board's segments are active-low (common anode).
  --
  --      aaa
  --     f   b
  --      ggg
  --     e   c
  --      ddd
  -- --------------------------------------------------------------------------
  subtype glyph_t is std_logic_vector(6 downto 0);

  constant SEG_BLANK : glyph_t := "0000000";
  constant SEG_DASH  : glyph_t := "1000000";   -- g only
  constant SEG_J     : glyph_t := "0011110";   -- b c d e
  constant SEG_P     : glyph_t := "1110011";   -- a b e f g

  -- Hex digit 0..F -> glyph
  function hex7(n : std_logic_vector(3 downto 0)) return glyph_t;
  function hex7(n : integer) return glyph_t;

end package common_pkg;


package body common_pkg is

  function hex7(n : std_logic_vector(3 downto 0)) return glyph_t is
  begin
    case n is
      when "0000" => return "0111111";  -- 0
      when "0001" => return "0000110";  -- 1
      when "0010" => return "1011011";  -- 2
      when "0011" => return "1001111";  -- 3
      when "0100" => return "1100110";  -- 4
      when "0101" => return "1101101";  -- 5
      when "0110" => return "1111101";  -- 6
      when "0111" => return "0000111";  -- 7
      when "1000" => return "1111111";  -- 8
      when "1001" => return "1101111";  -- 9
      when "1010" => return "1110111";  -- A
      when "1011" => return "1111100";  -- b
      when "1100" => return "0111001";  -- C
      when "1101" => return "1011110";  -- d
      when "1110" => return "1111001";  -- E
      when others => return "1110001";  -- F
    end case;
  end function;

  function hex7(n : integer) return glyph_t is
  begin
    return hex7(std_logic_vector(to_unsigned(n mod 16, 4)));
  end function;

end package body common_pkg;
