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
--   After a game ends the buttons can't start a new one for 1.5 s (so a
--   hard drop pressed just as the rival loses doesn't start the next round).
--
-- Slide switches (a row of 16; left = SW22 ... right = SW2). Like a
-- two-sided controller: the left 8 are the chaos task switches, the right
-- end holds the settings, and SW8..SW10 are left free as a gap.
--   SW22 SW21 SW19 SW17 SW15 SW13 SW12 SW11   task switches (bit 7 .. bit 0)
--   SW7  link to the PC over USB instead of the J5 cable (test with
--        tools\fake_opponent.py, the PC plays the other board)
--   SW6  CHAOS on (tasks + attacks)
--   SW5  sound effects on    SW4  music / media sound on    SW2  pause (rightmost)
--   All slide switches go through switch_filter (bounce removed).
--
-- Versus rules: clearing 2 / 3 / 4 lines sends 1 / 2 / 4 garbage lines.
-- Lines you clear first cancel garbage waiting for you (red meter left of
-- the field). Last one standing wins.
-- CHAOS: every 10-17 s (random, no warning) a task pops up on the right; do
-- it with the task switches before the time runs out -> attack the rival or
-- get a bonus. The LOCK attack locks all buttons until you finish a task.
-- MEDIA (from the SPI flash, written there with tools\flash_media.bat
-- media\game_media.bin): the music, the media attacks (Bad Apple, OIIA,
-- Jevil play behind the rival's game), a random clip / picture when you win
-- or lose, Jevil and the friends' faces as sprites. Without the media file
-- the game works the same, just without them.
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
--     +-- tetris_render  game state -> pixel colours (text_multi, + overlay)
--     +-- media_engine   reads the flash: pictures, sound (adpcm_dec), sprites
--     |                  (spi_flash; its clock goes out through STARTUPE2)
--     +-- media_ctrl     what plays when: music, attacks, win / lose
--     +-- media_mix      media on top of / behind the game -> VGA pins
--     +-- tetris_sound   media sound + effects -> audio jack, buzzer
--     +-- seg7_scan      lines, or the task countdown, on the 7-segment display
-- ============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
library unisim;
use unisim.vcomponents.all;                      -- STARTUPE2
use work.common_pkg.all;
use work.tetris_pkg.all;
use work.chaos_pkg.all;

entity top_tetris is
  generic (
    DEBOUNCE_CYCLES   : integer := 250_000;       -- 5 ms; testbenches use less
    LINK_CLKS_PER_BIT : integer := CLKS_PER_BIT;  -- 115200 baud
    CHAOS_FIRST_DELAY : integer := 600;           -- frames until the first task
    CHAOS_FORCE_TASK  : integer := -1;            -- testbenches: always this task
    SW_TICK_CYCLES    : integer := 50_000;        -- switch_filter sample: 1 ms
    USE_STARTUP       : boolean := true           -- testbenches: false (STARTUPE2's simulation
                                                  -- model has a clock that never stops)
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
    sw_usb    : in  std_logic;                       -- N10 SW7
    sw_chaos  : in  std_logic;                       -- P12 SW6
    sw_task   : in  std_logic_vector(7 downto 0);    -- SW22 (bit 7, leftmost) .. SW11 (bit 0)
    link_tx   : out std_logic;                       -- L14 J5 pin 5
    link_rx   : in  std_logic;                       -- M13 J5 pin 6
    usb_tx    : out std_logic;                       -- F2  to the PC
    usb_rx    : in  std_logic;                       -- G1  from the PC
    audio_l   : out std_logic;                       -- A13
    audio_r   : out std_logic;                       -- B13
    buzzer    : out std_logic;                       -- B14 (needs jumper J6)
    -- the flash chip (its clock goes through STARTUPE2, see below)
    flash_cs_n  : out std_logic;                     -- C11 FCS_B
    flash_mosi  : out std_logic;                     -- B11 D00
    flash_miso  : in  std_logic := '1';              -- B12 D01
    flash_wp_n  : out std_logic;                     -- D10 D02, keep high
    flash_hold_n: out std_logic;                     -- C10 D03, keep high
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
  signal sw_raw, sw_s : std_logic_vector(12 downto 0);
  signal pause_s, music_s, sfx_s, usb_s, chaos_s : std_logic;
  signal task_sw     : std_logic_vector(7 downto 0);
  signal a_left, a_right, a_rot, a_soft, a_hard : std_logic;
  signal c_left, c_right : std_logic;            -- after the MIRROR attack
  signal g_left, g_right, g_rot, g_soft, g_hard : std_logic;  -- after the LOCK attack
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
  signal can_start   : std_logic;
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
  signal t_offsecs     : integer range 0 to 7;
  signal t_att_id    : integer range 0 to N_ATTACKS - 1;
  signal t_att_id31  : integer range 0 to 31;
  signal t_bonus_id  : integer range 0 to 2;
  signal fx_mirror, fx_flip, fx_blind, fx_bounce, fx_cat, fx_speed, fx_freeze : std_logic;
  signal fx_locked   : std_logic;
  signal fx_nbounce  : integer range 5 to 10;
  signal fx_garb, fx_next_bad, fx_next_i, fx_sink, fx_hit, fx_oiia : std_logic;
  signal ban_on      : std_logic;
  signal ban_id      : integer range 0 to 31;
  signal ov_on       : std_logic;
  signal ov_rgb      : rgb_t;
  signal face_en     : std_logic;
  signal face_addr   : unsigned(11 downto 0);

  -- media
  signal media_hit   : std_logic;
  signal media_id    : integer range 0 to 2;
  signal m_play, m_stop, m_ready, m_spr, m_busy, m_snd, m_picok, m_dimh : std_logic;
  signal m_item      : integer range 0 to 31;
  signal m_from, m_pos : unsigned(15 downto 0);
  signal m_mode, m_zone : integer range 0 to 3;
  signal m_musf, m_musn, m_atkf, m_losef, m_losen, m_winf, m_winn : integer range 0 to 31;
  signal m_rgb, s_rgb : std_logic_vector(11 downto 0);
  signal m_see, s_on : std_logic;
  signal j_en, f_en  : std_logic;
  signal j_addr      : unsigned(14 downto 0);
  signal pcm         : signed(15 downto 0);
  signal c_show, c_jev, c_won, show, jev : std_logic;
  signal sclk        : std_logic;
  signal r_r, r_g, r_b : std_logic_vector(3 downto 0);   -- tetris_render's picture
  signal r_hs, r_vs, see_bg, keep : std_logic;

  signal audio       : std_logic;
  signal g3, g2, g1, g0 : glyph_t;
begin

  u_sync : entity work.vga_sync
    port map (clk => clk, pix_en => open, x => x, y => y, video_on => video_on,
              hsync => hs, vsync => vs, frame_tick => frame_tick);

  -- buttons, in the order tetris_input expects
  btns <= btn_hard & btn_soft & btn_rot & btn_right & btn_left;

  -- slide switches are outside the clock's world and they bounce:
  -- synchronise and clean them
  sw_raw <= sw_task & sw_chaos & sw_usb & sw_sfx & sw_music & sw_pause;
  u_sw : entity work.switch_filter
    generic map (N => 13, TICK_CYCLES => SW_TICK_CYCLES)
    port map (clk => clk, sw_in => sw_raw, sw_out => sw_s);
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
  -- chaos LOCK: no button does anything until I finish a task
  g_left  <= c_left  and not fx_locked;
  g_right <= c_right and not fx_locked;
  g_rot   <= a_rot   and not fx_locked;
  g_soft  <= a_soft  and not fx_locked;
  g_hard  <= a_hard  and not fx_locked;
  -- (the HANDS task still sees every press, locked or not)
  touch   <= a_left or a_right or a_rot or a_soft or a_hard;

  -- garbage comes from the rival's GARBAGE message or the GARBAGE attack (+3)
  garb_in   <= got_garb or fx_garb;
  garb_in_n <= got_n when got_garb = '1' else 3;

  u_core : entity work.tetris_core
    port map (
      clk => clk, frame_tick => frame_tick, pause => pause_s,
      act_left => g_left, act_right => g_right, act_rot => g_rot,
      act_soft => g_soft, act_hard => g_hard,
      versus => link_ok, start_in => got_start, garb_in => garb_in, garb_in_n => garb_in_n,
      opp_lost => got_lost, start_out => start_out, lost_out => lost_out,
      garb_out => garb_out, garb_out_n => garb_out_n,
      height => height, pending => pending, result => result,
      fx_freeze => fx_freeze, fx_speed => fx_speed, fx_next_bad => fx_next_bad,
      fx_next_i => fx_next_i, fx_sink => fx_sink,
      occ => occ, colf => colf,
      cur_shape => cur_shape, cur_color => cur_color, cur_x => cur_x, cur_y => cur_y,
      ghost_y => ghost_y, next_shape => next_shape, next_color => next_color,
      playing => playing, can_start => can_start, game_over => game_over,
      lines_bcd => lines_bcd, level => level,
      clear_evt => clear_evt, clear_n => clear_n
    );

  -- the link: listen on the J5 cable, or on the USB serial port when SW7 is
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
      versus => link_ok, hurry => fx_locked, media_ok => m_ready, sw => task_sw, touch => touch,
      active => t_active, task => t_task, sel => t_sel, target => t_target,
      count => t_count, meter_pos => t_meter, zone_lo => t_zlo, zone_hi => t_zhi,
      progress => t_prog, secs => t_secs, hands_secs => t_offsecs,
      task_start => t_start, task_ok => t_ok, task_fail => t_fail,
      send_attack => t_send, attack_id => t_att_id, bonus => t_bonus, bonus_id => t_bonus_id
    );

  u_fx : entity work.chaos_fx
    port map (
      clk => clk, frame_tick => frame_tick, enable => chaos_en, paused => pause_s,
      got_attack => got_att, got_id => got_att_id,
      sent_attack => t_send, sent_id => t_att_id,
      bonus => t_bonus, bonus_id => t_bonus_id, task_ok => t_ok, task_fail => t_fail,
      mirror => fx_mirror, flip => fx_flip, blind => fx_blind, bounce => fx_bounce,
      n_bounce => fx_nbounce, cat => fx_cat, speed => fx_speed, freeze => fx_freeze,
      locked => fx_locked,
      garbage => fx_garb, next_bad => fx_next_bad, next_i => fx_next_i, sink => fx_sink,
      hit_evt => fx_hit, oiia_evt => fx_oiia, media_hit => media_hit, media_id => media_id,
      banner_on => ban_on, banner_id => ban_id
    );

  u_crender : entity work.chaos_render
    port map (
      clk => clk, frame_tick => frame_tick, x => x, y => y, enable => chaos_s,
      bounce => fx_bounce, n_bounce => fx_nbounce, cat => fx_cat, locked => fx_locked,
      t_active => t_active, t_task => t_task, t_sel => t_sel, t_target => t_target,
      t_sw => task_sw, t_count => t_count, t_meter => t_meter, t_zone_lo => t_zlo,
      t_zone_hi => t_zhi, t_progress => t_prog, t_secs => t_secs, t_offsecs => t_offsecs,
      banner_on => ban_on, banner_id => ban_id,
      ov_on => ov_on, ov_rgb => ov_rgb, face_en => face_en, face_addr => face_addr
    );

  -- ------------------------------------------------------------ picture + sound
  u_render : entity work.tetris_render
    port map (
      clk => clk, x => x, y => y, video_on => video_on, hsync => hs, vsync => vs,
      occ => occ, colf => colf,
      cur_shape => cur_shape, cur_color => cur_color, cur_x => cur_x, cur_y => cur_y,
      ghost_y => ghost_y, next_shape => next_shape, next_color => next_color,
      playing => playing, can_start => can_start, game_over => game_over, paused => pause_s, level => level,
      lines_bcd => lines_bcd, result => result, pending => pending,
      opp_height => opp_height, link_ok => link_ok,
      fx_flip => fx_flip, fx_blind => fx_blind, ov_on => ov_on, ov_rgb => ov_rgb,
      vga_r => r_r, vga_g => r_g, vga_b => r_b, vga_hs => r_hs, vga_vs => r_vs,
      see_bg => see_bg, keep => keep
    );

  -- ------------------------------------------------------------ media
  u_media : entity work.media_engine
    port map (
      clk => clk, frame_tick => frame_tick,
      play => m_play, item => m_item, from_rec => m_from, stop => m_stop,
      ready => m_ready, spr_ok => m_spr,
      mus_first => m_musf, mus_n => m_musn, atk_first => m_atkf,
      lose_first => m_losef, lose_n => m_losen, win_first => m_winf, win_n => m_winn,
      busy => m_busy, has_snd => m_snd, pic_ok => m_picok, mode => m_mode, dim_half => m_dimh,
      rec_pos => m_pos,
      sclk => sclk, cs_n => flash_cs_n, mosi => flash_mosi, miso => flash_miso,
      x => x, y => y, rgb => m_rgb, see => m_see, zone => m_zone,
      j_en => j_en, j_addr => j_addr, f_en => f_en, f_addr => face_addr,
      spr_on => s_on, spr_rgb => s_rgb, pcm => pcm
    );
  f_en <= face_en and m_spr;                     -- faces only once they are loaded
  flash_wp_n   <= '1';
  flash_hold_n <= '1';

  -- The flash clock pin is the FPGA's own configuration clock pin (CCLK).
  -- After configuration, user logic can only reach it through STARTUPE2:
  -- whatever goes into USRCCLKO comes out on CCLK (see docs\learn\08).
  g_startup : if USE_STARTUP generate
  u_startup : STARTUPE2
    generic map (PROG_USR => "FALSE", SIM_CCLK_FREQ => 0.0)
    port map (
      CFGCLK => open, CFGMCLK => open, EOS => open, PREQ => open,
      CLK => '0', GSR => '0', GTS => '0', KEYCLEARB => '1', PACK => '0',
      USRCCLKO  => sclk,                         -- our SPI clock -> CCLK pin
      USRCCLKTS => '0',                          -- '0' = drive the pin
      USRDONEO  => '1',                          -- keep the DONE LED on
      USRDONETS => '0'
    );
  end generate;

  u_mctrl : entity work.media_ctrl
    port map (
      clk => clk, playing => playing, result => result,
      media_hit => media_hit, media_id => media_id,
      ready => m_ready, mus_first => m_musf, mus_n => m_musn, atk_first => m_atkf,
      lose_first => m_losef, lose_n => m_losen, win_first => m_winf, win_n => m_winn,
      busy => m_busy, has_snd => m_snd, rec_pos => m_pos,
      play => m_play, item => m_item, from_rec => m_from, stop => m_stop,
      show => c_show, jevil => c_jev, won => c_won
    );
  show <= c_show and m_picok;
  jev  <= c_jev and m_picok and m_spr;

  u_mix : entity work.media_mix
    port map (
      clk => clk, frame_tick => frame_tick, x => x, y => y,
      g_r => r_r, g_g => r_g, g_b => r_b, g_hs => r_hs, g_vs => r_vs,
      see_bg => see_bg, keep => keep,
      show => show, mode => m_mode, dim_half => m_dimh, won => c_won, jevil => jev,
      m_rgb => m_rgb, m_see => m_see, m_zone => m_zone, s_on => s_on, s_rgb => s_rgb,
      j_en => j_en, j_addr => j_addr,
      vga_r => vga_r, vga_g => vga_g, vga_b => vga_b, vga_hs => vga_hs, vga_vs => vga_vs
    );

  u_sound : entity work.tetris_sound
    port map (
      clk => clk, frame_tick => frame_tick, music_on => music_s, sfx_on => sfx_s,
      playing => playing, pcm => pcm, clear_evt => clear_evt, clear_n => clear_n,
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
