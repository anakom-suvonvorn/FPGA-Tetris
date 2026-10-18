-- ============================================================================
-- top_tetris.vhd  -  Tetris Duel, CHAOS edition (two boards, versus)
--
-- Load the same design into both boards and connect them with 3 wires on J5
-- (see game\README.md). With no second board it plays single player.
--
-- Controls (the 5 push buttons form a cross):
--
--              SW16 rotate
--   SW14 left  SW18 hard drop  SW20 right       (hold left/right to keep moving)
--              SW23 soft drop (hold)
--
--   SW18 (centre) also starts a round; in versus it starts both boards.
--
-- Slide switches:
--   SW2  pause            SW4  music on        SW5  sound effects on
--   SW22 link to the PC over USB instead of the J5 cable (test with
--        tools\fake_opponent.py, the PC plays the other board)
--   SW21 CHAOS on (tasks + attacks)
--   SW6..SW13  the task switches (SW13 = left of the panel picture, bit 7)
--
-- Versus rules: clearing 2 / 3 / 4 lines sends 1 / 2 / 4 garbage lines.
-- Lines you clear first cancel garbage waiting for you (red meter left of
-- the field). Last one standing wins.
-- CHAOS: every 10-20 s a task pops up on the right; do it with the task
-- switches before the time runs out -> attack the rival or get a bonus.
--
-- Structure (top-down design):
--   top_tetris
--     +-- vga_sync       640x480 timing, frame_tick 60 times a second
--     +-- tetris_input   buttons -> action pulses (debounce, auto-repeat)
--     +-- tetris_core    the game rules and state (garbage, win/lose, chaos effects)
--     +-- versus_link    messages to/from the other board (uart_tx/uart_rx)
--     +-- chaos_task     the slide-switch tasks
--     +-- chaos_fx       attacks / bonuses acting on me, banner
--     +-- chaos_render   task panel, banner, bouncers, cat (an overlay)
--     +-- tetris_render  game state -> pixel colours (text_layer, + overlay)
--     +-- tetris_sound   music + effects -> audio jack, buzzer
--     +-- seg7_scan      lines, or the task countdown, on the 7-segment display
-- ============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.common_pkg.all;
use work.tetris_pkg.all;
use work.chaos_pkg.all;

entity top_tetris is
  generic (
    DEBOUNCE_CYCLES   : integer := 250_000;       -- 5 ms; testbenches use less
    LINK_CLKS_PER_BIT : integer := CLKS_PER_BIT;  -- 115200 baud
    CHAOS_FIRST_DELAY : integer := 600;           -- frames until the first task
    CHAOS_FORCE_TASK  : integer := -1             -- testbenches: always this task
  );
  port (
    clk       : in  std_logic;                       -- H11
    btn_left  : in  std_logic;                       -- J14 SW14, left of the cross
    btn_rot   : in  std_logic;                       -- J13 SW16, top
    btn_hard  : in  std_logic;                       -- J12 SW18, centre
    btn_soft  : in  std_logic;                       -- L13 SW23, bottom
    btn_right : in  std_logic;                       -- J11 SW20, right
    sw_pause  : in  std_logic;                       -- K11 SW2
    sw_music  : in  std_logic;                       -- M11 SW4
    sw_sfx    : in  std_logic;                       -- N14 SW5
    sw_usb    : in  std_logic;                       -- J1  SW22
    sw_chaos  : in  std_logic;                       -- K3  SW21
    sw_task   : in  std_logic_vector(7 downto 0);    -- SW13..SW6
    link_tx   : out std_logic;                       -- L14 J5 pin 5
    link_rx   : in  std_logic;                       -- M13 J5 pin 6
    usb_tx    : out std_logic;                       -- F2  to the PC
    usb_rx    : in  std_logic;                       -- G1  from the PC
    audio_l   : out std_logic;                       -- A13
    audio_r   : out std_logic;                       -- B13
    buzzer    : out std_logic;                       -- B14 (needs jumper J6)
    vga_r     : out std_logic_vector(3 downto 0);
    vga_g     : out std_logic_vector(3 downto 0);
    vga_b     : out std_logic_vector(3 downto 0);
    vga_hs    : out std_logic;
    vga_vs    : out std_logic;
    seg_n     : out std_logic_vector(7 downto 0);
    dig       : out std_logic_vector(3 downto 0)
  );
end entity;

architecture rtl of top_tetris is
  -- video timing
  signal x, y        : unsigned(9 downto 0);
  signal video_on    : std_logic;
  signal hs, vs      : std_logic;
  signal frame_tick  : std_logic;

  -- inputs
  signal btns        : std_logic_vector(4 downto 0);
  signal sw_raw, sw_s1, sw_s : std_logic_vector(12 downto 0) := (others => '0');
  signal pause_s, music_s, sfx_s, usb_s, chaos_s : std_logic;
  signal task_sw     : std_logic_vector(7 downto 0);
  signal a_left, a_right, a_rot, a_soft, a_hard : std_logic;
  signal c_left, c_right : std_logic;            -- after the MIRROR attack
  signal touch       : std_logic;

  -- game state
  signal occ         : occ_field_t;
  signal colf        : col_field_t;
  signal cur_shape   : shape_t;
  signal cur_color   : color_t;
  signal cur_x       : xpos_t;
  signal cur_y       : ypos_t;
  signal ghost_y     : ypos_t;
  signal next_shape  : shape_t;
  signal next_color  : color_t;
  signal playing     : std_logic;
  signal game_over   : std_logic;
  signal lines_bcd   : std_logic_vector(15 downto 0);
  signal level       : integer range 0 to 15;
  signal clear_evt   : std_logic;
  signal clear_n     : integer range 0 to 4;

  -- versus
  signal link_ok     : std_logic;
  signal rx_line, tx_line : std_logic;
  signal start_out, lost_out, garb_out : std_logic;
  signal garb_out_n  : integer range 0 to 31;
  signal got_start, got_lost, got_garb : std_logic;
  signal got_n       : integer range 0 to 31;
  signal height      : integer range 0 to 20;
  signal opp_height  : integer range 0 to 20;
  signal pending     : integer range 0 to 31;
  signal result      : integer range 0 to 4;
  signal garb_in     : std_logic;
  signal garb_in_n   : integer range 0 to 31;

  -- chaos
  signal chaos_en    : std_logic;
  signal got_att     : std_logic;
  signal got_att_id  : integer range 0 to 31;
  signal t_active, t_start, t_ok, t_fail, t_send, t_bonus : std_logic;
  signal t_task      : integer range 0 to N_TASKS - 1;
  signal t_sel       : integer range 0 to 7;
  signal t_target    : std_logic_vector(7 downto 0);
  signal t_count     : integer range 0 to 15;
  signal t_meter, t_zlo, t_zhi, t_prog : integer range 0 to 191;
  signal t_secs      : integer range 0 to 31;
  signal t_att_id    : integer range 0 to 7;
  signal t_att_id31  : integer range 0 to 31;
  signal t_bonus_id  : integer range 0 to 2;
  signal fx_mirror, fx_flip, fx_blind, fx_bounce, fx_cat, fx_speed, fx_freeze : std_logic;
  signal fx_garb, fx_next_bad, fx_next_i, fx_sink, fx_hit, fx_oiia : std_logic;
  signal ban_on      : std_logic;
  signal ban_id      : integer range 0 to 31;
  signal ov_on       : std_logic;
  signal ov_rgb      : rgb_t;

  signal audio       : std_logic;
  signal g3, g2, g1, g0 : glyph_t;
begin

  u_sync : entity work.vga_sync
    port map (clk => clk, pix_en => open, x => x, y => y, video_on => video_on,
              hsync => hs, vsync => vs, frame_tick => frame_tick);

  -- buttons, in the order tetris_input expects
  btns <= btn_hard & btn_soft & btn_rot & btn_right & btn_left;

  -- slide switches are outside the clock's world: synchronise them
  sw_raw <= sw_task & sw_chaos & sw_usb & sw_sfx & sw_music & sw_pause;
  process(clk)
  begin
    if rising_edge(clk) then
      sw_s1 <= sw_raw;
      sw_s  <= sw_s1;
    end if;
  end process;
  pause_s <= sw_s(0);
  music_s <= sw_s(1);
  sfx_s   <= sw_s(2);
  usb_s   <= sw_s(3);
  chaos_s <= sw_s(4);
  task_sw <= sw_s(12 downto 5);

  u_input : entity work.tetris_input
    generic map (DEBOUNCE_CYCLES => DEBOUNCE_CYCLES)
    port map (clk => clk, frame_tick => frame_tick, btn => btns,
              act_left => a_left, act_right => a_right, act_rot => a_rot,
              act_soft => a_soft, act_hard => a_hard);

  -- chaos MIRROR: left and right swap places
  c_left  <= a_right when fx_mirror = '1' else a_left;
  c_right <= a_left  when fx_mirror = '1' else a_right;
  touch   <= a_left or a_right or a_rot or a_soft or a_hard;

  -- garbage comes from the rival's GARBAGE message or the GARBAGE attack (+3)
  garb_in   <= got_garb or fx_garb;
  garb_in_n <= got_n when got_garb = '1' else 3;

  u_core : entity work.tetris_core
    port map (
      clk => clk, frame_tick => frame_tick, pause => pause_s,
      act_left => c_left, act_right => c_right, act_rot => a_rot,
      act_soft => a_soft, act_hard => a_hard,
      versus => link_ok, start_in => got_start, garb_in => garb_in, garb_in_n => garb_in_n,
      opp_lost => got_lost, start_out => start_out, lost_out => lost_out,
      garb_out => garb_out, garb_out_n => garb_out_n,
      height => height, pending => pending, result => result,
      fx_freeze => fx_freeze, fx_speed => fx_speed, fx_next_bad => fx_next_bad,
      fx_next_i => fx_next_i, fx_sink => fx_sink,
      occ => occ, colf => colf,
      cur_shape => cur_shape, cur_color => cur_color, cur_x => cur_x, cur_y => cur_y,
      ghost_y => ghost_y, next_shape => next_shape, next_color => next_color,
      playing => playing, game_over => game_over,
      lines_bcd => lines_bcd, level => level,
      clear_evt => clear_evt, clear_n => clear_n
    );

  -- the link: listen on the J5 cable, or on the USB serial port when SW22 is
  -- on. Send on both (whoever isn't listening just ignores it).
  rx_line <= usb_rx when usb_s = '1' else link_rx;
  link_tx <= tx_line;
  usb_tx  <= tx_line;
  t_att_id31 <= t_att_id;

  u_link : entity work.versus_link
    generic map (CLKS_PER_BIT => LINK_CLKS_PER_BIT)
    port map (
      clk => clk, frame_tick => frame_tick, rx => rx_line, tx => tx_line,
      send_start => start_out, send_lost => lost_out,
      send_garbage => garb_out, garbage_n => garb_out_n, my_height => height,
      send_attack => t_send, attack_id => t_att_id31,
      got_start => got_start, got_lost => got_lost, got_garbage => got_garb,
      got_n => got_n, opp_height => opp_height,
      got_attack => got_att, got_attack_id => got_att_id, link_ok => link_ok
    );

  -- ------------------------------------------------------------ chaos
  chaos_en <= chaos_s and playing;

  u_task : entity work.chaos_task
    generic map (FIRST_DELAY => CHAOS_FIRST_DELAY, FORCE_TASK => CHAOS_FORCE_TASK)
    port map (
      clk => clk, frame_tick => frame_tick, enable => chaos_en, paused => pause_s,
      versus => link_ok, sw => task_sw, touch => touch,
      active => t_active, task => t_task, sel => t_sel, target => t_target,
      count => t_count, meter_pos => t_meter, zone_lo => t_zlo, zone_hi => t_zhi,
      progress => t_prog, secs => t_secs,
      task_start => t_start, task_ok => t_ok, task_fail => t_fail,
      send_attack => t_send, attack_id => t_att_id, bonus => t_bonus, bonus_id => t_bonus_id
    );

  u_fx : entity work.chaos_fx
    port map (
      clk => clk, frame_tick => frame_tick, enable => chaos_en, paused => pause_s,
      got_attack => got_att, got_id => got_att_id,
      sent_attack => t_send, sent_id => t_att_id,
      bonus => t_bonus, bonus_id => t_bonus_id, task_fail => t_fail,
      mirror => fx_mirror, flip => fx_flip, blind => fx_blind, bounce => fx_bounce,
      cat => fx_cat, speed => fx_speed, freeze => fx_freeze,
      garbage => fx_garb, next_bad => fx_next_bad, next_i => fx_next_i, sink => fx_sink,
      hit_evt => fx_hit, oiia_evt => fx_oiia,
      banner_on => ban_on, banner_id => ban_id
    );

  u_crender : entity work.chaos_render
    port map (
      clk => clk, frame_tick => frame_tick, x => x, y => y, enable => chaos_s,
      bounce => fx_bounce, cat => fx_cat,
      t_active => t_active, t_task => t_task, t_sel => t_sel, t_target => t_target,
      t_sw => task_sw, t_count => t_count, t_meter => t_meter, t_zone_lo => t_zlo,
      t_zone_hi => t_zhi, t_progress => t_prog, t_secs => t_secs,
      banner_on => ban_on, banner_id => ban_id,
      ov_on => ov_on, ov_rgb => ov_rgb
    );

  -- ------------------------------------------------------------ picture + sound
  u_render : entity work.tetris_render
    port map (
      clk => clk, x => x, y => y, video_on => video_on, hsync => hs, vsync => vs,
      occ => occ, colf => colf,
      cur_shape => cur_shape, cur_color => cur_color, cur_x => cur_x, cur_y => cur_y,
      ghost_y => ghost_y, next_shape => next_shape, next_color => next_color,
      playing => playing, game_over => game_over, paused => pause_s, level => level,
      lines_bcd => lines_bcd, result => result, pending => pending,
      opp_height => opp_height, link_ok => link_ok,
      fx_flip => fx_flip, fx_blind => fx_blind, ov_on => ov_on, ov_rgb => ov_rgb,
      vga_r => vga_r, vga_g => vga_g, vga_b => vga_b, vga_hs => vga_hs, vga_vs => vga_vs
    );

  u_sound : entity work.tetris_sound
    port map (
      clk => clk, frame_tick => frame_tick, music_on => music_s, sfx_on => sfx_s,
      playing => playing, level => level, clear_evt => clear_evt, clear_n => clear_n,
      garb_evt => garb_in, result => result,
      task_start_evt => t_start, task_ok_evt => t_ok, task_fail_evt => t_fail,
      sent_evt => t_send, hit_evt => fx_hit, oiia_evt => fx_oiia,
      audio => audio, buzz => buzzer
    );
  audio_l <= audio;
  audio_r <= audio;

  -- 7-segment display: the task countdown "--ss" while a task runs, else lines
  process(t_active, chaos_en, t_secs, lines_bcd)
  begin
    if chaos_en = '1' and t_active = '1' then
      g3 <= SEG_DASH;
      g2 <= SEG_DASH;
      g1 <= hex7(t_secs / 10);
      g0 <= hex7(t_secs mod 10);
    else
      g3 <= hex7(lines_bcd(15 downto 12));
      g2 <= hex7(lines_bcd(11 downto 8));
      g1 <= hex7(lines_bcd(7 downto 4));
      g0 <= hex7(lines_bcd(3 downto 0));
    end if;
  end process;

  u_seg : entity work.seg7_scan
    port map (clk => clk, d3 => g3, d2 => g2, d1 => g1, d0 => g0,
              dp => "0000", seg_n => seg_n, dig => dig);

end architecture;
