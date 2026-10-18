-- ============================================================================
-- tetris_render.vhd
-- Draws the game: for every pixel (x, y) that vga_sync announces, work out
-- its colour from the game state coming out of tetris_core.
--
-- SCREEN LAYOUT (640 x 480)                                  (all multiples of 16)
--   left    "RIVAL", the other player's stack height as a bar  x 104..135, y 80..399
--           "LINKED" / "NO LINK" under it
--   middle  red garbage meter (garbage waiting for me)         x 226..233
--           playfield, 10 x 20 cells of 16 x 16 px             x 240..399, y 80..399
--           with a 4 px frame; result text / PRESS START over it
--   right   "NEXT" + next piece (4 x 4 cells)                  x 432..495, y 80..143
--           "LEVEL" + one small square per level               y 176..207
--           "LINES" + the line count                           y 224..271
--
-- Inside the field, from front to back:
--   result banner text > falling piece > locked blocks > ghost outline >
--   empty cell with a faint grid.
-- Every block is drawn with a 1 px lighter top/left edge and a darker
-- bottom/right edge, so it looks raised.
--
-- PIPELINE (2 clocks)
--   stage 1: from (x, y) find the cell, read that field row, check whether
--            the piece / ghost / next piece covers this cell.  -> s1_* registers
--            (the text_layer blocks do their own stage 1 and give t_* bits)
--   stage 2: choose the colour.                                -> output pins
-- hsync / vsync / video_on go through the same 2 registers, so they stay
-- lined up with the colour.
-- ============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.tetris_pkg.all;
use work.text_pkg.all;

entity tetris_render is
  port (
    clk        : in  std_logic;
    x, y       : in  unsigned(9 downto 0);
    video_on   : in  std_logic;
    hsync      : in  std_logic;
    vsync      : in  std_logic;
    -- game state
    occ        : in  occ_field_t;
    colf       : in  col_field_t;
    cur_shape  : in  shape_t;
    cur_color  : in  color_t;
    cur_x      : in  xpos_t;
    cur_y      : in  ypos_t;
    ghost_y    : in  ypos_t;
    next_shape : in  shape_t;
    next_color : in  color_t;
    playing    : in  std_logic;
    game_over  : in  std_logic;
    paused     : in  std_logic;
    level      : in  integer range 0 to 15;
    lines_bcd  : in  std_logic_vector(15 downto 0);
    -- versus
    result     : in  integer range 0 to 4;
    pending    : in  integer range 0 to 31;
    opp_height : in  integer range 0 to 20;
    link_ok    : in  std_logic;
    -- VGA pins
    vga_r      : out std_logic_vector(3 downto 0);
    vga_g      : out std_logic_vector(3 downto 0);
    vga_b      : out std_logic_vector(3 downto 0);
    vga_hs     : out std_logic;
    vga_vs     : out std_logic
  );
end entity;

architecture rtl of tetris_render is
  constant FX0 : integer := 240;  constant FY0 : integer := 80;    -- field
  constant FW  : integer := 160;  constant FH  : integer := 320;
  constant NX0 : integer := 432;  constant NY0 : integer := 80;    -- next piece
  constant LX0 : integer := 432;  constant LY0 : integer := 176;   -- level squares
  constant RX0 : integer := 104;  constant RW  : integer := 32;    -- rival bar
  constant GX0 : integer := 226;  constant GW  : integer := 8;     -- garbage meter

  constant BG       : rgb_t := x"113";     -- screen background
  constant FIELD_BG : rgb_t := x"000";
  constant GRID     : rgb_t := x"111";
  constant FRAME    : rgb_t := x"AAA";
  constant LABEL_C    : rgb_t := x"89B";

  -- stage 1 registers
  signal s1_vid, s1_hs, s1_vs : std_logic := '0';
  signal s1_in_field, s1_field_frame : std_logic := '0';
  signal s1_in_next, s1_next_frame   : std_logic := '0';
  signal s1_level_sq                 : std_logic := '0';
  signal s1_piece, s1_ghost, s1_next : std_logic := '0';
  signal s1_occ_bit                  : std_logic := '0';
  signal s1_cell_col                 : color_t := (others => '0');
  signal s1_px, s1_py                : unsigned(3 downto 0) := (others => '0');
  signal s1_garb_track, s1_garb_fill : std_logic := '0';
  signal s1_rival_frame, s1_rival_in, s1_rival_fill : std_logic := '0';
  signal s1_banner_res, s1_banner_press : std_logic := '0';

  -- text (each text_layer has its own stage-1 register inside)
  signal t_next, t_level, t_lines, t_num, t_rival, t_link : std_logic;
  signal t_press, t_res, t_over : std_logic;
  signal num_chars  : std_logic_vector(23 downto 0);
  signal link_chars : std_logic_vector(41 downto 0);
  signal res_chars  : std_logic_vector(23 downto 0);
  -- fixed texts (constants, because a port map may not call a function in VHDL-93)
  constant TXT_NEXT  : std_logic_vector(23 downto 0) := to_codes("NEXT");
  constant TXT_LEVEL : std_logic_vector(29 downto 0) := to_codes("LEVEL");
  constant TXT_LINES : std_logic_vector(29 downto 0) := to_codes("LINES");
  constant TXT_RIVAL : std_logic_vector(29 downto 0) := to_codes("RIVAL");
  constant TXT_PRESS : std_logic_vector(65 downto 0) := to_codes("PRESS START");
  constant TXT_OVER  : std_logic_vector(53 downto 0) := to_codes("GAME OVER");

  -- 3D edge for a block of colour c, at pixel (px, py) inside the cell
  function bevel(c : rgb_t; px, py : unsigned(3 downto 0)) return rgb_t is
  begin
    if px = 0 or py = 0 then
      return lighten(c);
    elsif px = 15 or py = 15 then
      return darken(c);
    else
      return c;
    end if;
  end function;

begin

  -- -------------------------------------------------------- text
  -- the 4 BCD digits are directly character codes 0..9
  num_chars  <= "00" & lines_bcd(3 downto 0) & "00" & lines_bcd(7 downto 4) &
                "00" & lines_bcd(11 downto 8) & "00" & lines_bcd(15 downto 12);
  link_chars <= to_codes(" LINKED") when link_ok = '1' else to_codes("NO LINK");
  with result select res_chars <=
    to_codes("WIN!") when 1,
    to_codes("LOSE") when 2,
    to_codes("DRAW") when 3,
    to_codes("    ") when others;

  u_t_next  : entity work.text_layer generic map (X0 => NX0, Y0 => 52,  LEN => 4,  SHIFT => 1)
    port map (clk => clk, x => x, y => y, chars => TXT_NEXT,   pix => t_next);
  u_t_level : entity work.text_layer generic map (X0 => LX0, Y0 => 156, LEN => 5,  SHIFT => 1)
    port map (clk => clk, x => x, y => y, chars => TXT_LEVEL, pix => t_level);
  u_t_lines : entity work.text_layer generic map (X0 => LX0, Y0 => 224, LEN => 5,  SHIFT => 1)
    port map (clk => clk, x => x, y => y, chars => TXT_LINES, pix => t_lines);
  u_t_num   : entity work.text_layer generic map (X0 => LX0, Y0 => 244, LEN => 4,  SHIFT => 2)
    port map (clk => clk, x => x, y => y, chars => num_chars,          pix => t_num);
  u_t_rival : entity work.text_layer generic map (X0 => 90,  Y0 => 52,  LEN => 5,  SHIFT => 1)
    port map (clk => clk, x => x, y => y, chars => TXT_RIVAL, pix => t_rival);
  u_t_link  : entity work.text_layer generic map (X0 => 78,  Y0 => 412, LEN => 7,  SHIFT => 1)
    port map (clk => clk, x => x, y => y, chars => link_chars,         pix => t_link);
  u_t_press : entity work.text_layer generic map (X0 => 254, Y0 => 264, LEN => 11, SHIFT => 1)
    port map (clk => clk, x => x, y => y, chars => TXT_PRESS, pix => t_press);
  u_t_res   : entity work.text_layer generic map (X0 => 272, Y0 => 202, LEN => 4,  SHIFT => 2)
    port map (clk => clk, x => x, y => y, chars => res_chars,          pix => t_res);
  u_t_over  : entity work.text_layer generic map (X0 => 266, Y0 => 210, LEN => 9,  SHIFT => 1)
    port map (clk => clk, x => x, y => y, chars => TXT_OVER, pix => t_over);

  -- -------------------------------------------------------- stage 1
  stage1 : process(clk)
    variable xi, yi   : integer range 0 to 1023;
    variable col      : integer range 0 to COLS - 1;
    variable row      : integer range 0 to ROWS - 1;
    variable in_f     : boolean;
    variable rr, cc   : integer range -32 to 32;
    variable nc, nr   : integer range 0 to 3;
    variable li, lj   : integer range 0 to 7;
    variable occ_row  : occ_row_t;
    variable col_row  : col_row_t;
    variable h        : integer range 0 to 640;
  begin
    if rising_edge(clk) then
      xi := to_integer(x);
      yi := to_integer(y);

      -- which field cell? (dividing by 16 = dropping 4 bits)
      in_f := xi >= FX0 and xi < FX0 + FW and yi >= FY0 and yi < FY0 + FH;
      if in_f then
        col := (xi - FX0) / 16;
        row := (yi - FY0) / 16;
      else
        col := 0;
        row := 0;
      end if;

      -- the field row under this pixel, and this cell in it
      occ_row := occ(row);
      col_row := colf(row);
      s1_occ_bit  <= occ_row(col);
      s1_cell_col <= col_row(3*col + 2 downto 3*col);

      -- does the falling piece cover this cell? (box row rr, box column cc)
      rr := row - cur_y;
      cc := col + 3 - cur_x;
      s1_piece <= '0';
      if in_f and playing = '1' and rr >= 0 and rr <= 3 and cc >= 0 and cc <= 3 then
        s1_piece <= cur_shape(4*rr + cc);
      end if;

      -- same for the ghost (same shape, at ghost_y)
      rr := row - ghost_y;
      s1_ghost <= '0';
      if in_f and playing = '1' and rr >= 0 and rr <= 3 and cc >= 0 and cc <= 3 then
        s1_ghost <= cur_shape(4*rr + cc);
      end if;

      -- next-piece box
      s1_in_next <= '0';
      s1_next    <= '0';
      if xi >= NX0 and xi < NX0 + 64 and yi >= NY0 and yi < NY0 + 64 then
        s1_in_next <= '1';
        nc := (xi - NX0) / 16;
        nr := (yi - NY0) / 16;
        if playing = '1' then
          s1_next <= next_shape(4*nr + nc);
        end if;
      end if;
      if xi >= NX0 - 4 and xi < NX0 + 68 and yi >= NY0 - 4 and yi < NY0 + 68 then
        s1_next_frame <= '1';
      else
        s1_next_frame <= '0';
      end if;

      -- level squares: 2 rows of 8, 12 x 12 px every 16 px
      s1_level_sq <= '0';
      if xi >= LX0 and xi < LX0 + 128 and yi >= LY0 and yi < LY0 + 32 then
        li := (xi - LX0) / 16;
        lj := (yi - LY0) / 16;
        if x(3 downto 0) < 12 and y(3 downto 0) < 12 and lj * 8 + li <= level then
          s1_level_sq <= '1';
        end if;
      end if;

      if in_f then s1_in_field <= '1'; else s1_in_field <= '0'; end if;
      if xi >= FX0 - 4 and xi < FX0 + FW + 4 and yi >= FY0 - 4 and yi < FY0 + FH + 4 then
        s1_field_frame <= '1';
      else
        s1_field_frame <= '0';
      end if;

      -- garbage meter: a column next to the field, filled from the bottom,
      -- 16 px per waiting line (at most the field height)
      s1_garb_track <= '0';
      s1_garb_fill  <= '0';
      if xi >= GX0 and xi < GX0 + GW and yi >= FY0 and yi < FY0 + FH then
        s1_garb_track <= '1';
        h := pending * 16;
        if h > FH then h := FH; end if;
        if yi >= FY0 + FH - h then
          s1_garb_fill <= '1';
        end if;
      end if;

      -- rival: the other player's stack height as a bar, 16 px per row
      s1_rival_in    <= '0';
      s1_rival_fill  <= '0';
      s1_rival_frame <= '0';
      if xi >= RX0 and xi < RX0 + RW and yi >= FY0 and yi < FY0 + FH then
        s1_rival_in <= '1';
        if yi >= FY0 + FH - opp_height * 16 then
          s1_rival_fill <= '1';
        end if;
      elsif xi >= RX0 - 4 and xi < RX0 + RW + 4 and yi >= FY0 - 4 and yi < FY0 + FH + 4 then
        s1_rival_frame <= '1';
      end if;

      -- dark bands behind the text written over the field
      s1_banner_res   <= '0';
      s1_banner_press <= '0';
      if in_f and yi >= 192 and yi < 240 and result /= 0 then
        s1_banner_res <= '1';
      end if;
      if in_f and yi >= 256 and yi < 288 and playing = '0' then
        s1_banner_press <= '1';
      end if;

      s1_px  <= x(3 downto 0);
      s1_py  <= y(3 downto 0);
      s1_vid <= video_on;
      s1_hs  <= hsync;
      s1_vs  <= vsync;
    end if;
  end process;

  -- -------------------------------------------------------- stage 2
  stage2 : process(clk)
    variable c    : rgb_t;
    variable cell : rgb_t;
  begin
    if rising_edge(clk) then
      c := BG;

      if s1_in_field = '1' then
        if s1_px = 0 or s1_py = 0 then
          c := GRID;
        else
          c := FIELD_BG;
        end if;
        if s1_piece = '1' then
          c := bevel(piece_rgb(cur_color), s1_px, s1_py);
        elsif s1_occ_bit = '1' then
          if game_over = '1' then
            cell := x"555";                       -- I lost: everything grey
          else
            cell := piece_rgb(s1_cell_col);
          end if;
          c := bevel(cell, s1_px, s1_py);
        elsif s1_ghost = '1' then
          -- outline only, in a dark version of the piece colour
          if s1_px = 0 or s1_py = 0 or s1_px = 15 or s1_py = 15 then
            c := darken(piece_rgb(cur_color));
          end if;
        end if;
        if paused = '1' then
          c := darken(darken(c));
        end if;
        -- text over the field, on a dark band
        if s1_banner_res = '1' then
          c := x"111";
          if t_res = '1' then
            case result is
              when 1      => c := x"FD3";         -- WIN!  gold
              when 2      => c := x"F44";         -- LOSE  red
              when 3      => c := x"DDD";         -- DRAW  white
              when others => c := x"111";
            end case;
          elsif t_over = '1' and result = 4 then
            c := x"F44";                          -- GAME OVER (single player)
          end if;
        end if;
        if s1_banner_press = '1' then
          c := x"111";
          if t_press = '1' then
            c := x"FFF";
          end if;
        end if;
      elsif s1_field_frame = '1' then
        if result = 1 then
          c := x"FD3";                            -- gold frame: I won
        elsif game_over = '1' then
          c := x"C22";                            -- red frame: I lost
        elsif playing = '0' then
          c := x"2C2";                            -- green frame: press to start
        else
          c := FRAME;
        end if;
      elsif s1_garb_track = '1' then
        if s1_garb_fill = '1' then
          c := x"F33";
        else
          c := x"211";
        end if;
      elsif s1_in_next = '1' then
        if s1_next = '1' then
          c := bevel(piece_rgb(next_color), s1_px, s1_py);
        else
          c := FIELD_BG;
        end if;
      elsif s1_next_frame = '1' then
        c := FRAME;
      elsif s1_level_sq = '1' then
        c := x"FC2";
      elsif s1_rival_in = '1' then
        if s1_rival_fill = '1' then
          if link_ok = '0' then
            c := x"333";
          elsif opp_height >= 15 then
            c := x"E44";                          -- the rival is nearly dead
          else
            c := x"888";
          end if;
        else
          c := FIELD_BG;
        end if;
      elsif s1_rival_frame = '1' then
        if link_ok = '1' then c := x"666"; else c := x"333"; end if;
      elsif t_link = '1' then
        if link_ok = '1' then c := x"3D5"; else c := x"E44"; end if;
      elsif t_next = '1' or t_level = '1' or t_lines = '1' or t_rival = '1' then
        c := LABEL_C;
      elsif t_num = '1' then
        c := x"FFF";
      end if;

      if s1_vid = '1' then
        vga_r <= c(11 downto 8);
        vga_g <= c(7 downto 4);
        vga_b <= c(3 downto 0);
      else
        vga_r <= "0000";
        vga_g <= "0000";
        vga_b <= "0000";
      end if;
      vga_hs <= s1_hs;
      vga_vs <= s1_vs;
    end if;
  end process;

end architecture;
