-- ============================================================================
-- tb_uart_probe.vhd  -  simulation test for tests\05_uart_probe
--
-- Pretends to be the PC's USB chip, wired either the way the manual says
-- (PATTERN = 0: PC sends on F2, listens on G1) or swapped (PATTERN = 1).
-- Sends 'a' and checks that the design answers on the right pin with
-- 'A' (the echo) followed by 'F' (first letter of the status line).
--
-- Run it with:  tools\sim.bat tb_uart_probe 0     and     tools\sim.bat tb_uart_probe 1
-- ============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_uart_probe is
  generic (PATTERN : integer range 0 to 1 := 0);   -- 0 = as manual, 1 = swapped
end entity;

architecture sim of tb_uart_probe is
  constant CPB : integer := 434;

  signal clk      : std_logic := '0';
  signal done     : boolean := false;
  signal pin_f2   : std_logic;
  signal pin_g1   : std_logic;
  signal seg_n    : std_logic_vector(7 downto 0);
  signal dig      : std_logic_vector(3 downto 0);

  -- the pretend PC
  signal pc_data   : std_logic_vector(7 downto 0) := (others => '0');
  signal pc_start  : std_logic := '0';
  signal pc_busy   : std_logic;
  signal pc_line   : std_logic;                     -- PC -> board
  signal pc_hear   : std_logic;                     -- board -> PC
  signal got_data  : std_logic_vector(7 downto 0);
  signal got_valid : std_logic;
begin

  clk <= not clk after 10 ns when not done else clk;

  dut : entity work.top_uart_probe
    port map (clk => clk, pin_f2 => pin_f2, pin_g1 => pin_g1, btn_send => '0',
              seg_n => seg_n, dig => dig);

  -- wiring: the PC drives one pin; the other pin has a pull-up ('H' = weak 1,
  -- overridden by the board when it drives)
  g_normal : if PATTERN = 0 generate
    pin_f2  <= pc_line;
    pin_g1  <= 'H';
    pc_hear <= to_x01(pin_g1);
  end generate;
  g_swapped : if PATTERN = 1 generate
    pin_g1  <= pc_line;
    pin_f2  <= 'H';
    pc_hear <= to_x01(pin_f2);
  end generate;

  u_pc_tx : entity work.uart_tx generic map (CLKS_PER_BIT => CPB)
    port map (clk => clk, data => pc_data, start => pc_start, tx => pc_line, busy => pc_busy);

  u_pc_rx : entity work.uart_rx generic map (CLKS_PER_BIT => CPB)
    port map (clk => clk, rx => pc_hear, data => got_data, valid => got_valid);

  stim : process
  begin
    wait for 1 us;
    wait until rising_edge(clk);
    pc_data  <= x"61";                -- 'a'
    pc_start <= '1';
    wait until rising_edge(clk);
    pc_start <= '0';
    wait;
  end process;

  check : process
    type bytes_t is array (0 to 1) of std_logic_vector(7 downto 0);
    constant EXPECT : bytes_t := (x"41", x"46");   -- 'A', 'F'
    variable errors : integer := 0;
  begin
    for i in EXPECT'range loop
      wait until rising_edge(clk) and got_valid = '1';
      if got_data = EXPECT(i) then
        report "reply byte " & integer'image(i) & " ok: " &
               integer'image(to_integer(unsigned(got_data)));
      else
        report "reply byte " & integer'image(i) & " WRONG: got " &
               integer'image(to_integer(unsigned(got_data))) severity error;
        errors := errors + 1;
      end if;
    end loop;
    if errors = 0 then
      report "TEST PASSED (PATTERN " & integer'image(PATTERN) & "): the board answered on the right pin";
    else
      report "TEST FAILED" severity error;
    end if;
    done <= true;
    wait;
  end process;

  -- the board must never drive the PC's transmit pin
  guard : process(clk)
  begin
    if rising_edge(clk) then
      if PATTERN = 0 and pin_f2 = 'X' then
        report "CONFLICT on F2: both the PC and the board drive it" severity error;
      elsif PATTERN = 1 and pin_g1 = 'X' then
        report "CONFLICT on G1: both the PC and the board drive it" severity error;
      end if;
    end if;
  end process;

end architecture;
