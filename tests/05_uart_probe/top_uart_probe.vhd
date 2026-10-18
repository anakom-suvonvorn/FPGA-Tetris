-- ============================================================================
-- Test 05: USB serial probe (finds which pin is which)
--
-- Test 03 (echo) got no reply on the PC. The manual says:
--     F2 = data FROM the PC (the USB chip's TXD)
--     G1 = data TO the PC   (the USB chip's RXD)
-- but board manuals sometimes have TX and RX swapped. This design does not
-- trust the manual. It works it out by listening:
--
--   1. At power-up BOTH pins are inputs (the FPGA drives neither of them, so
--      nothing can be damaged whichever way round they really are).
--      A receiver listens on each pin. The 7-segment display shows:
--          left 2 digits  = bytes received on F2
--          right 2 digits = bytes received on G1
--   2. Type a few keys in PuTTY. Whichever counter goes up is the pin the PC
--      talks on. From then on the FPGA transmits on the OTHER pin:
--          dot on the leftmost digit  -> TX on G1 (the manual is right)
--          dot on the rightmost digit -> TX on F2 (the manual is swapped)
--   3. Now it behaves like test 03: every key comes back in CAPITALS, Enter
--      starts a new line, PB3 (SW18, middle button) prints a status line, and
--      the status line is also printed every 3 seconds by itself.
--
-- If both counters stay at 00 while you type, no data reaches the FPGA at all
-- (wrong COM port, wrong baud rate, or the PC side is the problem).
--
-- VHDL notes:
--   * "inout" ports: a pin that can be an input or an output. Writing 'Z'
--     (high impedance) to it means "don't drive it", so it is just an input.
--   * Reading an inout port is allowed (unlike reading an out port).
-- ============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.common_pkg.all;

entity top_uart_probe is
  port (
    clk      : in    std_logic;                     -- H11
    pin_f2   : inout std_logic;                     -- F2  (manual: from PC)
    pin_g1   : inout std_logic;                     -- G1  (manual: to PC)
    btn_send : in    std_logic;                     -- J12 (SW18)
    seg_n    : out   std_logic_vector(7 downto 0);
    dig      : out   std_logic_vector(3 downto 0)
  );
end entity;

architecture rtl of top_uart_probe is
  -- both strings must have the same length (48 characters)
  constant MSG_G1 : string := "FPGA here: TX on G1, RX on F2 (as in the manual)";
  constant MSG_F2 : string := "FPGA here: TX on F2, RX on G1 (pins are SWAPPED)";
  constant MSG_LEN : integer := MSG_G1'length;

  constant TICKS_3S : integer := 3 * CLK_HZ;

  -- direction: nothing learned yet / TX on G1 / TX on F2
  signal tx_on_g1 : std_logic := '0';
  signal tx_on_f2 : std_logic := '0';

  -- one receiver per pin
  signal rxf_data, rxg_data   : std_logic_vector(7 downto 0);
  signal rxf_valid, rxg_valid : std_logic;
  signal cnt_f2, cnt_g1       : unsigned(7 downto 0) := (others => '0');

  -- the byte that counts as "received from the PC" (from whichever pin)
  signal pc_valid : std_logic := '0';
  signal pc_data  : std_logic_vector(7 downto 0) := (others => '0');

  -- one transmitter, its output goes to whichever pin was chosen
  signal tx_line  : std_logic;
  signal tx_data  : std_logic_vector(7 downto 0) := (others => '0');
  signal tx_start : std_logic := '0';
  signal tx_busy  : std_logic;

  signal send_p   : std_logic;
  signal timer    : integer range 0 to TICKS_3S - 1 := 0;

  signal echo_pending : std_logic := '0';
  signal echo_byte    : std_logic_vector(7 downto 0) := (others => '0');
  signal lf_pending   : std_logic := '0';
  signal msg_request  : std_logic := '0';
  signal msg_active   : std_logic := '0';
  signal msg_pos      : integer range 0 to MSG_LEN + 1 := 0;

  signal g3, g2, g1, g0 : glyph_t;
  signal dots           : std_logic_vector(3 downto 0);

  function to_byte(c : character) return std_logic_vector is
  begin
    return std_logic_vector(to_unsigned(character'pos(c), 8));
  end function;

  function upper(b : std_logic_vector(7 downto 0)) return std_logic_vector is
  begin
    if unsigned(b) >= 16#61# and unsigned(b) <= 16#7A# then
      return std_logic_vector(unsigned(b) - 32);
    else
      return b;
    end if;
  end function;

begin

  -- ---- the two pins: drive only the chosen TX pin, leave the other as input
  pin_g1 <= tx_line when tx_on_g1 = '1' else 'Z';
  pin_f2 <= tx_line when tx_on_f2 = '1' else 'Z';

  u_rx_f2 : entity work.uart_rx
    generic map (CLKS_PER_BIT => CLKS_PER_BIT)
    port map (clk => clk, rx => pin_f2, data => rxf_data, valid => rxf_valid);

  u_rx_g1 : entity work.uart_rx
    generic map (CLKS_PER_BIT => CLKS_PER_BIT)
    port map (clk => clk, rx => pin_g1, data => rxg_data, valid => rxg_valid);

  u_tx : entity work.uart_tx
    generic map (CLKS_PER_BIT => CLKS_PER_BIT)
    port map (clk => clk, data => tx_data, start => tx_start, tx => tx_line, busy => tx_busy);

  u_btn : entity work.debounce
    port map (clk => clk, btn_in => btn_send, level => open, pressed => send_p);

  process(clk)
  begin
    if rising_edge(clk) then
      tx_start <= '0';
      pc_valid <= '0';

      -- 1) listen on both pins. A pin we are transmitting on hears our own
      --    bytes, so it is ignored once it has been chosen as the TX pin.
      if rxf_valid = '1' and tx_on_f2 = '0' then
        cnt_f2   <= cnt_f2 + 1;
        pc_valid <= '1';
        pc_data  <= rxf_data;
        if tx_on_g1 = '0' then          -- first byte ever, and it came on F2
          tx_on_g1    <= '1';           -- -> the PC listens on G1
          msg_request <= '1';
        end if;
      elsif rxg_valid = '1' and tx_on_g1 = '0' then
        cnt_g1   <= cnt_g1 + 1;
        pc_valid <= '1';
        pc_data  <= rxg_data;
        if tx_on_f2 = '0' then          -- first byte ever, and it came on G1
          tx_on_f2    <= '1';           -- -> the PC listens on F2
          msg_request <= '1';
        end if;
      end if;

      -- 2) queue the echo of a byte from the PC
      if pc_valid = '1' then
        echo_byte    <= upper(pc_data);
        echo_pending <= '1';
        if pc_data = x"0D" then
          lf_pending <= '1';
        end if;
      end if;

      -- 3) status line: on the button, and every 3 seconds
      if timer = TICKS_3S - 1 then
        timer       <= 0;
        msg_request <= '1';
      else
        timer <= timer + 1;
      end if;
      if send_p = '1' then
        msg_request <= '1';
      end if;
      if msg_request = '1' and msg_active = '0' then
        msg_request <= '0';
        msg_active  <= '1';
        msg_pos     <= 0;
      end if;

      -- 4) transmitter free and a direction is known: send the next byte
      if tx_busy = '0' and tx_start = '0' and (tx_on_g1 = '1' or tx_on_f2 = '1') then
        if echo_pending = '1' then
          tx_data      <= echo_byte;
          tx_start     <= '1';
          echo_pending <= '0';
        elsif lf_pending = '1' then
          tx_data    <= x"0A";
          tx_start   <= '1';
          lf_pending <= '0';
        elsif msg_active = '1' then
          if msg_pos < MSG_LEN then
            if tx_on_g1 = '1' then
              tx_data <= to_byte(MSG_G1(msg_pos + 1));
            else
              tx_data <= to_byte(MSG_F2(msg_pos + 1));
            end if;
          elsif msg_pos = MSG_LEN then
            tx_data <= x"0D";
          else
            tx_data <= x"0A";
          end if;
          tx_start <= '1';
          if msg_pos = MSG_LEN + 1 then
            msg_active <= '0';
          else
            msg_pos <= msg_pos + 1;
          end if;
        end if;
      end if;
    end if;
  end process;

  -- display: F2 count . G1 count, plus a dot on the side that transmits
  g3 <= hex7(std_logic_vector(cnt_f2(7 downto 4)));
  g2 <= hex7(std_logic_vector(cnt_f2(3 downto 0)));
  g1 <= hex7(std_logic_vector(cnt_g1(7 downto 4)));
  g0 <= hex7(std_logic_vector(cnt_g1(3 downto 0)));
  dots <= tx_on_g1 & '1' & '0' & tx_on_f2;

  u_seg : entity work.seg7_scan
    port map (clk => clk, d3 => g3, d2 => g2, d1 => g1, d0 => g0,
              dp => dots, seg_n => seg_n, dig => dig);

end architecture;
