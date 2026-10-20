-- ============================================================================
-- tb_chaos_frame.vhd  -  "screenshots" of the CHAOS layer
--
-- Like tb_tetris_frame, with chaos switched on (SW6), the first task
-- forced to BINARY and coming after half a second, and the pretend PC
-- attacking:
--   screenshot 1 (frame.ppm)  : the BINARY task panel + the BLIND attack
--   screenshot 2 (frame2.ppm) : FLIP + BOUNCERS attacks
-- Run with:  tools\sim.bat tb_chaos_frame   (several minutes), then
--            python tools\ppm2png.py sim\out\frame2.ppm sim\out\frame2.png
-- ============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;

entity tb_chaos_frame is
end entity;

architecture sim of tb_chaos_frame is
  signal clk    : std_logic := '0';
  signal done   : boolean := false;
  signal r, g, b : std_logic_vector(3 downto 0);
  signal hs, vs : std_logic;
  signal seg_n  : std_logic_vector(7 downto 0);
  signal dig    : std_logic_vector(3 downto 0);
  signal b_left, b_rot, b_hard, b_soft, b_right : std_logic := '0';
  signal shot     : integer := 0;          -- which screenshot to take now (0 = none)
  signal shot_done : integer := 0;

  -- pretend PC on the USB serial line
  signal pc_data  : std_logic_vector(7 downto 0) := (others => '0');
  signal pc_start : std_logic := '0';
  signal pc_busy  : std_logic;
  signal pc_line  : std_logic;
  signal want_blind, want_flip : boolean := false;

  -- the robot's moves for each piece: rotations, then sideways steps
  type int_arr is array (natural range <>) of integer;
  constant ROTS  : int_arr := (0, 1, 0, 2, 1, 0, 3);
  constant MOVES : int_arr := (-3, 3, 0, -1, 2, -4, 4);
begin

  clk <= not clk after 10 ns when not done else clk;

  dut : entity work.top_tetris
    generic map (DEBOUNCE_CYCLES => 20, CHAOS_FIRST_DELAY => 30, CHAOS_FORCE_TASK => 2,
                 SW_TICK_CYCLES => 50, USE_STARTUP => false)
    port map (clk => clk, btn_left => b_left, btn_rot => b_rot, btn_hard => b_hard,
              btn_soft => b_soft, btn_right => b_right,
              sw_pause => '0', sw_music => '1', sw_sfx => '1', sw_usb => '1',
              sw_chaos => '1', sw_task => x"5A",
              link_tx => open, link_rx => '1', usb_tx => open, usb_rx => pc_line,
              audio_l => open, audio_r => open, buzzer => open,
              vga_r => r, vga_g => g, vga_b => b, vga_hs => hs, vga_vs => vs,
              seg_n => seg_n, dig => dig);

  u_pc : entity work.uart_tx
    generic map (CLKS_PER_BIT => 434)
    port map (clk => clk, data => pc_data, start => pc_start, tx => pc_line, busy => pc_busy);

  -- the pretend PC: a heartbeat every 20 ms, plus garbage / LOST on request
  pc : process
    procedure send(v : std_logic_vector(7 downto 0)) is
    begin
      wait until rising_edge(clk);
      pc_data  <= v;
      pc_start <= '1';
      wait until rising_edge(clk);
      pc_start <= '0';
      wait until rising_edge(clk);
      wait until pc_busy = '0';
    end procedure;
    variable sent_c, sent_f : boolean := false;
  begin
    loop
      send("000" & "01001");                     -- HEARTBEAT, height 9
      if want_blind and not sent_c then
        send("100" & "00010");                   -- ATTACK 2: BLIND
        sent_c := true;
      end if;
      if want_flip and not sent_f then
        send("100" & "00001");                   -- ATTACK 1: FLIP
        send("100" & "00011");                   -- ATTACK 3: BOUNCERS
        sent_f := true;
      end if;
      wait for 20 ms;
    end loop;
  end process;

  player : process
    procedure press(signal btn : out std_logic) is
    begin
      btn <= '1';
      for i in 1 to 100 loop wait until rising_edge(clk); end loop;
      btn <= '0';
      wait until falling_edge(vs);
    end procedure;
  begin
    wait for 60 ms;                              -- let the link come up
    wait until falling_edge(vs);
    press(b_hard);                               -- start
    wait until falling_edge(vs);
    for p in ROTS'range loop
      for i in 1 to ROTS(p) loop press(b_rot); end loop;
      if MOVES(p) < 0 then
        for i in 1 to -MOVES(p) loop press(b_left); end loop;
      else
        for i in 1 to MOVES(p) loop press(b_right); end loop;
      end if;
      if p < ROTS'high then
        press(b_hard);
        wait until falling_edge(vs);
      end if;
    end loop;
    want_blind <= true;                          -- the rival sends BLIND
    wait for 50 ms;
    report "taking screenshot 1";
    shot <= 1;
    wait until shot_done = 1;
    want_flip <= true;                           -- then FLIP + BOUNCERS
    wait for 50 ms;
    report "taking screenshot 2";
    shot <= 2;
    wait until shot_done = 2;
    done <= true;
    wait;
  end process;

  capture : process
    file     f      : text;
    variable l      : line;
    variable n_hs   : integer;
    variable row    : integer;
    type row_t is array (0 to 639) of integer;
    variable rr, gg, bb : row_t;
  begin
    for k in 1 to 2 loop
      wait until shot = k;
      if k = 1 then
        file_open(f, "frame.ppm", write_mode);
      else
        file_open(f, "frame2.ppm", write_mode);
      end if;
      write(l, string'("P3")); writeline(f, l);
      write(l, string'("640 480")); writeline(f, l);
      write(l, string'("15")); writeline(f, l);
      wait until falling_edge(vs);
      n_hs := 0;
      row  := 0;
      while row < 480 loop
        wait until falling_edge(hs);
        if n_hs >= 34 then
          for q in 1 to 288 loop
            wait until rising_edge(clk);
          end loop;
          for px in 0 to 639 loop
            wait until falling_edge(clk);
            rr(px) := to_integer(unsigned(r));
            gg(px) := to_integer(unsigned(g));
            bb(px) := to_integer(unsigned(b));
            wait until rising_edge(clk);
            wait until rising_edge(clk);
          end loop;
          for px in 0 to 639 loop
            write(l, rr(px)); write(l, string'(" "));
            write(l, gg(px)); write(l, string'(" "));
            write(l, bb(px)); write(l, string'("  "));
          end loop;
          writeline(f, l);
          row := row + 1;
        end if;
        n_hs := n_hs + 1;
      end loop;
      file_close(f);
      report "FRAME CAPTURED: screenshot " & integer'image(k);
      shot_done <= k;
    end loop;
    wait;
  end process;

end architecture;
