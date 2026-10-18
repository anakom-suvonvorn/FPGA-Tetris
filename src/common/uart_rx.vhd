-- ============================================================================
-- uart_rx.vhd
-- Receives bytes from a serial (UART) wire. Format 8N1, see uart_tx.vhd.
--
-- How it works:
--   1. The rx wire comes from outside (PC or another board), so it first goes
--      through a 2-flip-flop synchronizer, same reason as in debounce.vhd.
--   2. IDLE: wait for the wire to drop to '0' (the start bit begins).
--   3. START: wait half a bit (217 cycles) to reach the MIDDLE of the start
--      bit. If the wire is still '0', it really is a start bit (not a glitch).
--   4. DATA: from there, wait one full bit time (434 cycles) 8 times. Each
--      wait lands in the middle of the next data bit, where the signal is
--      cleanest. Sample it. Bits arrive LSB first, so each new bit is shifted
--      in at the top and ends up in the right place after 8 bits.
--   5. STOP: wait one more bit time. If the wire is '1' (a proper stop bit),
--      output the byte with valid = '1' for one clock. If not, the byte is
--      broken (wrong speed, noise) and we drop it.
-- ============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity uart_rx is
  generic (
    CLKS_PER_BIT : integer := 434
  );
  port (
    clk   : in  std_logic;
    rx    : in  std_logic;
    data  : out std_logic_vector(7 downto 0);
    valid : out std_logic                     -- one-clock pulse per good byte
  );
end entity;

architecture rtl of uart_rx is
  type state_t is (S_IDLE, S_START, S_DATA, S_STOP);
  signal state    : state_t := S_IDLE;
  signal sync1    : std_logic := '1';
  signal rx_s     : std_logic := '1';
  signal cnt      : integer range 0 to CLKS_PER_BIT - 1 := 0;
  signal bit_idx  : integer range 0 to 7 := 0;
  signal shreg    : std_logic_vector(7 downto 0) := (others => '0');
  signal data_r   : std_logic_vector(7 downto 0) := (others => '0');
  signal valid_r  : std_logic := '0';
begin

  process(clk)
  begin
    if rising_edge(clk) then
      sync1 <= rx;
      rx_s  <= sync1;
      valid_r <= '0';

      case state is
        when S_IDLE =>
          cnt <= 0;
          if rx_s = '0' then
            state <= S_START;
          end if;

        when S_START =>
          if cnt = CLKS_PER_BIT / 2 - 1 then
            cnt <= 0;
            if rx_s = '0' then
              bit_idx <= 0;
              state   <= S_DATA;
            else
              state   <= S_IDLE;              -- just a glitch
            end if;
          else
            cnt <= cnt + 1;
          end if;

        when S_DATA =>
          if cnt = CLKS_PER_BIT - 1 then
            cnt   <= 0;
            shreg <= rx_s & shreg(7 downto 1);
            if bit_idx = 7 then
              state <= S_STOP;
            else
              bit_idx <= bit_idx + 1;
            end if;
          else
            cnt <= cnt + 1;
          end if;

        when S_STOP =>
          if cnt = CLKS_PER_BIT - 1 then
            cnt <= 0;
            if rx_s = '1' then
              data_r  <= shreg;
              valid_r <= '1';
            end if;
            state <= S_IDLE;
          else
            cnt <= cnt + 1;
          end if;
      end case;
    end if;
  end process;

  data  <= data_r;
  valid <= valid_r;

end architecture;
