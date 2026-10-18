-- ============================================================================
-- debounce.vhd
-- Cleans up one push button.
--
-- Three problems with a raw button signal, and how this block fixes each:
--
-- 1. It is ASYNCHRONOUS: it can change at any moment, not in step with our
--    50 MHz clock. If it changes right as a flip-flop samples it, that
--    flip-flop can briefly go "half-way" (metastability). Fix: pass it through
--    two flip-flops in a row (sync1 -> sync2) before using it anywhere.
--
-- 2. It BOUNCES: the metal contacts chatter on/off for a few milliseconds when
--    pressed or released (see the picture in Lab 9). Fix: only accept a new
--    level after it has stayed the same for STABLE_CYCLES clocks (default
--    1,000,000 cycles = 20 ms at 50 MHz).
--
-- 3. We usually want ONE event per press, not "high for 200 ms".
--    Fix: 'pressed' is a single-clock pulse at the moment the clean level goes
--    from 0 to 1 (edge detect, like Lab 7).
--
-- Outputs:
--   level   : clean, stable version of the button ('1' while held down)
--   pressed : '1' for exactly one clock cycle per press
-- ============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity debounce is
  generic (
    STABLE_CYCLES : integer := 1_000_000      -- 20 ms at 50 MHz
  );
  port (
    clk     : in  std_logic;
    btn_in  : in  std_logic;                   -- raw pin, '1' = pressed
    level   : out std_logic;
    pressed : out std_logic
  );
end entity;

architecture rtl of debounce is
  signal sync1, sync2 : std_logic := '0';
  signal stable       : std_logic := '0';
  signal cnt          : integer range 0 to STABLE_CYCLES := 0;
  signal pulse        : std_logic := '0';
begin

  process(clk)
  begin
    if rising_edge(clk) then
      -- (1) two-flip-flop synchronizer
      sync1 <= btn_in;
      sync2 <= sync1;

      -- (2) debounce: count how long the input has disagreed with 'stable'
      pulse <= '0';
      if sync2 = stable then
        cnt <= 0;                              -- no change, keep waiting
      elsif cnt = STABLE_CYCLES - 1 then
        stable <= sync2;                       -- held long enough: accept it
        cnt    <= 0;
        if sync2 = '1' then
          pulse <= '1';                        -- (3) 0 -> 1 means "pressed"
        end if;
      else
        cnt <= cnt + 1;
      end if;
    end if;
  end process;

  level   <= stable;
  pressed <= pulse;

end architecture;
