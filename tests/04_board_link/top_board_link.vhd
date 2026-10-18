-- ============================================================================
-- Test 04: Board-to-board link
--
-- Load this same design into BOTH boards. Each board:
--   * sends the value of its 8 right-hand slide switches (SW2..SW10) over its
--     link_tx wire, 20 times per second, as one serial byte
--   * shows on its 7-segment display, in hex:
--        left 2 digits  = its own switch value (what it is sending)
--        right 2 digits = the last value received from the other board,
--                         or "--" if nothing has arrived for 0.25 seconds
--                         (cable unplugged, other board off, wrong wiring)
--
-- Wiring with jumper wires, through a 330 ohm resistor on each signal wire
-- (the resistor protects the pins if something is plugged in wrong):
--
--     Board A  J5 pin 5 (L14, link_tx)  ---[330]--->  Board B  J5 pin 6 (M13, link_rx)
--     Board A  J5 pin 6 (M13, link_rx)  <---[330]---  Board B  J5 pin 5 (L14, link_tx)
--     Board A  J5 pin 2 or 4 (GND)      ------------  Board B  J5 pin 2 or 4 (GND)
--
--   TX of one board always goes to RX of the other (crossed over).
--   The ground wire is required: a signal only means something relative to
--   ground, and the two boards' grounds are otherwise not connected.
--
-- One-board self-test first: connect J5 pin 5 to J5 pin 6 on the same board
-- (a "loopback"). The right digits should then show the board's own switches.
--
-- Run test 02 first to confirm pins 5 and 6 really are L14 and M13.
-- ============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.common_pkg.all;

entity top_board_link is
  port (
    clk     : in  std_logic;                       -- H11
    sw      : in  std_logic_vector(7 downto 0);    -- SW2..SW10 (K11 M11 N14 P12 N10 P10 M10 N4)
    link_tx : out std_logic;                       -- J5 pin 5 (L14)
    link_rx : in  std_logic;                       -- J5 pin 6 (M13)
    seg_n   : out std_logic_vector(7 downto 0);
    dig     : out std_logic_vector(3 downto 0)
  );
end entity;

architecture rtl of top_board_link is
  constant SEND_PERIOD : integer := CLK_HZ / 20;     -- 50 ms
  constant TIMEOUT     : integer := CLK_HZ / 4;      -- 250 ms

  signal sw_s1, sw_s   : std_logic_vector(7 downto 0) := (others => '0');
  signal send_cnt      : integer range 0 to SEND_PERIOD - 1 := 0;
  signal tx_start      : std_logic := '0';
  signal tx_busy       : std_logic;

  signal rx_data       : std_logic_vector(7 downto 0);
  signal rx_valid      : std_logic;
  signal last_rx       : std_logic_vector(7 downto 0) := (others => '0');
  signal silence       : integer range 0 to TIMEOUT := TIMEOUT;
  signal link_ok       : std_logic;

  signal g3, g2, g1, g0 : glyph_t;
begin

  u_tx : entity work.uart_tx
    generic map (CLKS_PER_BIT => CLKS_PER_BIT)
    port map (clk => clk, data => sw_s, start => tx_start, tx => link_tx, busy => tx_busy);

  u_rx : entity work.uart_rx
    generic map (CLKS_PER_BIT => CLKS_PER_BIT)
    port map (clk => clk, rx => link_rx, data => rx_data, valid => rx_valid);

  process(clk)
  begin
    if rising_edge(clk) then
      sw_s1 <= sw;
      sw_s  <= sw_s1;

      -- send our switch value every 50 ms
      tx_start <= '0';
      if send_cnt = SEND_PERIOD - 1 then
        send_cnt <= 0;
        if tx_busy = '0' then
          tx_start <= '1';
        end if;
      else
        send_cnt <= send_cnt + 1;
      end if;

      -- receive: remember the value, and measure how long since the last byte
      if rx_valid = '1' then
        last_rx <= rx_data;
        silence <= 0;
      elsif silence < TIMEOUT then
        silence <= silence + 1;
      end if;
    end if;
  end process;

  link_ok <= '1' when silence < TIMEOUT else '0';

  g3 <= hex7(sw_s(7 downto 4));
  g2 <= hex7(sw_s(3 downto 0));
  g1 <= hex7(last_rx(7 downto 4)) when link_ok = '1' else SEG_DASH;
  g0 <= hex7(last_rx(3 downto 0)) when link_ok = '1' else SEG_DASH;

  u_seg : entity work.seg7_scan
    port map (
      clk   => clk,
      d3    => g3,
      d2    => g2,
      d1    => g1,
      d0    => g0,
      dp    => "0100",
      seg_n => seg_n,
      dig   => dig
    );

end architecture;
