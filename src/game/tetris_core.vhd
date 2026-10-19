-- ============================================================================
-- tetris_core.vhd
-- The game itself: playfield, falling piece, collision, rotation, gravity,
-- locking, line clearing, the random piece sequence, lines and level.
-- No video here; tetris_render reads the outputs and draws them.
--
-- HOW IT WORKS
-- One state machine. Once per frame (frame_tick, 60 Hz) it runs a short
-- sequence of steps, each taking 1-2 clocks (a few hundred clocks in total,
-- out of the 833,333 clocks in a frame):
--
--   S_PLAY --frame_tick--> S_ROT   try to rotate (with wall kicks)
--                          S_MOVE  try to move left/right
--                          S_DOWN  try to move down (gravity / soft drop)
--                          S_GHOST find how far the piece could fall
--                                  (the "ghost" outline + hard drop use it)
--                          S_LOCKCHK  resting on something for 0.5 s,
--                                  or hard drop?  -> S_LOCK, else S_PLAY
--   S_LOCK   copy the piece into the playfield (4 clocks, one box row each)
--   S_CLEAR  remove full rows (one row per clock)
--   S_SCORE  add the cleared lines to the counter
--   S_ATTACK versus: lines -> garbage to send (cancelling garbage waiting
--            for me first); if nothing was cleared, waiting garbage comes in:
--   S_HOLE   pick the hole column,  S_GARB  push the field up, add grey rows
--   S_PICK   choose the next piece (7-bag), S_SPAWN put it at the top
--
-- VERSUS: the other board talks to us through versus_link. START starts a
-- round, GARBAGE adds to 'pending', LOST means we won (that check sits after
-- the big case, so it works in any state). Topping out sends LOST.
--
-- "Try" always works the same way: write the candidate position into the
-- cand_* registers, and one clock later the signal 'collide' says whether
-- that position overlaps a wall, the floor or a filled cell. If not, copy
-- the candidate into the cur_* registers. Only one collision checker is
-- built, and every step reuses it.
--
-- Button actions (act_*) are one-clock pulses that may arrive at any time.
-- They are remembered in req_* flags and used at the next frame.
-- ============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.tetris_pkg.all;

entity tetris_core is
  generic (
    COOLDOWN_FRAMES : integer := 90             -- 1.5 s after a game before a new start
  );
  port (
    clk        : in  std_logic;
    frame_tick : in  std_logic;
    pause      : in  std_logic;
    act_left   : in  std_logic;
    act_right  : in  std_logic;
    act_rot    : in  std_logic;
    act_soft   : in  std_logic;
    act_hard   : in  std_logic;    -- also "start" on the title / game-over screen

    -- versus mode (from / to versus_link)
    versus     : in  std_logic;                 -- '1' = another board is connected
    start_in   : in  std_logic;                 -- the other board started a round
    garb_in    : in  std_logic;                 -- garbage arrived...
    garb_in_n  : in  integer range 0 to 31;     -- ...this many lines
    opp_lost   : in  std_logic;                 -- the other board topped out
    start_out  : out std_logic;                 -- pulse: I started a round
    lost_out   : out std_logic;                 -- pulse: I topped out
    garb_out   : out std_logic;                 -- pulse: send garbage...
    garb_out_n : out integer range 0 to 31;     -- ...this many lines
    height     : out integer range 0 to 20;     -- how high my stack is
    pending    : out integer range 0 to 31;     -- garbage waiting to come in
    result     : out integer range 0 to 4;      -- 0 none, 1 WIN, 2 LOSE, 3 DRAW, 4 GAME OVER (solo)

    -- what the renderer needs
    occ        : out occ_field_t;
    colf       : out col_field_t;
    cur_shape  : out shape_t;
    cur_color  : out color_t;
    cur_x      : out xpos_t;
    cur_y      : out ypos_t;
    ghost_y    : out ypos_t;
    next_shape : out shape_t;
    next_color : out color_t;
    playing    : out std_logic;     -- a game is running
    can_start  : out std_logic;     -- not playing and the cool-down is over (PRESS START)
    game_over  : out std_logic;     -- the last game ended (field shown grey)

    -- score
    lines_bcd  : out std_logic_vector(15 downto 0);   -- 4 decimal digits
    level      : out integer range 0 to 15;
    clear_evt  : out std_logic;                       -- pulse after each lock...
    clear_n    : out integer range 0 to 4             -- ...with the lines cleared
  );
end entity;

architecture rtl of tetris_core is

  type state_t is (S_IDLE, S_INIT, S_PICK, S_SPAWN, S_SPAWN_CHK,
                   S_PLAY, S_ROT, S_ROT_CHK, S_MOVE, S_MOVE_CHK,
                   S_DOWN, S_DOWN_CHK, S_GHOST, S_GHOST_CHK, S_LOCKCHK,
                   S_LOCK, S_CLEAR, S_SCORE, S_ATTACK, S_HOLE, S_GARB);
  signal state : state_t := S_IDLE;

  -- the playfield
  signal occ_r : occ_field_t := (others => (others => '0'));
  signal col_r : col_field_t := (others => (others => '0'));

  -- the falling piece
  signal cur_p   : integer range 0 to 6 := 0;
  signal cur_rot : integer range 0 to 3 := 0;
  signal cur_sh  : shape_t := (others => '0');
  signal cur_xr  : xpos_t := SPAWN_X;
  signal cur_yr  : ypos_t := SPAWN_Y;
  signal ghost_r : ypos_t := SPAWN_Y;

  -- candidate position being tested
  signal cand_rot : integer range 0 to 3 := 0;
  signal cand_sh  : shape_t := (others => '0');
  signal cand_x   : xpos_t := SPAWN_X;
  signal cand_y   : ypos_t := SPAWN_Y;
  signal collide  : std_logic;

  -- rotation wall kicks: try the turned piece here, then 1 right, 1 left,
  -- 2 right, 2 left
  type kicks_t is array (0 to 4) of integer range -2 to 2;
  constant KICKS : kicks_t := (0, 1, -1, 2, -2);
  signal kick : integer range 0 to 4 := 0;

  -- next piece and the 7-bag randomiser
  signal next_p    : integer range 0 to 6 := 0;
  signal next_sh   : shape_t := (others => '0');
  signal have_next : std_logic := '0';
  signal bag       : std_logic_vector(6 downto 0) := (others => '0');  -- '1' = already dealt
  signal lfsr      : std_logic_vector(15 downto 0) := x"ACE1";

  -- requests from the buttons (remembered until the next frame) ...
  signal req_left, req_right, req_rot, req_soft, req_hard : std_logic := '0';
  -- ... and the ones being worked on in this frame
  signal w_left, w_right, w_rot, w_soft, w_hard, w_grav : std_logic := '0';

  signal grav_cnt : integer range 0 to 63 := 0;
  signal lock_cnt : integer range 0 to LOCK_FRAMES := 0;
  signal resets   : integer range 0 to LOCK_RESETS := 0;
  signal lock_r   : integer range 0 to 3 := 0;          -- box row being locked

  -- line clearing: read row rd, write row wr (both walk upwards)
  signal rd, wr      : integer range -1 to ROWS - 1 := 0;
  signal cleared     : integer range 0 to 4 := 0;
  signal score_left  : integer range 0 to 4 := 0;

  signal lines_r   : std_logic_vector(15 downto 0) := (others => '0');
  signal level_r   : integer range 0 to 15 := 0;
  signal lvl_cnt   : integer range 0 to 9 := 0;          -- lines towards the next level
  signal playing_r : std_logic := '0';
  signal over_r    : std_logic := '0';
  signal evt_r     : std_logic := '0';
  signal evt_n     : integer range 0 to 4 := 0;

  -- versus
  signal pending_r : integer range 0 to 31 := 0;     -- garbage waiting to come in
  signal garb_left : integer range 0 to 8 := 0;      -- rows still to insert now
  signal hole      : integer range 0 to COLS - 1 := 0;
  signal result_r  : integer range 0 to 4 := 0;
  signal lose_age  : integer range 0 to 63 := 63;    -- frames since I lost (for DRAW)
  signal cool      : integer range 0 to 255 := 0;    -- frames left before a new start is allowed
  signal playing_d : std_logic := '0';
  signal start_o, lost_o, garb_o : std_logic := '0';
  signal garb_o_n  : integer range 0 to 31 := 0;
  signal height_r  : integer range 0 to 20 := 0;

  constant R_NONE : integer := 0;
  constant R_WIN  : integer := 1;
  constant R_LOSE : integer := 2;
  constant R_DRAW : integer := 3;
  constant R_OVER : integer := 4;
  constant MAX_GARB_PER_LOCK : integer := 8;

  constant FULL_ROW  : occ_row_t := (others => '1');
  constant EMPTY_OCC : occ_row_t := (others => '0');
  constant EMPTY_COL : col_row_t := (others => '0');

  -- Does shape 'sh' with its box at (x, y) overlap anything?
  -- Builds the 16-bit "wide" row for each of the 4 box rows (walls + field,
  -- or all '1' below the floor) and checks the 4 box cells of that row.
  function collides(o : occ_field_t; sh : shape_t; x : xpos_t; y : ypos_t) return std_logic is
    variable wide : std_logic_vector(15 downto 0);
    variable ry   : integer range -2 to 24;
    variable hit  : std_logic := '0';
  begin
    for r in 0 to 3 loop
      ry := y + r;
      if ry > ROWS - 1 then
        wide := (others => '1');                    -- below the floor
      elsif ry < 0 then
        wide := "1110000000000111";                 -- above the top: walls only
      else
        wide := "111" & o(ry) & "111";              -- wall, field row, wall
      end if;
      for c in 0 to 3 loop
        if sh(4*r + c) = '1' then
          if x + c < 0 or x + c > 15 then
            hit := '1';
          elsif wide(x + c) = '1' then
            hit := '1';
          end if;
        end if;
      end loop;
    end loop;
    return hit;
  end function;

  -- Row r of the box, moved to its place in the 10 board columns.
  function placed_row(sh : shape_t; r : integer range 0 to 3; x : xpos_t) return occ_row_t is
    variable row : occ_row_t := (others => '0');
    variable j   : integer range -14 to 14;
  begin
    for c in 0 to COLS - 1 loop
      j := c + 3 - x;                               -- box column over board column c
      if j >= 0 and j <= 3 then
        row(c) := sh(4*r + j);
      end if;
    end loop;
    return row;
  end function;

  -- add 1 to a 4-digit BCD number (9999 stays 9999)
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
          r(4*d+3 downto 4*d) := "0000";            -- 9 -> 0, carry on
        else
          r(4*d+3 downto 4*d) := std_logic_vector(unsigned(r(4*d+3 downto 4*d)) + 1);
          carry := false;
        end if;
      end if;
    end loop;
    return r;
  end function;

begin

  -- the one collision checker, always looking at the candidate registers
  collide <= collides(occ_r, cand_sh, cand_x, cand_y);

  process(clk)
    variable rnd    : integer range 0 to 15;
    variable newbag : std_logic_vector(6 downto 0);
    variable prow   : occ_row_t;
    variable row    : integer range -2 to 24;
    variable nrot   : integer range 0 to 3;
    variable p      : integer range 0 to 31;        -- garbage pending, worked on below
    variable atk    : integer range 0 to 31;        -- garbage I send
    variable n      : integer range 0 to 31;
  begin
    if rising_edge(clk) then
      p := pending_r;
      start_o <= '0';
      lost_o  <= '0';
      garb_o  <= '0';
      if frame_tick = '1' and lose_age < 63 then
        lose_age <= lose_age + 1;
      end if;
      -- cool-down: when a game ends (playing goes 1 -> 0, for any reason),
      -- the buttons can't start a new one for COOLDOWN_FRAMES. Otherwise a
      -- hard drop pressed just as the rival tops out would start the next
      -- round by accident.
      playing_d <= playing_r;
      if playing_d = '1' and playing_r = '0' then
        cool <= COOLDOWN_FRAMES;
      elsif frame_tick = '1' and cool > 0 then
        cool <= cool - 1;
      end if;
      -- random number source: a 16-bit LFSR stepping every clock. When it is
      -- sampled depends on when the player presses buttons, so the piece
      -- order is different every game.
      lfsr <= lfsr(14 downto 0) & (lfsr(15) xor lfsr(13) xor lfsr(12) xor lfsr(10));

      evt_r <= '0';

      -- remember button actions until the next frame uses them
      if act_left  = '1' then req_left  <= '1'; end if;
      if act_right = '1' then req_right <= '1'; end if;
      if act_rot   = '1' then req_rot   <= '1'; end if;
      if act_soft  = '1' then req_soft  <= '1'; end if;
      if act_hard  = '1' then req_hard  <= '1'; end if;

      case state is

        -- ---------------------------------------------- title / game over
        when S_IDLE =>
          if cool > 0 then
            req_hard <= '0';                        -- cooling down: forget presses
            req_rot  <= '0';
            if start_in = '1' then                  -- (the other board may still start us)
              state <= S_INIT;
            end if;
          elsif req_hard = '1' or req_rot = '1' then
            start_o <= '1';                         -- tell the other board to start too
            state   <= S_INIT;
          elsif start_in = '1' then                 -- the other board started
            state   <= S_INIT;
          end if;

        when S_INIT =>
          occ_r      <= (others => EMPTY_OCC);
          col_r      <= (others => EMPTY_COL);
          lines_r    <= (others => '0');
          level_r    <= 0;
          lvl_cnt    <= 0;
          bag        <= (others => '0');
          have_next  <= '0';
          grav_cnt   <= 0;
          w_hard     <= '0';
          req_left   <= '0'; req_right <= '0'; req_rot <= '0';
          req_soft   <= '0'; req_hard  <= '0';
          over_r     <= '0';
          playing_r  <= '1';
          result_r   <= R_NONE;
          p          := 0;
          state      <= S_PICK;

        -- ---------------------------------------------- new piece
        -- 7-bag: every piece once in each group of 7, in random order.
        -- Try a random number every clock until it is 0..6 and not dealt yet.
        when S_PICK =>
          rnd := to_integer(unsigned(lfsr(2 downto 0)));
          if rnd < 7 then
            if bag(rnd) = '0' then
              newbag := bag;
              newbag(rnd) := '1';
              if newbag = "1111111" then
                newbag := (others => '0');          -- bag empty: start a new one
              end if;
              bag    <= newbag;
              cur_p  <= next_p;                     -- the waiting piece comes in
              next_p <= rnd;                        -- the new one waits
              if have_next = '0' then
                have_next <= '1';                   -- first piece of a game: pick twice
              else
                state <= S_SPAWN;
              end if;
            end if;
          end if;

        when S_SPAWN =>
          cur_rot  <= 0;
          cur_sh   <= shape_of(cur_p, 0);
          cur_xr   <= SPAWN_X;
          cur_yr   <= SPAWN_Y;
          cand_sh  <= shape_of(cur_p, 0);
          cand_x   <= SPAWN_X;
          cand_y   <= SPAWN_Y;
          next_sh  <= shape_of(next_p, 0);
          lock_cnt <= 0;
          resets   <= 0;
          state    <= S_SPAWN_CHK;

        when S_SPAWN_CHK =>
          if collide = '1' then                     -- no room for the new piece: I lose
            over_r    <= '1';
            playing_r <= '0';
            req_hard  <= '0';
            req_rot   <= '0';
            lost_o    <= '1';
            lose_age  <= 0;
            if versus = '1' then result_r <= R_LOSE; else result_r <= R_OVER; end if;
            state     <= S_IDLE;
          else
            state <= S_GHOST;
          end if;

        -- ---------------------------------------------- waiting for a frame
        when S_PLAY =>
          if frame_tick = '1' and pause = '0' then
            -- take this frame's actions (and any arriving right now)
            w_left  <= req_left  or act_left;
            w_right <= req_right or act_right;
            w_rot   <= req_rot   or act_rot;
            w_soft  <= req_soft  or act_soft;
            w_hard  <= req_hard  or act_hard;
            req_left <= '0'; req_right <= '0'; req_rot <= '0';
            req_soft <= '0'; req_hard  <= '0';
            -- gravity: one row down every gravity_frames(level) frames
            if grav_cnt >= gravity_frames(level_r) - 1 then
              grav_cnt <= 0;
              w_grav   <= '1';
            else
              grav_cnt <= grav_cnt + 1;
              w_grav   <= '0';
            end if;
            state <= S_ROT;
          end if;

        -- ---------------------------------------------- rotate
        when S_ROT =>
          if w_rot = '1' then
            if cur_rot = 3 then nrot := 0; else nrot := cur_rot + 1; end if;
            cand_rot <= nrot;
            cand_sh  <= shape_of(cur_p, nrot);
            cand_x   <= cur_xr;
            cand_y   <= cur_yr;
            kick     <= 0;
            state    <= S_ROT_CHK;
          else
            state <= S_MOVE;
          end if;

        when S_ROT_CHK =>
          if collide = '0' then
            cur_rot <= cand_rot;
            cur_sh  <= cand_sh;
            cur_xr  <= cand_x;
            if resets < LOCK_RESETS then            -- turning restarts the lock timer
              lock_cnt <= 0;
              resets   <= resets + 1;
            end if;
            state <= S_MOVE;
          elsif kick < 4 then
            kick   <= kick + 1;                     -- try the next kick position
            cand_x <= cur_xr + KICKS(kick + 1);
          else
            state <= S_MOVE;                        -- can't turn here
          end if;

        -- ---------------------------------------------- move left / right
        when S_MOVE =>
          if (w_left xor w_right) = '1' then
            cand_sh <= cur_sh;
            cand_y  <= cur_yr;
            if w_left = '1' then
              cand_x <= cur_xr - 1;
            else
              cand_x <= cur_xr + 1;
            end if;
            state <= S_MOVE_CHK;
          else
            state <= S_DOWN;
          end if;

        when S_MOVE_CHK =>
          if collide = '0' then
            cur_xr <= cand_x;
            if resets < LOCK_RESETS then
              lock_cnt <= 0;
              resets   <= resets + 1;
            end if;
          end if;
          state <= S_DOWN;

        -- ---------------------------------------------- move down
        when S_DOWN =>
          if w_hard = '0' and (w_soft = '1' or w_grav = '1') then
            cand_sh <= cur_sh;
            cand_x  <= cur_xr;
            cand_y  <= cur_yr + 1;
            state   <= S_DOWN_CHK;
          else
            state <= S_GHOST;                       -- (hard drop is done in S_LOCKCHK)
          end if;

        when S_DOWN_CHK =>
          if collide = '0' then
            cur_yr   <= cand_y;
            lock_cnt <= 0;
            if w_soft = '1' then
              grav_cnt <= 0;
            end if;
          end if;
          state <= S_GHOST;

        -- ---------------------------------------------- ghost: lowest free spot
        when S_GHOST =>
          cand_sh <= cur_sh;
          cand_x  <= cur_xr;
          cand_y  <= cur_yr + 1;
          state   <= S_GHOST_CHK;

        when S_GHOST_CHK =>
          if collide = '0' then
            cand_y <= cand_y + 1;                   -- still free, look one lower
          else
            ghost_r <= cand_y - 1;                  -- the last free position
            state   <= S_LOCKCHK;
          end if;

        -- ---------------------------------------------- lock?
        when S_LOCKCHK =>
          if w_hard = '1' then                      -- hard drop: straight to the ghost
            w_hard <= '0';
            cur_yr <= ghost_r;
            lock_r <= 0;
            state  <= S_LOCK;
          elsif ghost_r = cur_yr then               -- resting on something
            if lock_cnt = LOCK_FRAMES then
              lock_r <= 0;
              state  <= S_LOCK;
            else
              lock_cnt <= lock_cnt + 1;
              state    <= S_PLAY;
            end if;
          else
            lock_cnt <= 0;
            state    <= S_PLAY;
          end if;

        -- ---------------------------------------------- write piece into field
        when S_LOCK =>
          row  := cur_yr + lock_r;
          prow := placed_row(cur_sh, lock_r, cur_xr);
          if row >= 0 and row <= ROWS - 1 then
            occ_r(row) <= occ_r(row) or prow;
            for c in 0 to COLS - 1 loop
              if prow(c) = '1' then
                col_r(row)(3*c + 2 downto 3*c) <= std_logic_vector(to_unsigned(cur_p, 3));
              end if;
            end loop;
          end if;
          if lock_r = 3 then
            rd      <= ROWS - 1;
            wr      <= ROWS - 1;
            cleared <= 0;
            state   <= S_CLEAR;
          else
            lock_r <= lock_r + 1;
          end if;

        -- ---------------------------------------------- remove full rows
        -- Walk up from the bottom with a read row and a write row. Full rows
        -- are skipped (not copied), so everything above falls down. When the
        -- read row runs off the top, the rows left at the top are emptied.
        when S_CLEAR =>
          if rd >= 0 then
            if occ_r(rd) = FULL_ROW then
              cleared <= cleared + 1;
            else
              if wr /= rd then
                occ_r(wr) <= occ_r(rd);
                col_r(wr) <= col_r(rd);
              end if;
              wr <= wr - 1;
            end if;
            rd <= rd - 1;
          elsif wr >= 0 then
            occ_r(wr) <= EMPTY_OCC;
            col_r(wr) <= EMPTY_COL;
            wr <= wr - 1;
          else
            score_left <= cleared;
            evt_r      <= '1';
            evt_n      <= cleared;
            state      <= S_SCORE;
          end if;

        -- ---------------------------------------------- count lines, level up
        when S_SCORE =>
          if score_left > 0 then
            score_left <= score_left - 1;
            lines_r    <= bcd_inc(lines_r);
            if lvl_cnt = 9 then
              lvl_cnt <= 0;
              if level_r < 15 then
                level_r <= level_r + 1;
              end if;
            else
              lvl_cnt <= lvl_cnt + 1;
            end if;
          else
            state <= S_ATTACK;
          end if;

        -- ---------------------------------------------- versus: send / receive garbage
        -- Lines cleared become an attack: 2 lines -> 1, 3 -> 2, 4 (Tetris) -> 4.
        -- The attack first cancels garbage that is waiting for me; only the
        -- rest is sent. If I cleared nothing, waiting garbage comes in now.
        when S_ATTACK =>
          case cleared is
            when 2      => atk := 1;
            when 3      => atk := 2;
            when 4      => atk := 4;
            when others => atk := 0;
          end case;
          if atk >= p then
            atk := atk - p;
            p   := 0;
          else
            p   := p - atk;
            atk := 0;
          end if;
          if atk > 0 and versus = '1' then
            garb_o   <= '1';
            garb_o_n <= atk;
          end if;
          if cleared = 0 and p > 0 then
            if p > MAX_GARB_PER_LOCK then n := MAX_GARB_PER_LOCK; else n := p; end if;
            garb_left <= n;
            p         := p - n;
            state     <= S_HOLE;
          else
            state <= S_PICK;
          end if;

        -- pick the column of the hole in this batch of garbage (random 0..9)
        when S_HOLE =>
          rnd := to_integer(unsigned(lfsr(3 downto 0)));
          if rnd < COLS then
            hole  <= rnd;
            state <= S_GARB;
          end if;

        -- push the whole field up one row and add a grey row at the bottom,
        -- once per clock. Something already in the top row = pushed out = lose.
        when S_GARB =>
          if garb_left = 0 then
            state <= S_PICK;
          elsif occ_r(0) /= EMPTY_OCC then
            over_r    <= '1';
            playing_r <= '0';
            req_hard  <= '0';
            req_rot   <= '0';
            lost_o    <= '1';
            lose_age  <= 0;
            if versus = '1' then result_r <= R_LOSE; else result_r <= R_OVER; end if;
            state     <= S_IDLE;
          else
            for r in 0 to ROWS - 2 loop
              occ_r(r) <= occ_r(r + 1);
              col_r(r) <= col_r(r + 1);
            end loop;
            occ_r(ROWS - 1)       <= (others => '1');
            occ_r(ROWS - 1)(hole) <= '0';
            col_r(ROWS - 1)       <= (others => '1');      -- colour 7 = grey everywhere
            garb_left <= garb_left - 1;
          end if;

      end case;

      -- ---------------------------------------------- the other board lost
      if opp_lost = '1' then
        if playing_r = '1' then
          result_r  <= R_WIN;
          playing_r <= '0';
          req_hard  <= '0';
          req_rot   <= '0';
          state     <= S_IDLE;
        elsif result_r = R_LOSE and lose_age < 6 then
          -- I had just lost too: both boards topped out at (almost) the same
          -- moment, before either LOST message arrived. The other board gets
          -- my LOST the same way and also turns its LOSE into DRAW, so both
          -- screens agree without any extra message.
          result_r  <= R_DRAW;
        end if;
      end if;

      -- ---------------------------------------------- garbage arriving
      if garb_in = '1' then
        if p + garb_in_n > 31 then p := 31; else p := p + garb_in_n; end if;
      end if;
      pending_r <= p;
    end if;
  end process;

  -- stack height for the heartbeat: 20 - (the highest row with a block).
  -- The loop goes from the bottom up, so the last match is the highest row.
  process(clk)
    variable h : integer range 0 to 20;
  begin
    if rising_edge(clk) then
      h := 0;
      for r in ROWS - 1 downto 0 loop
        if occ_r(r) /= EMPTY_OCC then
          h := ROWS - r;
        end if;
      end loop;
      height_r <= h;
    end if;
  end process;

  start_out  <= start_o;
  lost_out   <= lost_o;
  garb_out   <= garb_o;
  garb_out_n <= garb_o_n;
  height     <= height_r;
  pending    <= pending_r;
  result     <= result_r;

  occ        <= occ_r;
  colf       <= col_r;
  cur_shape  <= cur_sh;
  cur_color  <= std_logic_vector(to_unsigned(cur_p, 3));
  cur_x      <= cur_xr;
  cur_y      <= cur_yr;
  ghost_y    <= ghost_r;
  next_shape <= next_sh;
  next_color <= std_logic_vector(to_unsigned(next_p, 3));
  playing    <= playing_r;
  can_start  <= '1' when playing_r = '0' and cool = 0 else '0';
  game_over  <= over_r;
  lines_bcd  <= lines_r;
  level      <= level_r;
  clear_evt  <= evt_r;
  clear_n    <= evt_n;

end architecture;
