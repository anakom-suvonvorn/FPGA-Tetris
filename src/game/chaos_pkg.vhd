-- ============================================================================
-- chaos_pkg.vhd
-- Shared definitions for the CHAOS layer: task numbers, attack and bonus
-- numbers, how long each effect lasts, and the banner texts.
--
-- THE IDEA
--   While chaos is on, a TASK pops up at a random moment (the right panel
--   only appears then; otherwise just "CHAOS MODE ON" is shown), done with
--   the slide switches while you keep playing Tetris with the buttons.
--   Finish it in time and either the RIVAL gets an ATTACK (sent over the
--   link as a type-4 message) or YOU get a BONUS. With no rival connected it
--   is always a bonus.
--
-- RANDOM TIMES
--   Every time below is a RANGE: when the thing starts, a random length
--   between the low and the high bound is picked (rand_range), so no two
--   are the same.
--
-- NUMBERS
--   tasks   0 FLIP     flip one switch 10 times                   (7-9 s)
--           1 MATCH    copy a pattern of 8 lights with SW22..SW11 (10-13 s)
--           2 BINARY   set a decimal number in binary             (13-17 s)
--           3 HANDS    don't touch any button for 3-5 seconds     (9-12 s)
--           4 HOLD     keep a bar in the green zone for 3-4 s     (13-16 s)
--           5 TIMING   flip a switch while the marker is in green, 3x (10-13 s)
--           6 HEX      set a 2-digit hex number on the switches   (11-14 s)
--   attacks 0 MIRROR   left and right swapped                 (8-12 s)
--           1 FLIP     the field is drawn upside down          (6-10 s)
--           2 BLIND    locked blocks invisible                 (5-8 s)
--           3 BOUNCE   5-10 bouncing squares over the field    (8-12 s)
--           4 GARBAGE  +3 garbage lines                        (at once)
--           5 CURSED   the next piece becomes an S or a Z      (at once)
--           6 SPEED    pieces fall much faster                 (8-12 s)
--           7 LOCK     all buttons locked until the victim finishes a task
--                      (a task starts for them right away; fail = another one)
--           8 BAD APPLE   } MEDIA attacks: a video from the flash plays behind
--           9 OIIA OIIA   } the rival's game, its sound replaces their music
--          10 JEVIL       } (Jevil also floats over the screen). Full length
--                         (40-84 s). The SENDER can't send another media
--                         attack until it is over + 10 s (MEDIA_COOL).
--                         Needs the media file in the flash (media_engine).
--   (Until the media layer, attack 4 was a little OIIA cat drawn from a ROM;
--   the real OIIA video replaced it.)
--   bonuses 0 FREEZE   no gravity                              (3-5 s)
--           1 SINK     remove the 2 bottom rows now, cancel waiting garbage
--           2 I PIECE  the next piece becomes an I
-- ============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.text_pkg.all;

package chaos_pkg is

  constant N_TASKS : integer := 7;
  constant T_FLIP   : integer := 0;
  constant T_MATCH  : integer := 1;
  constant T_BINARY : integer := 2;
  constant T_HANDS  : integer := 3;
  constant T_HOLD   : integer := 4;
  constant T_TIMING : integer := 5;
  constant T_HEX    : integer := 6;

  constant N_ATTACKS : integer := 11;
  constant A_MIRROR  : integer := 0;
  constant A_FLIP    : integer := 1;
  constant A_BLIND   : integer := 2;
  constant A_BOUNCE  : integer := 3;
  constant A_GARBAGE : integer := 4;
  constant A_CURSED  : integer := 5;
  constant A_SPEED   : integer := 6;
  constant A_LOCK    : integer := 7;
  constant A_APPLE   : integer := 8;      -- the 3 media attacks, in the order of
  constant A_OIIA    : integer := 9;      -- the attack items in the media file
  constant A_JEVIL   : integer := 10;
  constant A_MEDIA   : integer := 8;      -- ids >= this are media attacks

  constant B_FREEZE  : integer := 0;
  constant B_SINK    : integer := 1;
  constant B_IPIECE  : integer := 2;

  -- A random number between lo and hi (both included), from a random byte
  -- r (0..255): lo + r * (hi - lo + 1) / 256. With r spread evenly over
  -- 0..255 every value in lo..hi comes out about equally often.
  function rand_range(lo, hi : integer; r : integer range 0 to 255) return integer;

  -- how long a timed effect lasts, in frames (60 = 1 second): low .. high
  type frames_t is array (natural range <>) of integer range 0 to 1023;
  constant ATTACK_LO : frames_t(0 to N_ATTACKS - 1) := (480, 360, 300, 480, 0, 0, 480, 0, 0, 0, 0);
  constant ATTACK_HI : frames_t(0 to N_ATTACKS - 1) := (720, 600, 480, 720, 0, 0, 720, 0, 0, 0, 0);

  -- media attacks: how long the sender waits before it may send another
  -- one = the item's length (tools\media_plan.py) + 10 s, in frames
  type cool_t is array (0 to 2) of integer range 0 to 8191;
  constant MEDIA_COOL : cool_t := (5052 + 600, 2625 + 600, 2418 + 600);  -- 84.2 s, 43.75 s, 40.3 s
  constant FREEZE_LO : integer := 180;
  constant FREEZE_HI : integer := 300;

  -- time allowed for each task, in frames: low .. high
  constant TASK_LO : frames_t(0 to N_TASKS - 1) := (420, 600, 780, 540, 780, 600, 660);
  constant TASK_HI : frames_t(0 to N_TASKS - 1) := (540, 780, 1020, 720, 960, 780, 840);

  -- time between tasks, in frames (10..17 s)
  constant GAP_LO : integer := 600;
  constant GAP_HI : integer := 1020;

  -- ------------------------------------------------------------- banners
  -- The banner under the field: 20 characters, chosen by number.
  --   0..10  INCOMING: <attack>   (the rival hit me)
  --   11..21 SENT: <attack>       (I hit the rival)
  --   22..24 BONUS: <bonus>
  --   25     TASK FAILED
  constant BAN_SENT  : integer := 11;
  constant BAN_BONUS : integer := 22;
  constant BAN_FAIL  : integer := 25;
  constant BANNER_LEN : integer := 20;
  subtype banner_t is std_logic_vector(6 * BANNER_LEN - 1 downto 0);
  function banner_codes(n : integer range 0 to 31) return banner_t;


end package chaos_pkg;


package body chaos_pkg is

  type banner_table_t is array (0 to 25) of banner_t;
  constant BANNERS : banner_table_t := (
    to_codes(" INCOMING: MIRROR!  "),
    to_codes(" INCOMING: FLIPPED! "),
    to_codes(" INCOMING: BLIND!   "),
    to_codes(" INCOMING: BOUNCERS "),
    to_codes(" INCOMING: GARBAGE! "),
    to_codes(" INCOMING: CURSED!  "),
    to_codes(" INCOMING: SPEED UP "),
    to_codes("LOCKED! DO THE TASK "),
    to_codes("INCOMING: BAD APPLE "),
    to_codes("INCOMING: OIIA OIIA!"),
    to_codes(" INCOMING: JEVIL!   "),
    to_codes("   SENT: MIRROR!    "),
    to_codes("   SENT: FLIP!      "),
    to_codes("   SENT: BLIND!     "),
    to_codes("   SENT: BOUNCERS!  "),
    to_codes("   SENT: GARBAGE!   "),
    to_codes("   SENT: CURSE!     "),
    to_codes("   SENT: SPEED UP!  "),
    to_codes("   SENT: LOCK!      "),
    to_codes("   SENT: BAD APPLE! "),
    to_codes("   SENT: OIIA OIIA! "),
    to_codes("   SENT: JEVIL!     "),
    to_codes(" BONUS: FREEZE TIME "),
    to_codes(" BONUS: SINK 2 ROWS "),
    to_codes(" BONUS: I PIECE NEXT"),
    to_codes("    TASK FAILED     ")
  );

  function rand_range(lo, hi : integer; r : integer range 0 to 255) return integer is
  begin
    return lo + (r * (hi - lo + 1)) / 256;
  end function;

  function banner_codes(n : integer range 0 to 31) return banner_t is
  begin
    if n <= 25 then
      return BANNERS(n);
    end if;
    return to_codes("                    ");
  end function;


end package body chaos_pkg;
