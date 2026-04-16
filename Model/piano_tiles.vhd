-- Piano Tiles Model
-- We will have 4 lanes with notes on our screen, each lane can hold up to 8 notes at a time
-- each pulse cycle, the notes will move down the screen, and if a note is added to a lane, it will start at the top of the screen
-- when the note reaches the bottom of the screen, if the corresponding button is pressed, then the player gets a point

LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;
USE work.game_pkg.ALL;

-- represents one lane of notes
ENTITY note_lane IS
	PORT (
		clk : IN STD_LOGIC;
		reset_game : IN STD_LOGIC;
		shift_notes : IN STD_LOGIC;
		add_note : IN STD_LOGIC;
		mark_hit : IN STD_LOGIC;
		notes_out : OUT STD_LOGIC_VECTOR(NOTE_COUNT - 1 DOWNTO 0);
		hits_out : OUT STD_LOGIC_VECTOR(NOTE_COUNT - 1 DOWNTO 0)
	);
END ENTITY;

ARCHITECTURE rtl OF note_lane IS
	SIGNAL notes : STD_LOGIC_VECTOR(NOTE_COUNT - 1 DOWNTO 0) := (OTHERS => '0');
	SIGNAL hits : STD_LOGIC_VECTOR(NOTE_COUNT - 1 DOWNTO 0) := (OTHERS => '0');
BEGIN
	PROCESS (clk)
		VARIABLE next_notes : STD_LOGIC_VECTOR(NOTE_COUNT - 1 DOWNTO 0);
		VARIABLE next_hits : STD_LOGIC_VECTOR(NOTE_COUNT - 1 DOWNTO 0);
	BEGIN
		IF rising_edge(clk) THEN
			IF reset_game = '1' THEN
				notes <= (OTHERS => '0');
				hits <= (OTHERS => '0');
			ELSE
				next_notes := notes; -- Default to hold current value
				next_hits := hits;

			IF shift_notes = '1' THEN
				-- move notes down one position (0 -> 1 -> 2 ... -> 7)
				next_notes := next_notes(NOTE_COUNT - 2 DOWNTO 0) & '0';
				next_hits := next_hits(NOTE_COUNT - 2 DOWNTO 0) & '0';

				-- add a new note at the top if requested
				IF add_note = '1' THEN
					next_notes(0) := '1';
					next_hits(0) := '0';
				END IF;
			END IF;

			-- Mark the lowest tile inside the valid hit zone 
			IF mark_hit = '1' THEN
				IF next_notes(NOTE_COUNT - 1) = '1' AND next_hits(NOTE_COUNT - 1) = '0' THEN
					next_hits(NOTE_COUNT - 1) := '1';
				END IF;
			END IF;

				notes <= next_notes;
				hits <= next_hits;
			END IF;
		END IF;
	END PROCESS;

	notes_out <= notes;
	hits_out <= hits;
END ARCHITECTURE;

LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;
USE work.game_pkg.ALL;

ENTITY note_stage IS
	PORT (
		game_tick : IN STD_LOGIC;
		reset_game : IN STD_LOGIC;

		-- one button per lane
		buttons : IN STD_LOGIC_VECTOR(LANE_COUNT - 1 DOWNTO 0);

		-- current notes in all lanes
		notes_matrix : OUT note_matrix_t;
		hit_matrix : OUT note_matrix_t;

		-- current score
		score : OUT INTEGER;

		-- current max score (highest score seen this session)
		max_score : OUT INTEGER;

		-- current combo (consecutive hits without a miss or wrong press)
		combo : OUT INTEGER;

		-- best combo seen this session
		best_combo : OUT INTEGER;

		-- sub-note offset for rendering
		note_offset : OUT INTEGER RANGE 0 TO NOTE_HEIGHT
	);
END ENTITY;

ARCHITECTURE rtl OF note_stage IS

	-- Component declarations
	COMPONENT note_lane IS
		PORT (
			clk : IN STD_LOGIC;
			reset_game : IN STD_LOGIC;
			shift_notes : IN STD_LOGIC;
			add_note : IN STD_LOGIC;
			mark_hit : IN STD_LOGIC;
			notes_out : OUT STD_LOGIC_VECTOR(NOTE_COUNT - 1 DOWNTO 0);
			hits_out : OUT STD_LOGIC_VECTOR(NOTE_COUNT - 1 DOWNTO 0)
		);
	END COMPONENT;

	COMPONENT randomizer IS
		PORT (
			clk      : IN  STD_LOGIC;
			reset    : IN  STD_LOGIC;
			enable   : IN  STD_LOGIC;
			rand_out : OUT STD_LOGIC_VECTOR(31 DOWNTO 0)
		);
	END COMPONENT;

	-- internal storage for lane outputs
	SIGNAL notes_matrix_sig : note_matrix_t := (OTHERS => (OTHERS => '0'));
	SIGNAL hit_matrix_sig : note_matrix_t := (OTHERS => (OTHERS => '0'));

	-- pulse to shift all lanes by one note
	SIGNAL shift_notes_sig : STD_LOGIC := '0';

	-- one add pulse per lane
	SIGNAL add_note_sig : STD_LOGIC_VECTOR(LANE_COUNT - 1 DOWNTO 0) := (OTHERS => '0');

	-- mark hit pulse per lane (targets the lowest tile in valid zone)
	SIGNAL mark_hit_sig : STD_LOGIC_VECTOR(LANE_COUNT - 1 DOWNTO 0) := (OTHERS => '0');

	-- tracks whether each lane button has already been scored this note cycle
	SIGNAL button_pressed_sig : STD_LOGIC_VECTOR(LANE_COUNT - 1 DOWNTO 0) := (OTHERS => '0');

	-- counts game ticks between note shifts
	SIGNAL tick_count : INTEGER RANGE 0 TO NOTE_HEIGHT := 0;

	CONSTANT INITIAL_SCORE : INTEGER := 35;
	
	-- score register and running maximum
	SIGNAL score_signal : INTEGER := INITIAL_SCORE;
	SIGNAL max_score_sig : INTEGER := 0;

	-- combo counters: current streak and session best
	SIGNAL combo_sig      : INTEGER := 0;
	SIGNAL best_combo_sig : INTEGER := 0;

	-- progressive difficulty: penalty grows with playtime
	SIGNAL total_game_ticks : INTEGER := 0;
	SIGNAL current_penalty : INTEGER := 10;
	SIGNAL missed_penalty : INTEGER := 5;

	-- random lane selection (32-bit LFSR output)
	SIGNAL rand_lane_bits : STD_LOGIC_VECTOR(31 DOWNTO 0) := (OTHERS => '0');

BEGIN

	-- Progressive penalty: increases as the game goes on
	current_penalty <= 10 + (total_game_ticks / 25);
	missed_penalty  <= 5  + (total_game_ticks / 120);

	-- Lane instances
	lane0_inst : note_lane
		PORT MAP(
			clk => game_tick,
			reset_game => reset_game,
			shift_notes => shift_notes_sig,
			add_note => add_note_sig(0),
			mark_hit => mark_hit_sig(0),
			notes_out => notes_matrix_sig(0),
			hits_out => hit_matrix_sig(0)
		);

	lane1_inst : note_lane
		PORT MAP(
			clk => game_tick,
			reset_game => reset_game,
			shift_notes => shift_notes_sig,
			add_note => add_note_sig(1),
			mark_hit => mark_hit_sig(1),
			notes_out => notes_matrix_sig(1),
			hits_out => hit_matrix_sig(1)
		);

	lane2_inst : note_lane
		PORT MAP(
			clk => game_tick,
			reset_game => reset_game,
			shift_notes => shift_notes_sig,
			add_note => add_note_sig(2),
			mark_hit => mark_hit_sig(2),
			notes_out => notes_matrix_sig(2),
			hits_out => hit_matrix_sig(2)
		);

	lane3_inst : note_lane
		PORT MAP(
			clk => game_tick,
			reset_game => reset_game,
			shift_notes => shift_notes_sig,
			add_note => add_note_sig(3),
			mark_hit => mark_hit_sig(3),
			notes_out => notes_matrix_sig(3),
			hits_out => hit_matrix_sig(3)	
		);

	-- Randomizer instance (32-bit LFSR)
	randomizer_inst : randomizer
		PORT MAP(
			clk => game_tick,
			reset => '0',
			enable => '1',
			rand_out => rand_lane_bits
		);

	-- Main control process
	PROCESS (game_tick)
		VARIABLE score_next : INTEGER;
		VARIABLE combo_next : INTEGER;
		VARIABLE button_pressed_next : STD_LOGIC_VECTOR(LANE_COUNT - 1 DOWNTO 0);
		VARIABLE rand_val : INTEGER RANGE 0 TO 63;
		VARIABLE tile_hit_this_cycle : STD_LOGIC_VECTOR(LANE_COUNT - 1 DOWNTO 0);
	BEGIN
		IF rising_edge(game_tick) THEN
			tile_hit_this_cycle := (OTHERS => '0');
			-- default: pulses are low unless asserted this cycle
			shift_notes_sig <= '0';
			add_note_sig <= (OTHERS => '0');
			mark_hit_sig <= (OTHERS => '0');

			IF reset_game = '1' THEN
				-- Reset all counters and trackers on game reset
				score_signal <= INITIAL_SCORE;
				tick_count <= 0;	
				button_pressed_sig <= buttons;
				total_game_ticks <= 0;
				combo_sig      <= 0;
				best_combo_sig <= 0;
			ELSIF score_signal > 0 THEN
				total_game_ticks <= total_game_ticks + 1;
				score_next := score_signal;
				combo_next := combo_sig;
				button_pressed_next := button_pressed_sig;

				-- ---- Button / scoring loop --------------------------------
				-- Each lane scores or penalises at most once per note cycle.
				FOR i IN 0 TO LANE_COUNT - 1 LOOP
					IF buttons(i) = '1' AND button_pressed_sig(i) = '0' THEN
						button_pressed_next(i) := '1';

						IF notes_matrix_sig(i)(NOTE_COUNT - 1) = '1' AND hit_matrix_sig(i)(NOTE_COUNT - 1) = '0' THEN
							-- Correct hit: note is in the absolute bottom zone
							-- Score bonus rewards accuracy (hitting when tile is perfectly centered) + combo multiplier
							IF tick_count <= (NOTE_HEIGHT / 2) THEN
								score_next := score_next + NOTE_HEIGHT - ((NOTE_HEIGHT / 2) - tick_count) + (combo_sig / 4);
							ELSE
								score_next := score_next + NOTE_HEIGHT - (tick_count - (NOTE_HEIGHT / 2)) + (combo_sig / 4);
							END IF;
							
							mark_hit_sig(i) <= '1';
							tile_hit_this_cycle(i) := '1';
							combo_next := combo_next + 1; -- extend the streak
						ELSE
							-- Wrong press: apply escalating penalty and break streak
							current_penalty <= 10 + (total_game_ticks / 256);
							score_next := score_next - (10 + (total_game_ticks / 256));
							combo_next := 0;              -- break the streak
						END IF;
					END IF;
				END LOOP;

				-- ---- Update max score ----------------------------------------
				IF score_next > max_score_sig THEN
					max_score_sig <= score_next;
				END IF;

				-- ---- Note shift and miss detection ---------------------------
				IF tick_count = NOTE_HEIGHT THEN
					-- note_lane acted on shift_notes_sig='1' last cycle; reset counter
					tick_count <= 0;
					button_pressed_sig <= (OTHERS => '0');
				ELSIF tick_count = NOTE_HEIGHT - 1 THEN
					-- Assert shift one cycle early so note_lane shifts on the same edge
					-- that tick_count resets, keeping note_offset and notes_matrix in sync
					shift_notes_sig <= '1';

					-- Check for missed tiles (bottom tile scrolled off without a hit)
					FOR i IN 0 TO LANE_COUNT - 1 LOOP
						IF notes_matrix_sig(i)(NOTE_COUNT - 1) = '1' THEN
							IF hit_matrix_sig(i)(NOTE_COUNT - 1) = '0' AND tile_hit_this_cycle(i) = '0' THEN
								missed_penalty <= 10 + (total_game_ticks / 256);
								score_next := score_next - (10 + (total_game_ticks / 256));
								combo_next := 0; -- break the streak on a miss
							END IF;
						END IF;
					END LOOP;

					-- ---- Tile generation (6-bit random, 0-63) ----------------
					--   ~81.2% single  (52/64 - balanced 13 per lane)
					--   ~ 7.8% empty   (5/64)
					--   ~ 9.4% double  (6/64 - perfectly balanced covering all 6 pair combinations)
					--   ~ 1.5% triple  (1/64)
					rand_val := to_integer(unsigned(rand_lane_bits(5 DOWNTO 0)));
					CASE rand_val IS
						-- Single Tiles (Common)
						WHEN 0  TO 12 => add_note_sig(0) <= '1';
						WHEN 13 TO 25 => add_note_sig(1) <= '1';
						WHEN 26 TO 38 => add_note_sig(2) <= '1';
						WHEN 39 TO 51 => add_note_sig(3) <= '1';

						-- Double Tiles (~9.4% - All 6 combinations)
						WHEN 52 => add_note_sig(0) <= '1'; add_note_sig(1) <= '1';
						WHEN 53 => add_note_sig(1) <= '1'; add_note_sig(2) <= '1';
						WHEN 54 => add_note_sig(2) <= '1'; add_note_sig(3) <= '1';
						WHEN 55 => add_note_sig(0) <= '1'; add_note_sig(2) <= '1';
						WHEN 56 => add_note_sig(1) <= '1'; add_note_sig(3) <= '1';
						WHEN 57 => add_note_sig(0) <= '1'; add_note_sig(3) <= '1';

						-- Empty rows / breathing room (~7.8%)
						WHEN 58 TO 62 => NULL;

						-- Triple Tiles (~1.5%)
						WHEN 63 => add_note_sig(1) <= '1'; add_note_sig(2) <= '1'; add_note_sig(3) <= '1';

						WHEN OTHERS => NULL;
					END CASE;

					tick_count <= NOTE_HEIGHT;
					button_pressed_sig <= button_pressed_next;
				ELSE
					tick_count <= tick_count + 1;
					button_pressed_sig <= button_pressed_next;
				END IF;

				-- ---- Clamp score to zero (no negative score) -----------------
				IF score_next < 0 THEN
					score_next := 0;
				END IF;

				score_signal <= score_next;

				-- ---- Update combo and best combo -----------------------------
				combo_sig <= combo_next;
				IF combo_next > best_combo_sig THEN
					best_combo_sig <= combo_next;
				END IF;

			END IF;
		END IF;
	END PROCESS;

	-- Outputs
	notes_matrix <= notes_matrix_sig;
	hit_matrix   <= hit_matrix_sig;
	score        <= score_signal;
	max_score    <= max_score_sig;
	combo        <= combo_sig;
	best_combo   <= best_combo_sig;
	note_offset  <= tick_count;

END ARCHITECTURE;