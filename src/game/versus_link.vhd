-- ============================================================================
-- versus_link.vhd
-- The conversation between the two boards, over one serial wire each way
-- (the same uart_tx / uart_rx that test 04 used on J5).
--
-- MESSAGES: one byte each = 3-bit type + 5-bit value
--
--     bit  7 6 5 | 4 3 2 1 0
--          type  |  value
--
--   type 0  HEARTBEAT  value = my stack height (0..20). Sent 10 times a second.
--                      Proves the cable works; the other side shows the height.
--   type 1  GARBAGE    value = number of garbage lines to add (1..31)
--   type 2  LOST       I topped out (value unused)
--   type 3  START      I started a new round, start yours too
--   type 4  ATTACK     value = chaos attack number (chaos_pkg), 0..7
--   type 5..7          free
--
-- SENDING: requests (send_* pulses) are remembered until the transmitter is
-- free, then sent in priority order START > LOST > ATTACK > GARBAGE > HEARTBEAT.
-- Garbage that is waiting adds up (2 + 4 = one message "6").
--
-- RECEIVING: each good byte is decoded into a one-clock got_* pulse.
-- link_ok = a byte arrived in the last TIMEOUT_FRAMES frames (0.5 s). If the
-- cable is pulled, link_ok drops and the game plays single player.
-- ============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity versus_link is
  generic (
    CLKS_PER_BIT   : integer := 434;
    HB_FRAMES      : integer := 6;      -- heartbeat every 6 frames (10 per second)
    TIMEOUT_FRAMES : integer := 30      -- link lost after 0.5 s of silence
  );
  port (
    clk          : in  std_logic;
    frame_tick   : in  std_logic;
    rx           : in  std_logic;
    tx           : out std_logic;
    -- requests from the game
    send_start   : in  std_logic;
    send_lost    : in  std_logic;
    send_garbage : in  std_logic;
    garbage_n    : in  integer range 0 to 31;
    my_height    : in  integer range 0 to 20;
    send_attack  : in  std_logic;
    attack_id    : in  integer range 0 to 31;
    -- what arrived
    got_start    : out std_logic;
    got_lost     : out std_logic;
    got_garbage  : out std_logic;
    got_n        : out integer range 0 to 31;
    opp_height   : out integer range 0 to 20;
    got_attack   : out std_logic;
    got_attack_id : out integer range 0 to 31;
    link_ok      : out std_logic
  );
end entity;

architecture rtl of versus_link is
  constant T_HEARTBEAT : std_logic_vector(2 downto 0) := "000";
  constant T_GARBAGE   : std_logic_vector(2 downto 0) := "001";
  constant T_LOST      : std_logic_vector(2 downto 0) := "010";
  constant T_START     : std_logic_vector(2 downto 0) := "011";
  constant T_ATTACK    : std_logic_vector(2 downto 0) := "100";

  signal tx_data  : std_logic_vector(7 downto 0) := (others => '0');
  signal tx_start : std_logic := '0';
  signal tx_busy  : std_logic;
  signal rx_data  : std_logic_vector(7 downto 0);
  signal rx_valid : std_logic;

  -- waiting to be sent
  signal start_p, lost_p, hb_p : std_logic := '0';
  signal garb_p   : integer range 0 to 31 := 0;
  signal hb_cnt   : integer range 0 to HB_FRAMES - 1 := 0;
  signal att_p    : std_logic := '0';
  signal att_id   : integer range 0 to 31 := 0;

  -- receive side
  signal silence  : integer range 0 to TIMEOUT_FRAMES := TIMEOUT_FRAMES;
  signal g_start, g_lost, g_garb : std_logic := '0';
  signal g_n      : integer range 0 to 31 := 0;
  signal opp_h    : integer range 0 to 20 := 0;
  signal g_att    : std_logic := '0';
  signal g_att_id : integer range 0 to 31 := 0;

  function msg(t : std_logic_vector(2 downto 0); v : integer) return std_logic_vector is
  begin
    return t & std_logic_vector(to_unsigned(v, 5));
  end function;
begin

  u_tx : entity work.uart_tx
    generic map (CLKS_PER_BIT => CLKS_PER_BIT)
    port map (clk => clk, data => tx_data, start => tx_start, tx => tx, busy => tx_busy);

  u_rx : entity work.uart_rx
    generic map (CLKS_PER_BIT => CLKS_PER_BIT)
    port map (clk => clk, rx => rx, data => rx_data, valid => rx_valid);

  process(clk)
    variable gsum : integer range 0 to 62;
  begin
    if rising_edge(clk) then
      tx_start <= '0';
      g_start  <= '0';
      g_lost   <= '0';
      g_garb   <= '0';
      g_att    <= '0';

      -- ---------------------------------------------- remember requests
      if send_start = '1' then start_p <= '1'; end if;
      if send_lost  = '1' then lost_p  <= '1'; end if;
      if send_attack = '1' then
        att_p  <= '1';
        att_id <= attack_id;
      end if;
      if frame_tick = '1' then
        if hb_cnt = HB_FRAMES - 1 then
          hb_cnt <= 0;
          hb_p   <= '1';
        else
          hb_cnt <= hb_cnt + 1;
        end if;
      end if;

      -- ---------------------------------------------- send the most important one
      gsum := garb_p;
      if tx_busy = '0' and tx_start = '0' then
        if start_p = '1' then
          tx_data  <= msg(T_START, 0);
          tx_start <= '1';
          start_p  <= '0';
        elsif lost_p = '1' then
          tx_data  <= msg(T_LOST, 0);
          tx_start <= '1';
          lost_p   <= '0';
        elsif att_p = '1' then
          tx_data  <= msg(T_ATTACK, att_id);
          tx_start <= '1';
          att_p    <= '0';
        elsif garb_p > 0 then
          tx_data  <= msg(T_GARBAGE, garb_p);
          tx_start <= '1';
          gsum     := 0;
        elsif hb_p = '1' then
          tx_data  <= msg(T_HEARTBEAT, my_height);
          tx_start <= '1';
          hb_p     <= '0';
        end if;
      end if;
      if send_garbage = '1' then                    -- add new garbage to what waits
        gsum := gsum + garbage_n;
        if gsum > 31 then gsum := 31; end if;
      end if;
      garb_p <= gsum;

      -- ---------------------------------------------- decode what arrived
      if rx_valid = '1' then
        silence <= 0;
        case rx_data(7 downto 5) is
          when T_HEARTBEAT =>
            if to_integer(unsigned(rx_data(4 downto 0))) <= 20 then
              opp_h <= to_integer(unsigned(rx_data(4 downto 0)));
            end if;
          when T_GARBAGE =>
            g_garb <= '1';
            g_n    <= to_integer(unsigned(rx_data(4 downto 0)));
          when T_LOST =>
            g_lost <= '1';
          when T_START =>
            g_start <= '1';
          when T_ATTACK =>
            g_att    <= '1';
            g_att_id <= to_integer(unsigned(rx_data(4 downto 0)));
          when others =>
            null;                                   -- reserved for later
        end case;
      elsif frame_tick = '1' and silence < TIMEOUT_FRAMES then
        silence <= silence + 1;
      end if;
    end if;
  end process;

  got_start   <= g_start;
  got_lost    <= g_lost;
  got_garbage <= g_garb;
  got_n       <= g_n;
  opp_height  <= opp_h;
  got_attack  <= g_att;
  got_attack_id <= g_att_id;
  link_ok     <= '1' when silence < TIMEOUT_FRAMES else '0';

end architecture;
