-- ============================================================================
-- chaos_render.vhd
-- Draws everything the CHAOS layer adds to the picture, as an OVERLAY:
-- for each pixel it says "draw this colour on top" (ov_on = '1', ov_rgb) or
-- "nothing here" (ov_on = '0'). tetris_render puts it over its own picture.
--
--   * the TASK panel, right side       x 428..627, y 284..467
--       only while a task runs (otherwise just the words CHAOS MODE ON,
--       so a task always comes as a surprise). Two text lines, the 8 task
--       switches (SW22 left .. SW11 right, like the board), target lights (MATCH), a meter
--       with a green zone (HOLD, TIMING), a progress bar and a time bar.
--       The frame turns red while my buttons are LOCKED.
--   * the BANNER under the field       x 176..423, y 444..467
--   * BOUNCERS: 5..10 squares of 32 x 32 bouncing around the field (attack).
--       With the media file loaded, each shows a friend's face: this block
--       says which face pixel (face_en, face_addr = face * 1024 + row * 32 +
--       column) and media_engine / media_mix draw it on top.
--
-- TIMING: same as text_multi. Everything is worked out from (x, y) and put
-- in r_* registers on the next clock edge; the text_multi pixels arrive at
-- that same edge. So ov_on / ov_rgb are ready exactly when tetris_render's
-- stage 2 needs them.
-- ============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.tetris_pkg.all;
use work.text_pkg.all;
use work.chaos_pkg.all;

entity chaos_render is
  port (
    clk        : in  std_logic;
    frame_tick : in  std_logic;
    x, y       : in  unsigned(9 downto 0);
    enable     : in  std_logic;                     -- chaos switched on
    bounce     : in  std_logic;
    n_bounce   : in  integer range 5 to 10;         -- how many bouncers
    locked     : in  std_logic;                     -- LOCK attack: red frame
    -- task panel
    t_active   : in  std_logic;
    t_task     : in  integer range 0 to N_TASKS - 1;
    t_sel      : in  integer range 0 to 7;
    t_target   : in  std_logic_vector(7 downto 0);
    t_sw       : in  std_logic_vector(7 downto 0);
    t_count    : in  integer range 0 to 15;
    t_meter    : in  integer range 0 to 191;
    t_zone_lo  : in  integer range 0 to 191;
    t_zone_hi  : in  integer range 0 to 191;
    t_progress : in  integer range 0 to 191;
    t_secs     : in  integer range 0 to 31;
    t_offsecs    : in  integer range 0 to 7;          -- HANDS: seconds to keep off
    -- banner
    banner_on  : in  std_logic;
    banner_id  : in  integer range 0 to 31;
    -- overlay out
    ov_on      : out std_logic;
    ov_rgb     : out rgb_t;
    -- faces on the bouncers (same timing as ov_on)
    face_en    : out std_logic;
    face_addr  : out unsigned(11 downto 0)
  );
end entity;

architecture rtl of chaos_render is
  constant FX0 : integer := 240;  constant FY0 : integer := 80;
  constant FW  : integer := 160;  constant FH  : integer := 320;
  constant PX0 : integer := 432;  constant PY0 : integer := 288;    -- panel inside
  constant BQ  : integer := 32;                                     -- bouncer size

  -- bouncers: position + direction + speed + colour, 10 of them
  -- (only the first n_bounce are drawn)
  constant NB : integer := 10;
  type posn_t is array (0 to NB - 1) of integer range 0 to 639;
  type spdn_t is array (0 to NB - 1) of integer range 1 to 7;
  type rgbn_t is array (0 to NB - 1) of rgb_t;
  constant SPX : spdn_t := (3, 2, 4, 3, 5, 2, 4, 1, 3, 5);
  constant SPY : spdn_t := (2, 3, 3, 4, 2, 5, 1, 4, 5, 3);
  constant BCOL : rgbn_t := (x"F2F", x"2FF", x"FF2", x"FFF", x"F80",
                             x"8F2", x"F44", x"48F", x"FAF", x"0F8");
  signal bx : posn_t := (250, 300, 330, 360, 260, 350, 280, 310, 365, 245);
  signal by : posn_t := (100, 200, 300, 150, 360, 90, 240, 130, 330, 200);
  signal bdx : std_logic_vector(NB - 1 downto 0) := "0101100110";  -- '1' = moving right
  signal bdy : std_logic_vector(NB - 1 downto 0) := "1001011010";  -- '1' = moving down
  signal bk  : integer range 0 to NB := NB;                        -- bouncer being moved (NB = none)

  signal spin  : unsigned(1 downto 0) := (others => '0');     -- counts frames (shuffles the faces)

  -- which face each bouncer wears: (bouncer + foff) mod 4, new foff per attack
  signal foff    : unsigned(1 downto 0) := (others => '0');
  signal bounce_d : std_logic := '0';
  signal r_fen   : std_logic := '0';
  signal r_faddr : unsigned(11 downto 0) := (others => '0');

  -- registered overlay (from geometry), plus where text may appear
  signal r_on      : std_logic := '0';
  signal r_rgb     : rgb_t := (others => '0');
  signal r_panel   : std_logic := '0';
  signal r_band    : std_logic := '0';
  signal r_ban_rgb : rgb_t := (others => '0');

  signal t_l1, t_l2, t_ban : std_logic;
  signal l1_chars, l2_chars : std_logic_vector(95 downto 0);
  signal ban_chars : banner_t;
  signal txt_chars : std_logic_vector(6 * (32 + BANNER_LEN) - 1 downto 0);
  signal txt_pix   : std_logic_vector(2 downto 0);

  -- put a digit (0..9) into character position i of a 16-character line
  function put_digit(line : std_logic_vector(95 downto 0); i : integer; d : integer) return std_logic_vector is
    variable r : std_logic_vector(95 downto 0) := line;
  begin
    r(6*i + 5 downto 6*i) := std_logic_vector(to_unsigned(d, 6));
    return r;
  end function;

  -- the board label of task switch 0..7 (bit 0 = SW11 ... bit 7 = SW22, the
  -- 8 leftmost switches; the board skips the numbers used by the buttons)
  type swnum_t is array (0 to 7) of integer range 0 to 31;
  constant SW_NUM : swnum_t := (11, 12, 13, 15, 17, 19, 21, 22);

  type lines_t is array (0 to N_TASKS) of std_logic_vector(95 downto 0);
  constant L1_TXT : lines_t := (
    to_codes("FLIP THE SWITCH "), to_codes("COPY THE LIGHTS "), to_codes("SET IN BINARY:  "),
    to_codes("HANDS OFF!      "), to_codes("KEEP THE BAR IN "), to_codes("FLIP IN GREEN   "),
    to_codes("SET IN HEX:     "),
    to_codes(" CHAOS MODE ON  "));
  constant L2_TXT : lines_t := (
    to_codes("SW00 TEN TIMES  "), to_codes("WITH SW22-SW11  "), to_codes("      000       "),
    to_codes("NO BUTTONS 0 SEC"), to_codes("GREEN WITH SW00 "), to_codes("SW00  HITS: 0/3 "),
    to_codes("       00       "),
    to_codes("                "));
begin

  -- ---------------------------------------------------------------- moving things
  process(clk)
  begin
    if rising_edge(clk) then
      bounce_d <= bounce;
      if bounce = '1' and bounce_d = '0' then
        foff <= spin;                                  -- a new attack: shuffle the faces
      end if;
      -- the bouncers move one after the other, one per clock, in the 10
      -- clocks after frame_tick (the screen is blank then): one set of
      -- adders and comparators instead of 10
      if bk < NB then
        if bdx(bk) = '1' then
          if bx(bk) + SPX(bk) >= FX0 + FW - BQ then bdx(bk) <= '0'; else bx(bk) <= bx(bk) + SPX(bk); end if;
        else
          if bx(bk) - SPX(bk) <= FX0 then bdx(bk) <= '1'; else bx(bk) <= bx(bk) - SPX(bk); end if;
        end if;
        if bdy(bk) = '1' then
          if by(bk) + SPY(bk) >= FY0 + FH - BQ then bdy(bk) <= '0'; else by(bk) <= by(bk) + SPY(bk); end if;
        else
          if by(bk) - SPY(bk) <= FY0 then bdy(bk) <= '1'; else by(bk) <= by(bk) - SPY(bk); end if;
        end if;
        bk <= bk + 1;
      end if;
      if frame_tick = '1' then
        spin <= spin + 1;
        bk   <= 0;                                     -- start moving the bouncers
      end if;
    end if;
  end process;

  -- ---------------------------------------------------------------- text
  process(t_active, t_task, t_sel, t_target, t_count, t_offsecs)
    variable l1, l2 : std_logic_vector(95 downto 0);
    variable swn, v : integer range 0 to 255;
  begin
    swn := SW_NUM(t_sel);                          -- switch index 0..7 -> its label SW11..SW22
    v   := to_integer(unsigned(t_target));
    if t_active = '0' then
      l1 := L1_TXT(N_TASKS);                       -- just "CHAOS MODE ON"
      l2 := L2_TXT(N_TASKS);
    else
      l1 := L1_TXT(t_task);
      l2 := L2_TXT(t_task);
      case t_task is
        when T_FLIP | T_TIMING =>
          l2 := put_digit(l2, 2, swn / 10);
          l2 := put_digit(l2, 3, swn mod 10);
          if t_task = T_TIMING then
            if t_count <= 3 then l2 := put_digit(l2, 12, t_count); end if;
          end if;
        when T_HOLD =>
          l2 := put_digit(l2, 13, swn / 10);
          l2 := put_digit(l2, 14, swn mod 10);
        when T_BINARY =>
          l2 := put_digit(l2, 6, v / 100);
          l2 := put_digit(l2, 7, (v / 10) mod 10);
          l2 := put_digit(l2, 8, v mod 10);
        when T_HEX =>
          -- character codes 0..15 are '0'..'9','A'..'F': a hex digit is its own code
          l2 := put_digit(l2, 7, to_integer(unsigned(t_target(7 downto 4))));
          l2 := put_digit(l2, 8, to_integer(unsigned(t_target(3 downto 0))));
        when T_HANDS =>
          l2 := put_digit(l2, 11, t_offsecs);
        when others =>
          null;
      end case;
    end if;
    l1_chars <= l1;
    l2_chars <= l2;
  end process;

  ban_chars <= banner_codes(banner_id);

  -- the panel's 2 lines and the banner through ONE font ROM (text_multi)
  txt_chars <= ban_chars & l2_chars & l1_chars;
  u_text : entity work.text_multi
    generic map (N => 3,
                 X0S    => (PX0, PX0, 180),
                 Y0S    => (292, 312, 449),
                 LENS   => (16,  16,  BANNER_LEN),
                 SHIFTS => (1,   1,   1))
    port map (clk => clk, x => x, y => y, chars => txt_chars, en => "111", pix => txt_pix);
  t_l1  <= txt_pix(0);
  t_l2  <= txt_pix(1);
  t_ban <= txt_pix(2);

  -- ---------------------------------------------------------------- geometry
  process(clk)
    variable xi, yi : integer range 0 to 1023;
    variable hit    : std_logic;
    variable c      : rgb_t;
    variable i8     : integer range 0 to 7;
    variable bit_on : std_logic;
    variable px     : integer range 0 to 255;
    variable hb     : integer range 0 to NB - 1;
    variable fhit   : std_logic;
    variable fdx, fdy : unsigned(9 downto 0);
  begin
    if rising_edge(clk) then
      xi := to_integer(x);
      yi := to_integer(y);
      hit := '0';
      c  := (others => '0');

      -- ------------------------------------------ the task panel
      r_panel <= '0';
      if enable = '1' and t_active = '0' then
        -- no task: only the first text line ("CHAOS MODE ON"), no box
        if xi >= PX0 and xi < PX0 + 192 and yi >= 290 and yi < 308 then
          r_panel <= '1';
        end if;
      elsif enable = '1' and xi >= PX0 - 4 and xi < PX0 + 196 and yi >= PY0 - 4 and yi < PY0 + 180 then
        hit := '1';
        r_panel <= '1';
        if xi < PX0 - 2 or xi >= PX0 + 194 or yi < PY0 - 2 or yi >= PY0 + 178 then
          if locked = '1' then
            c := x"F22";                              -- red frame: buttons locked
          else
            c := x"A3C";                              -- purple frame
          end if;
        else
          c := x"101";                                -- dark inside
        end if;
        if xi >= PX0 and xi < PX0 + 192 then
          px := xi - PX0;
          i8 := 7 - px / 24;                           -- switch number under x (SW22 left)
          -- target lights (MATCH): a small lamp per switch
          if t_active = '1' and t_task = T_MATCH and yi >= 338 and yi < 346 and (px mod 24) >= 6 and (px mod 24) < 18 then
            if t_target(i8) = '1' then c := x"FE3"; else c := x"332"; end if;
          end if;
          -- the 8 switches: a slot with a knob at the top (on) or bottom (off)
          if yi >= 350 and yi < 374 and (px mod 24) >= 7 and (px mod 24) < 17 then
            if t_active = '1' and (t_task = T_FLIP or t_task = T_HOLD or t_task = T_TIMING) and i8 = t_sel then
              c := x"760";                             -- the switch this task wants
            else
              c := x"333";
            end if;
            bit_on := t_sw(i8);
            if (bit_on = '1' and yi < 361) or (bit_on = '0' and yi >= 363) then
              c := x"DDD";                             -- the knob
            end if;
          end if;
          -- meter with green zone and white marker (HOLD, TIMING)
          if t_active = '1' and (t_task = T_HOLD or t_task = T_TIMING) and yi >= 382 and yi < 398 then
            c := x"222";
            if px >= t_zone_lo and px < t_zone_hi then c := x"2A4"; end if;
            if px >= t_meter and px < t_meter + 4 then c := x"FFF"; end if;
          end if;
          -- progress bar
          if t_active = '1' and yi >= 406 and yi < 414 then
            if px < t_progress then c := x"3CE"; else c := x"123"; end if;
          end if;
          -- time bar (11 px per second, at most 17 s)
          if yi >= 422 and yi < 428 then
            if px < t_secs * 11 then
              if t_active = '1' and t_secs < 3 then c := x"F44"; else c := x"999"; end if;
            else
              c := x"222";
            end if;
          end if;
        end if;
      end if;

      -- ------------------------------------------ the banner band
      r_band <= '0';
      if banner_on = '1' and xi >= 176 and xi < 424 and yi >= 444 and yi < 468 then
        hit := '1';
        r_band <= '1';
        c := x"000";
      end if;
      if banner_id < BAN_SENT or banner_id = BAN_FAIL then
        r_ban_rgb <= x"F55";                           -- incoming / failed: red
      elsif banner_id < BAN_BONUS then
        r_ban_rgb <= x"FD3";                           -- sent: gold
      else
        r_ban_rgb <= x"5E7";                           -- bonus: green
      end if;

      -- ------------------------------------------ bouncers
      fhit := '0';
      hb   := 0;
      if bounce = '1' then
        for i in 0 to NB - 1 loop
          if i < n_bounce and xi >= bx(i) and xi < bx(i) + BQ and yi >= by(i) and yi < by(i) + BQ then
            hit  := '1';
            fhit := '1';
            c    := BCOL(i);
            hb   := i;
          end if;
        end loop;
      end if;
      -- the face pixel under (x, y): face, row, column (all 0..31)
      fdx := x - to_unsigned(bx(hb), 10);
      fdy := y - to_unsigned(by(hb), 10);
      r_faddr <= (to_unsigned(hb mod 4, 2) + foff) & fdy(4 downto 0) & fdx(4 downto 0);


      r_fen <= fhit;
      r_on  <= hit;
      r_rgb <= c;
    end if;
  end process;

  -- text goes on top of the panel / band it belongs to
  face_en   <= r_fen;
  face_addr <= r_faddr;

  ov_on  <= '1' when (r_panel = '1' and (t_l1 = '1' or t_l2 = '1')) or (r_band = '1' and t_ban = '1') else r_on;
  ov_rgb <= x"C6F"     when r_panel = '1' and t_l1 = '1' and t_active = '0' else
            x"FFF"     when r_panel = '1' and t_l1 = '1' else
            x"9BD"     when r_panel = '1' and t_l2 = '1' else
            r_ban_rgb  when r_band = '1' and t_ban = '1' else
            r_rgb;

end architecture;
