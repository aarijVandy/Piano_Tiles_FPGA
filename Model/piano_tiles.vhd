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
		shift_notes : IN STD_LOGIC;
		add_note : IN STD_LOGIC;
		clear_bottom: IN STD_LOGIC
		notes_out : OUT STD_LOGIC_VECTOR(NOTE_COUNT - 1 DOWNTO 0)
	);
END ENTITY;

ARCHITECTURE rtl OF note_lane IS
	SIGNAL notes : STD_LOGIC_VECTOR(NOTE_COUNT - 1 DOWNTO 0) := (OTHERS => '0');
BEGIN
        PROCESS (clk)
                VARIABLE next_notes : STD_LOGIC_VECTOR(NOTE_COUNT - 1 DOWNTO 0);
        BEGIN
                IF rising_edge(clk) THEN
                        next_notes := notes; -- Default to hold current value

                        IF shift_notes = '1' THEN
                                -- move notes down one position (0 -> 1 -> 2 ... -> 7)
                                next_notes := next_notes(NOTE_COUNT - 2 DOWNTO 0) & '0';

                                -- add a new note at the top if requested
                                IF add_note = '1' THEN
                                        next_notes(0) := '1';
                                END IF;
                        END IF;

                        -- Instantly clear the bottom tile if scored
                        IF clear_bottom = '1' THEN
                                next_notes(NOTE_COUNT - 1) := '0';
                        END IF;

                        notes <= next_notes;
                END IF;
        END PROCESS;

	notes_out <= notes;
END ARCHITECTURE;
LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;
USE work.game_pkg.ALL;

ENTITY note_stage IS
	PORT (
		game_tick : IN STD_LOGIC;

		-- one button per lane
		buttons : IN STD_LOGIC_VECTOR(LANE_COUNT - 1 DOWNTO 0);

		-- current notes in all lanes
		notes_matrix : OUT note_matrix_t;

		-- current score
		score : OUT INTEGER;

		-- sub-note offset for rendering
		note_offset : OUT INTEGER RANGE 0 TO NOTE_HEIGHT
	);
END ENTITY;
ARCHITECTURE rtl OF note_stage IS

	-- internal storage for lane outputs
	SIGNAL notes_matrix_sig : note_matrix_t := (OTHERS => (OTHERS => '0'));

	-- pulse to shift all lanes by one note
	SIGNAL shift_notes_sig : STD_LOGIC := '0';

	-- one add pulse per lane
	SIGNAL add_note_sig : STD_LOGIC_VECTOR(LANE_COUNT - 1 DOWNTO 0) := (OTHERS => '0');

	-- clear bottom pulse per lane
	SIGNAL clear_bottom_sig : STD_LOGIC_VECTOR(LANE_COUNT - 1 DOWNTO 0) := (OTHERS => '0');

	-- counts game ticks between note shifts
	SIGNAL tick_count : INTEGER RANGE 0 TO NOTE_HEIGHT := 0;

	-- score register
	SIGNAL score_signal : INTEGER := 0;

	-- random lane selection
	SIGNAL rand_lane_bits : STD_LOGIC_VECTOR(3 DOWNTO 0) := (OTHERS => '0');

BEGIN

	-- Lane instances
	lane0_inst : ENTITY work.note_lane
		PORT MAP(
			clk => game_tick,
			shift_notes => shift_notes_sig,
			add_note => add_note_sig(0),
			notes_out => notes_matrix_sig(0)
			clear_bottom => clear_bottom_sig(0)
		);

	lane1_inst : ENTITY work.note_lane
		PORT MAP(
			clk => game_tick,
			shift_notes => shift_notes_sig,
			add_note => add_note_sig(1),
			clear_bottom => clear_bottom_sig(1),
			notes_out => notes_matrix_sig(1)
		);

	lane2_inst : ENTITY work.note_lane
		PORT MAP(
			clk => game_tick,
			shift_notes => shift_notes_sig,
			add_note => add_note_sig(2),
			clear_bottom => clear_bottom_sig(2),
			notes_out => notes_matrix_sig(2)
		);

	lane3_inst : ENTITY work.note_lane
		PORT MAP(
			clk => game_tick,
			shift_notes => shift_notes_sig,
			add_note => add_note_sig(3),
			clear_bottom => clear_bottom_sig(3),
			notes_out => notes_matrix_sig(3)
		);

        -- Randomizer instance
        randomizer_inst : ENTITY work.randomizer
			PORT MAP(
					clk => game_tick,
					reset => '0',
					enable => '1',
					rand_out => rand_lane_bits
			);

        -- Main control process
        PROCESS (game_tick)
        BEGIN
                IF rising_edge(game_tick) and score_signal >= 0 THEN
                        -- default: pulses are low unless asserted this cycle
                        shift_notes_sig <= '0';
                        add_note_sig <= (OTHERS => '0');
                        clear_bottom_sig <= (OTHERS => '0');

                        -- check for scoring (note_matrix_sig represents the state)
                        FOR i IN 0 TO LANE_COUNT - 1 LOOP
                                -- note is in the bottom buffer zone
                                IF buttons(i) = '1' AND notes_matrix_sig(i)(NOTE_COUNT - 1) = '1' THEN
                                        -- score increases by how close the note is to the bottom
                                        score_signal <= score_signal + NOTE_HEIGHT - tick_count;

                                        -- tell the lane to erase the note so it can't be scored again
                                        clear_bottom_sig(i) <= '1';
                                END IF;

								IF buttons(i) = '1' AND notes_matrix_sig(i)(NOTE_COUNT - 1) = '0' THEN
									-- penalize for pressing when no note is there
									score_signal <= score_signal - 120;
								END IF;
                        END LOOP;

			IF tick_count = NOTE_HEIGHT THEN
				shift_notes_sig <= '1'; -- shift notes down
				add_note_sig <= rand_lane_bits; -- add new note to random lane
				tick_count <= 0; -- reset tick count
			ELSE
				tick_count <= tick_count + 1;
			END IF;
		END IF;
	END PROCESS;

	-- Outputs
	notes_matrix <= notes_matrix_sig;
	score <= score_signal;
	note_offset <= tick_count;

END ARCHITECTURE;