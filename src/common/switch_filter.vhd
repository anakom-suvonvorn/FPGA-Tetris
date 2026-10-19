-- ============================================================================
-- switch_filter.vhd
-- Cleans up slide switches: synchronises them to the clock and removes
-- contact bounce, for N switches at once.
--
-- THE PROBLEM
--   A metal contact doesn't close cleanly: for a few milliseconds it bounces
--   and the pin flickers 0-1-0-1. Held halfway, the switch touches neither
--   side and the pin is left floating, picking up noise (pins.xdc gives the
--   switch pins a PULLDOWN, so "halfway" reads as a steady 0 instead).
--   Without filtering, one flip can look like many flips.
--
-- HOW (an "integrator", one per switch)
--   Once every millisecond (a shared tick) each switch is sampled. A small
--   counter 0..LIMIT goes UP when the sample is 1 and DOWN when it is 0. The
--   output only becomes 1 when the counter reaches LIMIT, and only becomes
--   0 when it reaches 0. So a switch must read the new position for LIMIT
--   (10) more milliseconds than the old one before the output follows, and
--   short flickers just move the counter a little up and down.
--   Cost: ~10 ms delay after each flip, nobody notices.
-- ============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity switch_filter is
  generic (
    N            : integer := 4;
    TICK_CYCLES  : integer := 50_000;       -- 1 ms at 50 MHz; testbenches use less
    LIMIT        : integer := 10            -- samples to go all the way across
  );
  port (
    clk      : in  std_logic;
    sw_in    : in  std_logic_vector(N - 1 downto 0);   -- raw pins
    sw_out   : out std_logic_vector(N - 1 downto 0)    -- clean
  );
end entity;

architecture rtl of switch_filter is
  type cnt_t is array (0 to N - 1) of integer range 0 to LIMIT;
  signal s1, s2  : std_logic_vector(N - 1 downto 0) := (others => '0');  -- synchroniser
  signal cnt     : cnt_t := (others => 0);
  signal q       : std_logic_vector(N - 1 downto 0) := (others => '0');
  signal tick_n  : integer range 0 to TICK_CYCLES - 1 := 0;
begin

  process(clk)
  begin
    if rising_edge(clk) then
      s1 <= sw_in;                             -- two flip-flops: the usual synchroniser
      s2 <= s1;
      if tick_n = TICK_CYCLES - 1 then
        tick_n <= 0;
        for i in 0 to N - 1 loop
          if s2(i) = '1' then
            if cnt(i) = LIMIT then q(i) <= '1'; else cnt(i) <= cnt(i) + 1; end if;
          else
            if cnt(i) = 0 then q(i) <= '0'; else cnt(i) <= cnt(i) - 1; end if;
          end if;
        end loop;
      else
        tick_n <= tick_n + 1;
      end if;
    end if;
  end process;

  sw_out <= q;

end architecture;
