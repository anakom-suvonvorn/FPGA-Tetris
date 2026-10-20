-- ============================================================================
-- tetris_sound.vhd
-- Sound effects (chiptune square waves) mixed with the media sound (the
-- music and the videos' sound from the flash, media_engine's 'pcm'), sent
-- to the audio jack.
-- (Before the media layer this block also played the Tetris theme from a
-- ROM of notes; the real recordings in the flash replaced it.)
--
-- HOW A NOTE IS MADE
--   A square wave of frequency f flips between 0 and 1 every 25,000,000 / f
--   clocks (50 MHz clock, two flips per period). So a note is just a counter
--   that flips an output bit when it reaches the note's "half period".
--
-- EFFECTS: up to 4 (note, frames) steps each, started by game events:
--   lock, line clear, Tetris, garbage arriving, start, win, lose,
--   and the chaos events (task start / done / failed, attack sent / hit). If several start in the same clock, the later 'if' wins.
--   A new effect replaces the one playing. Need SW5 on.
--
-- MIXING TO ONE PIN (see docs\learn\06 section 6.5 for the long version):
--   A pin can only be 0 V or 3.3 V, but mixing two sounds and setting a
--   volume needs levels in between. Trick: switch the pin on and off much
--   faster than anyone can hear. The headphones only feel the AVERAGE, so a
--   pin that is on 1,024 clocks out of 4,096 sounds like 1/4 of full volume.
--   1. 'loudness' (0..4095) = how loud the pin should be right now:
--      1536 + the media sample / 32 (-1024..+1023)
--      + 1024 while the effect square is high.
--   2. 'bucket' turns loudness into on/off clocks ("sigma-delta"): every
--      clock pour 'loudness' into a bucket that holds 4,096; each time it
--      overflows, the pin is on for that clock and 4,096 is poured away.
--      Over every 4,096 clocks it overflows exactly 'loudness' times.
--      (Before the media layer it was the same idea with 16 levels.)
-- ============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tetris_sound is
  port (
    clk        : in  std_logic;
    frame_tick : in  std_logic;
    music_on   : in  std_logic;                   -- SW4: the media sound on
    sfx_on     : in  std_logic;
    playing    : in  std_logic;
    pcm        : in  signed(15 downto 0);          -- media sound (media_engine)
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
    audio      : out std_logic;                   -- to both audio jack pins
    buzz       : out std_logic                    -- effects only, for the buzzer
  );
end entity;

architecture rtl of tetris_sound is

  -- note number -> half period in clocks (25,000,000 / frequency)
  function half_period(n : integer range 0 to 31) return integer is
  begin
    case n is
      when 5  => return 37922;    -- E5  659.3
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
  constant E5 : integer := 5;  constant A5 : integer := 8;   -- (1-4, 6, 7 were the melody's)
  constant C4 : integer := 9;  constant E4 : integer := 10; constant G4 : integer := 11;
  constant C3 : integer := 12; constant F2 : integer := 13; constant A2 : integer := 14;
  constant C6 : integer := 15; constant E6 : integer := 16; constant G6 : integer := 17;
  constant C7 : integer := 18;

  type int_arr is array (natural range <>) of integer range 0 to 31;

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
  constant N_FX      : integer := 12;
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
    (A5, E5, A5, E5));
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
    (6,  6,  6,  6));

  -- effect player
  signal fx_id     : integer range 0 to N_FX - 1 := 0;
  signal fx_step   : integer range 0 to 4 := 4;           -- 4 = not playing
  signal fx_left   : integer range 0 to 63 := 0;
  signal fx_now   : integer range 0 to 31 := 0;

  -- tone generator
  signal s_cnt : integer range 0 to 300000 := 0;
  signal s_sq  : std_logic := '0';

  -- edge detection of the game state
  signal playing_d : std_logic := '0';
  signal result_d  : integer range 0 to 4 := 0;

  signal bucket : unsigned(12 downto 0) := (others => '0');  -- sigma-delta "bucket" (see mixer)
  signal buzz_r : std_logic := '0';


begin

  -- ---------------------------------------------------------------- sequencers
  process(clk)
    variable start_fx : integer range -1 to N_FX - 1;
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

    end if;
  end process;

  -- ---------------------------------------------------------------- tone generator
  process(clk)
  begin
    if rising_edge(clk) then
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
    variable loudness : integer range 0 to 4095;
  begin
    if rising_edge(clk) then
      -- 1. how loud should the pin be right now? (0 = silent .. 4095 = full)
      loudness := 1536;
      if music_on = '1' then
        loudness := loudness + to_integer(pcm(15 downto 5));                  -- media: -1024..+1023
      end if;
      if s_sq = '1' and sfx_on = '1' then loudness := loudness + 1024; end if;  -- effects

      -- 2. the bucket: bits 11..0 = what's in it, bit 12 = "it overflowed".
      --    Keep bits 11..0 (dropping bit 12 = pouring 4,096 away), add the
      --    loudness. The new bit 12 is '1' when the sum reached 4,096: pin on.
      bucket <= ('0' & bucket(11 downto 0)) + to_unsigned(loudness, 13);

      if s_sq = '1' and sfx_on = '1' then buzz_r <= '1'; else buzz_r <= '0'; end if;
    end if;
  end process;

  audio <= bucket(12);
  buzz  <= buzz_r;

end architecture;
