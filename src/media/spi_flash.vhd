-- ============================================================================
-- spi_flash.vhd
-- Reads bytes out of the board's SPI flash chip (Spansion/Infineon S25FL064L,
-- 8 MB) - the same chip the FPGA loads its bitstream from at power-up.
--
-- SPI IN ONE PARAGRAPH
--   Four wires. CS_N low = "I'm talking to you". SCLK = the clock the master
--   (us) makes. MOSI = bits from us to the chip, MISO = bits from the chip
--   to us. One bit moves per SCLK period, most significant bit first. We
--   use "mode 0": SCLK rests low; the chip reads MOSI when SCLK rises and
--   puts its next MISO bit out when SCLK falls.
--
-- ONE READ = ONE TRANSACTION
--   CS_N low, send a command byte (+ a 3-byte address for READ), then keep
--   clocking: the chip sends byte after byte (the address counts up by
--   itself) for as long as we keep clocking. CS_N high = finished.
--     cmd x"03" READ data      : 03, A23..A16, A15..A8, A7..A0, data...
--     cmd x"9F" read JEDEC ID  : 9F, then 3 ID bytes (01 60 17 for this chip)
--
-- SPEED
--   half_period = how many 50 MHz clocks SCLK stays low and then high:
--     1 -> 25 MHz (3.1 MB/s), 2 -> 12.5 MHz, 4 -> 6.25 MHz, 8 -> 3.1 MHz.
--   The READ command (03) is allowed up to 50 MHz on this chip.
--   MISO is sampled at the END of the high half (just before SCLK falls).
--   The chip only changes MISO a few ns AFTER the falling edge, so we read
--   the bit late but safely - this leaves room for the delays of the
--   STARTUPE2 path and the board wires (see docs/learn/08).
--
-- SCLK can't go to a normal pin: it is the FPGA's configuration clock pin
-- (CCLK). The top level passes 'sclk' to the STARTUPE2 primitive, the only
-- way to drive CCLK from user logic. STARTUPE2 ignores its first 3 clock
-- edges, so after power-up we first send 8 dummy clocks with CS_N high.
--
-- INTERFACE
--   start (pulse, while busy = '0') with cmd, use_addr, addr, len (bytes).
--   Every byte read gives one clock of dout_valid with dout. done = pulse at
--   the very end. The user must take each byte in the clock it arrives (at
--   most one byte every 16 clocks) - or hold it back: while 'hold' is '1'
--   the next byte does not start (SCLK just stays low; SPI chips don't mind
--   a pause). media_engine uses that while it writes long runs of pixels.
-- ============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity spi_flash is
  port (
    clk         : in  std_logic;
    half_period : in  integer range 1 to 8;
    -- request
    start       : in  std_logic;
    cmd         : in  std_logic_vector(7 downto 0);
    use_addr    : in  std_logic;
    addr        : in  unsigned(23 downto 0);
    len         : in  unsigned(23 downto 0);
    hold        : in  std_logic := '0';          -- '1' = don't start the next byte yet
    busy        : out std_logic;
    -- data
    dout        : out std_logic_vector(7 downto 0);
    dout_valid  : out std_logic;
    done        : out std_logic;
    -- the flash pins
    sclk        : out std_logic;                   -- to STARTUPE2.USRCCLKO
    cs_n        : out std_logic;
    mosi        : out std_logic;
    miso        : in  std_logic
  );
end entity;

architecture rtl of spi_flash is
  type state_t is (S_WAKE, S_IDLE, S_SEND, S_READ, S_END);
  signal state   : state_t := S_WAKE;

  signal sclk_r  : std_logic := '0';
  signal cs_r    : std_logic := '1';
  signal hp      : integer range 1 to 8 := 1;      -- half_period, kept for the whole transaction
  signal ph      : integer range 0 to 7 := 0;      -- clocks spent in this half of the SCLK period
  signal sh_out  : std_logic_vector(31 downto 0) := (others => '0');
  signal n_out   : integer range 0 to 32 := 0;     -- bits still to send
  signal sh_in   : std_logic_vector(7 downto 0) := (others => '0');
  signal n_in    : integer range 0 to 7 := 0;      -- bits of this byte already in
  signal left    : unsigned(23 downto 0) := (others => '0');  -- bytes still to read
  signal wake    : integer range 0 to 31 := 0;
  signal dv, dn  : std_logic := '0';
begin

  process(clk)
    variable half_done : boolean;
  begin
    if rising_edge(clk) then
      dv <= '0';
      dn <= '0';
      -- the SCLK half-period timer (used by S_WAKE, S_SEND, S_READ)
      half_done := (ph = hp - 1);
      if half_done then ph <= 0; else ph <= ph + 1; end if;

      case state is

        -- 8 SCLK periods with CS_N high: wakes up the STARTUPE2 clock path
        when S_WAKE =>
          hp <= 4;
          if half_done then
            sclk_r <= not sclk_r;
            if wake = 15 then state <= S_IDLE; sclk_r <= '0'; else wake <= wake + 1; end if;
          end if;

        when S_IDLE =>
          sclk_r <= '0';
          cs_r   <= '1';
          ph     <= 0;
          if start = '1' then
            hp     <= half_period;
            cs_r   <= '0';                         -- select the chip
            sh_out <= cmd & std_logic_vector(addr);
            if use_addr = '1' then n_out <= 32; else n_out <= 8; end if;
            left   <= len;
            n_in   <= 0;
            state  <= S_SEND;
          end if;

        -- command (+ address) out on MOSI, MSB first
        when S_SEND =>
          if half_done then
            if sclk_r = '0' then
              sclk_r <= '1';                       -- rising edge: the chip reads MOSI
            else
              sclk_r <= '0';                       -- falling edge: next bit
              sh_out <= sh_out(30 downto 0) & '0';
              if n_out = 1 then
                if left = 0 then state <= S_END; else state <= S_READ; end if;
              end if;
              n_out <= n_out - 1;
            end if;
          end if;

        -- data in on MISO, MSB first, one byte after another
        when S_READ =>
          if hold = '1' and n_in = 0 and sclk_r = '0' then
            ph <= 0;                               -- wait before the next byte
          elsif half_done then
            if sclk_r = '0' then
              sclk_r <= '1';
            else
              sclk_r <= '0';
              -- end of the high half: MISO still holds this bit, take it
              sh_in <= sh_in(6 downto 0) & miso;
              if n_in = 7 then
                n_in <= 0;
                dv   <= '1';                       -- a whole byte (sh_in shifted below)
                left <= left - 1;
                if left = 1 then state <= S_END; end if;
              else
                n_in <= n_in + 1;
              end if;
            end if;
          end if;

        -- deselect, and keep CS_N high a little before the next command
        when S_END =>
          cs_r   <= '1';
          sclk_r <= '0';
          if wake /= 0 then wake <= wake - 1; else dn <= '1'; state <= S_IDLE; end if;

      end case;

      if state = S_IDLE and start = '1' then
        wake <= 3;                                 -- reused as the S_END hold counter
      end if;
    end if;
  end process;

  busy       <= '0' when state = S_IDLE else '1';
  -- dv is set in the same clock as the last bit goes into sh_in, so the
  -- finished byte is visible one clock later, when dout_valid is '1'
  dout       <= sh_in;
  dout_valid <= dv;
  done       <= dn;
  sclk       <= sclk_r;
  cs_n       <= cs_r;
  mosi       <= sh_out(31);

end architecture;
