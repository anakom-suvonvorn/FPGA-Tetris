-- ============================================================================
-- media_engine.vhd
-- The game's media player: music, background videos, win / lose clips and
-- the sprites, all read from the SPI flash. The file format is "TDM2",
-- written by tools\make_game_media.py (its header explains every byte).
-- (tests\06_flash_read uses the simpler media_player.vhd, format 1.)
--
-- WHAT IT HAS INSIDE (block RAM)
--   frame buffer   160 x 120 pixels, 8 bits each (5 banks of 4,096 bytes)
--   palettes       512 colours of 12 bits: 0..255 for the item playing,
--                  256..511 for the sprites
--   sound ring     2,048 bytes of ADPCM sound waiting to be played
--   Jevil          8 poses of 48 x 50 pixels, 4 bits each (5 banks of 4,096)
--   faces          4 faces of 32 x 32 pixels, 8 bits each
--
-- AT POWER-UP: read the header (16 bytes); if it says "TDM2", load the
--   sprite block (palette + Jevil + faces) once. Then wait for commands.
--
-- PLAYING AN ITEM ('play' with 'item' and 'from_rec')
--   1. read its directory entry (16 bytes) and its palette
--   2. records, one after the other. A record = 8-byte header (where its
--      picture is, the ADPCM state) + its sound bytes. For each record:
--        header -> picture (if any) into the frame buffer -> sound into the ring
--   When is the next record loaded? ("pacing")
--      sound + picture: at the start of a frame (frame_tick), if the ring is
--                       below the item's "low water" mark (the sound sets the
--                       speed, so picture and sound can't drift apart)
--      sound only:      as soon as the ring has room for another record
--      picture only:    every frame_ticks frames
--   'from_rec' = start in the middle (music continuing after an attack).
--   The record's header holds the ADPCM state at its start, so the sound
--   decoder can pick up there.
--
-- PICTURES are "delta + run length" (only what changed since the last one,
--   see make_game_media.py). The decoder writes one pixel per clock. A run
--   can be 128 pixels long, but bytes come every 17 clocks - so while the
--   decoder is busy (and has the next byte waiting in 'pb') it holds the
--   flash reader back with spi_flash's 'hold'.
--
-- SOUND: every 3,125 clocks (16,000 times a second) one 4-bit code goes
--   from the ring into adpcm_dec (low nibble of a byte first).
--
-- THE SCREEN: give (x, y); 3 clocks later 'rgb' is the picture's colour
--   there, 'see' = '1' if its palette index is 0 (see-through in 'over'
--   mode) and 'zone' says where (x, y) is: 3 = on the picture, and for the
--   panel mode 1 = the 2 px frame, 2 = the 2 px dark gap inside it.
--   Normal pictures are drawn 4x (160 x 120 -> 640 x 480), panel pictures
--   2x (96 x 88 -> 192 x 176 at x 430, y 286).
-- SPRITES: give a Jevil address (pose * 2400 + row * 48 + column) and/or a
--   face address (face * 1024 + row * 32 + column) one clock after (x, y);
--   2 clocks later 'spr_on' / 'spr_rgb' (Jevil wins where both are).
-- ============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity media_engine is
  generic (
    BASE        : integer := 16#100000#;          -- flash address of the file
    HALF_PERIOD : integer range 1 to 8 := 1;      -- SPI speed: 1 = 25 MHz
    SAMPLE_CLKS : integer := 3125                 -- 50 MHz / 16 kHz
  );
  port (
    clk        : in  std_logic;
    frame_tick : in  std_logic;
    -- commands (one-clock pulses, remembered until they can be done)
    play       : in  std_logic;
    item       : in  integer range 0 to 31;
    from_rec   : in  unsigned(15 downto 0);
    stop       : in  std_logic;
    -- what the file holds
    ready      : out std_logic;                   -- header found ("TDM2")
    spr_ok     : out std_logic;                   -- sprites loaded
    mus_first, mus_n, atk_first, lose_first, lose_n, win_first, win_n : out integer range 0 to 31;
    -- the item playing
    busy       : out std_logic;                   -- records left, or sound in the ring
    has_snd    : out std_logic;
    pic_ok     : out std_logic;                   -- its first picture is complete
    mode       : out integer range 0 to 3;        -- 0 bg, 1 full, 2 over, 3 panel
    dim_half   : out std_logic;
    rec_pos    : out unsigned(15 downto 0);       -- next record to load
    -- flash pins (sclk goes to STARTUPE2 in the top level)
    sclk       : out std_logic;
    cs_n       : out std_logic;
    mosi       : out std_logic;
    miso       : in  std_logic;
    -- picture
    x, y       : in  unsigned(9 downto 0);
    rgb        : out std_logic_vector(11 downto 0);
    see        : out std_logic;
    zone       : out integer range 0 to 3;
    -- sprites
    j_en       : in  std_logic;
    j_addr     : in  unsigned(14 downto 0);
    f_en       : in  std_logic;
    f_addr     : in  unsigned(11 downto 0);
    spr_on     : out std_logic;
    spr_rgb    : out std_logic_vector(11 downto 0);
    -- sound
    pcm        : out signed(15 downto 0)
  );
end entity;

architecture rtl of media_engine is
  constant FB_SIZE   : integer := 160 * 120;
  constant RING_SIZE : integer := 2048;
  constant SPR_LEN   : integer := 512 + 9600 + 4096;   -- palette + Jevil + faces

  -- ------------------------------------------------------------ memories
  type bank8_t  is array (0 to 4095) of std_logic_vector(7 downto 0);
  type bank4_t  is array (0 to 4095) of std_logic_vector(3 downto 0);
  type q8_t     is array (0 to 4) of std_logic_vector(7 downto 0);
  type q4_t     is array (0 to 4) of std_logic_vector(3 downto 0);
  type pal_t    is array (0 to 511) of std_logic_vector(11 downto 0);
  type ring_t   is array (0 to RING_SIZE - 1) of std_logic_vector(7 downto 0);
  signal pal    : pal_t := (others => (others => '0'));
  signal ring   : ring_t := (others => (others => '0'));
  signal faces  : bank8_t := (others => (others => '0'));
  -- all of these MUST be block RAM (Vivado otherwise sometimes moves one
  -- into LUTs when it guesses wrongly that the block RAM has run out)
  attribute ram_style : string;
  attribute ram_style of pal, ring, faces : signal is "block";

  signal fb_we, j_we, f_we, pal_we, ring_we : std_logic := '0';
  signal fb_wa  : integer range 0 to FB_SIZE - 1 := 0;
  signal fb_wd  : std_logic_vector(7 downto 0) := (others => '0');
  signal j_wa   : integer range 0 to FB_SIZE - 1 := 0;
  signal j_wd   : std_logic_vector(3 downto 0) := (others => '0');
  signal f_wa   : integer range 0 to 4095 := 0;
  signal f_wd   : std_logic_vector(7 downto 0) := (others => '0');
  signal pal_wa : unsigned(8 downto 0) := (others => '0');
  signal pal_wd : std_logic_vector(11 downto 0) := (others => '0');
  signal ring_wa : integer range 0 to RING_SIZE - 1 := 0;
  signal ring_wd : std_logic_vector(7 downto 0) := (others => '0');
  signal ring_q  : std_logic_vector(7 downto 0) := (others => '0');

  -- screen read pipeline
  signal ra      : integer range 0 to FB_SIZE - 1 := 0;
  signal z1, z2, z3 : integer range 0 to 3 := 0;
  signal fq      : q8_t;
  signal rbank   : integer range 0 to 4 := 0;
  signal fb_q    : std_logic_vector(7 downto 0);
  signal pa      : unsigned(8 downto 0);
  signal pal_qa  : std_logic_vector(11 downto 0) := (others => '0');
  signal see3    : std_logic := '0';
  -- sprite read pipeline
  signal jq      : q4_t;
  signal jbank   : integer range 0 to 4 := 0;
  signal fcq     : std_logic_vector(7 downto 0) := (others => '0');
  signal j_en2, f_en2, s_on3 : std_logic := '0';
  signal jn      : std_logic_vector(3 downto 0);
  signal s_idx   : std_logic_vector(7 downto 0);
  signal s_on2   : std_logic;
  signal pal_qb  : std_logic_vector(11 downto 0) := (others => '0');

  -- ------------------------------------------------------------ flash reader
  signal fl_start, fl_busy, fl_valid, fl_done, fl_hold : std_logic := '0';
  signal fl_addr  : unsigned(23 downto 0) := (others => '0');
  signal fl_len   : unsigned(23 downto 0) := (others => '0');
  signal fl_data  : std_logic_vector(7 downto 0);

  -- ------------------------------------------------------------ state
  type state_t is (E_HDR, E_HDR_W, E_SPR, E_SPR_W, E_IDLE, E_ENT, E_ENT_W, E_PAL, E_PAL_W,
                   E_START, E_WAIT, E_RH, E_RH_W, E_PIC, E_PIC_W, E_PIC_END, E_SND, E_SND_W, E_NEXT);
  signal state   : state_t := E_HDR;
  signal bi      : unsigned(15 downto 0) := (others => '0');   -- byte number in this read (all reads < 64 KB)

  signal req_play, req_stop : std_logic := '0';
  signal req_item : integer range 0 to 31 := 0;
  signal req_rec  : unsigned(15 downto 0) := (others => '0');

  -- the header
  signal magic   : std_logic_vector(31 downto 0) := (others => '0');
  signal n_items : integer range 0 to 255 := 0;
  type hb_t is array (6 to 12) of integer range 0 to 255;
  signal hb      : hb_t := (others => 0);
  signal spr_adr : unsigned(23 downto 0) := (others => '0');
  signal spr_done : std_logic := '0';
  signal lo_byte : std_logic_vector(7 downto 0) := (others => '0');

  -- the item's directory entry
  signal e_bpp   : integer range 0 to 15 := 0;
  signal e_ft    : integer range 0 to 255 := 1;
  signal e_mode  : std_logic_vector(2 downto 0) := (others => '0');
  signal e_nrec  : unsigned(15 downto 0) := (others => '0');
  signal e_aud   : unsigned(15 downto 0) := (others => '0');
  signal e_paddr   : unsigned(23 downto 0) := (others => '0');
  signal e_rec   : unsigned(23 downto 0) := (others => '0');
  signal e_low   : unsigned(7 downto 0) := (others => '0');

  -- the record being loaded
  signal rec     : unsigned(15 downto 0) := (others => '0');
  signal r_addr  : unsigned(23 downto 0) := (others => '0');
  signal p_addr  : unsigned(23 downto 0) := (others => '0');
  signal p_len   : unsigned(15 downto 0) := (others => '0');
  signal h_pred  : signed(15 downto 0) := (others => '0');
  signal loading : std_logic := '0';
  signal started : std_logic := '0';
  signal pic_r   : std_logic := '0';
  signal ticks   : integer range 0 to 255 := 0;

  -- picture decoder (run length)
  type dstate_t is (D_OP, D_COL, D_FILL, D_LIT, D_UNP);
  signal dst     : dstate_t := D_OP;
  signal pb      : std_logic_vector(7 downto 0) := (others => '0');   -- the byte waiting
  signal pb_v    : std_logic := '0';
  signal cnt     : integer range 0 to 128 := 0;    -- pixels left in this run
  signal nb      : integer range 0 to 8 := 0;      -- pixels left in the literal byte
  signal sh      : std_logic_vector(7 downto 0) := (others => '0');
  signal col     : std_logic_vector(7 downto 0) := (others => '0');
  signal wa      : integer range 0 to 32767 := 0;  -- next pixel to write

  -- sprite loading: second nibble of a Jevil byte
  signal j_lo    : std_logic_vector(3 downto 0) := (others => '0');
  signal j_lo_v  : std_logic := '0';

  -- sound
  signal rd_ptr, wr_ptr : integer range 0 to RING_SIZE - 1 := 0;
  signal fill    : integer range 0 to RING_SIZE := 0;
  signal hi_nib  : std_logic := '0';               -- next code = the high nibble
  signal scnt    : integer range 0 to SAMPLE_CLKS - 1 := 0;
  signal d_go, d_load : std_logic := '0';
  signal d_code  : std_logic_vector(3 downto 0) := (others => '0');
  signal d_pred  : signed(15 downto 0) := (others => '0');
  signal d_idx   : integer range 0 to 88 := 0;

  function pal_len(bpp : integer range 0 to 15) return unsigned is
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
    port map (clk => clk, half_period => HALF_PERIOD,
              start => fl_start, cmd => x"03", use_addr => '1', addr => fl_addr,
              len => fl_len, hold => fl_hold, busy => fl_busy, dout => fl_data, dout_valid => fl_valid,
              done => fl_done, sclk => sclk, cs_n => cs_n, mosi => mosi, miso => miso);

  -- a byte waiting, or one arriving right now: the next one must wait
  fl_hold <= (pb_v or fl_valid) when state = E_PIC_W else '0';

  u_dec : entity work.adpcm_dec
    port map (clk => clk, load => d_load, load_pred => d_pred, load_idx => d_idx,
              go => d_go, code => d_code, pcm => pcm);

  -- ============================================================ control
  process(clk)
    variable b     : std_logic_vector(7 downto 0);
    variable k     : integer range 0 to 31;
    variable go    : boolean;
    variable dfill : integer range -1 to 1;
    variable px    : std_logic_vector(7 downto 0);
    variable rst   : boolean;                        -- the ring is emptied this clock
  begin
    if rising_edge(clk) then
      fl_start <= '0';
      fb_we   <= '0';
      j_we    <= '0';
      f_we    <= '0';
      pal_we  <= '0';
      ring_we <= '0';
      d_go    <= '0';
      d_load  <= '0';
      dfill   := 0;
      rst     := false;
      b       := fl_data;
      k       := to_integer(bi(4 downto 0));

      if play = '1' then req_play <= '1'; req_item <= item; req_rec <= from_rec; end if;
      if stop = '1' then req_stop <= '1'; end if;
      if fl_valid = '1' then bi <= bi + 1; end if;

      case state is

        -- ------------------------------------------------ power-up: the header
        when E_HDR =>
          if fl_busy = '0' then
            fl_addr <= to_unsigned(BASE, 24); fl_len <= to_unsigned(16, 24);
            fl_start <= '1'; bi <= (others => '0');
            state <= E_HDR_W;
          end if;
        when E_HDR_W =>
          if fl_valid = '1' then
            case k is
              when 0 | 1 | 2 | 3 => magic <= magic(23 downto 0) & b;
              when 5      => n_items <= to_integer(unsigned(b));
              when 6 to 12 => hb(k) <= to_integer(unsigned(b));
              when 13     => spr_adr(7 downto 0)   <= unsigned(b);
              when 14     => spr_adr(15 downto 8)  <= unsigned(b);
              when 15     => spr_adr(23 downto 16) <= unsigned(b);
              when others => null;
            end case;
          end if;
          if fl_done = '1' then
            if magic = x"54444D32" and spr_adr /= 0 then state <= E_SPR; else state <= E_IDLE; end if;
          end if;

        -- ------------------------------------------------ the sprite block, once
        when E_SPR =>
          fl_addr <= spr_adr; fl_len <= to_unsigned(SPR_LEN, 24);
          fl_start <= '1'; bi <= (others => '0');
          j_wa <= 0; f_wa <= 0;
          state <= E_SPR_W;
        when E_SPR_W =>
          if j_lo_v = '1' then                     -- the second pixel of a Jevil byte
            j_we <= '1'; j_wd <= j_lo; j_wa <= j_wa + 1; j_lo_v <= '0';
          end if;
          if fl_valid = '1' then
            if bi < 512 then                        -- palette, 2 bytes a colour
              if bi(0) = '0' then
                lo_byte <= b;
              else
                pal_we <= '1'; pal_wa <= '1' & bi(8 downto 1); pal_wd <= b(3 downto 0) & lo_byte;
              end if;
            elsif bi < 512 + 9600 then              -- Jevil, 2 pixels a byte
              j_we <= '1'; j_wd <= b(7 downto 4);
              if bi /= 512 then j_wa <= j_wa + 1; end if;
              j_lo <= b(3 downto 0); j_lo_v <= '1';
            else                                    -- faces, 1 pixel a byte
              f_we <= '1'; f_wd <= b;
              if bi /= 512 + 9600 then f_wa <= f_wa + 1; end if;
            end if;
          end if;
          if fl_done = '1' then spr_done <= '1'; state <= E_IDLE; end if;

        -- ------------------------------------------------ waiting for a command
        when E_IDLE =>
          if req_stop = '1' then
            req_stop <= '0';
            loading  <= '0';
            rd_ptr <= 0; wr_ptr <= 0; fill <= 0; hi_nib <= '0'; rst := true;
            d_load <= '1'; d_pred <= (others => '0'); d_idx <= 0;
          end if;
          if req_play = '1' then
            req_play <= '0';
            req_stop <= '0';
            if magic = x"54444D32" and req_item < n_items then
              pic_r   <= '0';
              loading <= '0';
              state   <= E_ENT;
            end if;
          end if;

        -- ------------------------------------------------ the item's directory entry
        when E_ENT =>
          fl_addr <= to_unsigned(BASE + 16, 24) + to_unsigned(req_item * 16, 24);
          fl_len <= to_unsigned(16, 24);
          fl_start <= '1'; bi <= (others => '0');
          state <= E_ENT_W;
        when E_ENT_W =>
          if fl_valid = '1' then
            case k is
              when 0      => e_bpp <= to_integer(unsigned(b(3 downto 0)));
              when 1      => e_ft  <= to_integer(unsigned(b));
              when 2      => e_mode <= b(2 downto 0);
              when 4      => e_nrec(7 downto 0)  <= unsigned(b);
              when 5      => e_nrec(15 downto 8) <= unsigned(b);
              when 6      => e_aud(7 downto 0)   <= unsigned(b);
              when 7      => e_aud(15 downto 8)  <= unsigned(b);
              when 8      => e_paddr(7 downto 0)   <= unsigned(b);
              when 9      => e_paddr(15 downto 8)  <= unsigned(b);
              when 10     => e_paddr(23 downto 16) <= unsigned(b);
              when 12     => e_rec(7 downto 0)   <= unsigned(b);
              when 13     => e_rec(15 downto 8)  <= unsigned(b);
              when 14     => e_rec(23 downto 16) <= unsigned(b);
              when 15     => e_low <= unsigned(b);
              when others => null;
            end case;
          end if;
          if fl_done = '1' then
            if e_bpp = 0 then state <= E_START; else state <= E_PAL; end if;
          end if;

        -- ------------------------------------------------ its palette (colours 0..255)
        when E_PAL =>
          fl_addr <= e_paddr; fl_len <= pal_len(e_bpp);
          fl_start <= '1'; bi <= (others => '0');
          state <= E_PAL_W;
        when E_PAL_W =>
          if fl_valid = '1' then
            if bi(0) = '0' then
              lo_byte <= b;                          -- low byte: G (high nibble), B
            else
              pal_we <= '1';                         -- high byte: R (low nibble)
              pal_wa <= '0' & bi(8 downto 1);
              pal_wd <= b(3 downto 0) & lo_byte;
            end if;
          end if;
          if fl_done = '1' then state <= E_START; end if;

        -- ------------------------------------------------ start (maybe in the middle)
        when E_START =>
          rec     <= req_rec;
          r_addr  <= e_rec + resize(req_rec * (e_aud + 8), 24);
          started <= '0';
          loading <= '1';
          ticks   <= 255;                            -- picture only: load at the next frame
          rd_ptr <= 0; wr_ptr <= 0; fill <= 0; hi_nib <= '0'; rst := true;
          d_load <= '1'; d_pred <= (others => '0'); d_idx <= 0;
          state   <= E_WAIT;

        -- ------------------------------------------------ pacing (see the header)
        when E_WAIT =>
          go := false;
          if frame_tick = '1' and ticks /= 255 then ticks <= ticks + 1; end if;
          if e_aud = 0 then
            go := frame_tick = '1' and ticks >= e_ft - 1;
          else
            go := fill < to_integer(e_low & "000") and (frame_tick = '1' or e_bpp = 0);
          end if;
          if req_play = '1' or req_stop = '1' then
            loading <= '0';
            state   <= E_IDLE;
          elsif go then
            ticks <= 0;
            state <= E_RH;
          end if;

        -- ------------------------------------------------ record header
        when E_RH =>
          fl_addr <= r_addr; fl_len <= to_unsigned(8, 24);
          fl_start <= '1'; bi <= (others => '0');
          state <= E_RH_W;
        when E_RH_W =>
          if fl_valid = '1' then
            case k is
              when 0      => p_addr(7 downto 0)   <= unsigned(b);
              when 1      => p_addr(15 downto 8)  <= unsigned(b);
              when 2      => p_addr(23 downto 16) <= unsigned(b);
              when 3      => p_len(7 downto 0)    <= unsigned(b);
              when 4      => p_len(15 downto 8)   <= unsigned(b);
              when 5      => h_pred(7 downto 0)   <= signed(b);
              when 6      => h_pred(15 downto 8)  <= signed(b);
              when others =>                          -- 7: the step index
                if started = '0' then                 -- first record: the decoder starts here
                  d_load <= '1';
                  d_pred <= h_pred;
                  if unsigned(b) > 88 then d_idx <= 88; else d_idx <= to_integer(unsigned(b)); end if;
                end if;
            end case;
          end if;
          if fl_done = '1' then
            started <= '1';
            if p_len /= 0 then state <= E_PIC; else state <= E_SND; end if;
          end if;

        -- ------------------------------------------------ picture into the frame buffer
        when E_PIC =>
          fl_addr <= p_addr; fl_len <= resize(p_len, 24);
          fl_start <= '1'; bi <= (others => '0');
          wa <= 0; dst <= D_OP;
          state <= E_PIC_W;
        when E_PIC_W =>
          if fl_done = '1' then state <= E_PIC_END; end if;
        when E_PIC_END =>                            -- let the decoder finish its last run
          if dst = D_OP and pb_v = '0' then
            pic_r <= '1';
            state <= E_SND;
          end if;

        -- ------------------------------------------------ sound into the ring
        when E_SND =>
          if e_aud = 0 then
            state <= E_NEXT;
          else
            fl_addr <= r_addr + 8; fl_len <= resize(e_aud, 24);
            fl_start <= '1'; bi <= (others => '0');
            state <= E_SND_W;
          end if;
        when E_SND_W =>
          if fl_valid = '1' then
            ring_we <= '1'; ring_wa <= wr_ptr; ring_wd <= b;
            if wr_ptr = RING_SIZE - 1 then wr_ptr <= 0; else wr_ptr <= wr_ptr + 1; end if;
            dfill := 1;
          end if;
          if fl_done = '1' then state <= E_NEXT; end if;

        when E_NEXT =>
          if rec >= e_nrec - 1 then
            loading <= '0';                          -- all loaded; the ring plays out
            state   <= E_IDLE;
          else
            rec    <= rec + 1;
            r_addr <= r_addr + resize(e_aud, 24) + 8;
            state  <= E_WAIT;
          end if;
      end case;

      -- ------------------------------------------------ the picture decoder
      if state = E_PIC_W and fl_valid = '1' then
        pb <= b; pb_v <= '1';                        -- (hold makes sure pb was empty)
      end if;
      case dst is
        when D_OP =>
          if pb_v = '1' then
            pb_v <= '0';
            if pb(7) = '1' then                      -- COPY n+1 pixels that follow
              cnt <= to_integer(unsigned(pb(6 downto 0))) + 1;
              dst <= D_LIT;
            elsif pb(6) = '1' then                   -- FILL n+1 pixels with the next byte
              cnt <= to_integer(unsigned(pb(5 downto 0))) + 1;
              dst <= D_COL;
            else                                     -- SKIP n+1 pixels
              wa <= wa + to_integer(unsigned(pb(5 downto 0))) + 1;
            end if;
          end if;
        when D_COL =>
          if pb_v = '1' then
            pb_v <= '0'; col <= pb; dst <= D_FILL;
          end if;
        when D_FILL =>
          if wa < FB_SIZE then fb_we <= '1'; fb_wa <= wa; fb_wd <= col; end if;
          wa  <= wa + 1;
          cnt <= cnt - 1;
          if cnt = 1 then dst <= D_OP; end if;
        when D_LIT =>
          if pb_v = '1' then
            pb_v <= '0'; sh <= pb; dst <= D_UNP;
            case e_bpp is
              when 1      => nb <= 8;
              when 2      => nb <= 4;
              when 4      => nb <= 2;
              when others => nb <= 1;
            end case;
          end if;
        when D_UNP =>                                -- one packed pixel per clock, MSB first
          case e_bpp is
            when 1      => px := "0000000" & sh(7);       sh <= sh(6 downto 0) & '0';
            when 2      => px := "000000" & sh(7 downto 6); sh <= sh(5 downto 0) & "00";
            when 4      => px := "0000" & sh(7 downto 4);   sh <= sh(3 downto 0) & "0000";
            when others => px := sh;
          end case;
          if wa < FB_SIZE then fb_we <= '1'; fb_wa <= wa; fb_wd <= px; end if;
          wa  <= wa + 1;
          cnt <= cnt - 1;
          nb  <= nb - 1;
          if cnt = 1 then dst <= D_OP; elsif nb = 1 then dst <= D_LIT; end if;
      end case;

      -- ------------------------------------------------ sound out, 16,000 codes a second
      if scnt = SAMPLE_CLKS - 1 then
        scnt <= 0;
        if fill > 0 and not rst then
          d_go <= '1';
          if hi_nib = '0' then
            d_code <= ring_q(3 downto 0);            -- ring_q = ring(rd_ptr)
            hi_nib <= '1';
          else
            d_code <= ring_q(7 downto 4);
            hi_nib <= '0';
            if rd_ptr = RING_SIZE - 1 then rd_ptr <= 0; else rd_ptr <= rd_ptr + 1; end if;
            dfill := dfill - 1;
          end if;
        end if;
      else
        scnt <= scnt + 1;
      end if;
      if not rst then
        fill <= fill + dfill;
      end if;
    end if;
  end process;

  -- ============================================================ memories
  -- frame buffer: address a = bank a / 4096, place a mod 4096
  g_fb : for i in 0 to 4 generate
    signal mem : bank8_t := (others => (others => '0'));
    attribute ram_style of mem : signal is "block";
  begin
    process(clk)
    begin
      if rising_edge(clk) then
        if fb_we = '1' and fb_wa / 4096 = i then
          mem(fb_wa mod 4096) <= fb_wd;
        end if;
        fq(i) <= mem(ra mod 4096);
      end if;
    end process;
  end generate;

  -- Jevil, 4 bits a pixel, banked the same way
  g_jev : for i in 0 to 4 generate
    signal mem : bank4_t := (others => (others => '0'));
    attribute ram_style of mem : signal is "block";
  begin
    process(clk)
    begin
      if rising_edge(clk) then
        if j_we = '1' and j_wa / 4096 = i then
          mem(j_wa mod 4096) <= j_wd;
        end if;
        jq(i) <= mem(to_integer(j_addr) mod 4096);
      end if;
    end process;
  end generate;

  process(clk)
  begin
    if rising_edge(clk) then
      if f_we = '1' then faces(f_wa) <= f_wd; end if;
      fcq <= faces(to_integer(f_addr));
      if ring_we = '1' then ring(ring_wa) <= ring_wd; end if;
      ring_q <= ring(rd_ptr);
    end if;
  end process;

  -- palettes: port A writes (loader) or reads the picture's colour,
  -- port B reads the sprite colour
  fb_q <= fq(rbank);
  pa   <= pal_wa when pal_we = '1' else '0' & unsigned(fb_q);
  process(clk)
  begin
    if rising_edge(clk) then
      if pal_we = '1' then pal(to_integer(pa)) <= pal_wd; end if;
      pal_qa <= pal(to_integer(pa));
    end if;
  end process;

  jn    <= jq(jbank);
  s_on2 <= (j_en2 and (jn(3) or jn(2) or jn(1) or jn(0))) or f_en2;
  s_idx <= "0000" & jn when j_en2 = '1' and jn /= "0000" else fcq;
  process(clk)
  begin
    if rising_edge(clk) then
      pal_qb <= pal(to_integer('1' & unsigned(s_idx)));
    end if;
  end process;

  -- ============================================================ screen pipeline
  -- clock 1: which frame buffer address, and which zone
  process(clk)
    variable xi, yi : integer range 0 to 1023;
    variable px, py : unsigned(9 downto 0);
  begin
    if rising_edge(clk) then
      xi := to_integer(x);
      yi := to_integer(y);
      ra <= 0;
      z1 <= 0;
      if e_mode(1 downto 0) = "11" then             -- panel: 96 x 88 at 2x
        if xi >= 430 and xi < 622 and yi >= 286 and yi < 462 then
          px := x - 430;
          py := y - 286;
          -- (py / 2) * 96 + px / 2, and 96 = 64 + 32
          ra <= to_integer(shift_left(resize(py(9 downto 1), 15), 6) + shift_left(resize(py(9 downto 1), 15), 5)
                           + resize(px(9 downto 1), 15));
          z1 <= 3;
        elsif xi >= 428 and xi < 624 and yi >= 284 and yi < 464 then
          z1 <= 2;
        elsif xi >= 426 and xi < 626 and yi >= 282 and yi < 466 then
          z1 <= 1;
        end if;
      elsif xi < 640 and yi < 480 then              -- whole screen: 160 x 120 at 4x
        -- (y / 4) * 160 + x / 4, and 160 = 128 + 32
        ra <= to_integer(shift_left(resize(y(8 downto 2), 15), 7) + shift_left(resize(y(8 downto 2), 15), 5)
                         + resize(x(9 downto 2), 15));
        z1 <= 3;
      end if;
      -- clock 2 (the frame buffer read is in g_fb), clock 3 (palette)
      rbank <= ra / 4096;
      z2    <= z1;
      z3    <= z2;
      if fb_q = x"00" then see3 <= '1'; else see3 <= '0'; end if;
      -- sprites: clock 2 = the RAM reads, clock 3 = the palette
      jbank <= to_integer(j_addr) / 4096;
      j_en2 <= j_en;
      f_en2 <= f_en;
      s_on3 <= s_on2;
    end if;
  end process;

  rgb      <= pal_qa;
  see      <= see3;
  zone     <= z3;
  spr_on   <= s_on3;
  spr_rgb  <= pal_qb;

  ready      <= '1' when magic = x"54444D32" else '0';
  spr_ok     <= spr_done;
  mus_first  <= hb(6) mod 32;
  mus_n      <= hb(7) mod 32;
  atk_first  <= hb(8) mod 32;
  lose_first <= hb(9) mod 32;
  lose_n     <= hb(10) mod 32;
  win_first  <= hb(11) mod 32;
  win_n      <= hb(12) mod 32;
  busy       <= '1' when loading = '1' or fill /= 0 or state = E_ENT or state = E_ENT_W
                         or state = E_PAL or state = E_PAL_W or state = E_START or req_play = '1' else '0';
  has_snd    <= '1' when e_aud /= 0 else '0';
  pic_ok     <= pic_r;
  mode       <= to_integer(unsigned(e_mode(1 downto 0)));
  dim_half   <= e_mode(2);
  rec_pos    <= rec;

end architecture;
