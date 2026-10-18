-- ============================================================================
-- Test 01: VGA picture test
--
-- Purpose: prove that the board -> VGA cable -> monitor path works, that the
-- colours are wired the right way round, and that our cell maths for Tetris
-- is right. Pick a picture with slide switches SW2 and SW4 (sw(1 downto 0)):
--
--   SW4 SW2  picture
--    0   0   8 colour bars: white yellow cyan green magenta red blue black
--    0   1   16-step brightness ramps: red, green, blue and grey bands
--    1   0   a Tetris-sized 10 x 20 field of 16x16-pixel cells with 3D edges
--    1   1   a square bouncing around the screen (checks the 60 Hz frame tick)
--
-- In every picture a 1-pixel white border is drawn around the edge of the
-- screen, so you can see whether the monitor shows the whole 640x480 area.
--
-- Structure (top-down):
--   top_vga_bars
--     +-- vga_sync      (timing: x, y, video_on, hsync, vsync, frame_tick)
--     +-- process "pattern": colour for the current (x, y)
--     +-- process "bounce": moves the square once per frame
--     +-- process "outreg": registers colour + sync together at the outputs
-- ============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity top_vga_bars is
  port (
    clk    : in  std_logic;                        -- H11, 50 MHz
    sw     : in  std_logic_vector(1 downto 0);     -- sw(0)=SW2 K11, sw(1)=SW4 M11
    vga_r  : out std_logic_vector(3 downto 0);
    vga_g  : out std_logic_vector(3 downto 0);
    vga_b  : out std_logic_vector(3 downto 0);
    vga_hs : out std_logic;
    vga_vs : out std_logic
  );
end entity;

architecture rtl of top_vga_bars is

  signal x, y        : unsigned(9 downto 0);
  signal video_on    : std_logic;
  signal hs, vs      : std_logic;
  signal frame_tick  : std_logic;
  signal pix_en      : std_logic;

  -- colour of the current pixel, 12 bits = RRRR GGGG BBBB
  signal rgb         : std_logic_vector(11 downto 0);

  -- slide switches are slow and asynchronous: synchronise them too
  signal sw_s1, sw_s : std_logic_vector(1 downto 0) := "00";

  -- bouncing square
  constant SQ        : integer := 32;               -- size in pixels
  signal sq_x        : unsigned(9 downto 0) := to_unsigned(100, 10);
  signal sq_y        : unsigned(9 downto 0) := to_unsigned(60, 10);
  signal sq_dx_neg   : std_logic := '0';            -- '1' = moving left
  signal sq_dy_neg   : std_logic := '0';            -- '1' = moving up

  -- Tetris field position on screen (16 px cells, 10 wide, 20 tall)
  constant FIELD_X0  : integer := 240;              -- 240 .. 399
  constant FIELD_Y0  : integer := 80;               --  80 .. 399
  constant FIELD_W   : integer := 160;
  constant FIELD_H   : integer := 320;

  -- the 8 colours used by Tetris pieces (I O T S Z J L + grey garbage)
  type palette_t is array (0 to 7) of std_logic_vector(11 downto 0);
  constant PALETTE : palette_t := (
    x"0FF",   -- 0 I cyan
    x"FF0",   -- 1 O yellow
    x"A0F",   -- 2 T purple
    x"0F0",   -- 3 S green
    x"F00",   -- 4 Z red
    x"00F",   -- 5 J blue
    x"F80",   -- 6 L orange
    x"888"    -- 7 garbage grey
  );

  -- make a colour lighter (half way to white) or darker (half brightness),
  -- used for the 3D edge of a block
  function lighten(c : std_logic_vector(11 downto 0)) return std_logic_vector is
    variable r : std_logic_vector(11 downto 0);
    variable v : unsigned(3 downto 0);
  begin
    for i in 0 to 2 loop
      v := unsigned(c(4*i+3 downto 4*i));
      v := v + shift_right(15 - v, 1);
      r(4*i+3 downto 4*i) := std_logic_vector(v);
    end loop;
    return r;
  end function;

  function darken(c : std_logic_vector(11 downto 0)) return std_logic_vector is
    variable r : std_logic_vector(11 downto 0);
  begin
    for i in 0 to 2 loop
      r(4*i+3 downto 4*i) := std_logic_vector(shift_right(unsigned(c(4*i+3 downto 4*i)), 1));
    end loop;
    return r;
  end function;

begin

  -- --------------------------------------------------------------------------
  -- VGA timing generator
  -- --------------------------------------------------------------------------
  u_sync : entity work.vga_sync
    port map (
      clk        => clk,
      pix_en     => pix_en,
      x          => x,
      y          => y,
      video_on   => video_on,
      hsync      => hs,
      vsync      => vs,
      frame_tick => frame_tick
    );

  -- --------------------------------------------------------------------------
  -- Synchronise switches, and move the square once per frame
  -- --------------------------------------------------------------------------
  bounce : process(clk)
  begin
    if rising_edge(clk) then
      sw_s1 <= sw;
      sw_s  <= sw_s1;

      if frame_tick = '1' then
        -- horizontal: 2 px per frame, turn around at the edges
        if sq_dx_neg = '0' then
          if sq_x >= 640 - SQ - 2 then sq_dx_neg <= '1'; else sq_x <= sq_x + 2; end if;
        else
          if sq_x <= 2 then sq_dx_neg <= '0'; else sq_x <= sq_x - 2; end if;
        end if;
        -- vertical: 2 px per frame
        if sq_dy_neg = '0' then
          if sq_y >= 480 - SQ - 2 then sq_dy_neg <= '1'; else sq_y <= sq_y + 2; end if;
        else
          if sq_y <= 2 then sq_dy_neg <= '0'; else sq_y <= sq_y - 2; end if;
        end if;
      end if;
    end if;
  end process;

  -- --------------------------------------------------------------------------
  -- Picture generator: what colour is pixel (x, y)?   (combinational)
  -- --------------------------------------------------------------------------
  pattern : process(x, y, sw_s, sq_x, sq_y)
    variable xi, yi     : integer range 0 to 1023;
    variable col, row   : integer range 0 to 63;
    variable px, py     : unsigned(3 downto 0);
    variable base       : std_logic_vector(11 downto 0);
    variable level      : std_logic_vector(3 downto 0);
    variable c          : std_logic_vector(11 downto 0);
  begin
    xi := to_integer(x);
    yi := to_integer(y);
    c  := x"000";                                     -- default: black

    case sw_s is
      -- ---------------------------------------------- colour bars
      when "00" =>
        if    xi <  80 then c := x"FFF";
        elsif xi < 160 then c := x"FF0";
        elsif xi < 240 then c := x"0FF";
        elsif xi < 320 then c := x"0F0";
        elsif xi < 400 then c := x"F0F";
        elsif xi < 480 then c := x"F00";
        elsif xi < 560 then c := x"00F";
        else                c := x"000";
        end if;

      -- ---------------------------------------------- brightness ramps
      -- level goes 0,1,2,...,15 in steps of 32 pixels (x = 0..511),
      -- then stays at 15. If a colour ramp looks "jumpy" instead of
      -- smoothly brighter, that colour's 4 wires are in the wrong order.
      when "01" =>
        if xi < 512 then
          level := std_logic_vector(x(8 downto 5));
        else
          level := "1111";
        end if;
        if    yi < 120 then c := level & "0000" & "0000";   -- red
        elsif yi < 240 then c := "0000" & level & "0000";   -- green
        elsif yi < 360 then c := "0000" & "0000" & level;   -- blue
        else                c := level & level & level;      -- grey
        end if;

      -- ---------------------------------------------- Tetris cell grid
      when "10" =>
        c := x"223";                                     -- dark background
        if xi >= FIELD_X0 and xi < FIELD_X0 + FIELD_W and
           yi >= FIELD_Y0 and yi < FIELD_Y0 + FIELD_H then
          -- which cell are we in? Cells are 16 px, so this is just
          -- "drop the lowest 4 bits" (no division needed).
          col := (xi - FIELD_X0) / 16;                   -- 0..9
          row := (yi - FIELD_Y0) / 16;                   -- 0..19
          -- where inside the cell? (0..15)
          px  := x(3 downto 0);
          py  := y(3 downto 0);
          base := PALETTE((col + row) mod 8);
          if px = 0 or py = 0 then
            c := lighten(base);                          -- top/left edge
          elsif px = 15 or py = 15 then
            c := darken(base);                           -- bottom/right edge
          else
            c := base;
          end if;
        elsif xi >= FIELD_X0 - 4 and xi < FIELD_X0 + FIELD_W + 4 and
              yi >= FIELD_Y0 - 4 and yi < FIELD_Y0 + FIELD_H + 4 then
          c := x"AAA";                                   -- 4 px frame
        end if;

      -- ---------------------------------------------- bouncing square
      when others =>
        c := x"113";
        if x >= sq_x and x < sq_x + SQ and y >= sq_y and y < sq_y + SQ then
          c := x"F80";
        end if;
    end case;

    -- white 1-pixel border around the visible area
    if xi = 0 or xi = 639 or yi = 0 or yi = 479 then
      c := x"FFF";
    end if;

    rgb <= c;
  end process;

  -- --------------------------------------------------------------------------
  -- Output register. Colour and sync are registered on the same clock edge,
  -- so they stay lined up. Outside the visible area the colour must be black.
  -- --------------------------------------------------------------------------
  outreg : process(clk)
  begin
    if rising_edge(clk) then
      if video_on = '1' then
        vga_r <= rgb(11 downto 8);
        vga_g <= rgb(7 downto 4);
        vga_b <= rgb(3 downto 0);
      else
        vga_r <= "0000";
        vga_g <= "0000";
        vga_b <= "0000";
      end if;
      vga_hs <= hs;
      vga_vs <= vs;
    end if;
  end process;

end architecture;
