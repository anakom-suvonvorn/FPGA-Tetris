-- ============================================================================
-- tb_chaos.vhd  -  the CHAOS layer: tasks, attacks over the link, effects
--
--   chaos_task (board A)  --send_attack-->  versus_link A  ~~wire~~>
--   versus_link B  --got_attack-->  chaos_fx (board B)
--
-- A "solver" process plays the tasks on board A like a person would, by
-- moving the 8 task switches:
--   FLIP    toggle the wanted switch 10 times
--   MATCH / BINARY / HEX   set the switches to the target
--   HANDS   don't touch anything (just wait)
--   HOLD    switch on when the bar is below the middle of the zone, else off
--   TIMING  flip the switch when the marker is inside the zone
-- Fast frame ticks (every 100 clocks) and a fast link (8 clocks per bit).
--
-- Checks:
--   * every task that starts is solved (task_ok, never task_fail)
--   * all 7 task types came up at least once
--   * every attack sent by A arrives at B with the same number, and turns
--     on the matching effect output of B's chaos_fx (or the pulse for
--     instant ones); every bonus on A turns on A's effect
--   * LOCK: B's buttons get locked, B's chaos_task starts a task at once
--     (hurry), and when B's little solver finishes it, B is unlocked.
--     B's tasks are always MATCH (FORCE_TASK) so its solver is one line.
--
-- Run with:  tools\sim.bat tb_chaos
-- ============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.chaos_pkg.all;

entity tb_chaos is
end entity;

architecture sim of tb_chaos is
  constant TICK_EVERY : integer := 100;
  constant N_RUNS     : integer := 30;

  signal clk        : std_logic := '0';
  signal done       : boolean := false;
  signal frame_tick : std_logic := '0';
  signal sw         : std_logic_vector(7 downto 0) := (others => '0');
  signal line_ab, line_ba : std_logic;

  -- board A task
  signal active, t_start, t_ok, t_fail, t_send, t_bonus : std_logic;
  signal task       : integer range 0 to N_TASKS - 1;
  signal sel        : integer range 0 to 7;
  signal target     : std_logic_vector(7 downto 0);
  signal count      : integer range 0 to 15;
  signal meter, zlo, zhi, prog : integer range 0 to 191;
  signal secs       : integer range 0 to 31;
  signal att_id     : integer range 0 to N_ATTACKS - 1;
  signal att_id31   : integer range 0 to 31;
  signal bon_id     : integer range 0 to 2;

  -- links
  signal link_a, link_b, b_got_att : std_logic;
  signal b_got_id   : integer range 0 to 31;

  -- effects on A (bonuses) and on B (attacks)
  signal a_freeze, a_sink, a_next_i : std_logic;
  signal b_mirror, b_flip, b_blind, b_bounce, b_cat, b_speed : std_logic;
  signal b_garb, b_next_bad, b_ban_on : std_logic;
  signal b_ban_id   : integer range 0 to 31;

  -- board B's own task (only used by the LOCK attack)
  signal b_locked, b_active, b_t_ok : std_logic;
  signal b_target, b_sw : std_logic_vector(7 downto 0) := (others => '0');
  signal b_starts   : integer := 0;
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

  att_id31 <= att_id;

  u_task : entity work.chaos_task
    generic map (FIRST_DELAY => 20)
    port map (clk => clk, frame_tick => frame_tick, enable => '1', paused => '0',
              versus => link_a, hurry => '0', sw => sw, touch => '0',
              active => active, task => task, sel => sel, target => target, count => count,
              meter_pos => meter, zone_lo => zlo, zone_hi => zhi, progress => prog, secs => secs,
              hands_secs => open, task_start => t_start, task_ok => t_ok, task_fail => t_fail,
              send_attack => t_send, attack_id => att_id, bonus => t_bonus, bonus_id => bon_id);

  u_fx_a : entity work.chaos_fx
    port map (clk => clk, frame_tick => frame_tick, enable => '1', paused => '0',
              got_attack => '0', got_id => 0, sent_attack => t_send, sent_id => att_id,
              bonus => t_bonus, bonus_id => bon_id, task_ok => t_ok, task_fail => t_fail,
              mirror => open, flip => open, blind => open, bounce => open, n_bounce => open,
              cat => open, speed => open, freeze => a_freeze, locked => open,
              garbage => open, next_bad => open,
              next_i => a_next_i, sink => a_sink, hit_evt => open, oiia_evt => open,
              banner_on => open, banner_id => open);

  u_link_a : entity work.versus_link
    generic map (CLKS_PER_BIT => 8)
    port map (clk => clk, frame_tick => frame_tick, rx => line_ba, tx => line_ab,
              send_start => '0', send_lost => '0', send_garbage => '0', garbage_n => 0,
              my_height => 0, send_attack => t_send, attack_id => att_id31,
              got_start => open, got_lost => open, got_garbage => open, got_n => open,
              opp_height => open, got_attack => open, got_attack_id => open, link_ok => link_a);

  u_link_b : entity work.versus_link
    generic map (CLKS_PER_BIT => 8)
    port map (clk => clk, frame_tick => frame_tick, rx => line_ab, tx => line_ba,
              send_start => '0', send_lost => '0', send_garbage => '0', garbage_n => 0,
              my_height => 0, send_attack => '0', attack_id => 0,
              got_start => open, got_lost => open, got_garbage => open, got_n => open,
              opp_height => open, got_attack => b_got_att, got_attack_id => b_got_id, link_ok => link_b);

  u_fx_b : entity work.chaos_fx
    port map (clk => clk, frame_tick => frame_tick, enable => '1', paused => '0',
              got_attack => b_got_att, got_id => b_got_id, sent_attack => '0', sent_id => 0,
              bonus => '0', bonus_id => 0, task_ok => b_t_ok, task_fail => '0',
              mirror => b_mirror, flip => b_flip, blind => b_blind, bounce => b_bounce,
              n_bounce => open, cat => b_cat, speed => b_speed, freeze => open,
              locked => b_locked, garbage => b_garb,
              next_bad => b_next_bad, next_i => open, sink => open, hit_evt => open,
              oiia_evt => open, banner_on => b_ban_on, banner_id => b_ban_id);

  -- B's task: never comes by itself (long first wait), only when locked
  u_task_b : entity work.chaos_task
    generic map (FIRST_DELAY => 1000, FORCE_TASK => T_MATCH)
    port map (clk => clk, frame_tick => frame_tick, enable => '1', paused => '0',
              versus => '0', hurry => b_locked, sw => b_sw, touch => '0',
              active => b_active, task => open, sel => open, target => b_target, count => open,
              meter_pos => open, zone_lo => open, zone_hi => open, progress => open, secs => open,
              hands_secs => open, task_start => open, task_ok => b_t_ok, task_fail => open,
              send_attack => open, attack_id => open, bonus => open, bonus_id => open);

  -- B's solver: copy the target a little after a task starts
  solver_b : process
  begin
    wait until rising_edge(clk) and b_active = '1';
    b_starts <= b_starts + 1;
    for k in 1 to 50 loop wait until rising_edge(clk); end loop;
    b_sw <= b_target;
    wait until b_active = '0';
  end process;

  -- ------------------------------------------------------------ the solver
  solver : process
    variable flips : integer;
    variable was_in : boolean;
  begin
    wait until rising_edge(clk) and t_start = '1';
    loop
      -- wait for the task's values to settle (they are set in the same clock)
      wait until rising_edge(clk);
      wait until rising_edge(clk);
      case task is
        when T_FLIP =>
          for i in 1 to 10 loop
            for k in 1 to 30 loop wait until rising_edge(clk); end loop;
            sw(sel) <= not sw(sel);
          end loop;
        when T_MATCH | T_BINARY | T_HEX =>
          for k in 1 to 200 loop wait until rising_edge(clk); end loop;
          sw <= target;
        when T_HANDS =>
          null;                                     -- just don't touch
        when T_HOLD =>
          while active = '1' loop
            wait until rising_edge(clk) and frame_tick = '1';
            if meter < (zlo + zhi) / 2 then sw(sel) <= '1'; else sw(sel) <= '0'; end if;
          end loop;
        when others =>                              -- T_TIMING
          was_in := false;
          while active = '1' loop
            wait until rising_edge(clk);
            if meter >= zlo + 4 and meter < zhi - 4 then
              if not was_in then
                sw(sel) <= not sw(sel);             -- one flip per pass through the zone
                was_in := true;
              end if;
            else
              was_in := false;
            end if;
          end loop;
      end case;
      if active = '1' then
        wait until active = '0';
      end if;
      wait until rising_edge(clk) and t_start = '1';
    end loop;
  end process;

  -- ------------------------------------------------------------ the referee
  referee : process
    type seen_t is array (0 to N_TASKS - 1) of integer;
    variable seen   : seen_t := (others => 0);
    variable errors : integer := 0;
    variable n_att, n_bon : integer := 0;
    variable id     : integer;
    variable effect_seen : boolean;
  begin
    for run in 1 to N_RUNS loop
      wait until rising_edge(clk) and t_start = '1';
      wait until rising_edge(clk);
      seen(task) := seen(task) + 1;
      wait until rising_edge(clk) and (t_ok = '1' or t_fail = '1');
      if t_fail = '1' then
        report "task " & integer'image(task) & " FAILED (the solver should always win)" severity error;
        errors := errors + 1;
      elsif t_send = '1' then
        n_att := n_att + 1;
        id := att_id;
        -- the attack must arrive at B with the same number, and act there
        wait until rising_edge(clk) and b_got_att = '1';
        if b_got_id /= id then
          report "attack " & integer'image(id) & " arrived as " & integer'image(b_got_id) severity error;
          errors := errors + 1;
        end if;
        wait until rising_edge(clk);
        case id is
          when A_MIRROR  => effect_seen := b_mirror = '1';
          when A_FLIP    => effect_seen := b_flip = '1';
          when A_BLIND   => effect_seen := b_blind = '1';
          when A_BOUNCE  => effect_seen := b_bounce = '1';
          when A_OIIA    => effect_seen := b_cat = '1';
          when A_SPEED   => effect_seen := b_speed = '1';
          when A_GARBAGE => effect_seen := b_garb = '1';
          when A_LOCK    => effect_seen := b_locked = '1';
          when others    => effect_seen := b_next_bad = '1';
        end case;
        if not effect_seen or b_ban_on = '0' or b_ban_id /= id then
          report "attack " & integer'image(id) & ": effect / banner missing on board B" severity error;
          errors := errors + 1;
        else
          report "task " & integer'image(task) & " solved -> attack " & integer'image(id) & " hit board B";
        end if;
        if id = A_LOCK then
          -- B must get a task right away, solve it, and be unlocked
          wait until b_locked = '0' for 100 us;
          if b_locked = '1' then
            report "LOCK: board B never got unlocked" severity error;
            errors := errors + 1;
          else
            report "LOCK: B got a task at once, solved it, unlocked (B tasks so far: " &
                   integer'image(b_starts) & ")";
          end if;
        end if;
      else
        n_bon := n_bon + 1;
        id := bon_id;
        wait until rising_edge(clk);
        case id is
          when B_FREEZE => effect_seen := a_freeze = '1';
          when B_SINK   => effect_seen := true;    -- the pulse was in the previous clock
          when others   => effect_seen := true;
        end case;
        if not effect_seen then
          report "bonus " & integer'image(id) & " had no effect" severity error;
          errors := errors + 1;
        else
          report "task " & integer'image(task) & " solved -> bonus " & integer'image(id);
        end if;
      end if;
    end loop;
    for k in 0 to N_TASKS - 1 loop
      if seen(k) = 0 then
        report "task type " & integer'image(k) & " never came up" severity warning;
      end if;
    end loop;
    report integer'image(N_RUNS) & " tasks: " & integer'image(n_att) & " attacks, " &
           integer'image(n_bon) & " bonuses";
    if errors = 0 then report "TEST PASSED"; else report "TEST FAILED" severity error; end if;
    done <= true;
    wait;
  end process;

end architecture;
