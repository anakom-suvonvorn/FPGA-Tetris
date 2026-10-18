-- ============================================================================
-- vga_sync.vhd
-- Generates the timing for a 640 x 480 picture at 60 frames per second.
--
-- How VGA works, in short:
--   The monitor draws the picture like a typewriter: left to right along one
--   line, then the next line down, top to bottom, 60 times per second. We
--   don't send "pixels with addresses". We send just the colour of the pixel
--   being drawn RIGHT NOW on the R, G and B wires, plus two timing pulses:
--     HSYNC : "this line is finished, go back to the left"   (once per line)
--     VSYNC : "this frame is finished, go back to the top"   (once per frame)
--   So the FPGA's job is to keep two counters (x along the line, y down the
--   screen) and output the right colour for (x, y) at the right moment.
--
-- Standard 640x480 @ 60 Hz timing, in pixel-clock ticks:
--
--   Horizontal (one line)          Vertical (one frame, in lines)
--     visible       640              visible       480
--     front porch    16              front porch    10
--     sync pulse     96              sync pulse      2
--     back porch     48              back porch     33
--     total         800              total         525
--
--   The porches and sync are invisible "off-screen" time (old CRT monitors
--   needed it to move the beam back). Both sync pulses are active-low.
--
-- Pixel clock: the standard says 25.175 MHz; 25 MHz is close enough for every
-- monitor we have tried. We do NOT make a separate 25 MHz clock. Instead the
-- whole design keeps running on the 50 MHz clock, and 'pix_en' is a pulse
-- that is '1' on every second clock cycle. The counters only move when
-- pix_en = '1'. (One clock + enable pulses = no timing surprises.)
--
-- Outputs:
--   pix_en      : '1' every 2nd clock (25 MHz rate)
--   x, y        : current pixel position (x 0..799, y 0..524)
--   video_on    : '1' while (x, y) is inside the visible 640x480 area.
--                 Outside it the colour outputs MUST be black.
--   hsync,vsync : sync pulses (active-low)
--   frame_tick  : one-clock pulse once per frame, right when the visible
--                 area has just finished (start of vertical blanking).
--                 Game logic should update on this tick (60 times a second).
--
-- x, y, video_on, hsync and vsync all change together, so the top level can
-- register them together with the colour to keep everything aligned.
-- ============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity vga_sync is
  port (
    clk        : in  std_logic;               -- 50 MHz
    pix_en     : out std_logic;
    x          : out unsigned(9 downto 0);
    y          : out unsigned(9 downto 0);
    video_on   : out std_logic;
    hsync      : out std_logic;
    vsync      : out std_logic;
    frame_tick : out std_logic
  );
end entity;

architecture rtl of vga_sync is
  constant H_VISIBLE : integer := 640;
  constant H_FRONT   : integer := 16;
  constant H_SYNC    : integer := 96;
  constant H_TOTAL   : integer := 800;
  constant V_VISIBLE : integer := 480;
  constant V_FRONT   : integer := 10;
  constant V_SYNC    : integer := 2;
  constant V_TOTAL   : integer := 525;

  signal half : std_logic := '0';             -- toggles every clock
  signal hc   : unsigned(9 downto 0) := (others => '0');
  signal vc   : unsigned(9 downto 0) := (others => '0');
  signal tick : std_logic := '0';
begin

  process(clk)
  begin
    if rising_edge(clk) then
      half <= not half;
      tick <= '0';

      if half = '1' then                      -- this is a pixel step
        if hc = H_TOTAL - 1 then
          hc <= (others => '0');
          if vc = V_TOTAL - 1 then
            vc <= (others => '0');
          else
            vc <= vc + 1;
          end if;
          if vc = V_VISIBLE - 1 then
            tick <= '1';                      -- last visible line just ended
          end if;
        else
          hc <= hc + 1;
        end if;
      end if;
    end if;
  end process;

  pix_en     <= half;
  x          <= hc;
  y          <= vc;
  video_on   <= '1' when (hc < H_VISIBLE and vc < V_VISIBLE) else '0';
  hsync      <= '0' when (hc >= H_VISIBLE + H_FRONT and
                          hc <  H_VISIBLE + H_FRONT + H_SYNC) else '1';
  vsync      <= '0' when (vc >= V_VISIBLE + V_FRONT and
                          vc <  V_VISIBLE + V_FRONT + V_SYNC) else '1';
  frame_tick <= tick;

end architecture;
