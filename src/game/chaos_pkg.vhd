-- ============================================================================
-- chaos_pkg.vhd
-- Shared definitions for the CHAOS layer: task numbers, attack and bonus
-- numbers, how long each effect lasts, the banner texts, and the OIIA cat.
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
--           1 MATCH    copy a pattern of 8 lights with SW6..SW13  (10-13 s)
--           2 BINARY   set a decimal number in binary             (13-17 s)
--           3 HANDS    don't touch any button for 3-5 seconds     (9-12 s)
--           4 HOLD     keep a bar in the green zone for 3-4 s     (13-16 s)
--           5 TIMING   flip a switch while the marker is in green, 3x (10-13 s)
--           6 HEX      set a 2-digit hex number on the switches   (11-14 s)
--   attacks 0 MIRROR   left and right swapped                 (8-12 s)
--           1 FLIP     the field is drawn upside down          (6-10 s)
--           2 BLIND    locked blocks invisible                 (5-8 s)
--           3 BOUNCE   5-10 bouncing squares over the field    (8-12 s)
--           4 OIIA     the spinning cat over the field         (6-10 s)
--           5 GARBAGE  +3 garbage lines                        (at once)
--           6 CURSED   the next piece becomes an S or a Z      (at once)
--           7 SPEED    pieces fall much faster                 (8-12 s)
--           8 LOCK     all buttons locked until the victim finishes a task
--                      (a task starts for them right away; fail = another one)
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

  constant N_ATTACKS : integer := 9;
  constant A_MIRROR  : integer := 0;
  constant A_FLIP    : integer := 1;
  constant A_BLIND   : integer := 2;
  constant A_BOUNCE  : integer := 3;
  constant A_OIIA    : integer := 4;
  constant A_GARBAGE : integer := 5;
  constant A_CURSED  : integer := 6;
  constant A_SPEED   : integer := 7;
  constant A_LOCK    : integer := 8;

  constant B_FREEZE  : integer := 0;
  constant B_SINK    : integer := 1;
  constant B_IPIECE  : integer := 2;

  -- A random number between lo and hi (both included), from a random byte
  -- r (0..255): lo + r * (hi - lo + 1) / 256. With r spread evenly over
  -- 0..255 every value in lo..hi comes out about equally often.
  function rand_range(lo, hi : integer; r : integer range 0 to 255) return integer;

  -- how long a timed effect lasts, in frames (60 = 1 second): low .. high
  type frames_t is array (natural range <>) of integer range 0 to 1023;
  constant ATTACK_LO : frames_t(0 to N_ATTACKS - 1) := (480, 360, 300, 480, 360, 0, 0, 480, 0);
  constant ATTACK_HI : frames_t(0 to N_ATTACKS - 1) := (720, 600, 480, 720, 600, 0, 0, 720, 0);
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
  --   0..8   INCOMING: <attack>   (the rival hit me)
  --   9..17  SENT: <attack>       (I hit the rival)
  --   18..20 BONUS: <bonus>
  --   21     TASK FAILED
  constant BAN_SENT  : integer := 9;
  constant BAN_BONUS : integer := 18;
  constant BAN_FAIL  : integer := 21;
  constant BANNER_LEN : integer := 20;
  subtype banner_t is std_logic_vector(6 * BANNER_LEN - 1 downto 0);
  function banner_codes(n : integer range 0 to 31) return banner_t;

  -- ------------------------------------------------------------- the cat
  -- 16 x 16 pixels, 3 bits each: 0 = see-through, 1 = black, 2 = grey fur,
  -- 3 = white, 4 = pink. Row r, column c = bits 3c+2..3c of CAT(r).
  subtype cat_row_t is std_logic_vector(47 downto 0);
  type cat_t is array (0 to 15) of cat_row_t;
  function cat_pixel(r, c : integer range 0 to 15) return integer;

end package chaos_pkg;


package body chaos_pkg is

  type banner_table_t is array (0 to 21) of banner_t;
  constant BANNERS : banner_table_t := (
    to_codes(" INCOMING: MIRROR!  "),
    to_codes(" INCOMING: FLIPPED! "),
    to_codes(" INCOMING: BLIND!   "),
    to_codes(" INCOMING: BOUNCERS "),
    to_codes("  INCOMING: OIIA!   "),
    to_codes(" INCOMING: GARBAGE! "),
    to_codes(" INCOMING: CURSED!  "),
    to_codes(" INCOMING: SPEED UP "),
    to_codes("LOCKED! DO THE TASK "),
    to_codes("   SENT: MIRROR!    "),
    to_codes("   SENT: FLIP!      "),
    to_codes("   SENT: BLIND!     "),
    to_codes("   SENT: BOUNCERS!  "),
    to_codes("   SENT: OIIA CAT!  "),
    to_codes("   SENT: GARBAGE!   "),
    to_codes("   SENT: CURSE!     "),
    to_codes("   SENT: SPEED UP!  "),
    to_codes("   SENT: LOCK!      "),
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
    if n <= 21 then
      return BANNERS(n);
    end if;
    return to_codes("                    ");
  end function;

  -- '.' see-through, 'K' black, 'G' grey, 'W' white, 'P' pink
  function crow(s : string) return cat_row_t is
    variable r : cat_row_t := (others => '0');
    variable v : integer range 0 to 7;
  begin
    for c in 0 to 15 loop
      case s(s'low + c) is
        when 'K'    => v := 1;
        when 'G'    => v := 2;
        when 'W'    => v := 3;
        when 'P'    => v := 4;
        when others => v := 0;
      end case;
      r(3*c + 2 downto 3*c) := std_logic_vector(to_unsigned(v, 3));
    end loop;
    return r;
  end function;

  constant CAT : cat_t := (
    crow("..K..........K.."),
    crow(".KGK........KGK."),
    crow(".KGGK......KGGK."),
    crow(".KGPGKKKKKKGPGK."),
    crow(".KGGGGGGGGGGGGK."),
    crow("KGGGGGGGGGGGGGGK"),
    crow("KGGKKGGGGGGKKGGK"),
    crow("KGGKWGGGGGGKWGGK"),
    crow("KGGGGGGPPGGGGGGK"),
    crow("KGGGWWGKKGWWGGGK"),
    crow("KGGWWWWGGWWWWGGK"),
    crow(".KGGWWWWWWWWGGK."),
    crow(".KGGGWWWWWWGGGK."),
    crow("..KGGGGGGGGGGK.."),
    crow("...KKGGGGGGKK..."),
    crow(".....KKKKKK.....")
  );

  function cat_pixel(r, c : integer range 0 to 15) return integer is
    variable row : cat_row_t;
  begin
    row := CAT(r);
    return to_integer(unsigned(row(3*c + 2 downto 3*c)));
  end function;

end package body chaos_pkg;
