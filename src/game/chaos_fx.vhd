-- ============================================================================
-- chaos_fx.vhd
-- Keeps track of the CHAOS effects acting on MY board, and of the banner
-- text under the field.
--
-- Effects come from two places:
--   * an ATTACK message from the rival (got_attack + got_id, via versus_link)
--   * a BONUS I earned with a task (bonus + bonus_id, from chaos_task)
--
-- Timed effects (mirror, flip, blind, bouncers, cat, speed, freeze) each have
-- a frame counter: set to a random length (ATTACK_LO..ATTACK_HI frames, see
-- chaos_pkg) when it starts, counted down once per frame, and the effect is
-- on while it is above 0. A second hit of the same attack restarts it.
-- BOUNCE also picks how many squares come (5..10).
-- Instant effects (garbage, cursed next, sink, I piece) are one-clock pulses
-- to tetris_core.
-- LOCK is different: 'locked' stays on until I finish a task (task_ok).
-- While it is on, the banner keeps saying LOCKED, and chaos_task is told to
-- hurry (give me a task now, and a new one after each failure).
--
-- The banner shows for 2.5 s: INCOMING / SENT / BONUS / TASK FAILED.
-- Nothing happens while chaos is switched off or no game is running.
-- ============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.chaos_pkg.all;

entity chaos_fx is
  port (
    clk         : in  std_logic;
    frame_tick  : in  std_logic;
    enable      : in  std_logic;                  -- chaos on and a game running
    paused      : in  std_logic;
    got_attack  : in  std_logic;                  -- the rival attacked me
    got_id      : in  integer range 0 to 31;
    sent_attack : in  std_logic;                  -- I attacked the rival
    sent_id     : in  integer range 0 to N_ATTACKS - 1;
    bonus       : in  std_logic;                  -- I earned a bonus
    bonus_id    : in  integer range 0 to 2;
    task_ok     : in  std_logic;
    task_fail   : in  std_logic;
    -- timed effects on me
    mirror      : out std_logic;
    flip        : out std_logic;
    blind       : out std_logic;
    bounce      : out std_logic;
    n_bounce    : out integer range 5 to 10;      -- how many bouncers
    cat         : out std_logic;
    speed       : out std_logic;
    freeze      : out std_logic;
    locked      : out std_logic;                  -- buttons locked until a task is done
    -- instant effects (pulses to tetris_core)
    garbage     : out std_logic;                  -- +3 garbage lines
    next_bad    : out std_logic;                  -- next piece -> S or Z
    next_i      : out std_logic;                  -- next piece -> I
    sink        : out std_logic;                  -- remove 2 bottom rows, cancel waiting garbage
    -- for the sound
    hit_evt     : out std_logic;                  -- an attack arrived
    oiia_evt    : out std_logic;                  -- the cat arrived
    -- banner
    banner_on   : out std_logic;
    banner_id   : out integer range 0 to 31
  );
end entity;

architecture rtl of chaos_fx is
  type timers_t is array (0 to 7) of integer range 0 to 1023;
  signal t      : timers_t := (others => 0);         -- one per timed attack number
  signal t_frz  : integer range 0 to 1023 := 0;
  signal lock_r : std_logic := '0';
  signal nb     : integer range 5 to 10 := 5;
  signal ban_t  : integer range 0 to 255 := 0;
  signal ban_id : integer range 0 to 31 := 0;
  signal g_p, nb_p, ni_p, sk_p, hit_p, oiia_p : std_logic := '0';
  signal lfsr   : std_logic_vector(15 downto 0) := x"9E37";
begin

  process(clk)
    variable rnd : integer range 0 to 255;
  begin
    if rising_edge(clk) then
      lfsr <= lfsr(14 downto 0) & (lfsr(15) xor lfsr(13) xor lfsr(12) xor lfsr(10));
      rnd  := to_integer(unsigned(lfsr(7 downto 0)));
      g_p <= '0'; nb_p <= '0'; ni_p <= '0'; sk_p <= '0'; hit_p <= '0'; oiia_p <= '0';

      if enable = '0' then
        t      <= (others => 0);
        t_frz  <= 0;
        ban_t  <= 0;
        lock_r <= '0';
      else
        -- count everything down once per frame (not while paused)
        if frame_tick = '1' and paused = '0' then
          for i in 0 to 7 loop
            if t(i) > 0 then t(i) <= t(i) - 1; end if;
          end loop;
          if t_frz > 0 then t_frz <= t_frz - 1; end if;
          if ban_t > 0 then ban_t <= ban_t - 1; end if;
        end if;

        -- locked: keep the LOCKED banner up until a task is done
        if lock_r = '1' and ban_t = 0 then
          ban_id <= A_LOCK;
          ban_t  <= 1;
        end if;
        if task_ok = '1' then
          lock_r <= '0';
        end if;

        -- the rival hit me
        if got_attack = '1' and got_id <= N_ATTACKS - 1 then
          hit_p  <= '1';
          ban_id <= got_id;                          -- banners 0..8: INCOMING
          ban_t  <= 150;
          case got_id is
            when A_GARBAGE => g_p    <= '1';
            when A_CURSED  => nb_p   <= '1';
            when A_LOCK    => lock_r <= '1';
            when others    =>
              if got_id = A_OIIA   then oiia_p <= '1'; end if;
              if got_id = A_BOUNCE then nb <= rand_range(5, 10, rnd); end if;
              if got_id <= 7 then
                t(got_id) <= rand_range(ATTACK_LO(got_id), ATTACK_HI(got_id), rnd);
              end if;
          end case;
        end if;

        -- banners for my own task results
        if sent_attack = '1' then
          ban_id <= BAN_SENT + sent_id;              -- banners 9..17: SENT
          ban_t  <= 150;
        end if;
        if bonus = '1' then
          ban_id <= BAN_BONUS + bonus_id;            -- banners 18..20: BONUS
          ban_t  <= 150;
          case bonus_id is
            when B_FREEZE => t_frz <= rand_range(FREEZE_LO, FREEZE_HI, rnd);
            when B_SINK   => sk_p  <= '1';
            when others   => ni_p  <= '1';
          end case;
        end if;
        if task_fail = '1' then
          ban_id <= BAN_FAIL;                        -- TASK FAILED
          ban_t  <= 150;
        end if;
      end if;
    end if;
  end process;

  mirror    <= '1' when t(A_MIRROR) > 0 else '0';
  flip      <= '1' when t(A_FLIP)   > 0 else '0';
  blind     <= '1' when t(A_BLIND)  > 0 else '0';
  bounce    <= '1' when t(A_BOUNCE) > 0 else '0';
  n_bounce  <= nb;
  cat       <= '1' when t(A_OIIA)   > 0 else '0';
  speed     <= '1' when t(A_SPEED)  > 0 else '0';
  freeze    <= '1' when t_frz > 0 else '0';
  locked    <= lock_r;
  garbage   <= g_p;
  next_bad  <= nb_p;
  next_i    <= ni_p;
  sink      <= sk_p;
  hit_evt   <= hit_p;
  oiia_evt  <= oiia_p;
  banner_on <= '1' when ban_t > 0 else '0';
  banner_id <= ban_id;

end architecture;
