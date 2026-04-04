LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;

ENTITY key_debounce IS
	GENERIC (
		TICKS_PER_SECOND : NATURAL := 50_000_000
	);
	PORT (
		clk : IN STD_LOGIC;
		key : IN STD_LOGIC;
		out_signal : OUT STD_LOGIC
	);
END ENTITY;

ARCHITECTURE rtl OF key_debounce IS
	-- incoming signal from the KEY button
	SIGNAL key_db_prev : STD_LOGIC;

	-- key_db be a stable 1 for 20ms at 50 MHz (1,000,000 ticks) to pulse
	SIGNAL key_db : STD_LOGIC;
	
	-- SIGNAL key_db_count : INTEGER RANGE 0 TO 1_000_000 := 0;
	SIGNAL key_db_count : NATURAL := 0;

	SIGNAL key_db_out : STD_LOGIC := '0';
	SIGNAL key_db_pulsed : STD_LOGIC := '0';
BEGIN
	PROCESS (clk)
	BEGIN
		IF rising_edge(clk) THEN
			key_db_prev <= key;
			key_db <= key_db_prev;
			key_db_out <= '0';

			IF key_db = '1' THEN
				-- button is not pressed, reset counter
				key_db_count <= 0;
				key_db_pulsed <= '0';
			ELSIF key_db = '0' THEN
				-- button pressed (active-low)
				IF key_db_pulsed = '0' THEN
					-- count
					key_db_count <= key_db_count + 1;
					IF key_db_count = TICKS_PER_SECOND / 50 THEN
						key_db_out <= '1';
						key_db_pulsed <= '1';
					END IF;
				END IF;
			END IF;
		END IF;
	END PROCESS;

	PROCESS (key_db_out)
	BEGIN
		out_signal <= key_db_out;
	END PROCESS;
END rtl;