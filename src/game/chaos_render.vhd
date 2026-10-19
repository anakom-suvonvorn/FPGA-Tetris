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
--   * BOUNCERS: 5..10 squares bouncing around the field (attack)
--   * the OIIA CAT: a 64 x 64 cat bouncing over the field, "spinning"
--     (attack). The spin is faked with 4 pictures: normal, squeezed to half
--     width, mirrored, mirrored + squeezed - like a coin turning.
--
-- TIMING: same as text_layer. Everything is worked out from (x, y) and put
-- in r_* registers on the next clock edge; the text_layer pixels arrive at
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
    cat        : in  std_logic;
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
    ov_rgb     : out rgb_t
  );
end entity;

architecture rtl of chaos_render is
  constant FX0 : integer := 240;  constant FY0 : integer := 80;
  constant FW  : integer := 160;  constant FH  : integer := 320;
  constant PX0 : integer := 432;  constant PY0 : integer := 288;    -- panel inside
  constant BQ  : integer := 20;                                     -- bouncer size
  constant CS  : integer := 64;                                     -- cat size

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
  signal bx : posn_t := (250, 300, 330, 370, 260, 350, 280, 310, 375, 245);
  signal by : posn_t := (100, 200, 300, 150, 360, 90, 240, 130, 330, 200);
  signal bdx : std_logic_vector(NB - 1 downto 0) := "0101100110";  -- '1' = moving right
  signal bdy : std_logic_vector(NB - 1 downto 0) := "1001011010";  -- '1' = moving down

  -- the cat
  signal cx    : integer range 0 to 639 := 260;
  signal cy    : integer range 0 to 479 := 120;
  signal cdx, cdy : std_logic := '1';
  signal spin  : unsigned(4 downto 0) := (others => '0');     -- picture = bits 4..3

  -- registered overlay (from geometry), plus where text may appear
  signal r_on      : std_logic := '0';
  signal r_rgb     : rgb_t := (others => '0');
  signal r_panel   : std_logic := '0';
  signal r_band    : std_logic := '0';
  signal r_ban_rgb : rgb_t := (others => '0');

  signal t_l1, t_l2, t_ban : std_logic;
  signal l1_chars, l2_chars : std_logic_vector(95 downto 0);
  signal ban_chars : banner_t;

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
      if frame_tick = '1' then
        spin <= spin + 1;
        for i in 0 to NB - 1 loop
          if bdx(i) = '1' then
            if bx(i) + SPX(i) >= FX0 + FW - BQ then bdx(i) <= '0'; else bx(i) <= bx(i) + SPX(i); end if;
          else
            if bx(i) - SPX(i) <= FX0 then bdx(i) <= '1'; else bx(i) <= bx(i) - SPX(i); end if;
          end if;
          if bdy(i) = '1' then
            if by(i) + SPY(i) >= FY0 + FH - BQ then bdy(i) <= '0'; else by(i) <= by(i) + SPY(i); end if;
          else
            if by(i) - SPY(i) <= FY0 then bdy(i) <= '1'; else by(i) <= by(i) - SPY(i); end if;
          end if;
        end loop;
        if cdx = '1' then
          if cx + 2 >= FX0 + FW - CS then cdx <= '0'; else cx <= cx + 2; end if;
        else
          if cx - 2 <= FX0 then cdx <= '1'; else cx <= cx - 2; end if;
        end if;
        if cdy = '1' then
          if cy + 3 >= FY0 + FH - CS then cdy <= '0'; else cy <= cy + 3; end if;
        else
          if cy - 3 <= FY0 then cdy <= '1'; else cy <= cy - 3; end if;
        end if;
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

  u_l1  : entity work.text_layer generic map (X0 => PX0, Y0 => 292, LEN => 16, SHIFT => 1)
    port map (clk => clk, x => x, y => y, chars => l1_chars, pix => t_l1);
  u_l2  : entity work.text_layer generic map (X0 => PX0, Y0 => 312, LEN => 16, SHIFT => 1)
    port map (clk => clk, x => x, y => y, chars => l2_chars, pix => t_l2);
  u_ban : entity work.text_layer generic map (X0 => 180, Y0 => 449, LEN => BANNER_LEN, SHIFT => 1)
    port map (clk => clk, x => x, y => y, chars => ban_chars, pix => t_ban);

  -- ---------------------------------------------------------------- geometry
  process(clk)
    variable xi, yi : integer range 0 to 1023;
    variable hit    : std_logic;
    variable c      : rgb_t;
    variable dx, dy : integer range -1024 to 1023;
    variable sx, sy : integer range 0 to 15;
    variable cp     : integer range 0 to 7;
    variable i8     : integer range 0 to 7;
    variable bit_on : std_logic;
    variable px     : integer range 0 to 255;
    variable ph     : integer range 0 to 3;
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
      if bounce = '1' then
        for i in 0 to NB - 1 loop
          if i < n_bounce and xi >= bx(i) and xi < bx(i) + BQ and yi >= by(i) and yi < by(i) + BQ then
            hit := '1';
            c   := BCOL(i);
          end if;
        end loop;
      end if;

      -- ------------------------------------------ the spinning cat
      if cat = '1' and xi >= cx and xi < cx + CS and yi >= cy and yi < cy + CS then
        dx := xi - cx;                                 -- 0..63
        dy := yi - cy;
        sy := dy / 4;
        ph := to_integer(spin(4 downto 3));            -- changes every 8 frames
        cp := 0;
        if ph = 0 or ph = 2 then                       -- full width
          sx := dx / 4;
          if ph = 2 then sx := 15 - sx; end if;        -- mirrored = the back half of the turn
          cp := cat_pixel(sy, sx);
        elsif dx >= 16 and dx < 48 then                -- squeezed to half width
          sx := (dx - 16) / 2;
          if ph = 3 then sx := 15 - sx; end if;
          cp := cat_pixel(sy, sx);
        end if;
        case cp is
          when 1      => hit := '1'; c := x"111";
          when 2      => hit := '1'; c := x"999";
          when 3      => hit := '1'; c := x"FFF";
          when 4      => hit := '1'; c := x"F9B";
          when others => null;                         -- see-through
        end case;
      end if;

      r_on  <= hit;
      r_rgb <= c;
    end if;
  end process;

  -- text goes on top of the panel / band it belongs to
  ov_on  <= '1' when (r_panel = '1' and (t_l1 = '1' or t_l2 = '1')) or (r_band = '1' and t_ban = '1') else r_on;
  ov_rgb <= x"C6F"     when r_panel = '1' and t_l1 = '1' and t_active = '0' else
            x"FFF"     when r_panel = '1' and t_l1 = '1' else
            x"9BD"     when r_panel = '1' and t_l2 = '1' else
            r_ban_rgb  when r_band = '1' and t_ban = '1' else
            r_rgb;

end architecture;
