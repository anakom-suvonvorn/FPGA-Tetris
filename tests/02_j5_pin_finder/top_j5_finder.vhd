-- ============================================================================
-- Test 02: J5 expansion-header pin finder
--
-- J5 is the 20-pin header on the board (2 rows x 10 pins). Pins 1-4 are power
-- and ground, pins 5-20 are 16 general I/O lines going straight to the FPGA.
-- We want to use two of them as the cable between the two boards, but the
-- printed manual lists the wrong (Spartan-6) pin names. The names we use here
-- come from the official pin file inside the TA's FPGA Builder:
--
--   J5 pin :  5    6    7    8    9    10   11   12
--   FPGA   :  L14  M13  H14  H13  F11  G11  C14  D14
--   J5 pin :  13   14   15   16   17   18   19   20
--   FPGA   :  E13  F13  F14  G14  D13  D12  E12  F12
--
-- The ORDER (which name sits on which header pin) was worked out from the
-- camera wiring drawing in the manual, so this test checks it on real
-- hardware.
--
-- What it does:
--   Exactly one of the 16 lines is driven high (3.3 V); the other 15 are low.
--   The 7-segment display shows which header pin should be the high one:
--        J5.05   means "J5 pin 5 should be at 3.3 V right now"
--   Every second it moves on to the next pin (5, 6, ... 20, 5, ...).
--
-- Buttons:
--   PB1 (SW14, left)    : previous pin
--   PB3 (SW18, middle)  : pause / run    (right-most dot lights while paused)
--   PB5 (SW23, bottom)  : next pin
--
-- How to check (nothing else plugged into J5!):
--   * Multimeter on DC volts: black probe on J5 pin 2 or 4 (GND), red probe
--     on each pin. Only the pin shown on the display reads about 3.3 V.
--   * Or an LED with a 330 ohm resistor in series, from the pin to GND:
--     it lights only on the pin shown.
--   Pause on each number and confirm. If a different pin is high, write down
--   the real mapping, the pin lists will need updating.
-- ============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.common_pkg.all;

entity top_j5_finder is
  port (
    clk       : in  std_logic;                      -- H11
    btn_prev  : in  std_logic;                      -- J14 (SW14)
    btn_pause : in  std_logic;                      -- J12 (SW18)
    btn_next  : in  std_logic;                      -- L13 (SW23)
    j5        : out std_logic_vector(15 downto 0);  -- j5(0) = header pin 5 ... j5(15) = pin 20
    seg_n     : out std_logic_vector(7 downto 0);
    dig       : out std_logic_vector(3 downto 0)
  );
end entity;

architecture rtl of top_j5_finder is
  signal prev_p, pause_p, next_p : std_logic;
  signal idx     : integer range 0 to 15 := 0;     -- which line is high
  signal running : std_logic := '1';
  signal sec_cnt : integer range 0 to CLK_HZ - 1 := 0;
  signal j5_r    : std_logic_vector(15 downto 0) := (others => '0');
  signal tens_g, ones_g : glyph_t;
  constant FIVE_G       : glyph_t := hex7(5);
  signal dots           : std_logic_vector(3 downto 0);
begin

  -- clean up the three buttons (one pulse per press)
  u_prev  : entity work.debounce port map (clk => clk, btn_in => btn_prev,  level => open, pressed => prev_p);
  u_pause : entity work.debounce port map (clk => clk, btn_in => btn_pause, level => open, pressed => pause_p);
  u_next  : entity work.debounce port map (clk => clk, btn_in => btn_next,  level => open, pressed => next_p);

  process(clk)
  begin
    if rising_edge(clk) then
      -- one-second timer (counts 50,000,000 clocks)
      if sec_cnt = CLK_HZ - 1 then
        sec_cnt <= 0;
      else
        sec_cnt <= sec_cnt + 1;
      end if;

      if pause_p = '1' then
        running <= not running;
      end if;

      if next_p = '1' or (running = '1' and sec_cnt = CLK_HZ - 1) then
        if idx = 15 then idx <= 0; else idx <= idx + 1; end if;
        sec_cnt <= 0;
      elsif prev_p = '1' then
        if idx = 0 then idx <= 15; else idx <= idx - 1; end if;
        sec_cnt <= 0;
      end if;

      -- drive exactly one line high
      j5_r <= (others => '0');
      j5_r(idx) <= '1';
    end if;
  end process;

  j5 <= j5_r;

  -- header pin number = idx + 5  ->  two decimal digits (05 .. 20)
  process(idx)
    variable p : integer range 0 to 31;
  begin
    p := idx + 5;
    if p >= 20 then
      tens_g <= hex7(2); ones_g <= hex7(p - 20);
    elsif p >= 10 then
      tens_g <= hex7(1); ones_g <= hex7(p - 10);
    else
      tens_g <= hex7(0); ones_g <= hex7(p);
    end if;
  end process;

  -- display "J5.nn"  (dot after the 5; right-most dot = paused)
  -- (VHDL-93 rule: only plain signals or constants may go into a port map,
  --  so anything calculated is put in a signal first.)
  dots <= "010" & (not running);

  u_seg : entity work.seg7_scan
    port map (
      clk   => clk,
      d3    => SEG_J,
      d2    => FIVE_G,
      d1    => tens_g,
      d0    => ones_g,
      dp    => dots,
      seg_n => seg_n,
      dig   => dig
    );

end architecture;
