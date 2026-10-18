-- ============================================================================
-- tetris_input.vhd
-- Turns the 5 push buttons into game actions.
--
--   btn(0) left   btn(1) right   btn(2) rotate   btn(3) soft drop   btn(4) hard drop
--
-- Each button goes through debounce.vhd (sync + debounce + press pulse).
-- Then:
--   * rotate, hard drop : one action per press.
--   * left, right       : one action when pressed; if still held after
--                         DAS frames, one more every ARR frames ("auto-repeat",
--                         like holding a key on a keyboard).
--   * soft drop         : one action when pressed, then one every 2 frames
--                         while held.
-- Outputs are one-clock pulses; tetris_core remembers them until its next
-- frame.
-- ============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tetris_input is
  generic (
    DEBOUNCE_CYCLES : integer := 250_000        -- 5 ms at 50 MHz
  );
  port (
    clk        : in  std_logic;
    frame_tick : in  std_logic;
    btn        : in  std_logic_vector(4 downto 0);   -- raw pins, '1' = pressed
    act_left   : out std_logic;
    act_right  : out std_logic;
    act_rot    : out std_logic;
    act_soft   : out std_logic;
    act_hard   : out std_logic
  );
end entity;

architecture rtl of tetris_input is
  signal lvl, prs : std_logic_vector(4 downto 0);
  signal act      : std_logic_vector(4 downto 0) := (others => '0');

  -- per button: does it repeat, first delay, repeat period (in frames)
  type int5_t is array (0 to 4) of integer range 0 to 31;
  constant REPEATS : std_logic_vector(4 downto 0) := "01011";   -- soft, right, left
  constant DAS     : int5_t := (10, 10, 1, 2, 1);   -- (unused for rotate/hard)
  constant ARR     : int5_t := ( 3,  3, 1, 2, 1);
  type cnt5_t is array (0 to 4) of integer range 0 to 31;
  signal held : cnt5_t := (others => 0);        -- frames since pressed
begin

  -- five copies of the debouncer, one per button
  g_db : for i in 0 to 4 generate
    u_db : entity work.debounce
      generic map (STABLE_CYCLES => DEBOUNCE_CYCLES)
      port map (clk => clk, btn_in => btn(i), level => lvl(i), pressed => prs(i));
  end generate;

  process(clk)
  begin
    if rising_edge(clk) then
      for i in 0 to 4 loop
        act(i) <= '0';
        if prs(i) = '1' then                     -- just pressed: act now
          act(i)  <= '1';
          held(i) <= 0;
        elsif lvl(i) = '1' and REPEATS(i) = '1' and frame_tick = '1' then
          if held(i) = DAS(i) - 1 then           -- held long enough: repeat
            act(i)  <= '1';
            held(i) <= DAS(i) - ARR(i);
          else
            held(i) <= held(i) + 1;
          end if;
        end if;
      end loop;
    end if;
  end process;

  act_left  <= act(0);
  act_right <= act(1);
  act_rot   <= act(2);
  act_soft  <= act(3);
  act_hard  <= act(4);

end architecture;
