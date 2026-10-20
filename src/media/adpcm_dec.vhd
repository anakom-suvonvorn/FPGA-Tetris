-- ============================================================================
-- adpcm_dec.vhd
-- Turns 4-bit IMA ADPCM codes back into 16-bit sound samples.
--
-- WHY ADPCM
--   Plain 16-bit sound at 16,000 samples a second is 32 KB per second; the
--   flash has 7 MB for everything. ADPCM stores only a 4-bit "nudge" per
--   sample (8 KB per second, 4x less) and still sounds close to the original
--   (tools\media_lab.py made the .wav renders with exactly this decoder).
--
-- HOW IT WORKS
--   We keep a guess of the current sample ('pred') and a step size ('step',
--   from a table of 89 sizes, chosen by 'idx'). Each code says how far to
--   move the guess, in units of the step:
--     code bit 3 = direction (1 = down), bits 2..0 = how far:
--     move = step/8 + (bit2 ? step) + (bit1 ? step/2) + (bit0 ? step/4)
--   Then the step adapts: a big move (bits 2..0 = 4..7) makes the next step
--   bigger (idx + 2/4/6/8), a small one (0..3) makes it smaller (idx - 1).
--   So loud, fast-changing sound gets big steps, quiet sound fine steps.
--   The encoder (tools\make_game_media.py) does the very same arithmetic, so
--   both sides always agree on pred and idx.
--
-- TIMING: 'go' with a code -> the new sample is on 'pcm' 3 clocks later.
--   'load' sets pred / idx directly (start of an item, or a jump to a
--   record in the middle of it: every record stores the state at its start).
-- ============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity adpcm_dec is
  port (
    clk       : in  std_logic;
    load      : in  std_logic;
    load_pred : in  signed(15 downto 0);
    load_idx  : in  integer range 0 to 88;
    go        : in  std_logic;
    code      : in  std_logic_vector(3 downto 0);
    pcm       : out signed(15 downto 0)
  );
end entity;

architecture rtl of adpcm_dec is
  type steps_t is array (0 to 88) of integer range 0 to 32767;
  constant STEPS : steps_t := (
    7, 8, 9, 10, 11, 12, 13, 14, 16, 17, 19, 21, 23, 25, 28, 31, 34, 37, 41, 45, 50, 55, 60, 66, 73,
    80, 88, 97, 107, 118, 130, 143, 157, 173, 190, 209, 230, 253, 279, 307, 337, 371, 408, 449, 494,
    544, 598, 658, 724, 796, 876, 963, 1060, 1166, 1282, 1411, 1552, 1707, 1878, 2066, 2272, 2499,
    2749, 3024, 3327, 3660, 4026, 4428, 4871, 5358, 5894, 6484, 7132, 7845, 8630, 9493, 10442, 11487,
    12635, 13899, 15289, 16818, 18500, 20350, 22385, 24623, 27086, 29794, 32767);

  signal pred  : signed(15 downto 0) := (others => '0');
  signal idx   : integer range 0 to 88 := 0;
  signal c     : std_logic_vector(3 downto 0) := (others => '0');
  signal step  : unsigned(14 downto 0) := (others => '0');
  signal dq    : unsigned(16 downto 0) := (others => '0');
  signal ph    : integer range 0 to 2 := 0;            -- 0 idle, 1 got the step, 2 got the move
begin

  process(clk)
    variable p : signed(17 downto 0);
    variable n : integer range -1 to 96;
  begin
    if rising_edge(clk) then
      case ph is
        when 0 =>
          if go = '1' then
            c    <= code;
            step <= to_unsigned(STEPS(idx), 15);       -- table look-up
            ph   <= 1;
          end if;
        when 1 =>                                      -- how far to move
          dq <= resize(step(14 downto 3), 17);
          if c(2) = '1' then dq <= resize(step(14 downto 3), 17) + step; end if;
          ph <= 2;
          -- (bits 1 and 0 are added in the next clock, to keep each clock short)
        when 2 =>
          p := resize(pred, 18);
          if c(3) = '1' then
            p := p - signed(resize(dq + (step(14 downto 1) and (13 downto 0 => c(1))) + (step(14 downto 2) and (12 downto 0 => c(0))), 18));
          else
            p := p + signed(resize(dq + (step(14 downto 1) and (13 downto 0 => c(1))) + (step(14 downto 2) and (12 downto 0 => c(0))), 18));
          end if;
          -- keep it inside 16 bits
          if p > 32767 then
            pred <= to_signed(32767, 16);
          elsif p < -32768 then
            pred <= to_signed(-32768, 16);
          else
            pred <= resize(p, 16);
          end if;
          -- adapt the step
          case c(2 downto 0) is
            when "100"  => n := idx + 2;
            when "101"  => n := idx + 4;
            when "110"  => n := idx + 6;
            when "111"  => n := idx + 8;
            when others => n := idx - 1;
          end case;
          if n < 0 then idx <= 0; elsif n > 88 then idx <= 88; else idx <= n; end if;
          ph <= 0;
      end case;

      if load = '1' then
        pred <= load_pred;
        idx  <= load_idx;
        ph   <= 0;
      end if;
    end if;
  end process;

  pcm <= pred;

end architecture;
