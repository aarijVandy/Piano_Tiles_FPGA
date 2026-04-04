-- Piano Tiles Model
-- We will have 4 lanes with notes on our screen, each lane can hold up to 8 notes at a time
-- each pulse cycle, the notes will move down the screen, and if a note is added to a lane, it will start at the top of the screen
-- when the note reaches the bottom of the screen, if the corresponding button is pressed, then the player gets a point


LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;
use work.game_pkg.all;

-- represents one note lane
ENTITY note_lane IS
	PORT(
		note_tick : IN STD_LOGIC;

		-- pulse this signal when adding a note to this lane
		add_note: IN STD_LOGIC;
		-- outputs all notes in this lane
		notes_out : OUT STD_LOGIC_VECTOR(NOTE_COUNT-1 DOWNTO 0)
	);
END ENTITY;

ARCHITECTURE rtl OF note_lane IS
	-- each bit in this vector represents a note, 1 means there is a note, 0 means there is no note
	SIGNAL notes : STD_LOGIC_VECTOR(NOTE_COUNT-1 DOWNTO 0) := (others => '0');
BEGIN
	PROCESS (note_tick)
	BEGIN
		IF rising_edge(note_tick) THEN
			-- move all notes down the screen
			notes <= '0' & notes(NOTE_COUNT-1 DOWNTO 1);
			-- add a new note at the top of the screen if add_note is pulsed
			IF add_note = '1' THEN
				notes(0) <= '1';
			END IF;
		END IF;
	END PROCESS;

	PROCESS (notes)
	BEGIN
		notes_out <= notes;
	END PROCESS;
END rtl;


LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;
use work.game_pkg.all;

-- now we need to create a note_stage for each of the 4 lanes
-- this note_stage will take in a game_tick signal
-- it will take in a button input for each lane
-- it uses NOTE_HEIGHT, after NOTE_HEIGHT game-ticks it will move the notes down the screen
-- after moving notes down the screen 
