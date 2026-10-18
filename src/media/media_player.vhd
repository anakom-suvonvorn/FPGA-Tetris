-- ============================================================================
-- media_player.vhd
-- Plays pictures, animations and sound stored in the SPI flash, in the
-- format written by tools\make_media.py (layout below).
--
-- WHAT IT HAS INSIDE (all on the FPGA's block RAM, "BRAM")
--   frame buffer  160 x 120 pixels, 8 bits each   (19,200 bytes)
--                 shown 4x bigger = 640 x 480 on the VGA screen
--   palette       256 colours, 12 bits each       (a pixel's 8 bits pick one)
--   audio ring    2,048 bytes of sound waiting to be played
--   spi_flash     the reader that brings bytes in from the flash chip
--
-- THE FLASH FILE (little-endian numbers), starting at flash address BASE
--   header, 16 bytes at BASE:
--     0..3   "TDMF"   (magic: "Tetris Duel Media File")
--     4      version (1)          5  number of items (up to 16)
--     8..11  address of the VERIFY block   12..15 its length in bytes
--   directory, 32 bytes per item, at BASE + 16 + 32 * item:
--     0      bpp: bits per pixel 1, 2, 4 or 8 (0 = sound only)
--     1      frame_ticks: 60ths of a second per frame (when there is no sound)
--     2      flags: bit 0 = loop
--     4..5   number of records (frames)
--     6..7   sound bytes per record
--     8..11  address of the item's data
--     12..13 sample rate (samples per second)
--     14..15 low water: load the next record when fewer sound bytes than
--            this are waiting (sound + picture items)
--     16..31 the item's name, 16 character codes (text_pkg)
--   item data at its address:
--     palette: 2^bpp colours x 2 bytes (12-bit 0x0RGB), none if bpp = 0
--     records: [sound bytes][picture bytes], one per frame. Picture bytes =
--              19,200 * bpp / 8 pixels packed MSB first, row by row.
--   verify block: bytes from a 16-bit LFSR (seed ACE1, 8 steps per byte) -
--     the FPGA makes the same sequence and counts every byte that differs.
--
-- WHEN IS THE NEXT RECORD LOADED? ("pacing")
--   picture only:   every frame_ticks frames, at the start of a frame
--   sound only:     whenever the ring has room for one more record
--   picture+sound:  when the ring runs low (below 'low water'), at the start
--                   of the next frame. The sound decides the speed, so the
--                   picture can never drift away from the sound.
--   Loading starts right at the end of the visible picture (frame_tick) and
--   goes faster than the screen is drawn, so we never show half-old,
--   half-new frames (at the faster SPI speeds).
--
-- COMMANDS: play (with item), stop, verify are one-clock pulses; they are
-- remembered and done as soon as the flash reader is free.
-- ============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity media_player is
  generic (
    BASE : integer := 16#100000#                     -- flash address of the media file
  );
  port (
    clk          : in  std_logic;
    frame_tick   : in  std_logic;                     -- end of the visible picture
    half_period  : in  integer range 1 to 8;          -- SPI speed (see spi_flash)
    -- commands
    play         : in  std_logic;
    item         : in  integer range 0 to 15;
    stop         : in  std_logic;
    verify       : in  std_logic;
    -- flash pins (sclk goes to STARTUPE2 in the top level)
    sclk         : out std_logic;
    cs_n         : out std_logic;
    mosi         : out std_logic;
    miso         : in  std_logic;
    -- picture: colour of screen pixel (x, y), ready 3 clocks later
    x, y         : in  unsigned(9 downto 0);
    rgb          : out std_logic_vector(11 downto 0);
    -- sound: 8-bit unsigned sample (128 = silence)
    sample       : out unsigned(7 downto 0);
    -- status, for the screen
    flash_id     : out std_logic_vector(23 downto 0);
    head         : out std_logic_vector(31 downto 0); -- the first 4 bytes at BASE
    found        : out std_logic;                     -- head = "TDMF"
    n_items      : out integer range 0 to 255;
    name         : out std_logic_vector(95 downto 0);
    is_playing   : out std_logic;
    has_video    : out std_logic;
    frame_bcd    : out std_logic_vector(15 downto 0); -- records loaded so far
    load_bcd     : out std_logic_vector(15 downto 0); -- last record's load time, 0.1 ms
    under_bcd    : out std_logic_vector(15 downto 0); -- sound ran dry this many times
    ver_state    : out integer range 0 to 2;          -- 0 never run, 1 running, 2 done
    ver_err_bcd  : out std_logic_vector(15 downto 0);
    ver_ms_bcd   : out std_logic_vector(15 downto 0)
  );
end entity;

architecture rtl of media_player is
  constant CLK_HZ   : integer := 50_000_000;
  constant FB_SIZE  : integer := 160 * 120;
  constant RING_SIZE     : integer := 2048;

  -- ------------------------------------------------------------ memories
  -- the frame buffer is 5 banks of 4,096 bytes: each bank fits exactly one
  -- 36 Kbit BRAM tile (left alone, Vivado would spend 8 tiles on it)
  type fbank_t is array (0 to 4095) of std_logic_vector(7 downto 0);
  type fq_t   is array (0 to 4) of std_logic_vector(7 downto 0);
  type pal_t  is array (0 to 255) of std_logic_vector(11 downto 0);
  type ring_t is array (0 to RING_SIZE - 1) of std_logic_vector(7 downto 0);
  signal fq    : fq_t;                                      -- each bank's output
  signal rbank : integer range 0 to 4 := 0;                 -- which bank fq is from
  signal pal   : pal_t := (others => (others => '0'));
  signal ring  : ring_t := (others => x"80");
  signal fb_we, pal_we, ring_we : std_logic := '0';
  signal fb_wa   : integer range 0 to FB_SIZE - 1 := 0;
  signal fb_wd   : std_logic_vector(7 downto 0) := (others => '0');
  signal pal_wa  : integer range 0 to 255 := 0;
  signal pal_wd  : std_logic_vector(11 downto 0) := (others => '0');
  signal ring_wa : integer range 0 to RING_SIZE - 1 := 0;
  signal ring_wd : std_logic_vector(7 downto 0) := (others => '0');
  signal ring_q  : std_logic_vector(7 downto 0) := x"80";
  signal ra      : integer range 0 to FB_SIZE - 1 := 0;
  signal fb_q    : std_logic_vector(7 downto 0);
  signal pal_q   : std_logic_vector(11 downto 0) := (others => '0');

  -- ------------------------------------------------------------ flash reader
  signal f_start, f_use_addr, f_busy, f_valid, f_done : std_logic := '0';
  signal f_cmd   : std_logic_vector(7 downto 0) := (others => '0');
  signal f_addr  : unsigned(23 downto 0) := (others => '0');
  signal f_len   : unsigned(23 downto 0) := (others => '0');
  signal f_data  : std_logic_vector(7 downto 0);

  -- ------------------------------------------------------------ state
  type state_t is (M_ID, M_ID_W, M_HDR, M_HDR_W, M_IDLE, M_ENT, M_ENT_W,
                   M_PAL, M_PAL_W, M_PLAY0, M_WAIT, M_REC, M_REC_W, M_VER, M_VER_W);
  signal state   : state_t := M_ID;
  signal bi      : unsigned(23 downto 0) := (others => '0');  -- byte number in this read

  signal req_play, req_stop, req_ver : std_logic := '0';
  signal req_item : integer range 0 to 15 := 0;

  signal id_r    : std_logic_vector(23 downto 0) := (others => '0');
  signal head_r  : std_logic_vector(31 downto 0) := (others => '0');
  signal nitems_r : integer range 0 to 255 := 0;
  signal v_addr, v_len : unsigned(23 downto 0) := (others => '0');

  -- the item being played (from its directory entry)
  signal e_bpp   : integer range 0 to 8 := 0;
  signal e_ft    : integer range 0 to 255 := 1;
  signal e_loop  : std_logic := '0';
  signal e_nrec  : unsigned(15 downto 0) := (others => '0');
  signal e_aud   : unsigned(15 downto 0) := (others => '0');
  signal e_addr  : unsigned(23 downto 0) := (others => '0');
  signal e_rate  : unsigned(15 downto 0) := (others => '0');
  signal e_low   : unsigned(15 downto 0) := (others => '0');
  signal name_r  : std_logic_vector(95 downto 0) := (others => '0');
  signal lo_byte : std_logic_vector(7 downto 0) := (others => '0');  -- first half of a 2-byte value

  signal rec     : unsigned(15 downto 0) := (others => '0');  -- record number
  signal r_addr  : unsigned(23 downto 0) := (others => '0');  -- address of that record
  signal playing : std_logic := '0';
  signal started : std_logic := '0';                         -- the first record is in
  signal ticks   : integer range 0 to 255 := 0;              -- frames since the last record

  -- picture unpacking (bpp < 8): pixels left in the current byte
  signal un_sh   : std_logic_vector(7 downto 0) := (others => '0');
  signal un_n    : integer range 0 to 8 := 0;
  signal wa      : integer range 0 to FB_SIZE := 0;

  -- sound
  signal rd_ptr, wr_ptr : integer range 0 to RING_SIZE - 1 := 0;
  signal fill    : integer range 0 to RING_SIZE := 0;
  signal acc     : unsigned(26 downto 0) := (others => '0');
  signal smp     : unsigned(7 downto 0) := x"80";

  -- counters for the screen
  signal frames_bcd, load_cnt, load_last, under_r : std_logic_vector(15 downto 0) := (others => '0');
  signal err_bcd, ms_bcd : std_logic_vector(15 downto 0) := (others => '0');
  signal ver_st  : integer range 0 to 2 := 0;
  signal cyc     : integer range 0 to 49_999 := 0;
  signal v_lfsr  : std_logic_vector(15 downto 0) := x"ACE1";

  -- add 1 to a 4-digit BCD number (9999 stays 9999), as in tetris_core
  function bcd_inc(v : std_logic_vector(15 downto 0)) return std_logic_vector is
    variable r     : std_logic_vector(15 downto 0) := v;
    variable carry : boolean := true;
  begin
    if v = x"9999" then
      return v;
    end if;
    for d in 0 to 3 loop
      if carry then
        if r(4*d+3 downto 4*d) = "1001" then
          r(4*d+3 downto 4*d) := "0000";
        else
          r(4*d+3 downto 4*d) := std_logic_vector(unsigned(r(4*d+3 downto 4*d)) + 1);
          carry := false;
        end if;
      end if;
    end loop;
    return r;
  end function;

  -- the verify LFSR, 8 steps at once (one step = shift left, new bit 0 =
  -- bit15 xor bit13 xor bit12 xor bit10) - make_media.py does the same
  function lfsr8(v : std_logic_vector(15 downto 0)) return std_logic_vector is
    variable s : std_logic_vector(15 downto 0) := v;
  begin
    for i in 1 to 8 loop
      s := s(14 downto 0) & (s(15) xor s(13) xor s(12) xor s(10));
    end loop;
    return s;
  end function;

  function pix_bytes(bpp : integer range 0 to 8) return unsigned is
  begin
    case bpp is
      when 1      => return to_unsigned(2400, 24);
      when 2      => return to_unsigned(4800, 24);
      when 4      => return to_unsigned(9600, 24);
      when 8      => return to_unsigned(19200, 24);
      when others => return to_unsigned(0, 24);
    end case;
  end function;

  function pal_bytes(bpp : integer range 0 to 8) return unsigned is
  begin
    case bpp is
      when 1      => return to_unsigned(4, 24);
      when 2      => return to_unsigned(8, 24);
      when 4      => return to_unsigned(32, 24);
      when 8      => return to_unsigned(512, 24);
      when others => return to_unsigned(0, 24);
    end case;
  end function;
begin

  u_spi : entity work.spi_flash
    port map (clk => clk, half_period => half_period,
              start => f_start, cmd => f_cmd, use_addr => f_use_addr, addr => f_addr,
              len => f_len, busy => f_busy, dout => f_data, dout_valid => f_valid,
              done => f_done, sclk => sclk, cs_n => cs_n, mosi => mosi, miso => miso);

  -- ============================================================ control
  process(clk)
    variable b       : std_logic_vector(7 downto 0);
    variable k       : integer range 0 to 31;
    variable go      : boolean;
    variable dfill   : integer range -1 to 1;
    variable aud_end : unsigned(23 downto 0);
  begin
    if rising_edge(clk) then
      f_start <= '0';
      fb_we   <= '0';
      pal_we  <= '0';
      ring_we <= '0';
      dfill   := 0;
      b       := f_data;
      k       := to_integer(bi(4 downto 0));
      aud_end := resize(e_aud, 24);

      -- remember commands until we can do them
      if play   = '1' then req_play <= '1'; req_item <= item; end if;
      if stop   = '1' then req_stop <= '1'; end if;
      if verify = '1' then req_ver  <= '1'; end if;

      -- count bytes of the current read
      if f_valid = '1' then bi <= bi + 1; end if;

      case state is

        -- ------------------------------------------------ power-up: who are you?
        when M_ID =>
          if f_busy = '0' then
            f_cmd <= x"9F"; f_use_addr <= '0'; f_len <= to_unsigned(3, 24);
            f_start <= '1'; bi <= (others => '0');
            state <= M_ID_W;
          end if;
        when M_ID_W =>
          if f_valid = '1' then id_r <= id_r(15 downto 0) & b; end if;
          if f_done = '1' then state <= M_HDR; end if;

        -- ------------------------------------------------ read the header
        when M_HDR =>
          f_cmd <= x"03"; f_use_addr <= '1';
          f_addr <= to_unsigned(BASE, 24); f_len <= to_unsigned(16, 24);
          f_start <= '1'; bi <= (others => '0');
          state <= M_HDR_W;
        when M_HDR_W =>
          if f_valid = '1' then
            case k is
              when 0 | 1 | 2 | 3 => head_r <= head_r(23 downto 0) & b;
              when 5      => nitems_r <= to_integer(unsigned(b));
              when 8      => v_addr(7 downto 0)   <= unsigned(b);
              when 9      => v_addr(15 downto 8)  <= unsigned(b);
              when 10     => v_addr(23 downto 16) <= unsigned(b);
              when 12     => v_len(7 downto 0)    <= unsigned(b);
              when 13     => v_len(15 downto 8)   <= unsigned(b);
              when 14     => v_len(23 downto 16)  <= unsigned(b);
              when others => null;
            end case;
          end if;
          if f_done = '1' then state <= M_IDLE; end if;

        -- ------------------------------------------------ waiting for a command
        when M_IDLE =>
          if req_play = '1' then
            req_play <= '0';
            if head_r = x"54444D46" and req_item < nitems_r then state <= M_ENT; end if;
          elsif req_ver = '1' then
            req_ver <= '0';
            state   <= M_VER;
          end if;
          req_stop <= '0';

        -- ------------------------------------------------ the item's directory entry
        when M_ENT =>
          playing <= '0';
          f_cmd <= x"03"; f_use_addr <= '1';
          f_addr <= to_unsigned(BASE + 16, 24) + to_unsigned(req_item * 32, 24);
          f_len <= to_unsigned(32, 24);
          f_start <= '1'; bi <= (others => '0');
          state <= M_ENT_W;
        when M_ENT_W =>
          if f_valid = '1' then
            case k is
              when 0      => e_bpp <= to_integer(unsigned(b(3 downto 0)));
              when 1      => e_ft  <= to_integer(unsigned(b));
              when 2      => e_loop <= b(0);
              when 4      => e_nrec(7 downto 0)  <= unsigned(b);
              when 5      => e_nrec(15 downto 8) <= unsigned(b);
              when 6      => e_aud(7 downto 0)   <= unsigned(b);
              when 7      => e_aud(15 downto 8)  <= unsigned(b);
              when 8      => e_addr(7 downto 0)  <= unsigned(b);
              when 9      => e_addr(15 downto 8) <= unsigned(b);
              when 10     => e_addr(23 downto 16) <= unsigned(b);
              when 12     => e_rate(7 downto 0)  <= unsigned(b);
              when 13     => e_rate(15 downto 8) <= unsigned(b);
              when 14     => e_low(7 downto 0)   <= unsigned(b);
              when 15     => e_low(15 downto 8)  <= unsigned(b);
              when 3 | 11 => null;                    -- not used
              when others => name_r <= b(5 downto 0) & name_r(95 downto 6);  -- 16..31
            end case;
          end if;
          if f_done = '1' then
            if e_bpp = 0 then state <= M_PLAY0; else state <= M_PAL; end if;
          end if;

        -- ------------------------------------------------ the palette
        when M_PAL =>
          f_addr <= e_addr; f_len <= pal_bytes(e_bpp);
          f_start <= '1'; bi <= (others => '0');
          state <= M_PAL_W;
        when M_PAL_W =>
          if f_valid = '1' then
            if bi(0) = '0' then
              lo_byte <= b;                          -- low byte: G (high nibble), B
            else
              pal_we <= '1';                         -- high byte: R (low nibble)
              pal_wa <= to_integer(bi(8 downto 1));
              pal_wd <= b(3 downto 0) & lo_byte;
            end if;
          end if;
          if f_done = '1' then state <= M_PLAY0; end if;

        -- ------------------------------------------------ start playing
        when M_PLAY0 =>
          rec        <= (others => '0');
          r_addr     <= e_addr + pal_bytes(e_bpp);
          frames_bcd <= (others => '0');
          under_r    <= (others => '0');
          started    <= '0';
          ticks      <= 255;                         -- picture-only: load at the next frame
          rd_ptr <= 0; wr_ptr <= 0; fill <= 0; dfill := 0;
          smp        <= x"80";
          playing    <= '1';
          state      <= M_WAIT;

        -- ------------------------------------------------ pacing (see the header)
        when M_WAIT =>
          go := false;
          if frame_tick = '1' and ticks /= 255 then ticks <= ticks + 1; end if;
          if e_aud = 0 then                          -- picture only
            if frame_tick = '1' and ticks >= e_ft - 1 then go := true; end if;
          elsif e_bpp = 0 then                       -- sound only
            if fill + to_integer(e_aud) <= RING_SIZE then go := true; end if;
          else                                       -- picture + sound
            if frame_tick = '1' and fill < to_integer(e_low) then go := true; end if;
          end if;
          if req_stop = '1' or req_play = '1' or req_ver = '1' then
            req_stop <= '0';
            playing  <= '0';
            state    <= M_IDLE;
          elsif go then
            ticks <= 0;
            state <= M_REC;
          end if;

        when M_REC =>
          f_addr <= r_addr; f_len <= aud_end + pix_bytes(e_bpp);
          f_start <= '1'; bi <= (others => '0');
          wa <= 0; un_n <= 0;
          load_cnt <= (others => '0'); cyc <= 0;
          state <= M_REC_W;

        -- sound bytes into the ring, then picture bytes into the frame buffer
        when M_REC_W =>
          if cyc = 4_999 then cyc <= 0; load_cnt <= bcd_inc(load_cnt); else cyc <= cyc + 1; end if;
          if f_valid = '1' then
            if bi < aud_end then
              ring_we <= '1'; ring_wa <= wr_ptr; ring_wd <= b;
              if wr_ptr = RING_SIZE - 1 then wr_ptr <= 0; else wr_ptr <= wr_ptr + 1; end if;
              dfill := 1;
            elsif e_bpp = 8 then
              if wa < FB_SIZE then fb_we <= '1'; fb_wa <= wa; fb_wd <= b; wa <= wa + 1; end if;
            else
              un_sh <= b;
              case e_bpp is                          -- pixels in this byte
                when 1      => un_n <= 8;
                when 2      => un_n <= 4;
                when others => un_n <= 2;
              end case;
            end if;
          elsif un_n > 0 then                          -- one packed pixel per clock
            if wa < FB_SIZE then fb_we <= '1'; fb_wa <= wa; wa <= wa + 1; end if;
            case e_bpp is
              when 1      => fb_wd <= "0000000" & un_sh(7);    un_sh <= un_sh(6 downto 0) & '0';
              when 2      => fb_wd <= "000000" & un_sh(7 downto 6); un_sh <= un_sh(5 downto 0) & "00";
              when others => fb_wd <= "0000" & un_sh(7 downto 4);   un_sh <= un_sh(3 downto 0) & "0000";
            end case;
            un_n <= un_n - 1;
          end if;
          if f_done = '1' then
            started    <= '1';
            load_last  <= load_cnt;
            frames_bcd <= bcd_inc(frames_bcd);
            if rec = e_nrec - 1 then
              rec    <= (others => '0');
              r_addr <= e_addr + pal_bytes(e_bpp);
              if e_loop = '1' then state <= M_WAIT; else playing <= '0'; state <= M_IDLE; end if;
            else
              rec    <= rec + 1;
              r_addr <= r_addr + aud_end + pix_bytes(e_bpp);
              state  <= M_WAIT;
            end if;
          end if;

        -- ------------------------------------------------ verify the test block
        when M_VER =>
          playing <= '0';
          f_addr <= v_addr; f_len <= v_len;
          f_start <= '1'; bi <= (others => '0');
          v_lfsr <= x"ACE1";
          err_bcd <= (others => '0'); ms_bcd <= (others => '0'); cyc <= 0;
          ver_st <= 1;
          state <= M_VER_W;
        when M_VER_W =>
          if cyc = 49_999 then cyc <= 0; ms_bcd <= bcd_inc(ms_bcd); else cyc <= cyc + 1; end if;
          if f_valid = '1' then
            if b /= v_lfsr(7 downto 0) then err_bcd <= bcd_inc(err_bcd); end if;
            v_lfsr <= lfsr8(v_lfsr);
          end if;
          if f_done = '1' then ver_st <= 2; state <= M_IDLE; end if;
      end case;

      -- ------------------------------------------------ sound out
      -- a sample is due every CLK_HZ / rate clocks: add 'rate' every clock,
      -- and every time the sum passes CLK_HZ, one sample is due
      if acc + e_rate >= CLK_HZ then
        acc <= acc + e_rate - CLK_HZ;
        if state = M_PLAY0 then
          null;                                      -- the ring is being emptied
        elsif fill > 0 then
          smp <= unsigned(ring_q);                   -- ring_q = ring(rd_ptr), see below
          if rd_ptr = RING_SIZE - 1 then rd_ptr <= 0; else rd_ptr <= rd_ptr + 1; end if;
          dfill := dfill - 1;
        elsif playing = '1' and started = '1' and e_aud /= 0 then
          under_r <= bcd_inc(under_r);               -- ran dry: count it, keep the last sample
        end if;
      else
        acc <= acc + e_rate;
      end if;
      if state /= M_PLAY0 then
        fill <= fill + dfill;
      end if;
    end if;
  end process;

  -- ============================================================ memories
  -- frame buffer: written by the loader, read for the screen.
  -- Address a = bank (a / 4096) and place in the bank (a mod 4096).
  g_fb : for k in 0 to 4 generate
    signal mem : fbank_t := (others => (others => '0'));
  begin
    process(clk)
    begin
      if rising_edge(clk) then
        if fb_we = '1' and fb_wa / 4096 = k then
          mem(fb_wa mod 4096) <= fb_wd;
        end if;
        fq(k) <= mem(ra mod 4096);
      end if;
    end process;
  end generate;

  process(clk)
  begin
    if rising_edge(clk) then
      rbank <= ra / 4096;                            -- remember the bank, read with fq
    end if;
  end process;
  fb_q <= fq(rbank);

  process(clk)
  begin
    if rising_edge(clk) then
      if pal_we = '1' then pal(pal_wa) <= pal_wd; end if;
      pal_q <= pal(to_integer(unsigned(fb_q)));
    end if;
  end process;

  process(clk)
  begin
    if rising_edge(clk) then
      if ring_we = '1' then ring(ring_wa) <= ring_wd; end if;
      ring_q <= ring(rd_ptr);
    end if;
  end process;

  -- screen pixel (x, y) -> frame buffer address (y/4) * 160 + (x/4)
  -- 160 = 128 + 32, so the multiply is two shifts and an add
  process(clk)
    variable yi : unsigned(6 downto 0);
    variable xi : unsigned(7 downto 0);
  begin
    if rising_edge(clk) then
      yi := y(8 downto 2);
      xi := x(9 downto 2);
      if x < 640 and y < 480 then
        ra <= to_integer(shift_left(resize(yi, 15), 7) + shift_left(resize(yi, 15), 5) + resize(xi, 15));
      else
        ra <= 0;
      end if;
    end if;
  end process;

  rgb         <= pal_q;
  sample      <= smp;
  flash_id    <= id_r;
  head        <= head_r;
  found       <= '1' when head_r = x"54444D46" else '0';
  n_items     <= nitems_r;
  name        <= name_r;
  is_playing  <= playing;
  has_video   <= '1' when e_bpp /= 0 else '0';
  frame_bcd   <= frames_bcd;
  load_bcd    <= load_last;
  under_bcd   <= under_r;
  ver_state   <= ver_st;
  ver_err_bcd <= err_bcd;
  ver_ms_bcd  <= ms_bcd;

end architecture;
