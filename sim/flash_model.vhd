-- ============================================================================
-- flash_model.vhd  -  a pretend SPI flash chip for the testbenches
--
-- Behaves like the S25FL064L for the two commands we use:
--   9F  -> sends the ID bytes 01 60 17
--   03  -> takes a 3-byte address, then sends the bytes from there on
-- The contents come from a text file with one hex byte per line (written
-- by tools\make_media.py --sim), placed at flash address BASE.
-- Like the real chip: reads MOSI on the rising SCLK edge, changes MISO on
-- the falling edge, T_V later (the real chip: at most 8 ns; we use a slower
-- 15 ns to make sure the design copes with some extra delay).
-- ============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.std_logic_textio.all;
use std.textio.all;

entity flash_model is
  generic (
    FILE_NAME : string  := "media_sim.hex";
    BASE      : integer := 16#100000#;
    SIZE      : integer := 49152;
    T_V       : time    := 15 ns
  );
  port (
    sclk, cs_n, mosi : in  std_logic;
    miso             : out std_logic
  );
end entity;

architecture sim of flash_model is
begin
  process
    type mem_t is array (0 to SIZE - 1) of integer range 0 to 255;
    variable mem  : mem_t := (others => 255);
    file     f    : text;
    variable l    : line;
    variable v    : std_logic_vector(7 downto 0);
    variable n    : integer := 0;
    variable cmd  : std_logic_vector(7 downto 0);
    variable a    : std_logic_vector(23 downto 0);
    variable addr : integer;
    variable byte : std_logic_vector(7 downto 0);
    variable k    : integer;
  begin
    file_open(f, FILE_NAME, read_mode);
    while not endfile(f) and n < SIZE loop
      readline(f, l);
      hread(l, v);
      mem(n) := to_integer(unsigned(v));
      n := n + 1;
    end loop;
    file_close(f);
    report "flash_model: loaded " & integer'image(n) & " bytes";
    miso <= 'Z';

    loop
      wait until cs_n = '0';
      -- the command byte
      for i in 7 downto 0 loop
        wait until rising_edge(sclk);
        cmd(i) := mosi;
      end loop;
      addr := 0;
      if cmd = x"03" then
        for i in 23 downto 0 loop
          wait until rising_edge(sclk);
          a(i) := mosi;
        end loop;
        addr := to_integer(unsigned(a));
      end if;
      -- send bytes until CS_N goes high
      k := 0;
      outer : loop
        if cmd = x"9F" then
          case k is
            when 0      => byte := x"01";
            when 1      => byte := x"60";
            when 2      => byte := x"17";
            when others => byte := x"FF";
          end case;
        elsif cmd = x"03" and addr >= BASE and addr < BASE + SIZE then
          byte := std_logic_vector(to_unsigned(mem(addr - BASE), 8));
        else
          byte := x"FF";                              -- erased flash reads as FF
        end if;
        for i in 7 downto 0 loop
          wait until falling_edge(sclk) or cs_n = '1';
          exit outer when cs_n = '1';
          miso <= byte(i) after T_V;
        end loop;
        k := k + 1;
        addr := addr + 1;
      end loop;
      miso <= 'Z';
    end loop;
  end process;
end architecture;
