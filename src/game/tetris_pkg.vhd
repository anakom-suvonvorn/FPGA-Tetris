-- ============================================================================
-- tetris_pkg.vhd
-- Everything the Tetris blocks share: field size, types for the playfield,
-- the 7 piece shapes in all 4 rotations, colours, and the speed table.
--
-- PLAYFIELD
--   10 columns x 20 rows. Row 0 is the TOP, row 19 the bottom. Column 0 is
--   the left. It is stored as two arrays of registers (flip-flops):
--     occ  : one 10-bit vector per row, bit c = '1' if cell (row, c) is full
--     colf : one 30-bit vector per row, 3 bits per cell = which colour
--            (bits 3c+2..3c belong to column c)
--   Keeping "is it full" separate makes collision checks cheap: just AND
--   10-bit vectors.
--
-- PIECES
--   Number 0..6 = I O T S Z J L. Colour number = piece number, and 7 = grey
--   (garbage lines in versus mode).
--   Each piece in each rotation is a 4x4 picture ("shape", 16 bits):
--       bit (4*r + c) = row r, column c of the 4x4 box   (r, c = 0..3)
--   The shapes follow the official "SRS" rotation system, so pieces turn
--   the way players expect.
--
-- POSITIONS ("wide" columns)
--   The box's left edge x is counted in "wide" columns: 3 wall columns on the
--   left, then the 10 field columns (wide 3..12), then 3 wall columns.
--   So board column = wide column - 3. This way a box partly sticking out
--   over a wall still has a valid x (0..12) and the walls are just '1' bits.
-- ============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package tetris_pkg is

  constant ROWS : integer := 20;
  constant COLS : integer := 10;

  subtype occ_row_t   is std_logic_vector(COLS - 1 downto 0);
  type    occ_field_t is array (0 to ROWS - 1) of occ_row_t;
  subtype col_row_t   is std_logic_vector(3 * COLS - 1 downto 0);
  type    col_field_t is array (0 to ROWS - 1) of col_row_t;

  subtype shape_t  is std_logic_vector(15 downto 0);
  subtype color_t  is std_logic_vector(2 downto 0);
  subtype rgb_t    is std_logic_vector(11 downto 0);    -- RRRR GGGG BBBB

  -- position ranges (wide x, and y = board row of the box's top row)
  subtype xpos_t is integer range -2 to 14;
  subtype ypos_t is integer range -2 to 21;

  constant SPAWN_X : integer := 6;     -- box at board columns 3..6 (centred)
  constant SPAWN_Y : integer := 0;

  -- game timing, in frames (1 frame = 1/60 s)
  constant LOCK_FRAMES : integer := 30;    -- a piece resting on something locks after 0.5 s
  constant LOCK_RESETS : integer := 15;    -- moves that restart that timer, per piece

  -- shape of piece p (0..6) in rotation rot (0..3)
  function shape_of(p : integer range 0 to 7; rot : integer range 0 to 3) return shape_t;

  -- frames per row of falling at a given level
  function gravity_frames(level : integer range 0 to 15) return integer;

  -- colour helpers
  function piece_rgb(c : color_t) return rgb_t;
  function lighten(c : rgb_t) return rgb_t;
  function darken(c : rgb_t) return rgb_t;

end package tetris_pkg;


package body tetris_pkg is

  -- Turns a picture written as text into a shape: 16 characters = the
  -- 4 rows of the box one after another, 'X' = filled, '.' = empty.
  -- Only used while compiling (to build the SHAPES table), not hardware.
  function pic(s : string) return shape_t is
    variable r : shape_t := (others => '0');
  begin
    for i in 0 to 15 loop
      if s(s'low + i) = 'X' then
        r(i) := '1';
      end if;
    end loop;
    return r;
  end function;

  type shape_table_t is array (0 to 31) of shape_t;
  --                       row0 row1 row2 row3
  constant SHAPES : shape_table_t := (
    -- 0: I
    pic("...." & "XXXX" & "...." & "...."),
    pic("..X." & "..X." & "..X." & "..X."),
    pic("...." & "...." & "XXXX" & "...."),
    pic(".X.." & ".X.." & ".X.." & ".X.."),
    -- 1: O
    pic(".XX." & ".XX." & "...." & "...."),
    pic(".XX." & ".XX." & "...." & "...."),
    pic(".XX." & ".XX." & "...." & "...."),
    pic(".XX." & ".XX." & "...." & "...."),
    -- 2: T
    pic(".X.." & "XXX." & "...." & "...."),
    pic(".X.." & ".XX." & ".X.." & "...."),
    pic("...." & "XXX." & ".X.." & "...."),
    pic(".X.." & "XX.." & ".X.." & "...."),
    -- 3: S
    pic(".XX." & "XX.." & "...." & "...."),
    pic(".X.." & ".XX." & "..X." & "...."),
    pic("...." & ".XX." & "XX.." & "...."),
    pic("X..." & "XX.." & ".X.." & "...."),
    -- 4: Z
    pic("XX.." & ".XX." & "...." & "...."),
    pic("..X." & ".XX." & ".X.." & "...."),
    pic("...." & "XX.." & ".XX." & "...."),
    pic(".X.." & "XX.." & "X..." & "...."),
    -- 5: J
    pic("X..." & "XXX." & "...." & "...."),
    pic(".XX." & ".X.." & ".X.." & "...."),
    pic("...." & "XXX." & "..X." & "...."),
    pic(".X.." & ".X.." & "XX.." & "...."),
    -- 6: L
    pic("..X." & "XXX." & "...." & "...."),
    pic(".X.." & ".X.." & ".XX." & "...."),
    pic("...." & "XXX." & "X..." & "...."),
    pic("XX.." & ".X.." & ".X.." & "...."),
    -- 7: unused (empty)
    pic("................"), pic("................"),
    pic("................"), pic("................")
  );

  function shape_of(p : integer range 0 to 7; rot : integer range 0 to 3) return shape_t is
  begin
    return SHAPES(p * 4 + rot);
  end function;

  function gravity_frames(level : integer range 0 to 15) return integer is
  begin
    case level is
      when 0  => return 48;
      when 1  => return 43;
      when 2  => return 38;
      when 3  => return 33;
      when 4  => return 28;
      when 5  => return 23;
      when 6  => return 18;
      when 7  => return 13;
      when 8  => return 8;
      when 9  => return 6;
      when 10 => return 5;
      when 11 => return 5;
      when 12 => return 4;
      when 13 => return 4;
      when 14 => return 3;
      when others => return 2;
    end case;
  end function;

  function piece_rgb(c : color_t) return rgb_t is
  begin
    case c is
      when "000"  => return x"0EF";   -- I cyan
      when "001"  => return x"EE0";   -- O yellow
      when "010"  => return x"A2F";   -- T purple
      when "011"  => return x"2E2";   -- S green
      when "100"  => return x"F22";   -- Z red
      when "101"  => return x"25F";   -- J blue
      when "110"  => return x"F80";   -- L orange
      when others => return x"888";   -- garbage grey
    end case;
  end function;

  -- each 4-bit colour half way towards 15
  function lighten(c : rgb_t) return rgb_t is
    variable r : rgb_t;
    variable v : unsigned(3 downto 0);
  begin
    for i in 0 to 2 loop
      v := unsigned(c(4*i+3 downto 4*i));
      v := v + shift_right(15 - v, 1);
      r(4*i+3 downto 4*i) := std_logic_vector(v);
    end loop;
    return r;
  end function;

  -- each 4-bit colour halved
  function darken(c : rgb_t) return rgb_t is
    variable r : rgb_t;
  begin
    for i in 0 to 2 loop
      r(4*i+3 downto 4*i) := std_logic_vector(shift_right(unsigned(c(4*i+3 downto 4*i)), 1));
    end loop;
    return r;
  end function;

end package body tetris_pkg;
