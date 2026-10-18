-- ============================================================================
-- tb_tetris_core.vhd  -  a robot plays Tetris against tetris_core
--
-- The frame tick is made fast (every 200 clocks instead of 833,333) so a
-- whole game takes well under a second of simulation.
-- For every new piece the robot tries all 4 rotations and every column,
-- picks the placement that clears the most lines (then: lands lowest),
-- presses rotate / left / right, then hard drop, exactly like a player.
--
-- Checks after every piece:
--   * filled cells = 4 x pieces - 10 x lines   (nothing lost or duplicated)
--   * no full row is left in the field          (line clear worked)
-- Prints the field every 20 pieces and at the end.
--
-- Run with:  tools\sim.bat tb_tetris_core
-- ============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.tetris_pkg.all;

entity tb_tetris_core is
end entity;

architecture sim of tb_tetris_core is
  constant TICK_EVERY : integer := 200;
  constant MAX_PIECES : integer := 300;

  signal clk        : std_logic := '0';
  signal done       : boolean := false;
  signal frame_tick : std_logic := '0';
  signal a_left, a_right, a_rot, a_soft, a_hard : std_logic := '0';

  signal occ        : occ_field_t;
  signal colf       : col_field_t;
  signal cur_shape  : shape_t;
  signal cur_color  : color_t;
  signal cur_x      : xpos_t;
  signal cur_y      : ypos_t;
  signal ghost_y    : ypos_t;
  signal next_shape : shape_t;
  signal next_color : color_t;
  signal playing    : std_logic;
  signal game_over  : std_logic;
  signal lines_bcd  : std_logic_vector(15 downto 0);
  signal level      : integer range 0 to 15;
  signal clear_evt  : std_logic;
  signal clear_n    : integer range 0 to 4;
  signal n_locks    : integer := 0;          -- counts clear_evt pulses

  -- same rule as in tetris_core
  function collides(o : occ_field_t; sh : shape_t; x, y : integer) return boolean is
    variable ry : integer;
    variable wx : integer;
  begin
    for r in 0 to 3 loop
      for c in 0 to 3 loop
        if sh(4*r + c) = '1' then
          ry := y + r;
          wx := x + c - 3;                          -- board column
          if wx < 0 or wx > COLS - 1 or ry > ROWS - 1 then
            return true;
          elsif ry >= 0 then
            if o(ry)(wx) = '1' then
              return true;
            end if;
          end if;
        end if;
      end loop;
    end loop;
    return false;
  end function;

  function count_cells(o : occ_field_t) return integer is
    variable n : integer := 0;
  begin
    for r in 0 to ROWS - 1 loop
      for c in 0 to COLS - 1 loop
        if o(r)(c) = '1' then n := n + 1; end if;
      end loop;
    end loop;
    return n;
  end function;

  function bcd_to_int(b : std_logic_vector(15 downto 0)) return integer is
  begin
    return to_integer(unsigned(b(15 downto 12))) * 1000 + to_integer(unsigned(b(11 downto 8))) * 100
         + to_integer(unsigned(b(7 downto 4))) * 10 + to_integer(unsigned(b(3 downto 0)));
  end function;

  procedure print_field(o : occ_field_t; cf : col_field_t) is
    constant LETTERS : string(1 to 8) := "IOTSZJLG";
    variable s : string(1 to COLS + 2);
    variable k : integer;
  begin
    for r in 0 to ROWS - 1 loop
      s(1) := '|'; s(COLS + 2) := '|';
      for c in 0 to COLS - 1 loop
        if o(r)(c) = '1' then
          k := to_integer(unsigned(cf(r)(3*c + 2 downto 3*c)));
          s(c + 2) := LETTERS(k + 1);
        else
          s(c + 2) := '.';
        end if;
      end loop;
      report s;
    end loop;
    report "+----------+";
  end procedure;

begin

  clk <= not clk after 10 ns when not done else clk;

  -- fast frame ticks
  process(clk)
    variable n : integer := 0;
  begin
    if rising_edge(clk) then
      frame_tick <= '0';
      if n = TICK_EVERY - 1 then
        n := 0;
        frame_tick <= '1';
      else
        n := n + 1;
      end if;
    end if;
  end process;

  dut : entity work.tetris_core
    port map (
      clk => clk, frame_tick => frame_tick, pause => '0',
      act_left => a_left, act_right => a_right, act_rot => a_rot,
      act_soft => a_soft, act_hard => a_hard,
      versus => '0', start_in => '0', garb_in => '0', garb_in_n => 0, opp_lost => '0',
      start_out => open, lost_out => open, garb_out => open, garb_out_n => open,
      height => open, pending => open, result => open,
      occ => occ, colf => colf, cur_shape => cur_shape, cur_color => cur_color,
      cur_x => cur_x, cur_y => cur_y, ghost_y => ghost_y,
      next_shape => next_shape, next_color => next_color,
      playing => playing, game_over => game_over,
      lines_bcd => lines_bcd, level => level, clear_evt => clear_evt, clear_n => clear_n);

  -- count lock events (the robot waits for this number to go up)
  process(clk)
  begin
    if rising_edge(clk) then
      if clear_evt = '1' then
        n_locks <= n_locks + 1;
      end if;
    end if;
  end process;

  robot : process
    variable best_rot, best_x, best_score : integer;
    variable y, full, score, lines, n_pieces, errors : integer;
    variable sh : shape_t;
    variable trial : occ_field_t;
    variable p : integer;

    -- one button press = a one-clock pulse, then wait two frames
    procedure press(signal a : out std_logic) is
    begin
      wait until rising_edge(clk);
      a <= '1';
      wait until rising_edge(clk);
      a <= '0';
      for i in 1 to 2 loop
        wait until rising_edge(clk) and frame_tick = '1';
      end loop;
    end procedure;
  begin
    errors := 0;
    n_pieces := 0;
    wait for 1 us;
    press(a_hard);                                   -- start a game
    wait until rising_edge(clk) and playing = '1';
    for i in 1 to 3 loop
      wait until rising_edge(clk) and frame_tick = '1';
    end loop;

    while playing = '1' and n_pieces < MAX_PIECES loop
      -- ---- choose a placement
      p := to_integer(unsigned(cur_color));
      best_score := -1000; best_rot := 0; best_x := SPAWN_X;
      for rot in 0 to 3 loop
        sh := shape_of(p, rot);
        for x in 0 to 12 loop
          if not collides(occ, sh, x, 0) then
            y := 0;
            while not collides(occ, sh, x, y + 1) loop
              y := y + 1;
            end loop;
            -- place it in a copy and count full rows
            trial := occ;
            for r in 0 to 3 loop
              for c in 0 to 3 loop
                if sh(4*r + c) = '1' and y + r >= 0 then
                  trial(y + r)(x + c - 3) := '1';
                end if;
              end loop;
            end loop;
            full := 0;
            for r in 0 to ROWS - 1 loop
              if trial(r) = "1111111111" then full := full + 1; end if;
            end loop;
            score := full * 100 + y * 4 - rot - abs(x - SPAWN_X);
            if score > best_score then
              best_score := score; best_rot := rot; best_x := x;
            end if;
          end if;
        end loop;
      end loop;

      -- ---- do it with the buttons
      for i in 1 to best_rot loop
        press(a_rot);
      end loop;
      while cur_x > best_x loop
        press(a_left);
        exit when cur_x <= best_x;
      end loop;
      for i in 1 to 12 loop
        exit when cur_x >= best_x;
        press(a_right);
      end loop;
      for i in 1 to 12 loop
        exit when cur_x <= best_x;
        press(a_left);
      end loop;
      press(a_hard);
      if n_locks = n_pieces then                     -- not locked yet: wait for it
        wait until n_locks > n_pieces;
      end if;
      n_pieces := n_pieces + 1;
      for i in 1 to 2 loop
        wait until rising_edge(clk) and frame_tick = '1';
      end loop;

      -- ---- checks
      lines := bcd_to_int(lines_bcd);
      if count_cells(occ) /= 4 * n_pieces - 10 * lines then
        report "CELL COUNT WRONG after piece " & integer'image(n_pieces) & ": " &
               integer'image(count_cells(occ)) & " cells, expected " &
               integer'image(4 * n_pieces - 10 * lines) severity error;
        print_field(occ, colf);
        errors := errors + 1;
      end if;
      for r in 0 to ROWS - 1 loop
        if occ(r) = "1111111111" then
          report "FULL ROW LEFT at row " & integer'image(r) severity error;
          errors := errors + 1;
        end if;
      end loop;
      if n_pieces mod 20 = 0 then
        report "after " & integer'image(n_pieces) & " pieces: " & integer'image(lines) &
               " lines, level " & integer'image(level);
        print_field(occ, colf);
      end if;
      exit when errors > 3;
    end loop;

    report "END: " & integer'image(n_pieces) & " pieces, " &
           integer'image(bcd_to_int(lines_bcd)) & " lines, level " & integer'image(level) &
           ", game over = " & std_logic'image(game_over);
    print_field(occ, colf);
    if errors = 0 and bcd_to_int(lines_bcd) > 0 then
      report "TEST PASSED";
    else
      report "TEST FAILED (" & integer'image(errors) & " errors)" severity error;
    end if;
    done <= true;
    wait;
  end process;

end architecture;
