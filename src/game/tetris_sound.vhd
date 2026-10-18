-- ============================================================================
-- tetris_sound.vhd
-- Background music (the Tetris theme, "Korobeiniki") and sound effects,
-- as chiptune square waves, mixed and sent to the audio jack.
--
-- HOW A NOTE IS MADE
--   A square wave of frequency f flips between 0 and 1 every 25,000,000 / f
--   clocks (50 MHz clock, two flips per period). So a note is just a counter
--   that flips an output bit when it reaches the note's "half period".
--   Two such tone generators: one for the music, one for the effects.
--
-- MUSIC: a ROM of 40 (note, length) pairs; length in eighth notes.
--   One eighth = 12 frames (0.2 s) at level 0, a bit faster every level.
--   The last frame of each note is silent so repeated notes are heard
--   separately. Plays only while a game is running and SW4 is on.
--
-- EFFECTS: up to 4 (note, frames) steps each, started by game events:
--   lock, line clear, Tetris, garbage arriving, start, win, lose,
--   and the chaos events (task start / done / failed, attack sent / hit,
--   the OIIA cat). If several start in the same clock, the later 'if' wins.
--   A new effect replaces the one playing. Need SW5 on.
--
-- MIXING TO ONE PIN (see docs\learn\06 section 6.5 for the long version):
--   A pin can only be 0 V or 3.3 V, but mixing two sounds and setting a
--   volume needs levels in between. Trick: switch the pin on and off much
--   faster than anyone can hear. The headphones only feel the AVERAGE, so a
--   pin that is on 3 clocks out of 16 sounds like 3/16 of full volume.
--   1. 'loudness' (0..15) = how loud the pin should be right now:
--      +3 while the music square is high, +7 while the effect square is high.
--   2. 'bucket' turns loudness into on/off clocks ("sigma-delta"): every
--      clock pour 'loudness' into a bucket that holds 16; each time it
--      overflows, the pin is on for that clock and 16 is poured away.
--      Over every 16 clocks it overflows exactly 'loudness' times.
-- ============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tetris_sound is
  port (
    clk        : in  std_logic;
    frame_tick : in  std_logic;
    music_on   : in  std_logic;
    sfx_on     : in  std_logic;
    playing    : in  std_logic;
    level      : in  integer range 0 to 15;
    clear_evt  : in  std_logic;                   -- a piece locked...
    clear_n    : in  integer range 0 to 4;        -- ...clearing this many lines
    garb_evt   : in  std_logic;                   -- garbage arrived
    result     : in  integer range 0 to 4;        -- 1 win, 2 lose, 3 draw, 4 game over
    -- chaos events (one-clock pulses)
    task_start_evt : in std_logic;
    task_ok_evt    : in std_logic;
    task_fail_evt  : in std_logic;
    sent_evt       : in std_logic;                -- I sent an attack
    hit_evt        : in std_logic;                -- an attack hit me
    oiia_evt       : in std_logic;                -- the cat arrived
    audio      : out std_logic;                   -- to both audio jack pins
    buzz       : out std_logic                    -- effects only, for the buzzer
  );
end entity;

architecture rtl of tetris_sound is

  -- note number -> half period in clocks (25,000,000 / frequency)
  function half_period(n : integer range 0 to 31) return integer is
  begin
    case n is
      when 1  => return 56818;    -- A4  440.0 Hz
      when 2  => return 50619;    -- B4  493.9
      when 3  => return 47778;    -- C5  523.3
      when 4  => return 42566;    -- D5  587.3
      when 5  => return 37922;    -- E5  659.3
      when 6  => return 35793;    -- F5  698.5
      when 7  => return 31888;    -- G5  784.0
      when 8  => return 28409;    -- A5  880.0
      when 9  => return 95555;    -- C4  261.6
      when 10 => return 75843;    -- E4  329.6
      when 11 => return 63776;    -- G4  392.0
      when 12 => return 191117;   -- C3  130.8
      when 13 => return 286336;   -- F2   87.3
      when 14 => return 227273;   -- A2  110.0
      when 15 => return 23889;    -- C6 1046.5
      when 16 => return 18961;    -- E6 1318.5
      when 17 => return 15944;    -- G6 1568.0
      when 18 => return 11945;    -- C7 2093.0
      when others => return 0;    -- 0 = rest (silence)
    end case;
  end function;

  constant R  : integer := 0;
  constant A4 : integer := 1;  constant B4 : integer := 2;  constant C5 : integer := 3;
  constant D5 : integer := 4;  constant E5 : integer := 5;  constant F5 : integer := 6;
  constant G5 : integer := 7;  constant A5 : integer := 8;
  constant C4 : integer := 9;  constant E4 : integer := 10; constant G4 : integer := 11;
  constant C3 : integer := 12; constant F2 : integer := 13; constant A2 : integer := 14;
  constant C6 : integer := 15; constant E6 : integer := 16; constant G6 : integer := 17;
  constant C7 : integer := 18;

  -- ---------------------------------------------- the melody (8 bars of 8 eighths)
  type int_arr is array (natural range <>) of integer range 0 to 31;
  constant MUS_LEN_N : integer := 40;
  constant MUS_NOTE : int_arr(0 to MUS_LEN_N - 1) := (
    E5, B4, C5, D5, C5, B4,            -- bar 1
    A4, A4, C5, E5, D5, C5,            -- bar 2
    B4, C5, D5, E5,                    -- bar 3
    C5, A4, A4, R,                     -- bar 4
    R, D5, F5, A5, G5, F5,             -- bar 5
    E5, C5, E5, D5, C5,                -- bar 6
    B4, B4, C5, D5, E5,                -- bar 7
    C5, A4, A4, R);                    -- bar 8
  constant MUS_LEN : int_arr(0 to MUS_LEN_N - 1) := (
    2, 1, 1, 2, 1, 1,
    2, 1, 1, 2, 1, 1,
    3, 1, 2, 2,
    2, 2, 2, 2,
    1, 2, 1, 2, 1, 1,
    3, 1, 2, 1, 1,
    2, 1, 1, 2, 2,
    2, 2, 2, 2);

  -- ---------------------------------------------- effects: 4 steps of (note, frames)
  constant FX_LOCK   : integer := 0;
  constant FX_CLEAR  : integer := 1;
  constant FX_TETRIS : integer := 2;
  constant FX_GARB   : integer := 3;
  constant FX_WIN    : integer := 4;
  constant FX_LOSE   : integer := 5;
  constant FX_START  : integer := 6;
  constant FX_TASK   : integer := 7;     -- chaos: a task pops up
  constant FX_OK     : integer := 8;     -- task done
  constant FX_FAIL   : integer := 9;     -- task failed
  constant FX_SENT   : integer := 10;    -- attack sent (a falling "zap")
  constant FX_HIT    : integer := 11;    -- attack arrived (alarm)
  constant FX_OIIA   : integer := 12;    -- "o - i - i - a" (the spinning cat)
  constant N_FX      : integer := 13;
  type fx_t is array (0 to N_FX - 1, 0 to 3) of integer range 0 to 63;
  constant FX_NOTE : fx_t := (
    (C6, R,  R,  R),
    (E6, G6, C7, R),
    (C6, E6, G6, C7),
    (A2, F2, R,  R),
    (C6, E6, G6, C7),
    (G4, E4, C4, C3),
    (C6, G6, R,  R),
    (C6, R,  C6, R),
    (E6, G6, C7, R),
    (C4, F2, R,  R),
    (C7, G6, E6, C6),
    (A5, E5, A5, E5),
    (G4, E6, E6, C5));
  constant FX_FRAMES : fx_t := (
    (2,  0,  0,  0),
    (3,  3,  5,  0),
    (3,  3,  3,  12),
    (5,  8,  0,  0),
    (6,  6,  6,  24),
    (10, 10, 10, 30),
    (4,  8,  0,  0),
    (3,  3,  3,  0),
    (3,  3,  10, 0),
    (8,  16, 0,  0),
    (2,  2,  2,  5),
    (6,  6,  6,  6),
    (10, 7,  7,  16));

  -- music player
  signal mus_i     : integer range 0 to MUS_LEN_N - 1 := 0;
  signal mus_left  : integer range 0 to 63 := 0;          -- frames left in this note
  signal mus_now  : integer range 0 to 31 := 0;          -- sounding now (0 = silent)

  -- effect player
  signal fx_id     : integer range 0 to N_FX - 1 := 0;
  signal fx_step   : integer range 0 to 4 := 4;           -- 4 = not playing
  signal fx_left   : integer range 0 to 63 := 0;
  signal fx_now   : integer range 0 to 31 := 0;

  -- tone generators
  signal m_cnt, s_cnt : integer range 0 to 300000 := 0;
  signal m_sq, s_sq   : std_logic := '0';

  -- edge detection of the game state
  signal playing_d : std_logic := '0';
  signal result_d  : integer range 0 to 4 := 0;

  signal bucket : unsigned(4 downto 0) := (others => '0');   -- sigma-delta "bucket" (see mixer)
  signal buzz_r : std_logic := '0';

  function eighth_frames(lv : integer range 0 to 15) return integer is
  begin
    if lv >= 6 then return 6; else return 12 - lv; end if;
  end function;

begin

  -- ---------------------------------------------------------------- sequencers
  process(clk)
    variable start_fx : integer range -1 to N_FX - 1;
    variable len      : integer range 0 to 63;
  begin
    if rising_edge(clk) then
      playing_d <= playing;
      result_d  <= result;

      -- which effect should start now? (-1 = none)
      start_fx := -1;
      if clear_evt = '1' then
        if clear_n = 4 then start_fx := FX_TETRIS;
        elsif clear_n > 0 then start_fx := FX_CLEAR;
        else start_fx := FX_LOCK;
        end if;
      end if;
      if garb_evt = '1' then start_fx := FX_GARB; end if;
      if playing = '1' and playing_d = '0' then start_fx := FX_START; end if;
      if task_start_evt = '1' then start_fx := FX_TASK; end if;
      if task_fail_evt  = '1' then start_fx := FX_FAIL; end if;
      if task_ok_evt    = '1' then start_fx := FX_OK;   end if;
      if sent_evt       = '1' then start_fx := FX_SENT; end if;
      if hit_evt        = '1' then start_fx := FX_HIT;  end if;
      if oiia_evt       = '1' then start_fx := FX_OIIA; end if;
      if result /= result_d then
        if result = 1 then start_fx := FX_WIN;
        elsif result >= 2 then start_fx := FX_LOSE;
        end if;
      end if;

      -- effect player: step through the 4 steps, one frame at a time
      if start_fx >= 0 then
        fx_id   <= start_fx;
        fx_step <= 0;
        fx_left <= FX_FRAMES(start_fx, 0);
        fx_now <= FX_NOTE(start_fx, 0);
      elsif frame_tick = '1' and fx_step < 4 then
        if fx_left > 1 then
          fx_left <= fx_left - 1;
        elsif fx_step = 3 or FX_FRAMES(fx_id, fx_step + 1) = 0 then
          fx_step <= 4;                           -- finished
          fx_now <= 0;
        else
          fx_step <= fx_step + 1;
          fx_left <= FX_FRAMES(fx_id, fx_step + 1);
          fx_now <= FX_NOTE(fx_id, fx_step + 1);
        end if;
      end if;

      -- music player: only while a game runs, restarts with every game
      if playing = '0' then
        mus_i    <= 0;
        mus_left <= 0;
        mus_now <= 0;
      elsif frame_tick = '1' then
        if mus_left = 0 then                      -- start the next note
          len      := MUS_LEN(mus_i) * eighth_frames(level);
          mus_left <= len - 1;
          mus_now <= MUS_NOTE(mus_i);
          if mus_i = MUS_LEN_N - 1 then mus_i <= 0; else mus_i <= mus_i + 1; end if;
        else
          mus_left <= mus_left - 1;
          if mus_left = 1 then
            mus_now <= 0;                        -- short gap before the next note
          end if;
        end if;
      end if;
    end if;
  end process;

  -- ---------------------------------------------------------------- tone generators
  process(clk)
  begin
    if rising_edge(clk) then
      if mus_now = 0 then
        m_cnt <= 0;
        m_sq  <= '0';
      elsif m_cnt >= half_period(mus_now) - 1 then
        m_cnt <= 0;
        m_sq  <= not m_sq;
      else
        m_cnt <= m_cnt + 1;
      end if;

      if fx_now = 0 then
        s_cnt <= 0;
        s_sq  <= '0';
      elsif s_cnt >= half_period(fx_now) - 1 then
        s_cnt <= 0;
        s_sq  <= not s_sq;
      else
        s_cnt <= s_cnt + 1;
      end if;
    end if;
  end process;

  -- ---------------------------------------------------------------- mixer + sigma-delta
  process(clk)
    variable loudness : integer range 0 to 15;
  begin
    if rising_edge(clk) then
      -- 1. how loud should the pin be right now? (0 = silent .. 15 = full)
      loudness := 0;
      if m_sq = '1' and music_on = '1' then loudness := loudness + 3; end if;   -- music: quiet
      if s_sq = '1' and sfx_on = '1'   then loudness := loudness + 7; end if;   -- effects: louder

      -- 2. the bucket: bits 3..0 = what's in it (0..15), bit 4 = "it overflowed".
      --    Keep bits 3..0 (dropping bit 4 = pouring 16 away), add the loudness.
      --    The new bit 4 is '1' when the sum reached 16 or more: pin on.
      bucket <= ('0' & bucket(3 downto 0)) + to_unsigned(loudness, 5);

      if s_sq = '1' and sfx_on = '1' then buzz_r <= '1'; else buzz_r <= '0'; end if;
    end if;
  end process;

  audio <= bucket(4);
  buzz  <= buzz_r;

end architecture;
