-- ============================================================================
-- tb_chaos_core.vhd  -  the chaos effects inside tetris_core
--
-- Drops a few pieces (hard drop at the spawn spot) to build a small stack,
-- then tries each effect input and checks what it did:
--   fx_next_i   -> the next piece is an I            (next_color = 0)
--   fx_next_bad -> the next piece is an S or a Z     (next_color = 3 or 4)
--   fx_freeze   -> the falling piece does not fall for 2 s worth of frames
--   fx_speed    -> it falls much faster than normal
--   fx_sink     -> right away (no lock needed), the 2 bottom rows are gone:
--                  cells = before - cells in rows 18, 19
-- Run with:  tools\sim.bat tb_chaos_core
-- ============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.tetris_pkg.all;

entity tb_chaos_core is
end entity;

architecture sim of tb_chaos_core is
  constant TICK_EVERY : integer := 200;
  signal clk        : std_logic := '0';
  signal done       : boolean := false;
  signal frame_tick : std_logic := '0';
  signal a_hard, a_left : std_logic := '0';
  signal fz, sp, nb, ni, sk : std_logic := '0';
  signal occ        : occ_field_t;
  signal next_color : color_t;
  signal cur_y      : ypos_t;
  signal playing    : std_logic;
  signal clear_evt  : std_logic;

  function count_cells(o : occ_field_t; r0, r1 : integer) return integer is
    variable n : integer := 0;
  begin
    for r in r0 to r1 loop
      for c in 0 to COLS - 1 loop
        if o(r)(c) = '1' then n := n + 1; end if;
      end loop;
    end loop;
    return n;
  end function;
begin

  clk <= not clk after 10 ns when not done else clk;

  process(clk)
    variable n : integer := 0;
  begin
    if rising_edge(clk) then
      frame_tick <= '0';
      if n = TICK_EVERY - 1 then n := 0; frame_tick <= '1'; else n := n + 1; end if;
    end if;
  end process;

  dut : entity work.tetris_core
    port map (
      clk => clk, frame_tick => frame_tick, pause => '0',
      act_left => a_left, act_right => '0', act_rot => '0', act_soft => '0', act_hard => a_hard,
      versus => '0', start_in => '0', garb_in => '0', garb_in_n => 0, opp_lost => '0',
      start_out => open, lost_out => open, garb_out => open, garb_out_n => open,
      height => open, pending => open, result => open,
      fx_freeze => fz, fx_speed => sp, fx_next_bad => nb, fx_next_i => ni, fx_sink => sk,
      occ => occ, colf => open, cur_shape => open, cur_color => open, cur_x => open,
      cur_y => cur_y, ghost_y => open, next_shape => open, next_color => next_color,
      playing => playing, game_over => open, lines_bcd => open, level => open,
      clear_evt => clear_evt, clear_n => open);

  test : process
    variable errors : integer := 0;
    variable y0, y1, before, bottom : integer;

    procedure pulse(signal s : out std_logic) is
    begin
      wait until rising_edge(clk); s <= '1';
      wait until rising_edge(clk); s <= '0';
    end procedure;

    procedure frames(n : integer) is
    begin
      for i in 1 to n loop wait until rising_edge(clk) and frame_tick = '1'; end loop;
    end procedure;

    procedure drop_piece is
    begin
      pulse(a_hard);
      wait until rising_edge(clk) and clear_evt = '1';
      frames(3);
    end procedure;
  begin
    wait for 1 us;
    pulse(a_hard);                                  -- start
    wait until rising_edge(clk) and playing = '1';
    frames(3);
    for i in 1 to 3 loop
      pulse(a_left);                                -- spread the stack a little
      frames(2);
      drop_piece;
    end loop;

    -- I piece next
    pulse(ni);
    wait until rising_edge(clk);
    if to_integer(unsigned(next_color)) /= 0 then
      report "fx_next_i: next is not an I" severity error; errors := errors + 1;
    else report "fx_next_i ok: next piece is I"; end if;

    -- cursed next
    pulse(nb);
    wait until rising_edge(clk);
    if to_integer(unsigned(next_color)) /= 3 and to_integer(unsigned(next_color)) /= 4 then
      report "fx_next_bad: next is not S/Z" severity error; errors := errors + 1;
    else report "fx_next_bad ok: next piece is " & integer'image(to_integer(unsigned(next_color))); end if;

    -- freeze: 120 frames without falling (level 0 normally falls every 48)
    fz <= '1';
    y0 := cur_y;
    frames(120);
    y1 := cur_y;
    fz <= '0';
    if y1 /= y0 then
      report "fx_freeze: piece moved from " & integer'image(y0) & " to " & integer'image(y1) severity error;
      errors := errors + 1;
    else report "fx_freeze ok: piece stayed at row " & integer'image(y0); end if;

    -- speed: in 48 frames the piece must fall several rows (normally 1)
    sp <= '1';
    y0 := cur_y;
    frames(48);
    y1 := cur_y;
    sp <= '0';
    if y1 - y0 < 3 then
      report "fx_speed: only fell " & integer'image(y1 - y0) & " rows" severity error;
      errors := errors + 1;
    else report "fx_speed ok: fell " & integer'image(y1 - y0) & " rows in 48 frames"; end if;

    -- sink: 2 bottom rows gone at once, while the piece is still falling
    before := count_cells(occ, 0, ROWS - 1);
    bottom := count_cells(occ, ROWS - 2, ROWS - 1);
    pulse(sk);
    for k in 1 to 20 loop wait until rising_edge(clk); end loop;
    if count_cells(occ, 0, ROWS - 1) /= before - bottom then
      report "fx_sink: " & integer'image(count_cells(occ, 0, ROWS - 1)) & " cells, expected " &
             integer'image(before - bottom) severity error;
      errors := errors + 1;
    else report "fx_sink ok: " & integer'image(bottom) & " cells of the bottom 2 rows removed"; end if;

    if errors = 0 then report "TEST PASSED"; else report "TEST FAILED" severity error; end if;
    done <= true;
    wait;
  end process;

end architecture;
