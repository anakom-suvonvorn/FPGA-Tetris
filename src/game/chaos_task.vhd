-- ============================================================================
-- chaos_task.vhd
-- The slide-switch tasks of the CHAOS layer (see chaos_pkg.vhd for the list).
--
-- HOW IT WORKS
--   Two states:
--     WAIT  count down a random 10..17 s (nothing is shown: it's a surprise)
--     RUN   one task is running; it either succeeds or its time runs out
--   Every task works on the 8 task switches sw(7..0) = SW22..SW11, and keeps
--   a few numbers that chaos_render draws in the right panel:
--     sel       which switch the task is about (FLIP, HOLD, TIMING)
--     target    the pattern (MATCH) or the number (BINARY, HEX)
--     meter_pos, zone_lo, zone_hi   the moving marker and green zone
--                                   (HOLD, TIMING), 0..191 = panel width
--     progress  how far the player got, 0..191
--     secs      seconds left (also shown on the 7-segment display)
--   On success it decides the reward: with a rival connected, 5 times in 8 an
--   ATTACK on the rival (send_attack + attack_id), otherwise a BONUS for me
--   (bonus + bonus_id). Without a rival it is always a bonus.
--
--   Every length of time is picked at random from a range when the task
--   starts (rand_range in chaos_pkg): the time allowed, how long HANDS and
--   HOLD must be kept up, the width of the green zone, the marker speed.
--
--   hurry = '1' (I am under the LOCK attack): don't wait, start a task now,
--   and after a failed task start the next one right away too.
--
--   MEDIA attacks (Bad Apple, OIIA, Jevil) are long, so after sending one
--   'mcool' counts down its length + 10 s (MEDIA_COOL); until then (or when
--   there is no media file, media_ok = '0') the attack is picked again
--   from the normal ones.
--
--   Switch flips are found by comparing sw with its value one clock ago
--   (edge detection); everything else is updated once per frame.
-- ============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.chaos_pkg.all;

entity chaos_task is
  generic (
    FIRST_DELAY : integer := 600;     -- frames from the start of a game to the first task
    FORCE_TASK  : integer := -1       -- >= 0: always this task (for testbenches)
  );
  port (
    clk         : in  std_logic;
    frame_tick  : in  std_logic;
    enable      : in  std_logic;                      -- chaos on and a game running
    paused      : in  std_logic;
    versus      : in  std_logic;                      -- a rival is connected
    hurry       : in  std_logic;                      -- LOCK attack: a task now, please
    media_ok    : in  std_logic := '0';               -- the media file is there (media attacks allowed)
    sw          : in  std_logic_vector(7 downto 0);   -- SW22..SW11, debounced
    touch       : in  std_logic;                      -- any button action (pulse)
    -- for the panel
    active      : out std_logic;                      -- a task is running
    task        : out integer range 0 to N_TASKS - 1;
    sel         : out integer range 0 to 7;
    target      : out std_logic_vector(7 downto 0);
    count       : out integer range 0 to 15;
    meter_pos   : out integer range 0 to 191;
    zone_lo     : out integer range 0 to 191;
    zone_hi     : out integer range 0 to 191;
    progress    : out integer range 0 to 191;
    secs        : out integer range 0 to 31;          -- seconds left
    hands_secs  : out integer range 0 to 7;           -- HANDS: how long to keep off
    -- results (one-clock pulses)
    task_start  : out std_logic;
    task_ok     : out std_logic;
    task_fail   : out std_logic;
    send_attack : out std_logic;
    attack_id   : out integer range 0 to N_ATTACKS - 1;
    bonus       : out std_logic;
    bonus_id    : out integer range 0 to 2
  );
end entity;

architecture rtl of chaos_task is
  signal running   : std_logic := '0';
  signal task_r    : integer range 0 to N_TASKS - 1 := 0;
  signal last_task : integer range 0 to N_TASKS - 1 := 0;
  signal sel_r     : integer range 0 to 7 := 0;
  signal target_r  : std_logic_vector(7 downto 0) := (others => '0');
  signal cnt_r     : integer range 0 to 15 := 0;
  signal frames    : integer range 0 to 1023 := FIRST_DELAY;  -- frames left (wait or task)
  signal sw_d      : std_logic_vector(7 downto 0) := (others => '0');
  signal lfsr      : std_logic_vector(15 downto 0) := x"B5C3";

  -- HOLD and TIMING
  signal pos       : integer range 0 to 191 := 96;
  signal vel       : integer range -4 to 4 := 0;
  signal dir_up    : std_logic := '1';
  signal step      : integer range 1 to 4 := 3;               -- TIMING marker speed
  signal zlo       : integer range 0 to 191 := 0;
  signal zw        : integer range 0 to 63 := 40;
  -- HANDS and HOLD: frames counted towards success, and how many are needed
  signal good      : integer range 0 to 511 := 0;
  signal goal      : integer range 0 to 511 := 180;
  signal pscale    : integer range 0 to 511 := 256;           -- progress = good * pscale / 256

  signal start_p, ok_p, fail_p, atk_p, bon_p : std_logic := '0';
  signal atk_id    : integer range 0 to N_ATTACKS - 1 := 0;
  signal mcool     : integer range 0 to 8191 := 0;     -- frames until a media attack is allowed
  signal bon_id    : integer range 0 to 2 := 0;
  signal prog      : integer range 0 to 191 := 0;

  -- HANDS / HOLD: 4 possible goals (frames) and the matching progress scale
  -- 256 * 180 / goal, so the bar is full (180) exactly when the goal is reached
  type int4_t is array (0 to 3) of integer range 0 to 511;
  constant HANDS_GOAL  : int4_t := (180, 240, 240, 300);    -- 3, 4, 4, 5 s
  constant HANDS_SCALE : int4_t := (256, 192, 192, 154);
  constant HOLD_GOAL   : int4_t := (180, 200, 220, 240);    -- 3 .. 4 s
  constant HOLD_SCALE  : int4_t := (256, 230, 209, 192);

  function ones(v : std_logic_vector(7 downto 0)) return integer is
    variable n : integer range 0 to 8 := 0;
  begin
    for i in 0 to 7 loop
      if v(i) = '1' then n := n + 1; end if;
    end loop;
    return n;
  end function;
begin

  process(clk)
    variable rnd     : integer range 0 to 255;     -- two random bytes
    variable rnd2    : integer range 0 to 255;
    variable t       : integer range 0 to 7;
    variable g       : integer range 0 to 3;
    variable flipped : std_logic;
    variable success : boolean;
    variable p       : integer range -8 to 200;
    variable b       : integer range 0 to 3;
    variable a       : integer range 0 to N_ATTACKS - 1;
  begin
    if rising_edge(clk) then
      lfsr <= lfsr(14 downto 0) & (lfsr(15) xor lfsr(13) xor lfsr(12) xor lfsr(10));
      rnd  := to_integer(unsigned(lfsr(7 downto 0)));
      rnd2 := to_integer(unsigned(lfsr(15 downto 8)));
      g    := to_integer(unsigned(lfsr(12 downto 11)));
      sw_d <= sw;
      start_p <= '0'; ok_p <= '0'; fail_p <= '0'; atk_p <= '0'; bon_p <= '0';
      success := false;

      if frame_tick = '1' and mcool > 0 then
        mcool <= mcool - 1;
      end if;

      if enable = '0' then
        -- no game (or chaos off): forget any task, restart the first wait
        running <= '0';
        frames  <= FIRST_DELAY;
        mcool   <= 0;
      elsif paused = '1' then
        null;                                          -- everything waits
      elsif running = '0' then
        -- ------------------------------------------------ WAIT for the next task
        if hurry = '1' and frames > 0 then
          frames <= 0;                                 -- LOCK attack: no waiting
        elsif frame_tick = '1' then
          if frames > 0 then
            frames <= frames - 1;
          else
            -- pick a task (random, not the same as last time)
            t := rnd mod 8;
            if FORCE_TASK >= 0 then t := FORCE_TASK; end if;
            if t < N_TASKS and (t /= last_task or FORCE_TASK >= 0) then
              task_r    <= t;
              last_task <= t;
              running   <= '1';
              start_p   <= '1';
              frames    <= rand_range(TASK_LO(t), TASK_HI(t), rnd2);
              sel_r     <= to_integer(unsigned(lfsr(10 downto 8)));
              -- a pattern / number that is not already on the switches
              if lfsr(15 downto 8) = sw or lfsr(15 downto 8) = x"00" then
                target_r <= not sw;
              else
                target_r <= lfsr(15 downto 8);
              end if;
              cnt_r  <= 0;
              good   <= 0;
              pos    <= 96;
              vel    <= 0;
              dir_up <= '1';
              step   <= rand_range(2, 4, rnd2);
              if t = T_HANDS then
                goal   <= HANDS_GOAL(g);
                pscale <= HANDS_SCALE(g);
              else
                goal   <= HOLD_GOAL(g);
                pscale <= HOLD_SCALE(g);
              end if;
              if t = T_TIMING then
                zw  <= rand_range(28, 44, rnd2);
                zlo <= rand_range(0, 147, rnd);
              else
                zw  <= rand_range(40, 60, rnd2);
                zlo <= rand_range(0, 131, rnd);
              end if;
            end if;                                    -- else: try again next frame
          end if;
        end if;
      else
        -- ------------------------------------------------ RUN the task
        flipped := sw(sel_r) xor sw_d(sel_r);          -- the task switch moved this clock

        case task_r is
          when T_FLIP =>
            if flipped = '1' then
              if cnt_r = 9 then success := true; end if;
              cnt_r <= cnt_r + 1;
            end if;
          when T_MATCH | T_BINARY | T_HEX =>
            if sw = target_r then success := true; end if;
          when T_HANDS =>
            if touch = '1' then
              good <= 0;                               -- touched a button: start over
            elsif frame_tick = '1' then
              if good = goal - 1 then success := true; end if;
              good <= good + 1;
            end if;
          when T_HOLD =>
            if frame_tick = '1' then
              -- the switch pushes the bar up, gravity pulls it down
              if sw(sel_r) = '1' then
                if vel < 4 then vel <= vel + 1; end if;
              else
                if vel > -4 then vel <= vel - 1; end if;
              end if;
              p := pos + vel;
              if p < 0 then p := 0; vel <= 0; end if;
              if p > 191 then p := 191; vel <= 0; end if;
              pos <= p;
              if pos >= zlo and pos < zlo + zw then
                if good = goal - 1 then success := true; end if;
                good <= good + 1;
              end if;
            end if;
          when others =>                               -- T_TIMING
            if frame_tick = '1' then                   -- marker sweeps back and forth
              if dir_up = '1' then
                if pos >= 191 - step then dir_up <= '0'; else pos <= pos + step; end if;
              else
                if pos <= step then dir_up <= '1'; else pos <= pos - step; end if;
              end if;
            end if;
            if flipped = '1' then
              if pos >= zlo and pos < zlo + zw then
                if cnt_r = 2 then success := true; end if;
                cnt_r <= cnt_r + 1;
                -- a new zone (place and width) for the next hit
                zw  <= rand_range(28, 44, rnd2);
                zlo <= rand_range(0, 147, rnd);
              else
                cnt_r <= 0;                            -- missed: start over
              end if;
            end if;
        end case;

        if success then
          running <= '0';
          ok_p    <= '1';
          frames  <= rand_range(GAP_LO, GAP_HI, rnd);  -- next task in 10..17 s
          if versus = '1' and to_integer(unsigned(lfsr(10 downto 8))) < 5 then
            atk_p  <= '1';
            a := rand_range(0, N_ATTACKS - 1, rnd2);
            if a >= A_MEDIA and (mcool > 0 or media_ok = '0') then
              a := rand_range(0, A_MEDIA - 1, rnd2);   -- a normal one instead
            end if;
            if a >= A_MEDIA then
              mcool <= MEDIA_COOL(a - A_MEDIA);
            end if;
            atk_id <= a;
          else
            bon_p <= '1';
            b := to_integer(unsigned(lfsr(12 downto 11)));
            if b = 3 then b := 0; end if;
            bon_id <= b;
          end if;
        elsif frame_tick = '1' then
          if frames = 0 then
            running <= '0';                            -- out of time
            fail_p  <= '1';
            frames  <= rand_range(GAP_LO, GAP_HI, rnd);
          else
            frames <= frames - 1;
          end if;
        end if;
      end if;
    end if;
  end process;

  -- progress bar (0..191) for each task
  process(task_r, cnt_r, target_r, sw, good, pscale)
    variable m : integer range 0 to 8;
    variable q : integer range 0 to 511;
  begin
    q := (good * pscale) / 256;                    -- 0..180 for HANDS / HOLD
    if q > 180 then q := 180; end if;
    case task_r is
      when T_FLIP =>
        prog <= cnt_r * 19;
      when T_MATCH | T_BINARY | T_HEX =>
        m := 8 - ones(target_r xor sw);              -- switches already right
        prog <= m * 23;
      when T_HANDS | T_HOLD =>
        prog <= q;
      when others =>
        if cnt_r > 3 then prog <= 189; else prog <= cnt_r * 63; end if;
    end case;
  end process;

  active      <= running;
  task        <= task_r;
  sel         <= sel_r;
  target      <= target_r;
  count       <= cnt_r;
  meter_pos   <= pos;
  zone_lo     <= zlo;
  zone_hi     <= zlo + zw;
  progress    <= prog;
  secs        <= frames / 60;
  hands_secs  <= goal / 60;
  task_start  <= start_p;
  task_ok     <= ok_p;
  task_fail   <= fail_p;
  send_attack <= atk_p;
  attack_id   <= atk_id;
  bonus       <= bon_p;
  bonus_id    <= bon_id;

end architecture;
