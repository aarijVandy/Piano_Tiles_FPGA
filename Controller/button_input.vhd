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
	SIGNAL key_db_prev : STD_LOGIC := '1';
	SIGNAL key_db      : STD_LOGIC := '1';
	SIGNAL key_db_state: STD_LOGIC := '1'; -- 1 = not pressed, 0 = pressed
	
	CONSTANT DEBOUNCE_MAX : NATURAL := TICKS_PER_SECOND / 50; -- ~20ms
	SIGNAL key_db_count : INTEGER RANGE 0 TO DEBOUNCE_MAX := 0;
	
	SIGNAL key_db_out : STD_LOGIC := '0';
BEGIN
	PROCESS (clk)
	BEGIN
		IF rising_edge(clk) THEN
			key_db_prev <= key;
			key_db <= key_db_prev;
			key_db_out <= '0';

			-- Active low counting logic
			IF key_db = '0' THEN
				IF key_db_count < DEBOUNCE_MAX THEN
					key_db_count <= key_db_count + 1;
				END IF;
			ELSE
				IF key_db_count > 0 THEN
					key_db_count <= key_db_count - 1;
				END IF;
			END IF;

			-- State machine with solid hysteresis
			IF key_db_count = DEBOUNCE_MAX THEN
				IF key_db_state = '1' THEN
					key_db_state <= '0'; -- officially pressed
					key_db_out <= '1';   -- send 1-tick pulse
				END IF;
			ELSIF key_db_count = 0 THEN
				key_db_state <= '1';     -- officially released
			END IF;
		END IF;
	END PROCESS;

	out_signal <= key_db_out;
END rtl;