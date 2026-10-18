-- ============================================================================
-- seg7_scan.vhd
-- Drives the board's 4-digit 7-segment display.
--
-- The 4 digits share the same 8 segment wires (a..g, dp). Only one digit can
-- be switched on at a time, so we light digit 3, then 2, then 1, then 0, over
-- and over, about 190 times per second. Your eyes blend it into a steady image.
--
-- This is the same circuit as the "display" block of our Lab 7:
--   * a 2-bit counter picks the digit (Lab 7: two toggle flip-flops)
--   * a 4-to-1 mux picks that digit's glyph (Lab 7: mux_4_1_4b)
--   * a 2-to-4 decoder turns on that digit's enable (Lab 7: y0..y3)
-- with two changes:
--   * the 2-bit counter is the top 2 bits of an 18-bit counter, so each digit
--     stays on for 1.3 ms instead of 40 ns. Everything still runs on the one
--     50 MHz clock, no clock made from a flip-flop output.
--   * a short "all digits off" gap at the start of each digit's turn stops the
--     previous digit's glyph from faintly showing on the next one (ghosting).
--
-- Board polarity (from Lab 7, which works on our board):
--   digit enables: ACTIVE-HIGH  ('1' = this digit is on)
--   segments:      ACTIVE-LOW   ('0' = this segment is lit, common anode)
--
-- Inputs  : four glyphs (from common_pkg: hex7(), SEG_J, ...) and 4 dot bits.
--           d3 / dp(3) is the LEFTMOST digit, d0 / dp(0) the RIGHTMOST.
-- Outputs : seg_n(6..0) = segments g..a, seg_n(7) = dp   (active-low)
--           dig(3..0)   = digit enables, dig(3) = leftmost (active-high)
--
-- Board pins (EDGE Spartan-7):
--   seg_n(0)=L3 a, (1)=P4 b, (2)=P2 c, (3)=M3 d, (4)=M1 e, (5)=J4 f,
--   seg_n(6)=K4 g, (7)=J2 dp
--   dig(3)=H4 DIGIT1 (left) ... dig(0)=H1 DIGIT4 (right)
--   Remove jumper J9, otherwise LEDs D10-D17 light up with the segments.
-- ============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity seg7_scan is
  port (
    clk   : in  std_logic;
    d3    : in  std_logic_vector(6 downto 0);   -- leftmost digit glyph
    d2    : in  std_logic_vector(6 downto 0);
    d1    : in  std_logic_vector(6 downto 0);
    d0    : in  std_logic_vector(6 downto 0);   -- rightmost digit glyph
    dp    : in  std_logic_vector(3 downto 0);   -- decimal points, '1' = on
    seg_n : out std_logic_vector(7 downto 0);   -- '0' = segment lit
    dig   : out std_logic_vector(3 downto 0)    -- '1' = digit on
  );
end entity;

architecture rtl of seg7_scan is
  -- 18-bit free-running counter at 50 MHz.
  --   bits 17..16 = which digit is on (each digit gets 2^16 cycles = 1.3 ms)
  --   bits 15..12 = "0000" during the first 1/16 of each turn: all digits off
  signal cnt   : unsigned(17 downto 0) := (others => '0');
  signal sel   : unsigned(1 downto 0);
  signal blank : std_logic;
  signal glyph : std_logic_vector(6 downto 0);
  signal dot   : std_logic;

  -- output registers: every output pin comes straight from a flip-flop,
  -- so the pins switch cleanly once per clock with no glitches
  signal seg_r : std_logic_vector(7 downto 0) := (others => '1');   -- all off
  signal dig_r : std_logic_vector(3 downto 0) := (others => '0');   -- all off
begin

  -- the counter (flip-flops)
  process(clk)
  begin
    if rising_edge(clk) then
      cnt <= cnt + 1;
    end if;
  end process;

  sel   <= cnt(17 downto 16);
  blank <= '1' when cnt(15 downto 12) = "0000" else '0';

  -- 4-to-1 mux: the selected digit's glyph and dot (gates, no flip-flops)
  with sel select glyph <=
    d3 when "11",
    d2 when "10",
    d1 when "01",
    d0 when others;

  with sel select dot <=
    dp(3) when "11",
    dp(2) when "10",
    dp(1) when "01",
    dp(0) when others;

  -- output registers
  process(clk)
  begin
    if rising_edge(clk) then
      -- 2-to-4 decoder with an enable: one-hot, active-high
      if blank = '1' then
        dig_r <= "0000";
      else
        case sel is
          when "11"   => dig_r <= "1000";
          when "10"   => dig_r <= "0100";
          when "01"   => dig_r <= "0010";
          when others => dig_r <= "0001";
        end case;
      end if;

      -- segments: glyphs use '1' = lit, the board wants '0' = lit
      seg_r <= not (dot & glyph);
    end if;
  end process;

  seg_n <= seg_r;
  dig   <= dig_r;

end architecture;
