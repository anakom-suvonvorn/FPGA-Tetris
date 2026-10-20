-- ============================================================================
-- media_ctrl.vhd
-- Decides WHAT media_engine plays, and when:
--
--   a game starts       -> music: the music items one after the other
--                          (Teto SV, then the original, then again...)
--   a media attack hits -> the attack's video + sound (behind the game);
--                          the music remembers where it was, and carries on
--                          from there when the attack is over
--   the game ends       -> I won: one of the win items, picked at random
--                          I lost: one of the lose items, picked at random
--                          (a draw: nothing)
--   the next game starts -> whatever plays is stopped, music again
--
-- 'show' = the picture of the item playing should be on screen (media_mix
-- also waits for the engine's pic_ok). Videos with sound disappear when they
-- end; still pictures stay until the next game. 'jevil' = Jevil floats over
-- the screen (the Jevil attack).
--
-- The item numbers come from the media file's header (mus_first, ...), so
-- the plan can change without touching this block - except the 3 attacks,
-- which are fixed: Bad Apple, OIIA, Jevil (chaos_pkg A_APPLE, A_OIIA, A_JEVIL).
-- ============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity media_ctrl is
  port (
    clk        : in  std_logic;
    -- the game
    playing    : in  std_logic;
    result     : in  integer range 0 to 4;       -- 1 win, 2 lose, 3 draw, 4 game over
    media_hit  : in  std_logic;                  -- a media attack arrived (chaos_fx)
    media_id   : in  integer range 0 to 2;
    -- the engine
    ready      : in  std_logic;
    mus_first, mus_n, atk_first, lose_first, lose_n, win_first, win_n : in integer range 0 to 31;
    busy       : in  std_logic;
    has_snd    : in  std_logic;
    rec_pos    : in  unsigned(15 downto 0);
    play       : out std_logic;
    item       : out integer range 0 to 31;
    from_rec   : out unsigned(15 downto 0);
    stop       : out std_logic;
    -- for media_mix
    show       : out std_logic;
    jevil      : out std_logic;
    won        : out std_logic                   -- the panel frame: gold (won) or red
  );
end entity;

architecture rtl of media_ctrl is
  type cstate_t is (C_IDLE, C_MUSIC, C_ATTACK, C_END);
  signal st        : cstate_t := C_IDLE;
  signal playing_d : std_logic := '0';
  signal result_d  : integer range 0 to 4 := 0;
  signal mus_k     : integer range 0 to 31 := 0;        -- which music item is playing
  signal mus_save  : unsigned(15 downto 0) := (others => '0');
  signal gap       : integer range 0 to 7 := 0;         -- clocks to wait after a command
  signal show_r, jev_r, won_r : std_logic := '0';
  signal play_r, stop_r : std_logic := '0';
  signal item_r    : integer range 0 to 31 := 0;
  signal rec_r     : unsigned(15 downto 0) := (others => '0');
  signal lfsr      : std_logic_vector(15 downto 0) := x"5EED";

  -- a random number 0 .. n-1 (n = 1..8) from a random byte r: r * n / 256
  function pick(r : std_logic_vector(7 downto 0); n : integer range 0 to 31) return integer is
    variable p : unsigned(12 downto 0);
  begin
    p := unsigned(r) * to_unsigned(n, 5);
    return to_integer(p(12 downto 8));
  end function;
begin

  process(clk)
    variable r : std_logic_vector(7 downto 0);
  begin
    if rising_edge(clk) then
      lfsr <= lfsr(14 downto 0) & (lfsr(15) xor lfsr(13) xor lfsr(12) xor lfsr(10));
      r := lfsr(7 downto 0);
      playing_d <= playing;
      result_d  <= result;
      play_r <= '0';
      stop_r <= '0';
      if gap > 0 then gap <= gap - 1; end if;

      if ready = '0' then
        null;                                        -- no media file: nothing to do

      elsif playing = '1' and playing_d = '0' then   -- ---- a new game: music
        show_r <= '0';
        jev_r  <= '0';
        if mus_n > 0 then
          item_r <= mus_first + mus_k;
          rec_r  <= (others => '0');
          play_r <= '1';
          st     <= C_MUSIC;
        else
          stop_r <= '1';
          st     <= C_IDLE;
        end if;
        gap <= 7;

      elsif result /= 0 and result_d = 0 then       -- ---- the game is over
        jev_r <= '0';
        rec_r <= (others => '0');
        gap   <= 7;
        if result = 1 and win_n > 0 then
          item_r <= win_first + pick(r, win_n);
          play_r <= '1'; show_r <= '1'; won_r <= '1';
          st     <= C_END;
        elsif (result = 2 or result = 4) and lose_n > 0 then
          item_r <= lose_first + pick(r, lose_n);
          play_r <= '1'; show_r <= '1'; won_r <= '0';
          st     <= C_END;
        else
          stop_r <= '1'; show_r <= '0';
          st     <= C_IDLE;
        end if;

      elsif media_hit = '1' and (st = C_MUSIC or st = C_ATTACK) then   -- ---- attacked
        if st = C_MUSIC then
          -- remember the music: the next record to load, minus the 2 records
          -- that were still waiting in the ring (better to hear a bit twice)
          if rec_pos >= 2 then mus_save <= rec_pos - 2; else mus_save <= (others => '0'); end if;
        end if;
        item_r <= atk_first + media_id;
        rec_r  <= (others => '0');
        play_r <= '1';
        show_r <= '1';
        if media_id = 2 then jev_r <= '1'; else jev_r <= '0'; end if;
        st  <= C_ATTACK;
        gap <= 7;

      elsif gap = 0 and busy = '0' then             -- ---- the item has finished
        case st is
          when C_MUSIC =>                            -- next music item
            if mus_k + 1 >= mus_n then
              mus_k  <= 0;
              item_r <= mus_first;
            else
              mus_k  <= mus_k + 1;
              item_r <= mus_first + mus_k + 1;
            end if;
            rec_r  <= (others => '0');
            play_r <= '1';
            gap    <= 7;
          when C_ATTACK =>                           -- back to the music, where it was
            item_r <= mus_first + mus_k;
            rec_r  <= mus_save;
            play_r <= '1';
            show_r <= '0';
            jev_r  <= '0';
            st     <= C_MUSIC;
            gap    <= 7;
          when C_END =>                              -- a video ends: off the screen
            if has_snd = '1' then show_r <= '0'; end if;
          when C_IDLE =>
            null;
        end case;
      end if;
    end if;
  end process;

  play     <= play_r;
  stop     <= stop_r;
  item     <= item_r;
  from_rec <= rec_r;
  show     <= show_r;
  jevil    <= jev_r;
  won      <= won_r;

end architecture;
