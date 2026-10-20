-- ============================================================================
-- tb_media_ctrl.vhd  -  media_ctrl driving media_engine (+ the pretend flash
-- with the tiny game_sim.hex file), going through a whole game:
--
--   1. a game starts             -> the music item plays (item 0)
--   2. it ends                   -> the playlist starts it again
--   3. a media attack (id 0)     -> attack item 1 plays, show = 1; the music
--                                   position is remembered (record 3)
--   4. the attack ends           -> the music carries on from record 3
--   5. a Jevil attack (id 2)     -> item 3, jevil = 1
--   6. I win                     -> the win item (2, a panel picture), show
--                                   stays on after it loaded, won = 1
--   7. a new game, then I lose   -> music again (show off), then the lose
--                                   item (3)
-- Every 'play' command is written down (item, from_rec); after each event
-- the next one is compared.
-- frame_tick every 20,000 clocks, a sound sample every 100 clocks.
--
-- Run with:  tools\sim.bat tb_media_ctrl
-- ============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_media_ctrl is
end entity;

architecture sim of tb_media_ctrl is
  constant TICK_EVERY : integer := 20_000;

  signal clk        : std_logic := '0';
  signal done       : boolean := false;
  signal tick       : std_logic := '0';
  signal sclk, cs_n, mosi, miso : std_logic;

  signal playing    : std_logic := '0';
  signal result     : integer range 0 to 4 := 0;
  signal media_hit  : std_logic := '0';
  signal media_id   : integer range 0 to 2 := 0;

  signal play, stop, ready, spr_ok, busy, has_snd, pic_ok, dim_half : std_logic;
  signal item       : integer range 0 to 31;
  signal from_rec, rec_pos : unsigned(15 downto 0);
  signal mus_first, mus_n, atk_first, lose_first, lose_n, win_first, win_n : integer range 0 to 31;
  signal mode       : integer range 0 to 3;
  signal show, jevil, won : std_logic;

  -- every play command
  type ints_t is array (0 to 63) of integer;
  shared variable p_item, p_rec : ints_t;
  shared variable n_play : integer := 0;
begin

  clk <= not clk after 10 ns when not done else clk;

  process(clk)
    variable n : integer := 0;
  begin
    if rising_edge(clk) then
      tick <= '0';
      if n = TICK_EVERY - 1 then n := 0; tick <= '1'; else n := n + 1; end if;
      if play = '1' and n_play < 64 then
        p_item(n_play) := item;
        p_rec(n_play)  := to_integer(from_rec);
        n_play := n_play + 1;
      end if;
    end if;
  end process;

  u_eng : entity work.media_engine
    generic map (SAMPLE_CLKS => 100)
    port map (clk => clk, frame_tick => tick, play => play, item => item, from_rec => from_rec,
              stop => stop, ready => ready, spr_ok => spr_ok,
              mus_first => mus_first, mus_n => mus_n, atk_first => atk_first,
              lose_first => lose_first, lose_n => lose_n, win_first => win_first, win_n => win_n,
              busy => busy, has_snd => has_snd, pic_ok => pic_ok, mode => mode, dim_half => dim_half,
              rec_pos => rec_pos, sclk => sclk, cs_n => cs_n, mosi => mosi, miso => miso,
              x => (others => '0'), y => (others => '0'), rgb => open, see => open, zone => open,
              j_en => '0', j_addr => (others => '0'), f_en => '0', f_addr => (others => '0'),
              spr_on => open, spr_rgb => open, pcm => open);

  u_ctrl : entity work.media_ctrl
    port map (clk => clk, playing => playing, result => result,
              media_hit => media_hit, media_id => media_id,
              ready => ready, mus_first => mus_first, mus_n => mus_n, atk_first => atk_first,
              lose_first => lose_first, lose_n => lose_n, win_first => win_first, win_n => win_n,
              busy => busy, has_snd => has_snd, rec_pos => rec_pos,
              play => play, item => item, from_rec => from_rec, stop => stop,
              show => show, jevil => jevil, won => won);

  u_flash : entity work.flash_model
    generic map (FILE_NAME => "../game_sim.hex", SIZE => 65536)
    port map (sclk => sclk, cs_n => cs_n, mosi => mosi, miso => miso);

  checker : process
    variable errors : integer := 0;
    variable n0     : integer;

    procedure hit(id : integer) is
    begin
      wait until rising_edge(clk);
      media_id <= id; media_hit <= '1';
      wait until rising_edge(clk);
      media_hit <= '0';
    end procedure;

    -- the first play command after number k must be item 'it' from record
    -- 'rec' (-1 = any record)
    procedure expect(k, it, rec : integer; what : string) is
    begin
      if n_play <= k then
        report what & ": no play command" severity error;
        errors := errors + 1;
      elsif p_item(k) /= it or (rec >= 0 and p_rec(k) /= rec) then
        report what & ": played item " & integer'image(p_item(k)) & " from record " &
               integer'image(p_rec(k)) & ", expected " & integer'image(it) severity error;
        errors := errors + 1;
      else
        report what & ": item " & integer'image(it) & " from record " & integer'image(p_rec(k)) & " - right";
      end if;
    end procedure;
  begin
    wait until spr_ok = '1' for 10 ms;

    -- 1. game starts: music
    n0 := n_play;
    playing <= '1';
    wait for 2 us;
    expect(n0, 0, 0, "1. game start -> music");
    if show /= '0' then report "music must not show a picture" severity error; errors := errors + 1; end if;

    -- 2. the music item (6 records, 0.15 s here) ends -> the playlist plays it again
    wait until n_play = n0 + 2 for 5 ms;
    expect(n0 + 1, 0, 0, "2. music ended -> next in the playlist");

    -- 3. a media attack in the middle of the music: all 6 records are
    --    loaded (rec_pos = 5), so the music should continue at 5 - 2 = 3
    wait until rec_pos = 5 for 5 ms;
    wait for 1 us;
    n0 := n_play;
    hit(0);
    wait for 2 us;
    expect(n0, 1, 0, "3. attack 0 -> attack item");
    if show /= '1' or jevil /= '0' then report "attack: show/jevil wrong" severity error; errors := errors + 1; end if;

    -- 4. the attack ends -> music from where it was
    wait until n_play = n0 + 2 for 10 ms;
    expect(n0 + 1, 0, 3, "4. attack over -> music continues");
    if show /= '0' then report "after the attack show must be off" severity error; errors := errors + 1; end if;

    -- 5. Jevil
    n0 := n_play;
    hit(2);
    wait for 2 us;
    expect(n0, 3, 0, "5. attack 2 -> the third attack item");
    if jevil /= '1' then report "Jevil should float" severity error; errors := errors + 1; end if;

    -- 6. I win (the win item is a still picture: show stays on)
    n0 := n_play;
    result <= 1;
    wait for 2 us;
    expect(n0, 2, 0, "6. win -> win item");
    wait until pic_ok = '1' for 10 ms;
    wait for 100 us;
    if show /= '1' or won /= '1' or jevil /= '0' or n_play /= n0 + 1 then
      report "win: show / won / jevil wrong, or something else played" severity error; errors := errors + 1;
    else
      report "   the win picture stays on screen, gold frame, nothing else plays";
    end if;

    -- 7. a new game, then I lose
    playing <= '0';
    wait for 1 us;
    result <= 0;
    n0 := n_play;
    playing <= '1';
    wait for 2 us;
    expect(n0, 0, -1, "7. new game -> music");
    if show /= '0' then report "new game: show must be off" severity error; errors := errors + 1; end if;
    wait for 100 us;
    playing <= '0';
    n0 := n_play;
    result <= 2;
    wait for 2 us;
    expect(n0, 3, 0, "   lose -> lose item");

    if errors = 0 then report "TEST PASSED"; else report "TEST FAILED" severity error; end if;
    done <= true;
    wait;
  end process;

end architecture;
