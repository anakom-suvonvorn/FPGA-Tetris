-- ============================================================================
-- text_layer.vhd
-- Draws one line of text on the VGA picture.
--
-- Place one instance per piece of text. Generics say where and how big:
--   X0, Y0  : top-left pixel of the text
--   LEN     : number of characters
--   SHIFT   : size; every font pixel becomes a 2^SHIFT x 2^SHIFT square
--             (0 = 6x8 px per character, 1 = 12x16, 2 = 24x32, ...)
-- Input 'chars' holds LEN character codes (text_pkg), 6 bits each,
-- character 0 (leftmost) in bits 5..0. For fixed text use
-- to_codes("HELLO") from text_pkg; for numbers, put BCD digits in.
--
-- Each character cell is 6 x 8 font pixels: the 5x7 glyph plus one empty
-- column and row as spacing.
--
-- Output 'pix' is '1' when the pixel (x, y) is part of a letter. It comes
-- out of a register, one clock after x, y, which is exactly when
-- tetris_render's stage 2 needs it (same timing as its s1_* registers).
-- ============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.text_pkg.all;

entity text_layer is
  generic (
    X0    : integer := 0;
    Y0    : integer := 0;
    LEN   : integer := 4;
    SHIFT : integer := 1
  );
  port (
    clk   : in  std_logic;
    x, y  : in  unsigned(9 downto 0);
    chars : in  std_logic_vector(6 * LEN - 1 downto 0);
    pix   : out std_logic
  );
end entity;

architecture rtl of text_layer is
  constant S  : integer := 2 ** SHIFT;
  constant W  : integer := LEN * 6 * S;     -- width in screen pixels
  constant H  : integer := 7 * S;           -- height (7 font rows)
  signal pix_r : std_logic := '0';
begin

  process(clk)
    variable xi, yi : integer range 0 to 1023;
    variable dx, dy : integer range 0 to 1023;
    variable ci     : integer range 0 to 255;   -- which character
    variable cc     : integer range 0 to 7;     -- column inside it
    variable code   : char_t;
    variable gl     : font_glyph_t;
  begin
    if rising_edge(clk) then
      xi := to_integer(x);
      yi := to_integer(y);
      pix_r <= '0';
      if xi >= X0 and xi < X0 + W and yi >= Y0 and yi < Y0 + H then
        dx := (xi - X0) / S;                   -- position in font pixels
        dy := (yi - Y0) / S;
        ci := dx / 6;                          -- character number
        cc := dx mod 6;                        -- column in the 6-wide cell
        code := (others => '0');
        for i in 0 to LEN - 1 loop             -- pick that character's code
          if i = ci then
            code := chars(6*i + 5 downto 6*i);
          end if;
        end loop;
        gl := glyph_of(code);
        if cc < 5 then
          pix_r <= gl(5 * dy + cc);
        end if;
      end if;
    end if;
  end process;

  pix <= pix_r;

end architecture;
