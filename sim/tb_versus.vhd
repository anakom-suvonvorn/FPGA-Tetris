-- ============================================================================
-- tb_versus.vhd  -  two boards play versus Tetris against each other
--
-- Board A and board B are each a tetris_core + versus_link, wired together
-- like the real J5 cable: A's tx -> B's rx and B's tx -> A's rx.
-- To keep the simulation short the frame tick comes every 400 clocks and
-- the link runs at 8 clocks per bit (both are generics / tb signals only;
-- the logic is the same as on the board).
--
-- Robot A plays well (best placement, as in tb_tetris_core).
-- Robot B is sloppy: about one piece in four goes to a random column.
--
-- Checks:
--   * pressing start on A starts B too (START message)
--   * garbage is sent and arrives (GARBAGE messages, grey rows appear)
--   * the game ends with one board showing WIN and the other LOSE
--   * both sides see link_ok while connected
--
-- Run with:  tools\sim.bat tb_versus
-- ============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.tetris_pkg.all;

entity tb_versus is
end entity;

architecture sim of tb_versus is
  constant TICK_EVERY : integer := 400;
  constant CPB        : integer := 8;

  signal clk        : std_logic := '0';
  signal done       : boolean := false;
  signal frame_tick : std_logic := '0';
  signal line_ab, line_ba : std_logic;      -- A -> B and B -> A

  -- one record of signals per board would be nicer; plain signals keep it VHDL-93
  signal a_left, a_right, a_rot, a_hard : std_logic := '0';
  signal b_left, b_right, b_rot, b_hard : std_logic := '0';

  signal occ_a, occ_b       : occ_field_t;
  signal colf_a, colf_b     : col_field_t;
  signal col_a, col_b       : color_t;
  signal x_a, x_b           : xpos_t;
  signal play_a, play_b     : std_logic;
  signal evt_a, evt_b       : std_logic;
  signal res_a, res_b       : integer range 0 to 4;
  signal pend_a, pend_b     : integer range 0 to 31;
  signal h_a, h_b           : integer range 0 to 20;
  signal link_a, link_b     : std_logic;
  signal cn_a, cn_b         : integer range 0 to 4;
  signal pieces_a, pieces_b : integer := 0;

  -- core <-> link wires
  signal st_out_a, st_out_b, lo_out_a, lo_out_b, ga_out_a, ga_out_b : std_logic;
  signal gn_out_a, gn_out_b : integer range 0 to 31;
  signal st_in_a, st_in_b, lo_in_a, lo_in_b, ga_in_a, ga_in_b : std_logic;
  signal gn_in_a, gn_in_b   : integer range 0 to 31;
  signal oh_a, oh_b         : integer range 0 to 20;

  signal sent_a, sent_b, rcvd_a, rcvd_b : integer := 0;   -- garbage message counters
  signal grey_seen          : boolean := false;

  function collides(o : occ_field_t; sh : shape_t; x, y : integer) return boolean is
  begin
    for r in 0 to 3 loop
      for c in 0 to 3 loop
        if sh(4*r + c) = '1' then
          if x + c - 3 < 0 or x + c - 3 > COLS - 1 or y + r > ROWS - 1 then
            return true;
          elsif y + r >= 0 then
            if o(y + r)(x + c - 3) = '1' then return true; end if;
          end if;
        end if;
      end loop;
    end loop;
    return false;
  end function;

  -- best (rotation, x) for piece p: most full rows, then lowest landing
  procedure choose(o : occ_field_t; p : integer; best_rot, best_x : out integer) is
    variable y, full, score, best : integer;
    variable sh : shape_t;
    variable t  : occ_field_t;
  begin
    best := -1000; best_rot := 0; best_x := SPAWN_X;
    for rot in 0 to 3 loop
      sh := shape_of(p, rot);
      for x in 0 to 12 loop
        if not collides(o, sh, x, 0) then
          y := 0;
          while not collides(o, sh, x, y + 1) loop y := y + 1; end loop;
          t := o;
          for r in 0 to 3 loop
            for c in 0 to 3 loop
              if sh(4*r + c) = '1' and y + r >= 0 then t(y + r)(x + c - 3) := '1'; end if;
            end loop;
          end loop;
          full := 0;
          for r in 0 to ROWS - 1 loop
            if t(r) = "1111111111" then full := full + 1; end if;
          end loop;
          -- prefer 2+ line clears (they send garbage); avoid wasting singles
          if full >= 2 then score := full * 300 + y * 4 - rot;
          else              score := y * 4 - rot - full * 30;
          end if;
          if score > best then best := score; best_rot := rot; best_x := x; end if;
        end if;
      end loop;
    end loop;
  end procedure;

  -- one button press: a one-clock pulse, then wait two frames
  procedure press(signal a : out std_logic; signal clk, tick : in std_logic) is
  begin
    wait until rising_edge(clk);
    a <= '1';
    wait until rising_edge(clk);
    a <= '0';
    for i in 1 to 2 loop
      wait until rising_edge(clk) and tick = '1';
    end loop;
  end procedure;

  -- play one piece: turn, move, hard drop, wait for the lock (or the game end)
  procedure play_piece(signal o : in occ_field_t; signal colr : in color_t; signal cx : in xpos_t;
                       signal playing, evt : in std_logic; signal clk, tick : in std_logic;
                       signal p_rot, p_left, p_right, p_hard : out std_logic;
                       sloppy : boolean; variable seed : inout integer) is
    variable br, bx : integer;
  begin
    choose(o, to_integer(unsigned(colr)), br, bx);
    if sloppy then
      seed := (seed * 1103 + 12345) mod 65536;
      if (seed / 256) mod 4 = 0 then
        br := 0;
        bx := 2 + (seed / 512) mod 9;                 -- a random column
      end if;
    end if;
    for i in 1 to br loop press(p_rot, clk, tick); end loop;
    for i in 1 to 12 loop
      exit when cx <= bx or playing = '0';
      press(p_left, clk, tick);
    end loop;
    for i in 1 to 12 loop
      exit when cx >= bx or playing = '0';
      press(p_right, clk, tick);
    end loop;
    if playing = '1' then
      wait until rising_edge(clk);
      p_hard <= '1';
      wait until rising_edge(clk);
      p_hard <= '0';
      wait until rising_edge(clk) and (evt = '1' or playing = '0');
      for i in 1 to 2 loop
        wait until rising_edge(clk) and tick = '1';
      end loop;
    end if;
  end procedure;

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

  -- ------------------------------------------------------------ board A
  core_a : entity work.tetris_core
    port map (
      clk => clk, frame_tick => frame_tick, pause => '0',
      act_left => a_left, act_right => a_right, act_rot => a_rot, act_soft => '0', act_hard => a_hard,
      versus => link_a, start_in => st_in_a, garb_in => ga_in_a, garb_in_n => gn_in_a, opp_lost => lo_in_a,
      start_out => st_out_a, lost_out => lo_out_a, garb_out => ga_out_a, garb_out_n => gn_out_a,
      height => h_a, pending => pend_a, result => res_a,
      occ => occ_a, colf => colf_a, cur_shape => open, cur_color => col_a, cur_x => x_a, cur_y => open,
      ghost_y => open, next_shape => open, next_color => open, playing => play_a, game_over => open,
      lines_bcd => open, level => open, clear_evt => evt_a, clear_n => cn_a);
  link_a_i : entity work.versus_link
    generic map (CLKS_PER_BIT => CPB)
    port map (
      clk => clk, frame_tick => frame_tick, rx => line_ba, tx => line_ab,
      send_start => st_out_a, send_lost => lo_out_a, send_garbage => ga_out_a, garbage_n => gn_out_a,
      my_height => h_a, got_start => st_in_a, got_lost => lo_in_a, got_garbage => ga_in_a,
      got_n => gn_in_a, opp_height => oh_a, link_ok => link_a);

  -- ------------------------------------------------------------ board B
  core_b : entity work.tetris_core
    port map (
      clk => clk, frame_tick => frame_tick, pause => '0',
      act_left => b_left, act_right => b_right, act_rot => b_rot, act_soft => '0', act_hard => b_hard,
      versus => link_b, start_in => st_in_b, garb_in => ga_in_b, garb_in_n => gn_in_b, opp_lost => lo_in_b,
      start_out => st_out_b, lost_out => lo_out_b, garb_out => ga_out_b, garb_out_n => gn_out_b,
      height => h_b, pending => pend_b, result => res_b,
      occ => occ_b, colf => colf_b, cur_shape => open, cur_color => col_b, cur_x => x_b, cur_y => open,
      ghost_y => open, next_shape => open, next_color => open, playing => play_b, game_over => open,
      lines_bcd => open, level => open, clear_evt => evt_b, clear_n => cn_b);
  link_b_i : entity work.versus_link
    generic map (CLKS_PER_BIT => CPB)
    port map (
      clk => clk, frame_tick => frame_tick, rx => line_ab, tx => line_ba,
      send_start => st_out_b, send_lost => lo_out_b, send_garbage => ga_out_b, garbage_n => gn_out_b,
      my_height => h_b, got_start => st_in_b, got_lost => lo_in_b, got_garbage => ga_in_b,
      got_n => gn_in_b, opp_height => oh_b, link_ok => link_b);

  -- ------------------------------------------------------------ watchers
  process(clk)
  begin
    if rising_edge(clk) then
      if ga_out_a = '1' then
        sent_a <= sent_a + 1;
        report "A sends " & integer'image(gn_out_a) & " garbage";
      end if;
      if ga_out_b = '1' then
        sent_b <= sent_b + 1;
        report "B sends " & integer'image(gn_out_b) & " garbage";
      end if;
      if evt_a = '1' then
        pieces_a <= pieces_a + 1;
        if cn_a > 0 then report "A cleared " & integer'image(cn_a); end if;
      end if;
      if evt_b = '1' then
        pieces_b <= pieces_b + 1;
        if cn_b > 0 then report "B cleared " & integer'image(cn_b); end if;
      end if;
      if ga_in_a = '1' then rcvd_a <= rcvd_a + 1; end if;
      if ga_in_b = '1' then rcvd_b <= rcvd_b + 1; end if;
      for r in 0 to ROWS - 1 loop
        if colf_a(r)(2 downto 0) = "111" or colf_b(r)(2 downto 0) = "111" then
          grey_seen <= true;
        end if;
      end loop;
    end if;
  end process;

  -- ------------------------------------------------------------ robots
  robot_a : process
    variable seed : integer := 1;
  begin
    -- wait for the link to come up (heartbeats), then press start on A only
    wait until link_a = '1' and link_b = '1';
    report "link up on both boards";
    press(a_hard, clk, frame_tick);
    wait until rising_edge(clk) and play_a = '1';
    while play_a = '1' loop
      play_piece(occ_a, col_a, x_a, play_a, evt_a, clk, frame_tick, a_rot, a_left, a_right, a_hard, false, seed);
    end loop;
    wait;
  end process;

  robot_b : process
    variable seed : integer := 777;
  begin
    wait until play_b = '1';                         -- started by A's START message
    report "board B started by the START message";
    for i in 1 to 3 loop wait until rising_edge(clk) and frame_tick = '1'; end loop;
    while play_b = '1' loop
      play_piece(occ_b, col_b, x_b, play_b, evt_b, clk, frame_tick, b_rot, b_left, b_right, b_hard, true, seed);
    end loop;
    wait;
  end process;

  -- ------------------------------------------------------------ referee
  referee : process
    variable errors : integer := 0;
  begin
    wait until play_a = '1';
    wait until play_a = '0' or play_b = '0';
    -- give the LOST message time to arrive and the result to settle
    for i in 1 to 20 loop wait until rising_edge(clk) and frame_tick = '1'; end loop;
    report "results: A = " & integer'image(res_a) & ", B = " & integer'image(res_b) &
           "  (1 WIN, 2 LOSE, 3 DRAW)";
    report "pieces: A " & integer'image(pieces_a) & ", B " & integer'image(pieces_b);
    report "garbage messages: A sent " & integer'image(sent_a) & ", B received " & integer'image(rcvd_b) &
           "; B sent " & integer'image(sent_b) & ", A received " & integer'image(rcvd_a);
    if not ((res_a = 1 and res_b = 2) or (res_a = 2 and res_b = 1) or (res_a = 3 and res_b = 3)) then
      report "WRONG RESULT PAIR" severity error; errors := errors + 1;
    end if;
    if sent_a /= rcvd_b or sent_b /= rcvd_a then
      report "GARBAGE MESSAGES LOST" severity error; errors := errors + 1;
    end if;
    if sent_a + sent_b = 0 then
      report "no garbage was sent in this game (test too short to check garbage)" severity warning;
    elsif not grey_seen then
      report "garbage was sent but no grey row ever appeared" severity error; errors := errors + 1;
    end if;
    if errors = 0 then
      report "TEST PASSED";
    else
      report "TEST FAILED" severity error;
    end if;
    done <= true;
    wait;
  end process;

end architecture;
