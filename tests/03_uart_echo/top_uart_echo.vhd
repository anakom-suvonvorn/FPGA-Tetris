-- ============================================================================
-- Test 03: Serial echo with the PC
--
-- The board's USB cable carries two things at once (the FT2232 chip on the
-- board has two channels):
--   channel A: JTAG, used by FPGA Builder to load the .bit file
--   channel B: a serial port (UART). On the PC it appears as a COM port; on
--              the FPGA it is two pins: G1 (data coming FROM the PC) and
--              F2 (data going TO the PC). The board manual has these two
--              swapped; test 05 (uart_probe) proved it on 16 Oct 2026.
--
-- This test talks to a terminal program on the PC (PuTTY):
--   * Every character you type is received by the FPGA and sent straight
--     back ("echo"), converted to UPPER CASE so you can tell the FPGA really
--     processed it (PuTTY itself shows nothing you type unless it comes back).
--   * Pressing Enter sends back a new line.
--   * PB3 (SW18, middle button) sends the line "Hello from the FPGA!".
--   * The 7-segment display shows, in hex:
--        left 2 digits  = how many bytes have been received (wraps at FF)
--        right 2 digits = the last byte received (e.g. 'a' = 61)
--
-- PuTTY settings: Connection type Serial, the board's COM port,
--   speed 115200, 8 data bits, 1 stop bit, parity None, flow control None.
--
-- Why this matters for the project: the board-to-board cable uses exactly the
-- same uart_tx / uart_rx blocks, and later the PC can pretend to be the
-- other player (type bytes in PuTTY) to test the game with only one board.
-- ============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.common_pkg.all;

entity top_uart_echo is
  port (
    clk      : in  std_logic;    -- H11
    uart_rx  : in  std_logic;    -- G1  (from PC)
    uart_tx  : out std_logic;    -- F2  (to PC)
    btn_send : in  std_logic;    -- J12 (SW18)
    seg_n    : out std_logic_vector(7 downto 0);
    dig      : out std_logic_vector(3 downto 0)
  );
end entity;

architecture rtl of top_uart_echo is
  constant MSG : string := "Hello from the FPGA!";   -- followed by CR LF

  signal rx_data  : std_logic_vector(7 downto 0);
  signal rx_valid : std_logic;

  signal tx_data  : std_logic_vector(7 downto 0) := (others => '0');
  signal tx_start : std_logic := '0';
  signal tx_busy  : std_logic;

  signal send_p   : std_logic;

  signal rx_count : unsigned(7 downto 0) := (others => '0');
  signal last_rx  : std_logic_vector(7 downto 0) := (others => '0');
  signal g3, g2, g1, g0 : glyph_t;

  -- bytes waiting to be sent back
  signal echo_pending : std_logic := '0';
  signal echo_byte    : std_logic_vector(7 downto 0) := (others => '0');
  signal lf_pending   : std_logic := '0';              -- line feed after Enter

  -- message sender: position in MSG, then CR, then LF
  signal msg_active : std_logic := '0';
  signal msg_pos    : integer range 0 to MSG'length + 1 := 0;

  function to_byte(c : character) return std_logic_vector is
  begin
    return std_logic_vector(to_unsigned(character'pos(c), 8));
  end function;

  -- 'a'..'z' -> 'A'..'Z', anything else unchanged
  function upper(b : std_logic_vector(7 downto 0)) return std_logic_vector is
  begin
    if unsigned(b) >= 16#61# and unsigned(b) <= 16#7A# then
      return std_logic_vector(unsigned(b) - 32);
    else
      return b;
    end if;
  end function;

begin

  u_rx : entity work.uart_rx
    generic map (CLKS_PER_BIT => CLKS_PER_BIT)
    port map (clk => clk, rx => uart_rx, data => rx_data, valid => rx_valid);

  u_tx : entity work.uart_tx
    generic map (CLKS_PER_BIT => CLKS_PER_BIT)
    port map (clk => clk, data => tx_data, start => tx_start, tx => uart_tx, busy => tx_busy);

  u_btn : entity work.debounce
    port map (clk => clk, btn_in => btn_send, level => open, pressed => send_p);

  process(clk)
  begin
    if rising_edge(clk) then
      tx_start <= '0';

      -- 1) a byte arrived from the PC: remember it and queue the echo
      if rx_valid = '1' then
        rx_count     <= rx_count + 1;
        last_rx      <= rx_data;
        echo_byte    <= upper(rx_data);
        echo_pending <= '1';
        if rx_data = x"0D" then           -- Enter key sends CR (0x0D)
          lf_pending <= '1';              -- ...so also send LF (0x0A) after it
        end if;
      end if;

      -- 2) button: start sending the message (if not already sending it)
      if send_p = '1' and msg_active = '0' then
        msg_active <= '1';
        msg_pos    <= 0;
      end if;

      -- 3) the transmitter is free: send the next byte.
      --    Echoes go first so typing never feels slow.
      --    (tx_start = '0' check: busy only rises one clock after start.)
      if tx_busy = '0' and tx_start = '0' then
        if echo_pending = '1' then
          tx_data      <= echo_byte;
          tx_start     <= '1';
          echo_pending <= '0';
        elsif lf_pending = '1' then
          tx_data    <= x"0A";
          tx_start   <= '1';
          lf_pending <= '0';
        elsif msg_active = '1' then
          if msg_pos < MSG'length then
            tx_data <= to_byte(MSG(msg_pos + 1));   -- VHDL strings start at 1
          elsif msg_pos = MSG'length then
            tx_data <= x"0D";                         -- CR
          else
            tx_data <= x"0A";                         -- LF
          end if;
          tx_start <= '1';
          if msg_pos = MSG'length + 1 then
            msg_active <= '0';
          else
            msg_pos <= msg_pos + 1;
          end if;
        end if;
      end if;
    end if;
  end process;

  -- glyphs for the display (calculated into signals first, VHDL-93 rule)
  g3 <= hex7(std_logic_vector(rx_count(7 downto 4)));
  g2 <= hex7(std_logic_vector(rx_count(3 downto 0)));
  g1 <= hex7(last_rx(7 downto 4));
  g0 <= hex7(last_rx(3 downto 0));

  u_seg : entity work.seg7_scan
    port map (
      clk   => clk,
      d3    => g3,
      d2    => g2,
      d1    => g1,
      d0    => g0,
      dp    => "0100",                     -- dot separates count | byte
      seg_n => seg_n,
      dig   => dig
    );

end architecture;
