-- ============================================================================
-- uart_tx.vhd
-- Sends one byte over a serial (UART) wire.
--
-- What goes on the wire for one byte (format "8N1"):
--
--   idle ...1111 | 0 | b0 b1 b2 b3 b4 b5 b6 b7 | 1 | 1111... idle
--                start   8 data bits, LSB first   stop
--
--   * The wire sits at '1' when nothing is being sent.
--   * A '0' "start bit" says "a byte is coming".
--   * Then the 8 data bits, lowest bit first.
--   * A '1' "stop bit" ends it.
--   Every bit lasts the same time: CLKS_PER_BIT clock cycles
--   (434 cycles at 50 MHz = 115,200 bits per second).
--   There is no clock wire: both sides just agree on the speed beforehand.
--
-- How to use:
--   Put the byte on 'data' and make 'start' = '1' for one clock while
--   busy = '0'. 'busy' stays '1' until the stop bit is finished (about 87 us).
--   Wait for busy = '0' (and don't pulse start again in the very next cycle)
--   before sending the next byte.
-- ============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity uart_tx is
  generic (
    CLKS_PER_BIT : integer := 434
  );
  port (
    clk   : in  std_logic;
    data  : in  std_logic_vector(7 downto 0);
    start : in  std_logic;
    tx    : out std_logic;
    busy  : out std_logic
  );
end entity;

architecture rtl of uart_tx is
  signal sending  : std_logic := '0';
  -- the 10 bits of one frame: stop & data & start. We send bit 0 first and
  -- shift right after each bit.
  signal frame    : std_logic_vector(9 downto 0) := (others => '1');
  signal bit_idx  : integer range 0 to 9 := 0;
  signal baud_cnt : integer range 0 to CLKS_PER_BIT - 1 := 0;
begin

  process(clk)
  begin
    if rising_edge(clk) then
      if sending = '0' then
        if start = '1' then
          frame    <= '1' & data & '0';       -- stop, data, start
          bit_idx  <= 0;
          baud_cnt <= 0;
          sending  <= '1';
        end if;
      else
        if baud_cnt = CLKS_PER_BIT - 1 then   -- current bit has lasted long enough
          baud_cnt <= 0;
          if bit_idx = 9 then
            sending <= '0';                   -- stop bit done
            frame   <= (others => '1');
          else
            bit_idx <= bit_idx + 1;
            frame   <= '1' & frame(9 downto 1);   -- next bit to position 0
          end if;
        else
          baud_cnt <= baud_cnt + 1;
        end if;
      end if;
    end if;
  end process;

  tx   <= frame(0) when sending = '1' else '1';
  busy <= sending;

end architecture;
