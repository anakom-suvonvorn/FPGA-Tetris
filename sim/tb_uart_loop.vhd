-- ============================================================================
-- tb_uart_loop.vhd  -  simulation test for uart_tx + uart_rx
--
-- A testbench is VHDL that never goes on the board. It "plugs" our design into
-- a pretend world inside the simulator: it makes the clock, drives the inputs,
-- and checks the outputs, printing PASS or FAIL.
--
-- Here: the tx wire of uart_tx is connected straight to the rx of uart_rx
-- ("loopback"). We send a few bytes and check each one comes out identical.
--
-- Run it with:  tools\sim.bat tb_uart_loop
-- ============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_uart_loop is
end entity;

architecture sim of tb_uart_loop is
  constant CPB : integer := 434;

  signal clk      : std_logic := '0';
  signal tx_data  : std_logic_vector(7 downto 0) := (others => '0');
  signal tx_start : std_logic := '0';
  signal tx_busy  : std_logic;
  signal line     : std_logic;
  signal rx_data  : std_logic_vector(7 downto 0);
  signal rx_valid : std_logic;
  signal done     : boolean := false;

  type bytes_t is array (natural range <>) of std_logic_vector(7 downto 0);
  constant TEST_BYTES : bytes_t := (x"55", x"A3", x"00", x"FF", x"41", x"0D");
begin

  -- 50 MHz clock: 10 ns high, 10 ns low (stops when the test is done)
  clk <= not clk after 10 ns when not done else clk;

  u_tx : entity work.uart_tx generic map (CLKS_PER_BIT => CPB)
    port map (clk => clk, data => tx_data, start => tx_start, tx => line, busy => tx_busy);

  u_rx : entity work.uart_rx generic map (CLKS_PER_BIT => CPB)
    port map (clk => clk, rx => line, data => rx_data, valid => rx_valid);

  -- sender
  stim : process
  begin
    wait for 200 ns;
    for i in TEST_BYTES'range loop
      wait until rising_edge(clk);
      tx_data  <= TEST_BYTES(i);
      tx_start <= '1';
      wait until rising_edge(clk);
      tx_start <= '0';
      wait until rising_edge(clk);
      wait until tx_busy = '0';
    end loop;
    wait for 50 us;
    done <= true;
    wait;
  end process;

  -- checker
  check : process
    variable errors : integer := 0;
  begin
    for i in TEST_BYTES'range loop
      wait until rising_edge(clk) and rx_valid = '1';
      if rx_data = TEST_BYTES(i) then
        report "byte " & integer'image(i) & " ok: " &
               integer'image(to_integer(unsigned(rx_data)));
      else
        report "byte " & integer'image(i) & " WRONG: got " &
               integer'image(to_integer(unsigned(rx_data))) & " expected " &
               integer'image(to_integer(unsigned(TEST_BYTES(i)))) severity error;
        errors := errors + 1;
      end if;
    end loop;
    if errors = 0 then
      report "TEST PASSED: all " & integer'image(TEST_BYTES'length) & " bytes came back correctly";
    else
      report "TEST FAILED: " & integer'image(errors) & " wrong bytes" severity error;
    end if;
    wait;
  end process;

end architecture;
