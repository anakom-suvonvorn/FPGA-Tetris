-- ============================================================================
-- tb_switch_filter.vhd  -  does switch_filter turn bouncy flips into clean ones?
--
-- One switch is flipped 10 times. Every flip bounces: for 3 sample periods
-- the pin jumps between 0 and 1 at random (every 1..20 clocks) before it
-- settles. Then it stays put for 30 sample periods.
-- Checks: the output changes exactly 10 times (once per flip, never during
-- bounce), and ends at the switch's final position.
-- TICK_CYCLES is 1,000 here instead of 50,000 to keep the run short; the
-- logic is the same.
--
-- Run with:  tools\sim.bat tb_switch_filter
-- ============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

entity tb_switch_filter is
end entity;

architecture sim of tb_switch_filter is
  constant TICK : integer := 1000;
  signal clk    : std_logic := '0';
  signal done   : boolean := false;
  signal pin    : std_logic_vector(0 downto 0) := "0";
  signal q      : std_logic_vector(0 downto 0);
  signal edges  : integer := 0;
begin
  clk <= not clk after 10 ns when not done else clk;

  dut : entity work.switch_filter
    generic map (N => 1, TICK_CYCLES => TICK, LIMIT => 10)
    port map (clk => clk, sw_in => pin, sw_out => q);

  -- count output changes
  process(clk)
    variable last : std_logic := '0';
  begin
    if rising_edge(clk) then
      if q(0) /= last then edges <= edges + 1; end if;
      last := q(0);
    end if;
  end process;

  stim : process
    variable s1, s2 : positive := 42;
    variable r      : real;
    variable level  : std_logic := '0';
    variable t      : integer;
  begin
    for k in 1 to 10 loop
      level := not level;
      -- bounce for 3 sample periods
      t := 0;
      while t < 3 * TICK loop
        uniform(s1, s2, r);
        pin(0) <= not pin(0);
        for c in 1 to 1 + integer(r * 19.0) loop wait until rising_edge(clk); end loop;
        t := t + 1 + integer(r * 19.0);
      end loop;
      pin(0) <= level;
      for c in 1 to 30 * TICK loop wait until rising_edge(clk); end loop;
    end loop;
    if edges = 10 and q(0) = level then
      report "10 bouncy flips -> " & integer'image(edges) & " clean output changes";
      report "TEST PASSED";
    else
      report "got " & integer'image(edges) & " output changes for 10 flips" severity error;
      report "TEST FAILED" severity error;
    end if;
    done <= true;
    wait;
  end process;
end architecture;
